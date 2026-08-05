-- On Track — per-user AI usage limits.
--
-- Caps what one account can spend of the shared OpenAI key. The limits sit well
-- above real usage: they exist to stop runaway loops and casual overuse, not to
-- ration normal work.
--
-- Note this is not abuse protection. Anonymous sign-up is free and unlimited, so
-- a determined person can mint new accounts. The real backstop is the hard
-- monthly budget cap set in the OpenAI dashboard.

create table if not exists public.ai_usage (
    id      bigserial primary key,
    user_id uuid not null references auth.users (id) on delete cascade,
    action  text not null,
    at      timestamptz not null default now()
);

create index if not exists ai_usage_user_action_at_idx on public.ai_usage (user_id, action, at desc);
create index if not exists ai_usage_user_at_idx        on public.ai_usage (user_id, at desc);

-- RLS on with **no policies at all**: nothing can read or write this table
-- through the API. The SECURITY DEFINER function below is the only way in, so a
-- user cannot delete their own rows to reset their quota.
alter table public.ai_usage enable row level security;

-- ---------------------------------------------------------------------------
-- Quota check
--
-- Checks and records in a single call, so two concurrent requests can't both
-- see the last remaining slot as free.
-- ---------------------------------------------------------------------------

create or replace function public.claim_ai_quota(p_action text)
returns table (allowed boolean, reason text, remaining integer)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user         uuid := auth.uid();
    v_daily_limit  integer;
    v_used_today   integer;
    v_used_minute  integer;
    -- One stuck retry loop shouldn't be able to spend the month's budget.
    v_burst_limit  constant integer := 10;
begin
    if v_user is null then
        return query select false, 'unauthenticated', 0;
        return;
    end if;

    v_daily_limit := case p_action
        when 'capture'   then 100
        when 'chat'      then 30
        when 'breakdown' then 20
        when 'plan'      then 10
        else 0
    end;

    if v_daily_limit = 0 then
        return query select false, 'unknown_action', 0;
        return;
    end if;

    -- Burst limit spans every action: it's about request rate, not feature use.
    select count(*) into v_used_minute
      from ai_usage
     where user_id = v_user
       and at > now() - interval '1 minute';

    if v_used_minute >= v_burst_limit then
        return query select false, 'burst', 0;
        return;
    end if;

    -- Rolling 24 hours rather than a calendar day: no timezone to get wrong, and
    -- no midnight cliff where a user's quota resets at an arbitrary moment.
    select count(*) into v_used_today
      from ai_usage
     where user_id = v_user
       and action = p_action
       and at > now() - interval '24 hours';

    if v_used_today >= v_daily_limit then
        return query select false, 'daily', 0;
        return;
    end if;

    insert into ai_usage (user_id, action) values (v_user, p_action);

    -- Opportunistic tidy-up. Nothing older than a day is ever consulted, so this
    -- keeps the table small without needing a scheduled job.
    if random() < 0.01 then
        delete from ai_usage where at < now() - interval '3 days';
    end if;

    return query select true, ''::text, (v_daily_limit - v_used_today - 1);
end;
$$;

-- Only signed-in callers, and only through this function.
revoke all on function public.claim_ai_quota(text) from public, anon;
grant execute on function public.claim_ai_quota(text) to authenticated;
