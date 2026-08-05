# On Track — setup

An AI-first todo app for iPhone. White paper, black ink, and a creature that
judges you when things are late.

**You can run it right now with no accounts at all.** Open `OnTrack.xcodeproj`,
pick a simulator, press Run. Tasks save to the device and voice capture works
offline. Steps 2–4 turn on sync, planning and chat.

---

## What you get

| Surface | How it works |
| --- | --- |
| **Natural-language capture** | Speak or type "gym mon wed fri 7am, pay rent before the 5th" and it becomes structured tasks with dates, recurrence, priority and tags. |
| **Daily planner** | The bolt icon builds today's plan: one focus, tasks slotted into now/morning/afternoon/evening, and honest suggestions about what to drop. |
| **Chat over your list** | The speech-bubble icon. It reads and edits the real database through tools — "push everything this week back two days" actually does it. |
| **Auto breakdown** | Open any task → "Break it down" turns a vague project into concrete next actions. |
| **Voice quick capture** | Four one-gesture triggers, all opening the same sheet. See step 5. |

---

## 1. Run it (no accounts needed)

```bash
open "OnTrack.xcodeproj"
```

Select an iPhone simulator or your own device, then Run. Requires **Xcode 26+
and iOS 26**, because transcription uses the on-device `SpeechAnalyzer` API.

To see it populated with sample tasks: Product → Scheme → Edit Scheme →
Arguments → add `-seedDemo`.

In this mode:

- Tasks are stored locally in a JSON file.
- Voice capture works, transcribed entirely on device.
- Capture parsing uses on-device rules (`NSDataDetector` plus keyword matching)
  — it handles "tomorrow at 4", "every Monday", "urgent" and `#tags`.
- Planning falls back to a heuristic; chat and breakdown are off.

---

## 2. Supabase

Create a free project at [supabase.com](https://supabase.com), then:

**a. Create the schema.** Dashboard → SQL Editor → New query. Paste all of
[`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql) and Run.

This creates the `tasks` table and — importantly — the row level security
policies. RLS is the only thing separating users' lists, which is why the app
can safely ship the anon key.

**b. Enable anonymous sign-ins.** Authentication → Sign In / Providers →
Anonymous Sign-ins → on. This powers "Continue without an account", so you can
use the cloud features before dealing with Apple's developer program.

**c. Point the app at it.** Dashboard → Project Settings → API. Copy the URL and
the `anon` / publishable key into [`OnTrack/App/AppConfig.swift`](OnTrack/App/AppConfig.swift):

```swift
static let supabaseURL = "https://YOUR-PROJECT.supabase.co"
static let supabaseAnonKey = "eyJhbGciOi..."
```

> Only ever put the **anon** key here. The service-role key would bypass every
> policy above.

---

## 3. The AI function

This is where your OpenAI key lives. It never ships in the app.

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref YOUR-PROJECT-REF

supabase secrets set OPENAI_API_KEY=sk-proj-...
supabase functions deploy ai
```

Get an API key from [platform.openai.com](https://platform.openai.com/api-keys)
and add a few dollars of credit — capture costs a fraction of a cent per use.

The model is `gpt-5.6-luna`, set both as the code default and as the
`OPENAI_MODEL` secret. To try another, `supabase secrets set OPENAI_MODEL=...`
— the function reads it at module load, so a warm isolate keeps the old value
for a few minutes. Redeploy if you need the switch to be immediate.

> **If you change the model, re-test chat specifically.** Chat runs on
> `/v1/responses` with `reasoning: { effort: "medium" }`, because `gpt-5.6-luna`
> refuses function tools alongside reasoning on `/v1/chat/completions`. Capture,
> plan and breakdown stay on chat completions with structured outputs and are far
> less picky. A different model may need that split undone.

Check it deployed:

```bash
supabase functions list
```

The function is bundled remotely on deploy, so a local Deno install isn't
required. Any TypeScript error surfaces on the first invocation rather than at
deploy time — check the logs in the dashboard if a call returns a 500.

Now relaunch the app → menu icon → **Continue without an account**. Capture,
planning and chat all run through the model. Anything you captured in local mode
migrates up automatically on first sign-in.

---

## 4. Sign in with Apple *(needs the paid developer program)*

Skip this until you have an [Apple Developer](https://developer.apple.com)
membership ($99/yr). Anonymous sign-in above does everything except survive an
app reinstall.

1. **Xcode** → OnTrack target → Signing & Capabilities → **+ Capability** →
   Sign in with Apple. Set your Team on both the app and widget targets.
2. **Apple Developer portal** → Certificates, IDs & Profiles → Identifiers →
   your App ID → enable Sign in with Apple. Then create a **Services ID** and a
   **Key** with Sign in with Apple enabled; download the `.p8`.
3. **Supabase** → Authentication → Sign In / Providers → Apple → on. Fill in the
   Services ID, Team ID, Key ID and the `.p8` contents.

The button is already in the app (menu icon → Account). Nonce handling and the
`id_token` grant are implemented in
[`SignInWithApple.swift`](OnTrack/Features/Auth/SignInWithApple.swift).

---

## 5. The one-gesture capture triggers

All four run the same App Intent and open the same sheet. Set them up once.

### Triple-tap the back of the phone — closest to what you asked for
Settings → Accessibility → Touch → **Back Tap** → **Triple Tap** → choose the
**Capture with On Track** shortcut. Works on iPhone 8 and newer.

### Action Button — iPhone 15 Pro and newer
Settings → **Action Button** → swipe to Shortcut → choose **Capture with On Track**.

### Control Centre and Lock Screen
Swipe down → hold → **+ Add a control** → search "On Track". The same control can
be bound to the Action Button. For the Lock Screen, long-press the wallpaper →
Customise → Lock Screen → add the On Track widget.

### Siri, no buttons at all
- "Hey Siri, **capture with On Track**" — opens listening.
- "Hey Siri, **add a task to On Track**" — captures and saves without ever
  unlocking the phone.

### Why not a triple-press of the power button?

iOS doesn't allow it, for any app. The side button and every power+volume
combination are reserved by the system for screenshots, Emergency SOS, power off
and force restart, and the triple-click Accessibility Shortcut only accepts
Apple's own accessibility features — third-party apps can't join that list.
There's no entitlement and no workaround. Back Tap is the closest equivalent and
lands in about the same time.

---

## Project layout

```
OnTrack/
  App/            AppModel (all state), routing, config, demo seed
  DesignSystem/   Ink palette, type scale, rough-drawn shapes, components
  Mascot/         The creature — procedurally drawn, mood-driven
  Models/         TaskItem, recurrence rules
  Services/
    Store/        TaskStore protocol → local JSON or Supabase
    Supabase/     Hand-rolled auth + PostgREST (zero package dependencies)
    AI/           AIService protocol → remote model or on-device fallback
    Speech/       SpeechAnalyzer pipeline
    Notifications/
  Features/       Today, Capture, Chat, Plan, Detail, Settings, Auth
  Intents/        App Intents behind every quick-capture trigger
OnTrackWidgets/   Control Centre control + Lock Screen widget
supabase/         SQL migration + the ai Edge Function
```

**No third-party packages.** Auth and PostgREST are hand-rolled over
`URLSession`, so the project builds from a clean checkout with nothing but Xcode.

Two protocols carry the whole design: `TaskStore` and `AIService` each have a
local and a remote implementation, and the views never know which one is live.
That's why the app is fully usable before any backend exists.

---

## Design notes

- **Two colours.** Ink `#0B0C0E` on paper `#FCFBF9`. Everything else is opacity.
  Red appears in exactly one situation: something is late.
- **Nothing is a perfect rectangle.** Borders, checkboxes and dividers are drawn
  through a seeded RNG, so each element has stable imperfections that never
  re-wobble between redraws.
- **The creature is code, not assets.** `MascotView` draws it with `Canvas`, so
  one implementation serves the 30pt header and the 150pt empty state, and moods
  are parameters rather than a folder of PNGs.
- **It only speaks when it has something to say.** `MascotMood.watching` renders
  nothing in banners. Late work, streaks and empty lists earn a face.
- The app is locked to light mode to protect the ink-on-paper identity. Remove
  `UIUserInterfaceStyle` from `Config/OnTrack-Info.plist` to allow dark mode —
  you'd want to invert the palette in `Ink.swift` at the same time.
