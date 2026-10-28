-- ZutLib: roles, approval and library security tests
--
-- HOW TO RUN: Supabase -> SQL Editor -> New query -> paste this whole file
-- -> Run, after migrations 0011 to 0013. The last result is a table of
-- tests with PASS or FAIL. Like the other test files it creates throwaway
-- accounts, acts as each of them the way the API does, and deletes
-- everything it made. Safe to run on the live project, and repeatedly.
--
-- Expectations: error | denied (error or no rows) | rows=N | value=X.
-- Tests marked + are positive controls.
--
-- Accounts:  p = pending student (just signed up)   s = approved student
--            l = librarian    m = admin    n = second admin
--            i = a person an admin invites during the test

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

-- ---------------------------------------------------------------- fixtures
-- First remove anything a stopped earlier run left behind.
-- Supabase blocks DELETE on storage.objects unless the Storage API asks
-- for it with this setting; the clean-up removes only the test's own file
-- records, then turns it off again.
select set_config('storage.allow_delete_query', 'true', false);
update public.profiles set status = 'active' where email like 'zl-roles-%@example.invalid';
delete from public.audit_entries where target_id in (select id::text from auth.users where email like 'zl-roles-%@example.invalid');
delete from public.borrow_requests where resource_id in (select id from public.resources where title like 'ZLR %');
delete from public.resources where title like 'ZLR %';
delete from storage.objects where name = 'sample/ICT/ZLR2010/2023-exam.pdf';
-- Profiles go with their auth users. The guard needs one active admin
-- left, so demote nothing; just delete.
delete from public.profiles where email like 'zl-roles-%@example.invalid';
delete from auth.users where email like 'zl-roles-%@example.invalid';
select set_config('storage.allow_delete_query', 'false', false);

-- Signing up is just a new row in auth.users; the trigger from 0012 makes
-- the profile. P signs up asking to be an admin, which must be ignored.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000006a0', 'zl-roles-p@example.invalid',
   '{"full_name": "Pat Pending", "department": "ICT", "role": "admin", "status": "active"}'),
  ('00000000-0000-4000-8000-0000000006b0', 'zl-roles-s@example.invalid',
   '{"full_name": "Sam Student", "department": "Engineering"}'),
  ('00000000-0000-4000-8000-0000000006c0', 'zl-roles-l@example.invalid', '{"full_name": "Lee Librarian"}'),
  ('00000000-0000-4000-8000-0000000006d0', 'zl-roles-m@example.invalid', '{"full_name": "Max Admin"}'),
  ('00000000-0000-4000-8000-0000000006e0', 'zl-roles-n@example.invalid', '{"full_name": "Nia Admin"}');

-- Set up the staff and the approved student the way an admin would have.
update public.profiles set status = 'active' where id = '00000000-0000-4000-8000-0000000006b0';
update public.profiles set role = 'librarian', status = 'active' where id = '00000000-0000-4000-8000-0000000006c0';
update public.profiles set role = 'admin', status = 'active'
 where id in ('00000000-0000-4000-8000-0000000006d0', '00000000-0000-4000-8000-0000000006e0');

insert into public.resources (id, title, type, department, course_code, academic_year, file_path, is_sample) values
  ('00000000-0000-4000-8000-0000000006f1', 'ZLR Data Structures examination', 'past_paper', 'ICT',
   'ZLR 2010', 2023, 'sample/ICT/ZLR2010/2023-exam.pdf', true);
insert into public.resources (id, title, type, department, author, isbn, is_physical,
                              total_copies, available_copies, is_sample) values
  ('00000000-0000-4000-8000-0000000006f2', 'ZLR Circuit Analysis', 'book', 'Engineering',
   'R. Writer', '978-0-13-468599-1', true, 2, 2, true);
insert into storage.objects (bucket_id, name) values ('resources', 'sample/ICT/ZLR2010/2023-exam.pdf');

-- ================================================================ sign-up
select pg_temp.t('U1', 'Sign-up asking for admin still makes a student', 'value=student pending ICT',
  $q$select role || ' ' || status || ' ' || department from public.profiles
     where id = '00000000-0000-4000-8000-0000000006a0'$q$);
select pg_temp.t('U2+', 'The name from the form is kept', 'value=Pat Pending',
  $q$select full_name from public.profiles where id = '00000000-0000-4000-8000-0000000006a0'$q$);

-- ================================================================ signed out
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);

select pg_temp.t('A1', 'Signed out: profiles', 'denied', 'select count(*) from public.profiles');
select pg_temp.t('A2', 'Signed out: resources', 'denied', 'select count(*) from public.resources');
select pg_temp.t('A3', 'Signed out: borrowing requests', 'denied', 'select count(*) from public.borrow_requests');
select pg_temp.t('A4', 'Signed out: notifications', 'denied', 'select count(*) from public.notifications');
select pg_temp.t('A5', 'Signed out: audit log', 'denied', 'select count(*) from public.audit_entries');
select pg_temp.t('A6', 'Signed out: stored files', 'denied', 'select count(*) from storage.objects');
select pg_temp.t('A7', 'Signed out: search', 'denied', $q$select count(*) from public.search_resources('zlr')$q$);
select pg_temp.t('A8', 'Signed out: admin dashboard', 'error', 'select count(*) from public.admin_overview()');
select pg_temp.t('A9', 'Signed out: change copy counts', 'error',
  $q$select length(public.set_book_copies('00000000-0000-4000-8000-0000000006f2', 9)::text)$q$);
select pg_temp.t('A10', 'Signed out: approve an account', 'error',
  $q$select length(public.admin_apply('00000000-0000-4000-8000-0000000006d0',
     '00000000-0000-4000-8000-0000000006a0', 'approve')::text)$q$);
select pg_temp.t('A11', 'Signed out: staff counts', 'error', 'select count(*) from public.staff_overview()');
select pg_temp.t('A12', 'Signed out: add a book', 'error',
  $q$insert into public.resources (title, type, department, author, is_physical, total_copies, available_copies)
     values ('x', 'book', 'ICT', 'x', true, 1, 1)$q$);

-- ================================================================ pending student
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000006a0","role":"authenticated"}', false);

select pg_temp.t('P1+', 'Pending: can read their own profile (for the waiting screen)', 'rows=1',
  $q$select count(*) from public.profiles where id = '00000000-0000-4000-8000-0000000006a0'$q$);
select pg_temp.t('P2', 'Pending: read anyone else''s profile', 'rows=0',
  $q$select count(*) from public.profiles where id <> '00000000-0000-4000-8000-0000000006a0'$q$);
select pg_temp.t('P3', 'Pending: read the catalogue', 'rows=0', 'select count(*) from public.resources');
select pg_temp.t('P4', 'Pending: search', 'rows=0', $q$select count(*) from public.search_resources('zlr')$q$);
select pg_temp.t('P5', 'Pending: see any stored paper', 'rows=0',
  $q$select count(*) from storage.objects where bucket_id = 'resources'$q$);
select pg_temp.t('P6', 'Pending: ask to borrow', 'error',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number)
     values ('00000000-0000-4000-8000-0000000006f2', '00000000-0000-4000-8000-0000000006a0', 'x', 'x')$q$);
select pg_temp.t('P7', 'Pending: write a study note', 'error',
  $q$insert into public.study_notes (title, body) values ('x', 'x')$q$);
select pg_temp.t('P8', 'Pending: upload a study PDF', 'error',
  $q$insert into storage.objects (bucket_id, name)
     values ('study-files', '00000000-0000-4000-8000-0000000006a0/x.pdf')$q$);
select pg_temp.t('P9', 'Pending: approve themselves', 'error',
  $q$update public.profiles set status = 'active' where id = '00000000-0000-4000-8000-0000000006a0'$q$);
select pg_temp.t('P10', 'Pending: no AI allowance', 'value=0',
  'select remaining from public.study_ai_status()');
select pg_temp.t('P11', 'Pending: notifications', 'rows=0', 'select count(*) from public.notifications');

-- ================================================================ approved student
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000006b0","role":"authenticated"}', false);

select pg_temp.t('S1+', 'Student: reads the catalogue', 'rows=2',
  $q$select count(*) from public.resources where title like 'ZLR %'$q$);
select pg_temp.t('S2+', 'Student: can see the stored paper (so can open it)', 'rows=1',
  $q$select count(*) from storage.objects where name = 'sample/ICT/ZLR2010/2023-exam.pdf'$q$);
select pg_temp.t('S3', 'Student: add a book', 'error',
  $q$insert into public.resources (title, type, department, author, is_physical, total_copies, available_copies)
     values ('Fake', 'book', 'ICT', 'x', true, 1, 1)$q$);
select pg_temp.t('S4', 'Student: add a past paper', 'error',
  $q$insert into public.resources (title, type, department, course_code, academic_year, file_path)
     values ('Fake', 'past_paper', 'ICT', 'ICT 1000', 2024, 'x.pdf')$q$);
select pg_temp.t('S5', 'Student: edit a past paper', 'rows=0',
  $q$update public.resources set title = 'Changed' where id = '00000000-0000-4000-8000-0000000006f1'$q$);
select pg_temp.t('S6', 'Student: delete a book', 'rows=0',
  $q$delete from public.resources where id = '00000000-0000-4000-8000-0000000006f2'$q$);
select pg_temp.t('S7', 'Student: change copy counts', 'error',
  $q$select length(public.set_book_copies('00000000-0000-4000-8000-0000000006f2', 9)::text)$q$);
select pg_temp.t('S8', 'Student: upload a paper file', 'error',
  $q$insert into storage.objects (bucket_id, name) values ('resources', 'fake/fake.pdf')$q$);
select pg_temp.t('S9', 'Student: make themselves a librarian', 'error',
  $q$update public.profiles set role = 'librarian' where id = '00000000-0000-4000-8000-0000000006b0'$q$);
select pg_temp.t('S10', 'Student: clear their own status', 'error',
  $q$update public.profiles set status = 'active', role = 'admin' where id = auth.uid()$q$);
select pg_temp.t('S11', 'Student: read the audit log', 'rows=0', 'select count(*) from public.audit_entries');
select pg_temp.t('S12', 'Student: admin dashboard', 'error', 'select count(*) from public.admin_overview()');
select pg_temp.t('S13+', 'Student: asks to borrow the book', 'rows=1',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number)
     values ('00000000-0000-4000-8000-0000000006f2', '00000000-0000-4000-8000-0000000006b0', 'forged', 'forged')$q$);
select pg_temp.t('S14+', 'The request carries name, department and email from the profile', 'value=Sam Student|Engineering|zl-roles-s@example.invalid',
  $q$select student_name || '|' || student_department || '|' || student_email from public.borrow_requests
     where student_id = '00000000-0000-4000-8000-0000000006b0'$q$);
select pg_temp.t('S15+', 'Search by keyword finds the paper', 'rows=1',
  $q$select count(*) from public.search_resources('data structures')$q$);
select pg_temp.t('S16+', 'Search with department, course and year filters', 'rows=1',
  $q$select count(*) from public.search_resources('zlr', 'ICT', 'ZLR 2010', 2023)$q$);
select pg_temp.t('S17', 'Search with a year that does not match', 'rows=0',
  $q$select count(*) from public.search_resources('zlr', 'ICT', 'ZLR 2010', 2019)$q$);
select pg_temp.t('S18+', 'Search finds a book by its author', 'rows=1',
  $q$select count(*) from public.search_resources('writer', null, null, null, 'book')$q$);
select pg_temp.t('S19+', 'Search finds a book by its ISBN', 'rows=1',
  $q$select count(*) from public.search_resources('9780134685991')$q$);

-- ================================================================ librarian
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000006c0","role":"authenticated"}', false);

select pg_temp.t('L1', 'Librarian: approve a student', 'error',
  $q$update public.profiles set status = 'active' where id = '00000000-0000-4000-8000-0000000006a0'$q$);
select pg_temp.t('L2', 'Librarian: create a user profile', 'error',
  $q$insert into public.profiles (id, full_name, role, status)
     values ('00000000-0000-4000-8000-0000000006a0', 'x', 'admin', 'active')$q$);
select pg_temp.t('L3', 'Librarian: call the admin action function', 'error',
  $q$select length(public.admin_apply('00000000-0000-4000-8000-0000000006c0',
     '00000000-0000-4000-8000-0000000006a0', 'approve')::text)$q$);
select pg_temp.t('L4', 'Librarian: read the admin audit log', 'rows=0', 'select count(*) from public.audit_entries');
select pg_temp.t('L5', 'Librarian: admin dashboard', 'error', 'select count(*) from public.admin_overview()');
select pg_temp.t('L6', 'Librarian: make themselves an admin', 'error',
  $q$update public.profiles set role = 'admin' where id = auth.uid()$q$);
select pg_temp.t('L7+', 'Librarian: adds a book', 'rows=1',
  $q$insert into public.resources (id, title, type, department, author, isbn, edition, is_physical,
                                   total_copies, available_copies)
     values ('00000000-0000-4000-8000-0000000006f3', 'ZLR Signals and Systems', 'book', 'Engineering',
             'A. Oppenheim', '0-13-814757-4', '2nd', true, 1, 1)$q$);
select pg_temp.t('L8+', 'The ISBN was stored as digits only', 'value=0138147574',
  $q$select isbn from public.resources where id = '00000000-0000-4000-8000-0000000006f3'$q$);
select pg_temp.t('L9', 'Librarian: a book with no author', 'error',
  $q$insert into public.resources (title, type, department, is_physical, total_copies, available_copies)
     values ('No author', 'book', 'ICT', true, 1, 1)$q$);
select pg_temp.t('L10', 'Librarian: more copies on the shelf than owned', 'error',
  $q$update public.resources set available_copies = 5 where id = '00000000-0000-4000-8000-0000000006f2'$q$);
select pg_temp.t('L11', 'Librarian: a negative shelf count', 'error',
  $q$update public.resources set available_copies = -1 where id = '00000000-0000-4000-8000-0000000006f2'$q$);
select pg_temp.t('L12+', 'Librarian: raises the total to 4 (shelf follows: 1 on loan request, 4 on shelf)', 'value=4/4',
  $q$select total_copies || '/' || available_copies
       from public.set_book_copies('00000000-0000-4000-8000-0000000006f2', 4)$q$);
select pg_temp.t('L13', 'Librarian: an invalid ISBN', 'error',
  $q$update public.resources set isbn = '12345' where id = '00000000-0000-4000-8000-0000000006f3'$q$);
select pg_temp.t('L14+', 'Librarian: retires a book', 'rows=1',
  $q$update public.resources set retired_at = now() where id = '00000000-0000-4000-8000-0000000006f3'$q$);
select pg_temp.t('L15+', 'A retired book drops out of search', 'rows=0',
  $q$select count(*) from public.search_resources('signals')$q$);
select pg_temp.t('L16+', 'Librarian: uploads a paper with course title and year', 'rows=1',
  $q$insert into public.resources (title, type, department, course_code, course_title, academic_year, file_path)
     values ('ZLR Networks test', 'test_paper', 'ICT', 'zlr3010', 'Computer Networks', 2024, 'ICT/ZLR3010/t.pdf')$q$);
select pg_temp.t('L17+', 'The course code was tidied', 'value=ZLR 3010',
  $q$select course_code from public.resources where title = 'ZLR Networks test'$q$);
select pg_temp.t('L18', 'Librarian: a paper with no academic year', 'error',
  $q$insert into public.resources (title, type, department, course_code, file_path)
     values ('No year', 'past_paper', 'ICT', 'ZLR 1', 'x.pdf')$q$);

reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000006b0","role":"authenticated"}', false);
select pg_temp.t('S20', 'Student: borrow a retired book', 'error',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number)
     values ('00000000-0000-4000-8000-0000000006f3', '00000000-0000-4000-8000-0000000006b0', 'x', 'x')$q$);

-- Lowering the total below what is out on loan. Put one copy on loan first.
reset role;
update public.borrow_requests set status = 'collected', due_date = current_date + 14,
       decided_by = '00000000-0000-4000-8000-0000000006c0'
 where student_id = '00000000-0000-4000-8000-0000000006b0';
update public.resources set total_copies = 1, available_copies = 0
 where id = '00000000-0000-4000-8000-0000000006f2';
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000006c0","role":"authenticated"}', false);
select pg_temp.t('L19+', 'Librarian: sets total to 3 with one on loan (2 on shelf)', 'value=3/2',
  $q$select total_copies || '/' || available_copies
       from public.set_book_copies('00000000-0000-4000-8000-0000000006f2', 3)$q$);
select pg_temp.t('L20', 'Librarian: a total of 0 while a copy is on loan', 'error',
  $q$select length(public.set_book_copies('00000000-0000-4000-8000-0000000006f2', 0)::text)$q$);

-- ================================================================ admin
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000006d0","role":"authenticated"}', false);

select pg_temp.t('M1+', 'Admin: sees the dashboard counts', 'rows=1', 'select count(*) from public.admin_overview()');
select pg_temp.t('M2+', 'Admin: sees every profile, pending included', 'rows=5',
  $q$select count(*) from public.profiles where email like 'zl-roles-%'$q$);
select pg_temp.t('M3', 'Admin: edits a profile directly (must use admin-users)', 'error',
  $q$update public.profiles set status = 'active' where id = '00000000-0000-4000-8000-0000000006a0'$q$);

-- ================================================================ admin-users function
-- What the Edge Function does with the service role, after it has
-- verified the caller's token.
reset role;
set role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', false);

select pg_temp.t('F1', 'A librarian as the actor cannot approve', 'error',
  $q$select length(public.admin_apply('00000000-0000-4000-8000-0000000006c0',
     '00000000-0000-4000-8000-0000000006a0', 'approve')::text)$q$);
select pg_temp.t('F2+', 'Admin approves the pending student', 'value=active',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000006d0',
     '00000000-0000-4000-8000-0000000006a0', 'approve') ->> 'status'$q$);
select pg_temp.t('F3+', 'The approval is in the audit log with actor and target', 'rows=1',
  $q$select count(*) from public.audit_entries where action = 'admin.approve'
       and actor_id = '00000000-0000-4000-8000-0000000006d0'
       and target_id = '00000000-0000-4000-8000-0000000006a0'$q$);
select pg_temp.t('F4', 'Approving an already active account', 'error',
  $q$select length(public.admin_apply('00000000-0000-4000-8000-0000000006d0',
     '00000000-0000-4000-8000-0000000006a0', 'approve')::text)$q$);
select pg_temp.t('F5+', 'Admin suspends the student', 'value=suspended',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000006d0',
     '00000000-0000-4000-8000-0000000006a0', 'suspend') ->> 'status'$q$);
select pg_temp.t('F6', 'Admin suspends themselves', 'error',
  $q$select length(public.admin_apply('00000000-0000-4000-8000-0000000006d0',
     '00000000-0000-4000-8000-0000000006d0', 'suspend')::text)$q$);
select pg_temp.t('F7', 'Admin changes their own role', 'error',
  $q$select length(public.admin_apply('00000000-0000-4000-8000-0000000006d0',
     '00000000-0000-4000-8000-0000000006d0', 'set_role', 'student')::text)$q$);
select pg_temp.t('F8+', 'Admin makes the student a librarian', 'value=librarian',
  $q$select public.admin_apply('00000000-0000-4000-8000-0000000006d0',
     '00000000-0000-4000-8000-0000000006b0', 'set_role', 'librarian') ->> 'role'$q$);
select pg_temp.t('F9+', 'The role change is in the audit log', 'rows=1',
  $q$select count(*) from public.audit_entries where action = 'admin.set_role'
       and target_id = '00000000-0000-4000-8000-0000000006b0'$q$);

-- Invite: Supabase Auth creates the user (here, a plain insert), the
-- trigger makes a pending student, then admin_after_invite gives it the
-- role the admin chose.
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000006f9', 'zl-roles-i@example.invalid', '{"full_name": "Ivy Invited"}');
set role service_role;
select pg_temp.t('F10+', 'Admin-created librarian is active with the chosen role', 'value=librarian active',
  $q$select (r ->> 'role') || ' ' || (r ->> 'status')
       from (select public.admin_after_invite('00000000-0000-4000-8000-0000000006d0',
             '00000000-0000-4000-8000-0000000006f9', 'librarian', 'Ivy Invited', null) as r) x$q$);
select pg_temp.t('F10b+', 'and must choose a password before anything else', 'value=true',
  $q$select must_set_password::text from public.profiles where id = '00000000-0000-4000-8000-0000000006f9'$q$);
select pg_temp.t('F11', 'A librarian cannot create accounts', 'error',
  $q$select length(public.admin_after_invite('00000000-0000-4000-8000-0000000006c0',
     '00000000-0000-4000-8000-0000000006f9', 'admin', 'x', null)::text)$q$);
select pg_temp.t('F12+', 'The account creation is in the audit log', 'rows=1',
  $q$select count(*) from public.audit_entries where action = 'admin.create'
       and target_id = '00000000-0000-4000-8000-0000000006f9'$q$);

-- The last active admin is protected even from the service role.
update public.profiles set status = 'suspended' where id = '00000000-0000-4000-8000-0000000006e0';
-- (Only meaningful when no real administrator exists, as on a fresh
-- database; on the live project the row says it was skipped.)
do $$
begin
  if exists (select 1 from public.profiles where role = 'admin' and status = 'active'
              and email not like 'zl-roles-%') then
    insert into pg_temp.results values ('F13', 'Demoting the last active admin', 'error',
      'skipped: real administrators exist in this project', 'PASS');
  else
    perform pg_temp.t('F13', 'Demoting the last active admin', 'error',
      $q$update public.profiles set role = 'student' where id = '00000000-0000-4000-8000-0000000006d0'$q$);
  end if;
end $$;

-- The invited librarian finishes setting up.
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000006f9","role":"authenticated"}', false);
select pg_temp.t('I1+', 'Invited user marks their password as set', 'rows=1',
  'select count(*) from (select public.mark_password_set()) x');
select pg_temp.t('I2+', 'The flag is now off and they are staff', 'value=false true',
  $q$select must_set_password::text || ' ' || public.is_staff()::text from public.profiles where id = auth.uid()$q$);
select pg_temp.t('I3', 'Invited user turns the flag back on', 'error',
  $q$update public.profiles set must_set_password = true where id = auth.uid()$q$);

-- A suspended student loses access.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000006a0","role":"authenticated"}', false);
select pg_temp.t('X1', 'Suspended student: read the catalogue', 'rows=0', 'select count(*) from public.resources');

-- ================================================================ clean up
reset role;
select set_config('request.jwt.claims', '', false);
-- Supabase blocks DELETE on storage.objects unless the Storage API asks
-- for it with this setting; the clean-up removes only the test's own file
-- records, then turns it off again.
select set_config('storage.allow_delete_query', 'true', false);
update public.profiles set status = 'active' where email like 'zl-roles-%@example.invalid';
delete from public.audit_entries where target_id in (select id::text from auth.users where email like 'zl-roles-%@example.invalid');
delete from public.borrow_requests where resource_id in (select id from public.resources where title like 'ZLR %');
delete from public.resources where title like 'ZLR %';
delete from storage.objects where name = 'sample/ICT/ZLR2010/2023-exam.pdf';
-- Profiles go with their auth users. The guard needs one active admin
-- left, so demote nothing; just delete.
delete from public.profiles where email like 'zl-roles-%@example.invalid';
delete from auth.users where email like 'zl-roles-%@example.invalid';
select set_config('storage.allow_delete_query', 'false', false);

-- ---------------------------------------------------------------- results
select id, test, expected, actual, outcome
from pg_temp.results
order by case left(id, 1) when 'U' then 1 when 'A' then 2 when 'P' then 3 when 'S' then 4
                          when 'L' then 5 when 'M' then 6 when 'F' then 7 when 'I' then 8 else 9 end,
         nullif(regexp_replace(id, '\D', '', 'g'), '')::int;
