-- ZutLib: security tests for plan items 2 to 12 (0018 to 0021)
--
-- HOW TO RUN: Supabase -> SQL Editor -> New query -> paste this whole file
-- -> Run, after migrations 0018 to 0021. The last result is a table of
-- tests with PASS or FAIL. It creates throwaway accounts and rows, acts as
-- each account the way the API does, and removes everything it made,
-- including putting the system settings back as they were.
--
-- Expectations: error | denied (error or no rows) | rows=N | value=X.
-- Tests marked + are positive controls.
--
-- Accounts:  x = super admin   a = admin   l = librarian
--            s = student (ICT)   t = student (Engineering)   e = student (ICT)

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


create or replace function pg_temp.as_user(p_id text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_id = '' then '' else json_build_object('sub', p_id, 'role', 'authenticated')::text end, false);
end $$;

-- ---------------------------------------------------------------- fixtures
drop table if exists pg_temp.saved_settings;
create temp table saved_settings as select * from public.settings;

create or replace function pg_temp.cleanup() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', false);
  perform set_config('zutlib.break_glass', 'on', false);
  perform set_config('storage.allow_delete_query', 'true', false);
  delete from public.audit_entries
   where target_id in (select id::text from auth.users where email like 'zl-items-%@example.invalid')
      or actor_id in (select id from auth.users where email like 'zl-items-%@example.invalid')
      or (target_table = 'announcements' and detail ->> 'title' like 'ZLI %')
      or (detail -> 'after' ->> 'title') like 'ZLI %';
  delete from public.announcements where title like 'ZLI %';
  delete from public.borrow_requests where resource_id = '00000000-0000-4000-8000-00000000a1f3';
  delete from public.resources where id = '00000000-0000-4000-8000-00000000a1f3';
  delete from storage.objects where name like '00000000-0000-4000-8000-00000000a1d0/%' or name like '00000000-0000-4000-8000-00000000a1d1/%';
  delete from public.notifications where user_id in (select id from auth.users where email like 'zl-items-%@example.invalid');
  delete from public.profiles where email like 'zl-items-%@example.invalid';
  delete from auth.users where email like 'zl-items-%@example.invalid';
  perform set_config('storage.allow_delete_query', 'false', false);
  perform set_config('zutlib.break_glass', 'off', false);
end $$;

reset role;
select pg_temp.cleanup();

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-00000000a1a0', 'zl-items-x@example.invalid', '{"full_name": "Xia Super"}'),
  ('00000000-0000-4000-8000-00000000a1b0', 'zl-items-a@example.invalid', '{"full_name": "Abe Admin"}'),
  ('00000000-0000-4000-8000-00000000a1c0', 'zl-items-l@example.invalid', '{"full_name": "Lia Librarian"}'),
  ('00000000-0000-4000-8000-00000000a1d0', 'zl-items-s@example.invalid', '{"full_name": "Sue Student", "department": "ICT"}'),
  ('00000000-0000-4000-8000-00000000a1d1', 'zl-items-t@example.invalid', '{"full_name": "Tom Student", "department": "Engineering"}'),
  ('00000000-0000-4000-8000-00000000a1e0', 'zl-items-e@example.invalid', '{"full_name": "Eve Student", "department": "ICT"}');
begin;
select set_config('zutlib.break_glass', 'on', true);
update public.profiles set role = 'super_admin', status = 'active' where id = '00000000-0000-4000-8000-00000000a1a0';
commit;
update public.profiles set role = 'admin', status = 'active' where id = '00000000-0000-4000-8000-00000000a1b0';
update public.profiles set role = 'librarian', status = 'active' where id = '00000000-0000-4000-8000-00000000a1c0';
update public.profiles set status = 'active' where id in ('00000000-0000-4000-8000-00000000a1d0', '00000000-0000-4000-8000-00000000a1d1', '00000000-0000-4000-8000-00000000a1e0');
insert into auth.sessions (id, user_id) values (gen_random_uuid(), '00000000-0000-4000-8000-00000000a1d0'), (gen_random_uuid(), '00000000-0000-4000-8000-00000000a1d0');
insert into public.resources (id, title, type, department, author, is_physical, total_copies, available_copies, is_sample)
values ('00000000-0000-4000-8000-00000000a1f3', 'ZLI Sample book', 'book', 'ICT', 'A. Writer', true, 5, 5, true);
insert into public.study_notes (id, user_id, title, body) values
  ('00000000-0000-4000-8000-00000000a1f1', '00000000-0000-4000-8000-00000000a1d0', 'Sue kit', 'Sue notes'),
  ('00000000-0000-4000-8000-00000000a1f2', '00000000-0000-4000-8000-00000000a1d1', 'Tom kit', 'Tom notes');
insert into storage.objects (bucket_id, name, metadata) values
  ('study-files', '00000000-0000-4000-8000-00000000a1d0/a.pdf', '{"size": 1048576}'),
  ('study-files', '00000000-0000-4000-8000-00000000a1d0/big.pdf', '{"size": 31457280}'),
  ('study-files', '00000000-0000-4000-8000-00000000a1d1/t.pdf', '{"size": 1000}');
update public.settings set loan_days = 14, max_active_borrows = 3, registration_open = true;

-- ================================================================ K: account tools (item 2)
select pg_temp.t('K1', 'Admin edits a student''s details', 'error',
  $q$select public.admin_edit_profile('00000000-0000-4000-8000-00000000a1b0', '00000000-0000-4000-8000-00000000a1d0', 'Sue New', 'ICT', null, 'Typo')$q$);
select pg_temp.t('K2', 'Super admin edits without a reason', 'error',
  $q$select public.admin_edit_profile('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1d0', 'Sue New', 'ICT', null, ' ')$q$);
select pg_temp.t('K3', '+ Super admin edits name, department and student number', 'value=Sue Banda ICT ZUT/2024/01',
  $q$select (r ->> 'full_name') || ' ' || (r ->> 'department') || ' ' || (r ->> 'student_number')
       from (select public.admin_edit_profile('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1d0', ' Sue  Banda ', 'ICT', 'zut/2024/01', 'Name spelling') r) q$q$);
select pg_temp.t('K4', '+ The edit is audited with before and after', 'value=Sue Student -> Sue Banda',
  $q$select (detail -> 'before' ->> 'full_name') || ' -> ' || (detail -> 'after' ->> 'full_name')
       from public.audit_entries where action = 'admin.edit_profile' and target_id = '00000000-0000-4000-8000-00000000a1d0'$q$);
select pg_temp.t('K5', 'Super admin edits their own details through the tool', 'error',
  $q$select public.admin_edit_profile('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1a0', 'Me', null, null, 'Because')$q$);
select pg_temp.t('K6', 'A bad department is refused', 'error',
  $q$select public.admin_edit_profile('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1d1', 'Tom', 'Medicine', null, 'Because')$q$);
select pg_temp.t('K7', 'Admin signs a student out everywhere', 'error',
  $q$select public.admin_revoke_sessions('00000000-0000-4000-8000-00000000a1b0', '00000000-0000-4000-8000-00000000a1d0', 'Lost phone')$q$);
select pg_temp.t('K8', '+ Super admin signs the student out everywhere', 'value=2',
  $q$select public.admin_revoke_sessions('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1d0', 'Lost phone')::text$q$);
select pg_temp.t('K9', '+ No sessions are left', 'rows=0', $q$select count(*) from auth.sessions where user_id = '00000000-0000-4000-8000-00000000a1d0'$q$);
select pg_temp.t('K10', 'Admin records an email change', 'error',
  $q$select public.admin_super_record('00000000-0000-4000-8000-00000000a1b0', '00000000-0000-4000-8000-00000000a1d0', 'change_email', 'Typo')$q$);
select pg_temp.t('K11', '+ Super admin records a password link', 'rows=1',
  $q$select count(*) from (select public.admin_super_record('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1d0', 'password_link', 'Forgot it')) q$q$);
select pg_temp.t('K12', 'Super admin removes without a reason', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1e0', 'remove')$q$);
select pg_temp.t('K13', '+ Super admin removes with a reason', 'value=removed',
  $q$select public.admin_apply('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1e0', 'remove', null, 'Left ZUT') ->> 'status'$q$);
select pg_temp.t('K14', 'Admin restores the removed account', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-00000000a1b0', '00000000-0000-4000-8000-00000000a1e0', 'restore', null, 'Mistake')$q$);
select pg_temp.t('K15', 'Super admin restores without a reason', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1e0', 'restore')$q$);
select pg_temp.t('K16', '+ Super admin restores with a reason', 'value=active',
  $q$select public.admin_apply('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1e0', 'restore', null, 'Removed by mistake') ->> 'status'$q$);
select pg_temp.t('K17', 'Restoring an account that is not removed', 'error',
  $q$select public.admin_apply('00000000-0000-4000-8000-00000000a1a0', '00000000-0000-4000-8000-00000000a1e0', 'restore', null, 'Again')$q$);
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1b0');
set role authenticated;
select pg_temp.t('K18', 'Admin calls an account tool directly', 'error',
  $q$select public.admin_revoke_sessions('00000000-0000-4000-8000-00000000a1b0', '00000000-0000-4000-8000-00000000a1d0', 'x')$q$);
reset role;

-- ================================================================ C: settings (item 3)
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('C1', '+ A student reads the borrowing period', 'value=14', 'select loan_days::text from public.settings');
select pg_temp.t('C2', 'A student changes the settings', 'error', 'select public.admin_set_settings(30, 5, true)');
select pg_temp.t('C3', 'A student updates the table directly', 'denied', 'update public.settings set loan_days = 60');
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1c0');
set role authenticated;
select pg_temp.t('C4', 'A librarian changes the settings', 'error', 'select public.admin_set_settings(30, 5, true)');
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1b0');
set role authenticated;
select pg_temp.t('C5', 'An admin changes the settings', 'error', 'select public.admin_set_settings(30, 5, true)');
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1a0');
set role authenticated;
select pg_temp.t('C6', 'A borrowing period of 0 days is refused', 'error', 'select public.admin_set_settings(0, 1, true)');
select pg_temp.t('C7', '+ Super admin sets 7 days, 1 borrow, registration closed', 'value=7 1 false',
  $q$select loan_days || ' ' || max_active_borrows || ' ' || registration_open
       from public.admin_set_settings(7, 1, false, 'Exam period')$q$);
reset role;
select pg_temp.t('C8', '+ The change is audited with before and after', 'value=14 -> 7',
  $q$select (detail -> 'before' ->> 'loan_days') || ' -> ' || (detail -> 'after' ->> 'loan_days')
       from public.audit_entries where action = 'admin.settings' and actor_id = '00000000-0000-4000-8000-00000000a1a0'$q$);
set role anon;
select pg_temp.t('C9', '+ The sign-up screen can ask whether registration is open', 'value=false',
  'select public.registration_open()::text');
reset role;
select pg_temp.t('C10', 'Signing up while registration is closed', 'error',
  $q$insert into auth.users (id, email) values ('00000000-0000-4000-8000-00000000a1aa', 'zl-items-new@example.invalid')$q$);
select pg_temp.t('C11', '+ An invited person can still join while it is closed', 'rows=1',
  $q$insert into auth.users (id, email, invited_at) values ('00000000-0000-4000-8000-00000000a1ab', 'zl-items-inv@example.invalid', now())$q$);
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('C12', '+ First borrow request (limit 1)', 'rows=1',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number)
     values ('00000000-0000-4000-8000-00000000a1f3', '00000000-0000-4000-8000-00000000a1d0', 'x', 'x')$q$);
select pg_temp.t('C13', 'Second borrow request over the limit', 'error',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number)
     values ('00000000-0000-4000-8000-00000000a1f3', '00000000-0000-4000-8000-00000000a1d0', 'x', 'x')$q$);
reset role;
update public.borrow_requests set status = 'approved', decided_by = '00000000-0000-4000-8000-00000000a1c0', decided_at = now()
 where resource_id = '00000000-0000-4000-8000-00000000a1f3' and student_id = '00000000-0000-4000-8000-00000000a1d0';
set role service_role;
update public.borrow_requests set status = 'collected', due_date = current_date + 100
 where resource_id = '00000000-0000-4000-8000-00000000a1f3' and student_id = '00000000-0000-4000-8000-00000000a1d0';
reset role;
select pg_temp.t('C14', '+ Collecting sets the due date from the borrowing period, whatever was sent', 'value=7',
  $q$select (due_date - public.zl_today())::text from public.borrow_requests
      where resource_id = '00000000-0000-4000-8000-00000000a1f3' and student_id = '00000000-0000-4000-8000-00000000a1d0'$q$);

-- ================================================================ N: announcements (item 10)
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('N1', 'A student posts an announcement directly', 'error',
  $q$insert into public.announcements (title, body) values ('ZLI hack', 'nope')$q$);
select pg_temp.t('N2', 'A student posts through the function', 'error',
  $q$select public.admin_save_announcement(null, 'ZLI hack', 'nope')$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1c0');
set role authenticated;
select pg_temp.t('N3', 'A librarian posts an announcement', 'error',
  $q$select public.admin_save_announcement(null, 'ZLI hack', 'nope')$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1b0');
set role authenticated;
select pg_temp.t('N4', '+ Admin posts one for everyone', 'value=ZLI Library hours',
  $q$select title from public.admin_save_announcement(null, 'ZLI Library hours', 'Open until 20:00 this week.')$q$);
select pg_temp.t('N5', '+ Admin posts one for Engineering only', 'value=Engineering',
  $q$select department from public.admin_save_announcement(null, 'ZLI Lab books', 'New lab manuals.', 'Engineering')$q$);
select pg_temp.t('N6', 'An end date in the past is refused', 'error',
  $q$select public.admin_save_announcement(null, 'ZLI Old', 'Old news.', null, current_date - 5)$q$);
reset role;
insert into public.announcements (title, body, ends_on) values ('ZLI Ended', 'Gone.', current_date - 1);
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('N7', 'An ICT student sees the general one, not Engineering''s or the ended one', 'value=ZLI Library hours',
  $q$select string_agg(title, ',') from public.announcements where title like 'ZLI %'$q$);
select pg_temp.t('N8', 'A student edits an announcement directly', 'denied',
  $q$update public.announcements set title = 'ZLI hacked' where title = 'ZLI Library hours'$q$);
select pg_temp.t('N9', 'A student removes one', 'error',
  $q$select public.admin_remove_announcement(id) from public.announcements where title = 'ZLI Library hours'$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d1');
set role authenticated;
select pg_temp.t('N10', '+ An Engineering student sees both live ones', 'rows=2',
  $q$select count(*) from public.announcements where title like 'ZLI %'$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1b0');
set role authenticated;
select pg_temp.t('N11', '+ Admin edits one', 'value=ZLI Library hours (updated)',
  $q$select title from public.admin_save_announcement(
       (select id from public.announcements where title = 'ZLI Library hours'),
       'ZLI Library hours (updated)', 'Open until 21:00.')$q$);
select pg_temp.t('N12', '+ Admin removes it', 'rows=1',
  $q$select count(*) from (select public.admin_remove_announcement(id) from public.announcements
      where title = 'ZLI Library hours (updated)') q$q$);
reset role;
select pg_temp.t('N13', '+ Create, edit and remove are all in the audit log', 'value=3',
  $q$select count(*)::text from public.audit_entries where actor_id = '00000000-0000-4000-8000-00000000a1b0'
      and action in ('admin.announcement_create', 'admin.announcement_edit', 'admin.announcement_remove')
      and target_id = (select id::text from public.announcements where title = 'ZLI Library hours (updated)')$q$);
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('N14', 'A removed announcement is hidden from students', 'rows=0',
  $q$select count(*) from public.announcements where title like 'ZLI Library%'$q$);
reset role;

-- ================================================================ V: saved resources (item 9)
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('V1', '+ A student saves a book', 'rows=1',
  $q$insert into public.saved_resources (resource_id) values ('00000000-0000-4000-8000-00000000a1f3')$q$);
select pg_temp.t('V2', 'Saving for someone else', 'error',
  $q$insert into public.saved_resources (user_id, resource_id) values ('00000000-0000-4000-8000-00000000a1d1', '00000000-0000-4000-8000-00000000a1f3')$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d1');
set role authenticated;
select pg_temp.t('V3', 'Another student cannot see those saves', 'rows=0', 'select count(*) from public.saved_resources');
select pg_temp.t('V4', 'Another student cannot delete them', 'rows=0',
  $q$delete from public.saved_resources where resource_id = '00000000-0000-4000-8000-00000000a1f3'$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('V5', '+ The student still has the save, and removes it', 'rows=1',
  $q$delete from public.saved_resources where resource_id = '00000000-0000-4000-8000-00000000a1f3'$q$);
reset role;

-- ================================================================ Q: kit sources (item 7)
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('Q1', '+ Student A adds typed text to her kit', 'rows=1',
  $q$insert into public.study_note_sources (note_id, kind, label, body) values ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Formulas', 'V = IR')$q$);
select pg_temp.t('Q2', '+ and an uploaded PDF from her folder', 'rows=1',
  $q$insert into public.study_note_sources (note_id, kind, label, file_path, file_name)
     values ('00000000-0000-4000-8000-00000000a1f1', 'upload', 'a.pdf', '00000000-0000-4000-8000-00000000a1d0/a.pdf', 'a.pdf')$q$);
select pg_temp.t('Q3', '+ The PDF''s size is recorded by the database', 'value=1048576',
  $q$select file_bytes::text from public.study_note_sources where note_id = '00000000-0000-4000-8000-00000000a1f1' and kind = 'upload'$q$);
select pg_temp.t('Q4', 'A PDF from another student''s folder', 'error',
  $q$insert into public.study_note_sources (note_id, kind, label, file_path, file_name)
     values ('00000000-0000-4000-8000-00000000a1f1', 'upload', 't.pdf', '00000000-0000-4000-8000-00000000a1d1/t.pdf', 't.pdf')$q$);
select pg_temp.t('Q5', 'A PDF that would take the kit over 30 MB', 'error',
  $q$insert into public.study_note_sources (note_id, kind, label, file_path, file_name)
     values ('00000000-0000-4000-8000-00000000a1f1', 'upload', 'big.pdf', '00000000-0000-4000-8000-00000000a1d0/big.pdf', 'big.pdf')$q$);
select pg_temp.t('Q6', 'Adding to student B''s kit', 'error',
  $q$insert into public.study_note_sources (note_id, kind, label, body) values ('00000000-0000-4000-8000-00000000a1f2', 'text', 'x', 'x')$q$);
select pg_temp.t('Q7', 'A link that is not a YouTube watch link', 'error',
  $q$insert into public.study_note_sources (note_id, kind, label, youtube_url) values ('00000000-0000-4000-8000-00000000a1f1', 'youtube', 'v', 'https://evil.example/v')$q$);
insert into public.study_note_sources (note_id, kind, label, body) values
  ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Three', '3'), ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Four', '4'), ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Five', '5'),
  ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Six', '6'), ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Seven', '7'), ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Eight', '8'),
  ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Nine', '9'), ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Ten', '10');
-- Since 0022 a kit holds up to 10 sources.
select pg_temp.t('Q8', 'An eleventh source', 'error',
  $q$insert into public.study_note_sources (note_id, kind, label, body) values ('00000000-0000-4000-8000-00000000a1f1', 'text', 'Eleven', '11')$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d1');
set role authenticated;
select pg_temp.t('Q9', 'Student B cannot see student A''s sources', 'rows=0',
  $q$select count(*) from public.study_note_sources where note_id = '00000000-0000-4000-8000-00000000a1f1'$q$);
select pg_temp.t('Q10', 'Student B cannot delete them', 'rows=0',
  $q$delete from public.study_note_sources where note_id = '00000000-0000-4000-8000-00000000a1f1'$q$);
select pg_temp.t('Q11', 'Student B cannot clear A''s main source', 'error',
  $q$select public.study_remove_main_source('00000000-0000-4000-8000-00000000a1f1')$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1b0');
set role authenticated;
select pg_temp.t('Q12', 'Even an admin cannot read a student''s sources', 'rows=0',
  $q$select count(*) from public.study_note_sources where note_id = '00000000-0000-4000-8000-00000000a1f1'$q$);
reset role;
select pg_temp.t('Q13', '+ AI help reads every source', 'value=10',
  $q$select jsonb_array_length(public.study_ai_prepare('00000000-0000-4000-8000-00000000a1d0', '00000000-0000-4000-8000-00000000a1f1', 'kit') -> 'sources')::text$q$);
select pg_temp.t('Q14', 'AI help for B cannot read A''s kit', 'value=not_found',
  $q$select public.study_ai_prepare('00000000-0000-4000-8000-00000000a1d1', '00000000-0000-4000-8000-00000000a1f1', 'kit') ->> 'error'$q$);

-- ================================================================ D: dashboards and badges (items 4, 5, 11)
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('D1', 'A student opens the admin overview', 'error', $q$select public.admin_dashboard('week')$q$);
select pg_temp.t('D2', 'A student opens librarian Today', 'error', 'select public.librarian_today()');
select pg_temp.t('D3', 'A student reads the drawer badges', 'error', 'select public.admin_badges()');
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1c0');
set role authenticated;
select pg_temp.t('D4', 'A librarian opens the admin overview', 'error', $q$select public.admin_dashboard('week')$q$);
select pg_temp.t('D5', '+ A librarian opens Today', 'value=true',
  $q$select (public.librarian_today() ? 'low_stock')::text$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1b0');
set role authenticated;
select pg_temp.t('D6', '+ Admin overview has 8 weeks of trend', 'value=8',
  $q$select jsonb_array_length(public.admin_dashboard('week') -> 'trend')::text$q$);
select pg_temp.t('D7', '+ and 6 months on the Month option', 'value=6',
  $q$select jsonb_array_length(public.admin_dashboard('month') -> 'trend')::text$q$);
select pg_temp.t('D8', '+ Admin reads the badges', 'value=true', $q$select (public.admin_badges() ? 'overdue')::text$q$);
reset role;

-- ================================================================ W: View as (item 12)
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1b0');
set role authenticated;
select pg_temp.t('W1', 'An admin uses View as', 'error', $q$select public.view_as_start('00000000-0000-4000-8000-00000000a1d0')$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1d0');
set role authenticated;
select pg_temp.t('W2', 'A student uses View as', 'error', $q$select public.view_as_start('00000000-0000-4000-8000-00000000a1d1')$q$);
reset role;
select pg_temp.as_user('00000000-0000-4000-8000-00000000a1a0');
set role authenticated;
select pg_temp.t('W3', '+ Super admin views as a student', 'value=Sue Banda',
  $q$select public.view_as_start('00000000-0000-4000-8000-00000000a1d0') -> 'profile' ->> 'full_name'$q$);
select pg_temp.t('W4', 'The picture never includes study notes or kits', 'value=false',
  $q$select (d::text ilike '%Sue kit%' or d::text ilike '%Sue notes%' or d ? 'notes' or d ? 'kits')::text
       from (select public.view_as_data('00000000-0000-4000-8000-00000000a1d0') d) q$q$);
select pg_temp.t('W5', 'View as an administrator', 'error', $q$select public.view_as_start('00000000-0000-4000-8000-00000000a1b0')$q$);
select pg_temp.t('W6', 'View as yourself', 'error', $q$select public.view_as_start('00000000-0000-4000-8000-00000000a1a0')$q$);
select pg_temp.t('W7', '+ View as a librarian shows the library''s day', 'value=true',
  $q$select (public.view_as_start('00000000-0000-4000-8000-00000000a1c0') -> 'library' ? 'waiting')::text$q$);
select pg_temp.t('W8', '+ Ending the session', 'rows=1', $q$select count(*) from (select public.view_as_end('00000000-0000-4000-8000-00000000a1d0')) q$q$);
reset role;
select pg_temp.t('W9', '+ Start and end are both audited', 'value=admin.view_as_end,admin.view_as_start',
  $q$select string_agg(distinct action, ',' order by action) from public.audit_entries
      where actor_id = '00000000-0000-4000-8000-00000000a1a0' and target_id = '00000000-0000-4000-8000-00000000a1d0' and action like 'admin.view_as%'$q$);

-- ================================================================ clean up
reset role;
update public.settings s set loan_days = o.loan_days, max_active_borrows = o.max_active_borrows,
       registration_open = o.registration_open, updated_by = o.updated_by, updated_at = o.updated_at
  from pg_temp.saved_settings o;
select pg_temp.cleanup();

-- ---------------------------------------------------------------- results
select id, test, expected, actual, outcome
from pg_temp.results
order by case left(id, 1) when 'K' then 1 when 'C' then 2 when 'N' then 3 when 'V' then 4
                          when 'Q' then 5 when 'D' then 6 when 'W' then 7 else 9 end,
         nullif(regexp_replace(id, '\D', '', 'g'), '')::int;
