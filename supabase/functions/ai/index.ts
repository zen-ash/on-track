// On Track — the one AI endpoint.
//
// Every model call in the app goes through here. That's deliberate: the OpenAI
// key stays server-side, and the chat tool loop runs against Postgres using the
// *caller's* JWT, so row level security decides what the model can see and
// change. There is no service-role key anywhere in this file.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;
// Override with the OPENAI_MODEL secret; this is only the fallback for a fresh
// deploy. Capture sits on the critical path of "speak it before you forget",
// so if you swap this, weigh latency as heavily as reasoning quality.
const OPENAI_MODEL = Deno.env.get("OPENAI_MODEL") ?? "gpt-5.6-luna";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return fail(401, "Missing Authorization header");

    // Forwarding the caller's token means every query below is RLS-scoped.
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return fail(401, "Not signed in");

    const body = await req.json();
    const now: string = body.now ?? new Date().toISOString();
    const timezone: string = body.timezone ?? "UTC";

    // Caps what one account can spend of the shared key. Claimed before any
    // model call, and recorded in the same statement that checks it so two
    // concurrent requests can't both take the last slot.
    const quota = await claimQuota(supabase, body.action);
    if (!quota.allowed) return fail(429, quotaMessage(quota.reason));

    switch (body.action) {
      case "capture":
        // The Swift client encodes keys as snake_case.
        return ok(await capture(body.text ?? "", body.existing_titles ?? [], now, timezone));
      case "plan":
        return ok(await plan(body.tasks ?? [], now, timezone));
      case "chat":
        return ok(await chat(supabase, body.history ?? [], now, timezone));
      case "breakdown":
        return ok(await breakdown(body.title ?? "", body.notes ?? null, now));
      default:
        return fail(400, `Unknown action: ${body.action}`);
    }
  } catch (error) {
    console.error(error);
    return fail(500, error instanceof Error ? error.message : String(error));
  }
});

function ok(payload: unknown) {
  return new Response(JSON.stringify(payload), {
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/// Fails closed. If the quota can't be verified we decline rather than spend
/// money on an unverified request — capture degrades to on-device parsing, so
/// the cost of being cautious here is low.
async function claimQuota(supabase: SupabaseClient, action: string) {
  const { data, error } = await supabase.rpc("claim_ai_quota", { p_action: action });
  if (error) {
    console.error("quota check failed", error);
    return { allowed: false, reason: "unavailable" };
  }
  const row = Array.isArray(data) ? data[0] : data;
  return { allowed: row?.allowed === true, reason: String(row?.reason ?? "unknown") };
}

function quotaMessage(reason: string): string {
  switch (reason) {
    case "daily":
      return "You've used today's limit for this. It frees up again over the next 24 hours.";
    case "burst":
      return "Too many requests in the last minute. Give it a moment.";
    case "unauthenticated":
      return "Sign in to use this.";
    default:
      return "Couldn't check your usage limit. Try again shortly.";
  }
}

function fail(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// OpenAI
// ---------------------------------------------------------------------------

type Message = {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_calls?: unknown;
  tool_call_id?: string;
};

async function openai(path: string, payload: Record<string, unknown>) {
  const response = await fetch(`https://api.openai.com/v1/${path}`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model: OPENAI_MODEL, ...payload }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`OpenAI ${response.status}: ${detail.slice(0, 500)}`);
  }
  return await response.json();
}

/// Structured output call — the schema is enforced, so the result parses.
async function openaiJSON<T>(name: string, schema: object, messages: Message[]): Promise<T> {
  const result = await openai("chat/completions", {
    messages,
    // Generous headroom: on reasoning models the budget covers hidden reasoning
    // tokens too, and running out yields an empty completion.
    max_completion_tokens: 8000,
    response_format: {
      type: "json_schema",
      json_schema: { name, strict: true, schema },
    },
  });

  const content = result.choices?.[0]?.message?.content;
  if (!content) throw new Error("Model returned no content");
  return JSON.parse(content) as T;
}

// ---------------------------------------------------------------------------
// Shared prompt scaffolding
// ---------------------------------------------------------------------------

function clock(now: string, timezone: string) {
  const local = new Date(now).toLocaleString("en-GB", {
    timeZone: timezone,
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });

  // The offset is stated explicitly because every date the model emits has to
  // land on the right calendar day *for the user*, not in UTC.
  const offset = new Intl.DateTimeFormat("en-US", { timeZone: timezone, timeZoneName: "longOffset" })
    .formatToParts(new Date(now))
    .find((part) => part.type === "timeZoneName")?.value ?? "GMT+00:00";

  return `Right now it is ${local} (${timezone}, ${offset}). The exact instant is ${now}.

Every timestamp you emit MUST carry the user's own offset (${offset.replace("GMT", "")}).
For an all-day task — has_time false — use 09:00 local, e.g. 2026-08-20T09:00:00${offset.replace("GMT", "") || "+00:00"}.
Never emit midnight or a bare UTC time for an all-day task: it lands on the
wrong calendar day once it's shown back in the user's timezone. When you move an
all-day task to a new date, re-emit it at 09:00 local rather than preserving
whatever clock time it previously had.`;
}

const VOICE = `
You are the brain inside On Track, a todo app. Your tone is dry, brief and a
little blunt. Never cheerful, never patronising, never emoji.
`.trim();

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

const CAPTURED_TASK_SCHEMA = {
  type: "object",
  properties: {
    title: {
      type: "string",
      description:
        "The user's OWN words, trimmed of scaffolding. Sentence case, first letter capitalised, no trailing punctuation. Do not paraphrase or shorten beyond removing filler: 'call the bank' stays 'Call the bank', never 'call bank'. Strip every date, time, recurrence and priority phrase — those live in the other fields and must not appear twice: 'pay rent before the 5th' becomes 'Pay rent', 'gym every mon wed fri at 7am' becomes 'Gym', 'urgent send the invoice' becomes 'Send the invoice'.",
    },
    notes: { type: ["string", "null"], description: "Only if the user said something that doesn't fit the title." },
    due_at: { type: ["string", "null"], description: "ISO 8601 with timezone offset, or null if no date was implied." },
    has_time: { type: "boolean", description: "True only if a specific time of day was stated or clearly implied." },
    priority: { type: "integer", description: "0 none, 1 low, 2 medium, 3 urgent." },
    tags: {
      type: "array",
      items: { type: "string" },
      description:
        "Almost always empty. Only include a tag the user actually said, e.g. '#work' or 'for work'. Never infer a category from the subject — 'call the bank' does NOT get a 'finance' tag. Lowercase, no # prefix, at most 2.",
    },
    recurrence: {
      type: ["string", "null"],
      description: "RRULE-lite such as FREQ=DAILY, FREQ=WEEKLY;BYDAY=MO,WE,FR, FREQ=MONTHLY. Null for one-offs.",
    },
    estimate_minutes: { type: ["integer", "null"] },
    energy: { type: ["string", "null"], enum: ["low", "medium", "high", null] },
    subtasks: {
      type: "array",
      items: { type: "string" },
      description: "Only for a task that is obviously a multi-step project. Otherwise empty.",
    },
  },
  required: [
    "title", "notes", "due_at", "has_time", "priority",
    "tags", "recurrence", "estimate_minutes", "energy", "subtasks",
  ],
  additionalProperties: false,
} as const;

const CAPTURE_SCHEMA = {
  type: "object",
  properties: {
    tasks: { type: "array", items: CAPTURED_TASK_SCHEMA },
    reply: { type: ["string", "null"], description: "At most 8 words, or null if nothing useful to add." },
  },
  required: ["tasks", "reply"],
  additionalProperties: false,
} as const;

async function capture(text: string, existingTitles: string[], now: string, timezone: string) {
  if (!text.trim()) return { tasks: [], reply: null };

  const system = `
${VOICE}

Turn what the user said into structured tasks. This is usually raw speech, so
expect filler, false starts and no punctuation.

${clock(now, timezone)}

Rules:
- One utterance may contain several tasks. Split only on genuine boundaries —
  "buy milk and eggs" is ONE task; "buy milk and call the bank" is two.
- Strip scaffolding: "remind me to", "I need to", "don't forget to".
- Resolve all relative dates against the current time above. "Tomorrow morning"
  is a real timestamp. Never emit a date in the past for a new task.
- has_time is false for a bare day like "Friday", true for "Friday at 4".
- Set recurrence for anything repeating, and set due_at to the next occurrence.
- priority 3 only for genuinely urgent language ("asap", "urgent", "today or
  I'm dead"). Most tasks are 0.
- Only fill subtasks when the task is plainly a project with obvious steps.
  A normal errand gets none.
${
    existingTitles.length > 0
      ? `\n- These already exist; if the user is clearly restating one, return it\n  anyway but say so in reply:\n${existingTitles.map((t) => `  · ${t}`).join("\n")}`
      : ""
  }
`.trim();

  const result = await openaiJSON<{ tasks: RawCaptured[]; reply: string | null }>(
    "capture",
    CAPTURE_SCHEMA,
    [{ role: "system", content: system }, { role: "user", content: text }],
  );

  return { tasks: result.tasks.map((t) => sanitiseCaptured(t, timezone)).filter(Boolean), reply: result.reply };
}

type RawCaptured = {
  title: string;
  notes: string | null;
  due_at: string | null;
  has_time: boolean;
  priority: number;
  tags: string[];
  recurrence: string | null;
  estimate_minutes: number | null;
  energy: string | null;
  subtasks: string[];
};

/// The schema guarantees shape, not sanity. This guarantees the client can
/// decode every field without throwing.
function sanitiseCaptured(task: RawCaptured, timezone: string) {
  const title = (task.title ?? "").trim();
  if (!title) return null;

  return {
    // Guaranteed rather than requested — the on-device parser always sentence-cases,
    // and rows shouldn't look different depending on which path captured them.
    title: (title.charAt(0).toUpperCase() + title.slice(1)).slice(0, 500),
    notes: task.notes?.trim() || null,
    due_at: normaliseAllDay(isoOrNull(task.due_at), Boolean(task.has_time), timezone),
    has_time: Boolean(task.has_time),
    priority: clamp(Math.round(task.priority ?? 0), 0, 3),
    tags: (task.tags ?? []).map((t) => t.replace(/^#/, "").toLowerCase().trim()).filter(Boolean).slice(0, 3),
    recurrence: task.recurrence?.trim() || null,
    estimate_minutes: task.estimate_minutes && task.estimate_minutes > 0 ? Math.round(task.estimate_minutes) : null,
    energy: ["low", "medium", "high"].includes(task.energy ?? "") ? task.energy : null,
    subtasks: (task.subtasks ?? []).map((s) => s.trim()).filter(Boolean).slice(0, 12),
  };
}

function isoOrNull(value: string | null): string | null {
  if (!value) return null;
  const date = new Date(value);
  return isNaN(date.getTime()) ? null : date.toISOString();
}

/// The user's UTC offset on a given date, as "+05:30".
function offsetFor(date: Date, timezone: string): string {
  const label = new Intl.DateTimeFormat("en-US", { timeZone: timezone, timeZoneName: "longOffset" })
    .formatToParts(date)
    .find((part) => part.type === "timeZoneName")?.value ?? "GMT+00:00";
  const offset = label.replace("GMT", "");
  return offset === "" ? "+00:00" : offset;
}

/// Pins an all-day task to 09:00 in the user's own timezone, keeping whatever
/// calendar day it already landed on.
///
/// Guaranteed here rather than requested in the prompt: the model will happily
/// emit 23:59 or midnight for a "deadline", and midnight UTC silently becomes
/// the *next* day east of Greenwich. The on-device parser uses 09:00 too, so
/// both capture paths agree.
function normaliseAllDay(iso: string | null, hasTime: boolean, timezone: string): string | null {
  if (!iso || hasTime) return iso;
  const date = new Date(iso);
  if (isNaN(date.getTime())) return null;

  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const get = (type: string) => parts.find((part) => part.type === type)?.value;

  const local = new Date(`${get("year")}-${get("month")}-${get("day")}T09:00:00${offsetFor(date, timezone)}`);
  return isNaN(local.getTime()) ? iso : local.toISOString();
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, isNaN(value) ? min : value));
}

// ---------------------------------------------------------------------------
// Plan
// ---------------------------------------------------------------------------

const PLAN_SCHEMA = {
  type: "object",
  properties: {
    focus: { type: "string", description: "The single thing that matters most today. One sentence." },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          task_id: { type: "string", description: "Must be one of the supplied task ids, verbatim." },
          slot: { type: "string", enum: ["now", "morning", "afternoon", "evening"] },
          reason: { type: "string", description: "At most 12 words. Why this, why now." },
          order: { type: "integer", description: "0-based across the whole plan." },
        },
        required: ["task_id", "slot", "reason", "order"],
        additionalProperties: false,
      },
    },
    defer_ids: {
      type: "array",
      items: { type: "string" },
      description: "Task ids that should be pushed to tomorrow. Be willing to leave this empty.",
    },
    note: { type: ["string", "null"], description: "One blunt line about the shape of the day, or null." },
  },
  required: ["focus", "items", "defer_ids", "note"],
  additionalProperties: false,
} as const;

async function plan(tasks: TaskRow[], now: string, timezone: string) {
  const open = tasks.filter((t) => t.status === "open");
  if (open.length === 0) {
    return { focus: "Nothing to do.", items: [], defer_ids: [], note: null };
  }

  const system = `
${VOICE}

Build today's plan from the user's open tasks.

${clock(now, timezone)}

Rules:
- A realistic day, not a wish list. Eight items is already too many.
- Anything overdue goes in the "now" slot unless it genuinely can't be done yet.
- Respect stated times: a task due at 09:00 belongs in the morning.
- Group deep work together and put it where the day has room.
- If the list is overloaded, put the excess in defer_ids rather than pretending.
- Use task ids exactly as given. Never invent one.
`.trim();

  const digest = open.map((t) => ({
    id: t.id,
    title: t.title,
    due_at: t.due_at ?? t.dueAt ?? null,
    priority: t.priority ?? 0,
    tags: t.tags ?? [],
    estimate_minutes: t.estimate_minutes ?? t.estimateMinutes ?? null,
    energy: t.energy ?? null,
    recurrence: t.recurrence ?? null,
  }));

  const result = await openaiJSON<{
    focus: string;
    items: { task_id: string; slot: string; reason: string; order: number }[];
    defer_ids: string[];
    note: string | null;
  }>("plan", PLAN_SCHEMA, [
    { role: "system", content: system },
    { role: "user", content: JSON.stringify(digest) },
  ]);

  // A hallucinated id would fail to decode on the client, so drop anything
  // that isn't a real task.
  const valid = new Set(open.map((t) => String(t.id)));
  const items = result.items
    .filter((item) => valid.has(item.task_id))
    .map((item, index) => ({ ...item, order: index }));

  return {
    focus: result.focus,
    items,
    defer_ids: result.defer_ids.filter((id) => valid.has(id)),
    note: result.note,
  };
}

// ---------------------------------------------------------------------------
// Breakdown
// ---------------------------------------------------------------------------

const BREAKDOWN_SCHEMA = {
  type: "object",
  properties: {
    steps: {
      type: "array",
      items: { type: "string" },
      description: "3 to 7 concrete next actions, each startable in one sitting.",
    },
  },
  required: ["steps"],
  additionalProperties: false,
} as const;

async function breakdown(title: string, notes: string | null, now: string) {
  const system = `
${VOICE}

Break one task into concrete next actions.

Rules:
- Between 3 and 7 steps. Fewer is better than padding.
- Each step starts with a verb and is small enough to actually start.
- No step is "plan X" or "think about X". Those aren't actions.
- Today is ${now}.
`.trim();

  const user = notes ? `${title}\n\nNotes: ${notes}` : title;
  const result = await openaiJSON<{ steps: string[] }>("breakdown", BREAKDOWN_SCHEMA, [
    { role: "system", content: system },
    { role: "user", content: user },
  ]);

  return { steps: result.steps.map((s) => s.trim()).filter(Boolean).slice(0, 7) };
}

// ---------------------------------------------------------------------------
// Chat (tool loop)
// ---------------------------------------------------------------------------

type TaskRow = Record<string, any>;

const TOOLS = [
  {
    type: "function",
    function: {
      name: "list_tasks",
      description: "Read the user's tasks. Call this before answering anything about their list.",
      parameters: {
        type: "object",
        properties: {
          status: { type: "string", enum: ["open", "done", "all"], description: "Defaults to open." },
        },
        required: ["status"],
        additionalProperties: false,
      },
    },
  },
  {
    type: "function",
    function: {
      name: "create_task",
      description: "Add a new task.",
      parameters: {
        type: "object",
        properties: {
          title: { type: "string", description: "The user's own words, sentence case." },
          due_at: { type: ["string", "null"], description: "ISO 8601 with offset, or null." },
          has_time: { type: "boolean", description: "True only if a time of day was stated." },
          priority: { type: "integer", description: "0 none, 1 low, 2 medium/important, 3 urgent. 'High priority' means 3." },
          recurrence: { type: ["string", "null"], description: "RRULE-lite e.g. FREQ=WEEKLY;BYDAY=MO,WE,FR. Null for one-offs." },
          tags: { type: "array", items: { type: "string" }, description: "Only tags the user actually said. Usually empty." },
        },
        required: ["title", "due_at", "has_time", "priority", "recurrence", "tags"],
        additionalProperties: false,
      },
    },
  },
  {
    type: "function",
    function: {
      name: "update_task",
      description: "Change an existing task. Only include the fields you're changing.",
      parameters: {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: ["string", "null"], description: "Null to leave unchanged." },
          due_at: { type: ["string", "null"], description: "ISO 8601 with offset. Null to leave unchanged." },
          has_time: { type: ["boolean", "null"], description: "Null to leave unchanged." },
          priority: { type: ["integer", "null"], description: "0 none, 1 low, 2 medium/important, 3 urgent. Null to leave unchanged." },
          status: { type: ["string", "null"], enum: ["open", "done", "dropped", null] },
        },
        required: ["id", "title", "due_at", "has_time", "priority", "status"],
        additionalProperties: false,
      },
    },
  },
  {
    type: "function",
    function: {
      name: "delete_task",
      description: "Delete a task permanently. Prefer marking it done or dropped.",
      parameters: {
        type: "object",
        properties: { id: { type: "string" } },
        required: ["id"],
        additionalProperties: false,
      },
    },
  },
];

/// The Responses API takes function tools flattened — no nested `function`
/// wrapper. Derived from TOOLS so there's still only one definition of each.
const RESPONSES_TOOLS = TOOLS.map((tool) => ({
  type: "function",
  name: tool.function.name,
  description: tool.function.description,
  parameters: tool.function.parameters,
  strict: true,
}));

async function chat(supabase: SupabaseClient, history: { role: string; text: string }[], now: string, timezone: string) {
  const system = `
${VOICE}

You are talking to the user about their task list. You have tools that read and
change the real database — use them rather than guessing.

${clock(now, timezone)}

Rules:
- Always call list_tasks before answering a question about what's on the list.
- Bulk instructions ("push everything this week back") mean several update_task
  calls. Do them all, don't ask for confirmation on each one.
- Resolve relative dates against the current time above.
- Replies are two sentences at most. Say what you changed, not how you felt
  about it. No bullet lists unless the user asked for a list.
`.trim();

  // Chat runs on /v1/responses rather than /v1/chat/completions: this model
  // refuses function tools alongside reasoning on the completions endpoint, and
  // reasoning is exactly what bulk edits ("push everything back two days") need.
  const input: any[] = history.map((turn) => ({
    role: turn.role === "user" ? "user" : "assistant",
    content: turn.text,
  }));

  let didMutate = false;

  // Bounded so a confused model can't spin against the database.
  for (let round = 0; round < 6; round++) {
    const result = await openai("responses", {
      instructions: system,
      input,
      tools: RESPONSES_TOOLS,
      reasoning: { effort: "medium" },
      max_output_tokens: 8000,
    });

    const output: any[] = result.output ?? [];
    if (output.length === 0) throw new Error("Model returned no output");

    // Everything comes back into the next turn — including the reasoning items,
    // which the model needs to keep its own train of thought across tool calls.
    input.push(...output);

    const calls = output.filter((item) => item.type === "function_call");
    if (calls.length === 0) {
      const message = output.find((item) => item.type === "message");
      const text = message?.content?.find((part: any) => part.type === "output_text")?.text;
      return { message: text ?? "Done.", did_mutate: didMutate };
    }

    for (const call of calls) {
      let args: Record<string, any> = {};
      try {
        args = JSON.parse(call.arguments ?? "{}");
      } catch {
        // Fall through with empty args; the tool reports the failure below.
      }

      const { output: toolOutput, mutated } = await runTool(supabase, call.name, args, timezone);
      if (mutated) didMutate = true;

      input.push({
        type: "function_call_output",
        call_id: call.call_id,
        output: JSON.stringify(toolOutput),
      });
    }
  }

  return { message: "That turned into more steps than I could finish. Try asking for less at once.", did_mutate: didMutate };
}

async function runTool(supabase: SupabaseClient, name: string, args: Record<string, any>, timezone: string) {
  switch (name) {
    case "list_tasks": {
      let query = supabase
        .from("tasks")
        .select("id,title,status,priority,due_at,has_time,recurrence,tags,parent_id")
        .order("due_at", { ascending: true, nullsFirst: false })
        .limit(200);

      if (args.status === "done") query = query.eq("status", "done");
      else if (args.status !== "all") query = query.eq("status", "open");

      const { data, error } = await query;
      return { output: error ? { error: error.message } : data, mutated: false };
    }

    case "create_task": {
      const { data, error } = await supabase
        .from("tasks")
        .insert({
          title: String(args.title ?? "").slice(0, 500),
          due_at: normaliseAllDay(isoOrNull(args.due_at ?? null), Boolean(args.has_time), timezone),
          has_time: Boolean(args.has_time),
          priority: clamp(Math.round(args.priority ?? 0), 0, 3),
          recurrence: args.recurrence || null,
          tags: Array.isArray(args.tags) ? args.tags.slice(0, 3) : [],
          source: "ai",
        })
        .select("id,title")
        .single();
      return { output: error ? { error: error.message } : data, mutated: !error };
    }

    case "update_task": {
      // Nulls mean "not changing this", so build the patch from what's set.
      const patch: Record<string, unknown> = {};
      if (args.title != null) patch.title = String(args.title).slice(0, 500);
      if (args.due_at != null) {
        // has_time null means "unchanged", so only normalise when told it's all-day.
        patch.due_at = args.has_time === false
          ? normaliseAllDay(isoOrNull(args.due_at), false, timezone)
          : isoOrNull(args.due_at);
      }
      if (args.has_time != null) patch.has_time = Boolean(args.has_time);
      if (args.priority != null) patch.priority = clamp(Math.round(args.priority), 0, 3);
      if (args.status != null) {
        patch.status = args.status;
        patch.completed_at = args.status === "done" ? new Date().toISOString() : null;
      }
      if (Object.keys(patch).length === 0) {
        return { output: { error: "Nothing to update" }, mutated: false };
      }

      const { data, error } = await supabase
        .from("tasks")
        .update(patch)
        .eq("id", args.id)
        .select("id,title,status,due_at")
        .single();
      return { output: error ? { error: error.message } : data, mutated: !error };
    }

    case "delete_task": {
      const { error } = await supabase.from("tasks").delete().eq("id", args.id);
      return { output: error ? { error: error.message } : { deleted: args.id }, mutated: !error };
    }

    default:
      return { output: { error: `Unknown tool ${name}` }, mutated: false };
  }
}
