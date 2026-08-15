-- On Track — soft-delete tasks so a real Trash / recovery view is possible.
-- Run this in the Supabase dashboard: SQL Editor → New query → paste → Run.

alter table public.tasks
    add column if not exists deleted_at timestamptz;

-- The list view now filters "deleted_at is null" on every read; Trash filters
-- the opposite. Both want an index, not a sequential scan of the whole table.
create index if not exists tasks_user_deleted_idx
    on public.tasks (user_id, deleted_at);

-- A trashed row is still owned by the same user and still governed by the
-- existing owner-only policies — deleting is now an update (setting
-- deleted_at), and the "updatable by owner" policy already covers that. The
-- delete policy stays in place for the permanent purge (30-day sweep or an
-- explicit "Delete Forever"), which remains a real DELETE.
