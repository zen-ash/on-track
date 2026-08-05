// On Track — account management.
//
// Separate from the `ai` function on purpose. This is the only code in the
// project that touches the service-role key, because deleting an auth user
// requires admin privileges. Keeping it isolated means the AI endpoint — by far
// the busiest and most complex — never has access to credentials that bypass
// row level security.
//
// The account to delete is always taken from the caller's verified JWT. There is
// deliberately no user id parameter: accepting one would turn this into an
// endpoint that deletes anybody's account.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return fail(401, "Missing Authorization header");

    // Caller's own token — this is what establishes *who* is being deleted.
    const caller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userError } = await caller.auth.getUser();
    if (userError || !user) return fail(401, "Not signed in");

    const body = await req.json().catch(() => ({}));
    if (body.action !== "delete") return fail(400, `Unknown action: ${body.action}`);

    // 1. Delete their rows under their own RLS context. The foreign key would
    //    cascade anyway, but doing it explicitly means a partial failure leaves
    //    no data behind, and it works regardless of future schema changes.
    const { error: rowsError } = await caller.from("tasks").delete().eq("user_id", user.id);
    if (rowsError) return fail(500, `Could not delete tasks: ${rowsError.message}`);

    // 2. Delete the auth user itself. Requires admin privileges, hence the
    //    service-role client — scoped to the id we just verified from the JWT.
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) return fail(500, `Could not delete account: ${deleteError.message}`);

    return new Response(JSON.stringify({ deleted: true }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(error);
    return fail(500, error instanceof Error ? error.message : String(error));
  }
});

function fail(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
