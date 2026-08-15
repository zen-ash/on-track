# App Store submission notes

Everything needed to fill in App Store Connect without guessing. The privacy
answers must match what the app actually does — a mismatch discovered after
release is treated far more seriously than one caught at review.

---

## 1. App Privacy — the nutrition label

App Store Connect → your app → **App Privacy**.

### "Do you or your third-party partners collect data from this app?"
**Yes.**

### Data types to declare

Tick exactly these two. Nothing else applies.

| Apple category | Item | Linked to identity? | Used for tracking? | Purpose |
| --- | --- | --- | --- | --- |
| **User Content** | *Other User Content* | **Yes** | **No** | App Functionality |
| **Identifiers** | *User ID* | **Yes** | **No** | App Functionality |

Add *Contact Info → Email Address* and *Contact Info → Name* **only if** you ship
Sign in with Apple and store what Apple returns. Both are Linked, not Tracking,
App Functionality. If you launch guest-only, leave them off.

> **Calendar isn't a separate line — it stays under *Other User Content*.**
> Apple's nutrition label has no dedicated "Calendar" category. If a user turns
> on Setup → Calendar → "Plan around my calendar" (off by default), the app
> reads events' start/end times — never titles, notes, locations, or
> attendees, and never all-day events — and includes them in the same daily
> plan request that already sends task text, so it doesn't add a new checkbox.
> It does add an `NSCalendarsFullAccessUsageDescription` entry, which review
> will notice: be ready to point at this being opt-in, off by default, and
> read-only in review notes (see section 4).

### What to answer "No" to

Location, Contacts, Health, Financial, Browsing History, Search History,
Purchases, Usage Data, Diagnostics, Advertising Data, Sensitive Info, Photos,
Audio Data.

> **Audio Data is a genuine "No".** Speech is transcribed on-device and the audio
> is never uploaded or stored. Only the resulting text is sent, and that is
> already declared as User Content. Be ready to say this in review notes.

### "Is this data used to track you?"
**No**, for everything. No advertising, no analytics, no data brokers, no
cross-app or cross-site linking. You do **not** need App Tracking Transparency
and must not include `NSUserTrackingUsageDescription`.

### Privacy policy URL
Required. Host `PRIVACY.md` publicly first and fill in every `[…]` placeholder.

---

## 2. Age rating

Answer the questionnaire honestly. Two that matter here:

- **Does your app include a chatbot or generative AI?** — **Yes.** The chat
  surface and capture both call a model. Expect this to lift the rating above 4+.
- Everything else (violence, gambling, contests, mature themes) — No.

Understating this is a rejection risk and a post-release problem.

---

## 3. Encryption

`ITSAppUsesNonExemptEncryption` is already `false` in `Config/OnTrack-Info.plist`.
The app only uses HTTPS, which is exempt. No CCATS or self-classification needed.

---

## 4. Review notes — paste this in

```
On Track turns spoken or typed sentences into structured tasks.

SIGNING IN
No account required to test. Open the menu (☰) → Account →
"Continue without an account" for immediate full access.

WHAT TO TRY
1. Tap "Speak it" or the pencil icon.
2. Enter: "call the bank tomorrow at 4pm and gym every monday
   wednesday friday at 7am"
3. This creates two tasks with the correct dates, times and a
   weekly repeat rule.
4. The bolt icon builds a plan for the day; the speech bubble
   answers questions about the list and can edit it.

VOICE AND PRIVACY
Speech is transcribed entirely on device using SpeechAnalyzer.
No audio is uploaded or stored. Only the resulting text is sent
to our server, which calls OpenAI to structure it. Microphone
access is requested only when you tap "Speak it".

CALENDAR
Off by default. Setup -> Calendar -> "Plan around my calendar"
is the only thing that requests access, and the app never
creates, edits, or deletes an event. When it's on, only the
start/end time of today's events is sent when building a plan --
never a title, note, location, or attendee.

ACCOUNT DELETION
Menu (☰) → Account → "Delete account and all data". This
immediately and permanently deletes the account and every task
from the server.
```

---

## 5. Before you submit — checklist

- [ ] Paid Apple Developer Program membership active
- [ ] `PRIVACY.md` hosted at a public URL, placeholders replaced
- [ ] Privacy policy URL entered in App Store Connect
- [ ] Nutrition labels filled in per section 1
- [ ] Age rating questionnaire completed, AI question answered Yes
- [ ] Review notes pasted per section 4
- [ ] Screenshots for every required iPhone size
- [ ] App name availability confirmed — "On Track" is generic and may be taken
- [ ] Support URL (a page with a contact email is enough)
- [x] **Usage limits in place** — see below
- [ ] Test account deletion once on a real device before submitting

---

## 6. The thing Apple won't reject you for, but should worry you

**Every user spends your OpenAI credit.** The app is free and unlimited, and the
key is yours. A hundred active users is your bill, growing with your success, and
nothing in the code caps it.

Before public release, do at least one of:

- **Rate limit per user** in the `ai` Edge Function — a daily request ceiling per
  `user_id` is a small change and stops the worst case.
- **Charge**, via In-App Purchase. Apple requires IAP for digital content and
  takes 15–30%. Stripe is not permitted for this.
- **Let users bring their own OpenAI key.** No cost to you, but a poor
  first-run experience and a support burden.

The free Supabase tier will also not survive meaningful traffic.

**Per-user limits are now enforced** in `supabase/migrations/0002_ai_usage_limits.sql`
and checked by the `ai` function before any model call:

| Action | Per user, rolling 24h |
| --- | --- |
| Capture | 100 |
| Chat | 30 |
| Breakdown | 20 |
| Plan | 10 |

Plus 10 requests/minute across all actions, so a stuck retry loop can't run up a
bill. Worst case is roughly $0.43 per user per day; realistic use is under $1 a
month. Limits live in the `claim_ai_quota` function — edit the CASE block and
re-push to change them.

The counters are in a table with RLS enabled and **no policies**, so they are
unreachable from the client. Only the SECURITY DEFINER function can touch them,
which means a user cannot delete their own rows to reset a quota.

**Still do this:** set a hard monthly budget cap in the OpenAI dashboard
(Billing → Limits). It is the only control that survives a bug in the limiter.

Per-user caps stop accidents and casual overuse. They do **not** stop a
determined abuser, because anonymous sign-up is free and unlimited — someone can
mint fresh accounts. If that ever becomes real, require Sign in with Apple for
the AI features and leave capture available to guests.
