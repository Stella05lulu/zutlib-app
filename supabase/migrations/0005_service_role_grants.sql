-- ZutLib — service role privileges
-- The edge functions (register, decide-request) run under the service role
-- and are meant to bypass row level security entirely — but bypassing RLS
-- only skips policy checks, it does not substitute for the underlying
-- table privilege. This project never had the standard default privileges
-- set up for any role (see 0004_grants.sql), so service_role has none
-- either: every admin.from(...) call in an edge function was failing with
-- "permission denied for table x" before RLS ever entered the picture.

grant usage on schema public to service_role;
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant all privileges on all functions in schema public to service_role;

alter default privileges in schema public
  grant all privileges on tables to service_role;
alter default privileges in schema public
  grant all privileges on sequences to service_role;
alter default privileges in schema public
  grant all privileges on functions to service_role;
