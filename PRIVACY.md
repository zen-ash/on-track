# Privacy Policy — On Track

**Last updated: 5 August 2026**

> **Before you publish, replace every `[…]` placeholder below.** App Store Connect
> requires a publicly reachable URL for this document — a GitHub Pages site, a
> Gist, or any static host is fine. Do not submit with placeholders in place.

On Track is a todo app. This policy explains exactly what it collects, where that
data goes, and how to delete it.

**Contact:** [YOUR EMAIL ADDRESS]
**Provided by:** [YOUR NAME OR COMPANY]

---

## What is collected

**Your tasks.** The text of everything you capture — titles, notes, due dates,
tags, priorities, and whether a task repeats. This is the content of the app; it
cannot function without it.

**An account identifier.** A random identifier is created for you so your tasks
can sync. If you sign in with Apple, this is linked to the identifier Apple
provides, plus your name and email address if you choose to share them. Apple's
Hide My Email is fully supported. If you continue as a guest, the identifier is
anonymous and is not connected to your name, email, device, or anything else
about you.

**Nothing else.** There is no analytics SDK, no advertising, no crash reporting,
no tracking, and no third-party code of any kind in the app. Your location,
contacts, photos, and device identifiers are never accessed.

## Your voice

**Audio never leaves your device.** Speech is transcribed entirely on your iPhone
using Apple's on-device speech recognition. No recording is uploaded, and no
audio is stored — not on your device, not on our servers, not anywhere.

Only the resulting *text* is treated like any other task you type.

## Where your data goes

**Supabase** hosts the database that stores your tasks, in the United States
(`us-west-2`). Row level security means each account can only ever read or write
its own rows. Supabase acts as our data processor.

**OpenAI** receives task text when a feature needs it: turning what you said into
structured tasks, building a daily plan, answering a question about your list, or
breaking a task into steps. Requests are sent from our server, never from your
phone, and your account identifier is not included.

OpenAI processes this under its API data policy: submissions through the API are
**not used to train its models**, and are retained for a limited period for abuse
monitoring before deletion. See <https://openai.com/policies/api-data-usage-policies>.

If you never use a feature that needs the model, your task text is never sent to
OpenAI. Capture still works offline using on-device parsing.

**No one else.** Your data is never sold, rented, shared for advertising, or
disclosed to anyone, except where we are legally required to do so.

## How long it is kept

Your tasks are stored until you delete them or delete your account. There is no
separate archive and no backup that survives deletion beyond your host's ordinary
short-term backup rotation.

## Deleting everything

Open the menu (☰) → **Account** → **Delete account and all data**.

This permanently removes your account and every task from the server
immediately. It cannot be undone. If you are signed in as a guest, there is no
recovery path whatsoever, because the credential stored on your device *is* the
account.

You can also delete individual tasks at any time by swiping them away.

## Children

On Track is not directed at children and does not knowingly collect data from
anyone under 13.

## Security

Your session credential is stored in the iOS Keychain. All network traffic uses
HTTPS. Our OpenAI key is held on the server and is never present in the app.

## Changes

If this policy changes materially, the updated version will be posted here with a
new date, and the change will be noted in the app's release notes.

## Your rights

Depending on where you live, you may have the right to access, correct, export,
or delete your data. The app already lets you read and delete everything it
holds. For anything else, email [YOUR EMAIL ADDRESS].
