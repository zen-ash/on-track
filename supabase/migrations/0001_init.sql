-- On Track — initial schema.
-- Run this in the Supabase dashboard: SQL Editor → New query → paste → Run.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- tasks
-- ---------------------------------------------------------------------------

create table if not exists public.tasks (
    id               uuid primary key default gen_random_uuid(),
    -- Defaults to the caller so a client that omits it still passes RLS.
    user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,

    title            text not null check (char_length(title) between 1 and 500),
    notes            text,
    status           text not null default 'open' check (status in ('open', 'done', 'dropped')),
    priority         int  not null default 0 check (priority between 0 and 3),

    due_at           timestamptz,
    -- False when the user meant "Friday", true when they meant "Friday at 4".
    has_time         boolean not null default false,
    -- RRULE-lite, e.g. FREQ=WEEKLY;BYDAY=MO,WE,FR
    recurrence       text,

    tags             text[] not null default '{}',
    estimate_minutes int check (estimate_minutes is null or estimate_minutes > 0),
    energy           text check (energy is null or energy in ('low', 'medium', 'high')),

    -- Subtasks are tasks. One table, one set of rules.
    parent_id        uuid references public.tasks (id) on delete cascade,
    sort_index       double precision not null default 0,

    completed_at     timestamptz,
    source           text not null default 'manual' check (source in ('voice', 'text', 'ai', 'manual')),
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now()
);

-- The list view always filters by user + status and orders by due date.
create index if not exists tasks_user_status_due_idx
    on public.tasks (user_id, status, due_at);

create index if not exists tasks_parent_idx
    on public.tasks (parent_id)
    where parent_id is not null;

-- ---------------------------------------------------------------------------
-- updated_at
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists tasks_touch_updated_at on public.tasks;
create trigger tasks_touch_updated_at
    before update on public.tasks
    for each row
    execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Row level security
--
-- This is the only thing standing between users' lists, which is why the app
-- can safely ship the anon key and why no query in the client filters by user.
-- ---------------------------------------------------------------------------

alter table public.tasks enable row level security;

drop policy if exists "tasks are readable by their owner"   on public.tasks;
drop policy if exists "tasks are insertable by their owner" on public.tasks;
drop policy if exists "tasks are updatable by their owner"  on public.tasks;
drop policy if exists "tasks are deletable by their owner"  on public.tasks;

create policy "tasks are readable by their owner"
    on public.tasks for select
    using (auth.uid() = user_id);

create policy "tasks are insertable by their owner"
    on public.tasks for insert
    with check (auth.uid() = user_id);

create policy "tasks are updatable by their owner"
    on public.tasks for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "tasks are deletable by their owner"
    on public.tasks for delete
    using (auth.uid() = user_id);
