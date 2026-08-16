-- On Track — Focus: track time against user-defined categories.
-- Run this in the Supabase dashboard: SQL Editor → New query → paste → Run.

-- ---------------------------------------------------------------------------
-- focus_tracks
-- ---------------------------------------------------------------------------

create table if not exists public.focus_tracks (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,

    name         text not null check (char_length(name) between 1 and 60),
    sort_index   double precision not null default 0,
    -- Archived, not deleted, so a session logged against it keeps a real name.
    archived_at  timestamptz,

    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

drop trigger if exists focus_tracks_touch_updated_at on public.focus_tracks;
create trigger focus_tracks_touch_updated_at
    before update on public.focus_tracks
    for each row
    execute function public.touch_updated_at();

alter table public.focus_tracks enable row level security;

drop policy if exists "focus_tracks are readable by their owner"   on public.focus_tracks;
drop policy if exists "focus_tracks are insertable by their owner" on public.focus_tracks;
drop policy if exists "focus_tracks are updatable by their owner"  on public.focus_tracks;
drop policy if exists "focus_tracks are deletable by their owner"  on public.focus_tracks;

create policy "focus_tracks are readable by their owner"
    on public.focus_tracks for select
    using (auth.uid() = user_id);

create policy "focus_tracks are insertable by their owner"
    on public.focus_tracks for insert
    with check (auth.uid() = user_id);

create policy "focus_tracks are updatable by their owner"
    on public.focus_tracks for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "focus_tracks are deletable by their owner"
    on public.focus_tracks for delete
    using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- focus_sessions
-- ---------------------------------------------------------------------------

create table if not exists public.focus_sessions (
    id                  uuid primary key default gen_random_uuid(),
    user_id             uuid not null default auth.uid() references auth.users (id) on delete cascade,
    track_id            uuid not null references public.focus_tracks (id) on delete cascade,

    started_at          timestamptz not null,
    -- Null only for the brief window before a session is finalised; nothing
    -- reads a focus_sessions row from the server until it's been stopped.
    ended_at            timestamptz,
    accumulated_seconds integer not null default 0 check (accumulated_seconds >= 0),
    note                text,

    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);

-- Today's totals query filters by user + started_at.
create index if not exists focus_sessions_user_started_idx
    on public.focus_sessions (user_id, started_at);

drop trigger if exists focus_sessions_touch_updated_at on public.focus_sessions;
create trigger focus_sessions_touch_updated_at
    before update on public.focus_sessions
    for each row
    execute function public.touch_updated_at();

alter table public.focus_sessions enable row level security;

drop policy if exists "focus_sessions are readable by their owner"   on public.focus_sessions;
drop policy if exists "focus_sessions are insertable by their owner" on public.focus_sessions;
drop policy if exists "focus_sessions are updatable by their owner"  on public.focus_sessions;
drop policy if exists "focus_sessions are deletable by their owner"  on public.focus_sessions;

create policy "focus_sessions are readable by their owner"
    on public.focus_sessions for select
    using (auth.uid() = user_id);

create policy "focus_sessions are insertable by their owner"
    on public.focus_sessions for insert
    with check (auth.uid() = user_id);

create policy "focus_sessions are updatable by their owner"
    on public.focus_sessions for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "focus_sessions are deletable by their owner"
    on public.focus_sessions for delete
    using (auth.uid() = user_id);
