-- ZutLib — table privileges
-- A row level security policy only ever narrows access; it never grants it.
-- Postgres checks the underlying table privilege first, and without an
-- explicit GRANT here, "authenticated" has none on a table created by
-- plain DDL — every request fails with "permission denied for table x"
-- before RLS is ever evaluated, no matter how permissive the policy is.

grant usage on schema public to authenticated;

grant select, insert, update             on public.roll            to authenticated;
grant select, insert, update             on public.profiles        to authenticated;
grant select, insert, update, delete     on public.resources       to authenticated;
grant select, insert, update             on public.borrow_requests to authenticated;
grant select                             on public.audit_entries   to authenticated;
grant select, update                     on public.notifications   to authenticated;
grant select                             on public.heartbeat       to authenticated;
