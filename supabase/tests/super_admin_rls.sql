-- ZutLib: super admin security tests (0016, 0017)
--
-- HOW TO RUN: Supabase -> SQL Editor -> New query -> paste this whole file
-- -> Run, after migrations 0016 and 0017. The last result is a table of
-- tests with PASS or FAIL. It creates throwaway accounts, acts as each of
-- them the way the API and the admin-users Edge Function do, and deletes
-- everything it made. Your real accounts are never touched.
--
-- Expectations: error | denied (error or no rows) | rows=N | value=X.
-- Tests marked + are positive controls.
--
-- Accounts:  x = super admin (made with break glass, like the restore
--            script)   a = admin   b = second admin   l = librarian
--            s = student   p = pending student (signed up asking to be a
--            super admin)   i = a person invited during the test

-- ---------------------------------------------------------------- harness
drop table if exists pg_temp.results;
create temp table results (id text, test text, expected text, actual text, outcome text);
grant insert, select on pg_temp.results to public;

create or replace function pg_temp.t(p_id text, p_test text, p_expect text, p_sql text)
returns void language plpgsql as $$
declare n bigint; v text; actual text;
begin
  begin
    if p_expect like 'value=%' then
      execute p_sql into v;
      actual := 'value=' || coalesce(v, 'null');
    elsif p_sql ~* '^\s*select' then
      execute p_sql into n;
      actual := 'rows=' || n;
    else
      execute p_sql;
      get diagnostics n = row_count;
      actual := 'rows=' || n;
    end if;
  exception when others then
    actual := 'error ' || sqlstate || ': ' || sqlerrm;
  end;
  insert into pg_temp.results values (
    p_id, p_test, p_expect, actual,
    case when (p_expect = 'error' and actual like 'error%')
           or (p_expect = 'denied' and (actual like 'error%' or actual = 'rows=0'))
           or actual = p_expect then 'PASS' else 'FAIL' end);
end $$;

-- Acting as a signed-in user, the way PostgREST does.
create or replace function pg_temp.as_user(p_id text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_id, 'role', 'authenticated')::text, false);
end $$;

-- ---------------------------------------------------------------- fixtures
create or replace function pg_temp.cleanup() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', false);
  perform set_config('zutlib.break_glass', 'on', false);
  delete from public.audit_entries
   where target_id in (select id::text from auth.users where email like 'zl-super-%@example.invalid')
      or actor_id in (select id from auth.users where email like 'zl-super-%@example.invalid');
  delete from public.notifications
   where user_id in (select id from auth.users where email like 'zl-super-%@example.invalid');
  delete from public.profiles where email like 'zl-super-%@example.invalid';
  delete from auth.users where email like 'zl-super-%@example.invalid';
  perform set_config('zutlib.break_glass', 'off', false);
end $$;

reset role;
select pg_temp.cleanup();

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000009a0', 'zl-super-x@example.invalid', '{"full_name": "Xena Super"}'),
  ('00000000-0000-4000-8000-0000000009b0', 'zl-super-a@example.invalid', '{"full_name": "Ada Admin"}'),
  ('00000000-0000-4000-8000-0000000009b1', 'zl-super-b@example.invalid', '{"full_name": "Ben Admin"}'),
  ('00000000-0000-4000-8000-0000000009c0', 'zl-super-l@example.invalid', '{"full_name": "Lou Librarian"}'),
  ('00000000-0000-4000-8000-0000000009d0', 'zl-super-s@example.invalid',
   '{"full_name": "Sol Student", "department": "ICT"}'),
  ('00000000-0000-4000-8000-0000000009e0', 'zl-super-p@example.invalid',
   '{"full_name": "Pia Pending", "department": "ICT", "role": "super_admin", "status": "active"}'),
  ('00000000-0000-4000-8000-0000000009f0', 'zl-super-i@example.invalid', '{"full_name": "Ivy Invited"}');

update public.profiles set role = 'admin', status = 'active'
 where id in ('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009b1');
update public.profiles set role = 'librarian', status = 'active' where id = '00000000-0000-4000-8000-0000000009c0';
update public.profiles set status = 'active' where id = '00000000-0000-4000-8000-0000000009d0';

-- ================================================================ G: getting the role
select pg_temp.t('G1', 'Signing up asking to be a super admin makes a pending student', 'value=student pending',
  $q$select role || ' ' || status from public.profiles where id = '00000000-0000-4000-8000-0000000009e0'$q$);
select pg_temp.t('G2', 'Promoting to super admin without break glass (even as the owner)', 'error',
  $q$update public.profiles set role = 'super_admin' where id = '00000000-0000-4000-8000-0000000009a0'$q$);
select pg_temp.t('G3', 'An admin cannot make a super admin through admin_apply', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009d0',
       'set_role', 'super_admin')$q$);
select pg_temp.t('G4', 'Nobody can invite a super admin', 'error',
  $q$select public.admin_after_invite('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009f0',
       'super_admin', 'Ivy Invited', null)$q$);

-- + The break-glass path, as scripts/restore_super_admin.sql uses it.
begin;
select set_config('zutlib.break_glass', 'on', true);
update public.profiles set role = 'super_admin', status = 'active' where id = '00000000-0000-4000-8000-0000000009a0';
commit;
select pg_temp.t('G5', '+ Break glass makes a super admin', 'value=super_admin',
  $q$select role::text from public.profiles where id = '00000000-0000-4000-8000-0000000009a0'$q$);
select pg_temp.t('G6', 'Break glass is off again after its transaction', 'value=false',
  $q$select public.zl_break_glass()::text$q$);

-- ================================================================ W: who is who
select pg_temp.as_user('00000000-0000-4000-8000-0000000009a0');
set role authenticated;
select pg_temp.t('W1', '+ Super admin: is_super_admin()', 'value=true', 'select public.is_super_admin()::text');
select pg_temp.t('W2', '+ Super admin: is_admin()', 'value=true', 'select public.is_admin()::text');
select pg_temp.t('W3', '+ Super admin: is_staff()', 'value=true', 'select public.is_staff()::text');
select pg_temp.t('W4', '+ Super admin reads the audit log', 'value=true',
  'select (count(*) >= 0)::text from public.audit_entries');
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-0000000009b0');
set role authenticated;
select pg_temp.t('W5', 'Admin: is_super_admin() is false', 'value=false', 'select public.is_super_admin()::text');
select pg_temp.t('W6', 'Admin cannot call admin_apply directly', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009d0', 'suspend')$q$);
select pg_temp.t('W7', 'Admin cannot call admin_is_super', 'error',
  $q$select public.admin_is_super('00000000-0000-4000-8000-0000000009b0')$q$);
select pg_temp.t('W8', 'Admin cannot promote themselves by editing their profile', 'denied',
  $q$update public.profiles set role = 'super_admin' where id = '00000000-0000-4000-8000-0000000009b0'$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-0000000009d0');
set role authenticated;
select pg_temp.t('W9', 'Student: is_super_admin() is false', 'value=false', 'select public.is_super_admin()::text');
select pg_temp.t('W10', 'Student cannot call admin_apply', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009b0', 'suspend')$q$);
reset role;
select set_config('request.jwt.claims', '', false);

-- ================================================================ A: what an admin may do
-- (admin_apply is called the way admin-users calls it, with the actor id
-- the function verified from the token.)
select pg_temp.t('A1', '+ Admin suspends a librarian', 'value=suspended',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009c0', 'suspend') ->> 'status'$q$);
select pg_temp.t('A2', '+ Admin reinstates the librarian', 'value=active',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009c0', 'reactivate') ->> 'status'$q$);
select pg_temp.t('A3', '+ Admin suspends a student', 'value=suspended',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009d0', 'suspend') ->> 'status'$q$);
select pg_temp.t('A4', '+ Admin reinstates the student', 'value=active',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009d0', 'reactivate') ->> 'status'$q$);
select pg_temp.t('A5', 'Admin suspends another admin', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009b1', 'suspend')$q$);
select pg_temp.t('A6', 'Admin suspends the super admin', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009a0', 'suspend')$q$);
select pg_temp.t('A7', 'Admin changes a student''s role', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009d0', 'set_role', 'librarian')$q$);
select pg_temp.t('A8', 'Admin removes a student', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009d0', 'remove')$q$);
select pg_temp.t('A9', 'Admin invites an administrator', 'error',
  $q$select public.admin_after_invite('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009f0',
       'admin', 'Ivy Invited', null)$q$);
select pg_temp.t('A10', 'Admin suspends themselves', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009b0', 'suspend')$q$);
select pg_temp.t('A11', 'Admin logs an action on another admin', 'error',
  $q$select public.admin_record('00000000-0000-4000-8000-0000000009b0', 'resend_invite', '00000000-0000-4000-8000-0000000009b1')$q$);
select pg_temp.t('A12', 'Librarian acts as an admin', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009c0', '00000000-0000-4000-8000-0000000009d0', 'suspend')$q$);
select pg_temp.t('A13', '+ Admin approves a pending student', 'value=active',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b0', '00000000-0000-4000-8000-0000000009e0', 'approve') ->> 'status'$q$);

-- ================================================================ S: what only a super admin may do
select pg_temp.t('S1', '+ Super admin invites an administrator', 'value=admin',
  $q$select public.admin_after_invite('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009f0',
       'admin', 'Ivy Invited', null) ->> 'role'$q$);
select pg_temp.t('S2', '+ Super admin suspends an admin', 'value=suspended',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009b1', 'suspend') ->> 'status'$q$);
select pg_temp.t('S3', '+ Super admin reinstates the admin', 'value=active',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009b1', 'reactivate') ->> 'status'$q$);
select pg_temp.t('S4', '+ Super admin makes a student a librarian, with a reason', 'value=librarian',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009d0',
       'set_role', 'librarian', 'Started at the front desk') ->> 'role'$q$);
select pg_temp.t('S5', '+ The reason and the super admin role are in the audit entry', 'value=super_admin Started at the front desk',
  $q$select (detail ->> 'actor_role') || ' ' || (detail ->> 'reason') from public.audit_entries
      where action = 'admin.set_role' and target_id = '00000000-0000-4000-8000-0000000009d0'
      order by occurred_at desc limit 1$q$);
select pg_temp.t('S6', '+ Super admin removes an admin (soft delete)', 'value=removed',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009b1', 'remove',
       null, 'Left the college') ->> 'status'$q$);
select pg_temp.t('S7', 'The removed admin''s profile is still there', 'value=1',
  $q$select count(*)::text from public.profiles where id = '00000000-0000-4000-8000-0000000009b1'$q$);
select pg_temp.t('S8', 'A removed admin can no longer act', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009b1', '00000000-0000-4000-8000-0000000009d0', 'suspend')$q$);
select pg_temp.as_user('00000000-0000-4000-8000-0000000009b1');
set role authenticated;
select pg_temp.t('S9', 'A removed admin: is_admin() is false', 'value=false', 'select public.is_admin()::text');
select pg_temp.t('S10', 'A removed admin reads no audit entries', 'rows=0', 'select count(*) from public.audit_entries');
reset role;
select set_config('request.jwt.claims', '', false);
select pg_temp.t('S11', 'Super admin cannot make anyone a super admin', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009b0', 'set_role', 'super_admin')$q$);
select pg_temp.t('S12', 'Super admin cannot change their own role', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009a0', 'set_role', 'admin')$q$);
select pg_temp.t('S13', 'Super admin cannot suspend themselves', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009a0', 'suspend')$q$);

-- ================================================================ U: the audit log stays as written
select pg_temp.as_user('00000000-0000-4000-8000-0000000009a0');
set role authenticated;
select pg_temp.t('U1', 'Super admin edits an audit entry', 'denied',
  $q$update public.audit_entries set action = 'x' where target_id = '00000000-0000-4000-8000-0000000009d0'$q$);
select pg_temp.t('U2', 'Super admin deletes an audit entry', 'denied',
  $q$delete from public.audit_entries where target_id = '00000000-0000-4000-8000-0000000009d0'$q$);
select pg_temp.t('U3', 'Super admin writes a fake audit entry', 'error',
  $q$insert into public.audit_entries (actor_id, action, target_table, target_id)
     values ('00000000-0000-4000-8000-0000000009b0', 'admin.approve', 'profiles', 'x')$q$);
reset role;
set role service_role;
select pg_temp.t('U4', 'The service role (Edge Functions) edits an audit entry', 'error',
  $q$update public.audit_entries set action = 'x' where target_id = '00000000-0000-4000-8000-0000000009d0'$q$);
select pg_temp.t('U5', 'The service role deletes an audit entry', 'error',
  $q$delete from public.audit_entries where target_id = '00000000-0000-4000-8000-0000000009d0'$q$);
reset role;
select pg_temp.t('U6', '+ The entries are unchanged', 'value=true',
  $q$select (count(*) >= 2 and bool_and(action like 'admin.%'))::text from public.audit_entries
      where target_id = '00000000-0000-4000-8000-0000000009d0'$q$);

-- ================================================================ L: the last super admin
-- On a project that already has its own super admin, the test account is
-- not the last one, so these expect success there instead of a refusal.
create or replace function pg_temp.others() returns int language sql as $$
  select count(*)::int from public.profiles
   where role = 'super_admin' and status = 'active' and email not like 'zl-super-%@example.invalid'
$$;
select pg_temp.t('L1', 'Demote the last super admin (from the dashboard, no break glass)',
  case when pg_temp.others() = 0 then 'error' else 'rows=1' end,
  $q$update public.profiles set role = 'admin' where id = '00000000-0000-4000-8000-0000000009a0'$q$);
select pg_temp.t('L2', 'Suspend the last super admin',
  case when pg_temp.others() = 0 then 'error' else 'rows=0' end,
  $q$update public.profiles set status = 'suspended' where id = '00000000-0000-4000-8000-0000000009a0'
       and role = 'super_admin'$q$);
select pg_temp.t('L3', 'Delete the last super admin',
  case when pg_temp.others() = 0 then 'error' else 'rows=0' end,
  $q$delete from public.profiles where id = '00000000-0000-4000-8000-0000000009a0' and role = 'super_admin'
       and status = 'active'$q$);

-- ================================================================ clean up
reset role;
select pg_temp.cleanup();

-- ---------------------------------------------------------------- results
select id, test, expected, actual, outcome
from pg_temp.results
order by case left(id, 1) when 'G' then 1 when 'W' then 2 when 'A' then 3 when 'S' then 4
                          when 'U' then 5 when 'L' then 6 else 9 end,
         nullif(regexp_replace(id, '\D', '', 'g'), '')::int;
