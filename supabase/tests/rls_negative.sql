-- ZutLib — security tests (row level security, column privileges, triggers)
--
-- HOW TO RUN: Supabase -> SQL Editor -> New query -> paste this whole file
-- -> Run. The last result is a table of tests with PASS or FAIL.
-- It creates throwaway accounts and data, signs in as each role the same
-- way the API does (role + JWT claims), attempts what that role must NOT
-- be able to do, records what happened, then deletes everything it made.
-- It is safe to run on the live project and safe to run repeatedly.
--
-- Each test says what is expected:
--   error    the database must refuse
--   denied   either of the above two refusals (used where the answer
--            depends on project-wide default grants)
--   rows=N   the statement must see or change exactly N rows
--            (row level security hides rows rather than raising errors,
--             so "rows=0" is how a refusal shows up for reads)
-- Positive controls (marked +) prove the setup works, so a PASS on a
-- refusal cannot come from a broken fixture.

-- ---------------------------------------------------------------- harness
drop table if exists pg_temp.results;
create temp table results (
  id text, test text, expected text, actual text, outcome text
);
grant insert, select on pg_temp.results to public;

create or replace function pg_temp.t(p_id text, p_test text, p_expect text, p_sql text)
returns void language plpgsql as $$
declare n bigint; actual text;
begin
  begin
    if p_sql ~* '^\s*select' then
      execute p_sql into n;
    else
      execute p_sql;
      get diagnostics n = row_count;
    end if;
    actual := 'rows=' || n;
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
-- Fixed ids so every statement below can refer to them.
--   a = student A, b = student B, l = librarian, m = admin,
--   g = ghost (an auth account with no profile, as if made by calling
--       sign-up directly and skipping the roll)
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'zl-test-a@example.invalid'),
  ('00000000-0000-4000-8000-00000000000b', 'zl-test-b@example.invalid'),
  ('00000000-0000-4000-8000-00000000000c', 'zl-test-l@example.invalid'),
  ('00000000-0000-4000-8000-00000000000d', 'zl-test-m@example.invalid'),
  ('00000000-0000-4000-8000-00000000000e', 'zl-test-g@example.invalid');

insert into public.roll (student_number, surname, first_name, programme, department, intake_year) values
  ('ZLTEST01', 'Alpha', 'Ann', 'Test programme', 'ICT', 2023),
  ('ZLTEST02', 'Beta',  'Ben', 'Test programme', 'ICT', 2023);

insert into public.profiles (id, full_name, surname, student_number, programme, department, role) values
  ('00000000-0000-4000-8000-00000000000a', 'Ann Alpha', 'Alpha', 'ZLTEST01', 'Test programme', 'ICT', 'student'),
  ('00000000-0000-4000-8000-00000000000b', 'Ben Beta',  'Beta',  'ZLTEST02', 'Test programme', 'ICT', 'student'),
  ('00000000-0000-4000-8000-00000000000c', 'Lib Test',  'Test',  null, null, null, 'librarian'),
  ('00000000-0000-4000-8000-00000000000d', 'Adm Test',  'Test',  null, null, null, 'admin');

insert into public.resources (id, title, type, department, course_code, academic_year,
                              is_physical, total_copies, available_copies, external_url) values
  ('00000000-0000-4000-8000-0000000000f1', 'ZL test physical book', 'book_link', 'ICT',
   'ZLT 1000', 2024, true, 2, 2, 'https://example.invalid/book');

-- Student B already has a submitted request.
insert into public.borrow_requests (id, resource_id, student_id, student_name, student_number)
values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
        '00000000-0000-4000-8000-00000000000b', 'x', 'x');

-- Student A has one notification.
insert into public.notifications (id, user_id, subject, body) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-00000000000a',
   'Test notice', 'Original body');

-- ================================================================ anonymous
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);

select pg_temp.t('A1', 'Signed out: read the catalogue', 'denied',
  'select count(*) from public.resources');
select pg_temp.t('A2', 'Signed out: read the student roll', 'denied',
  'select count(*) from public.roll');
select pg_temp.t('A3', 'Signed out: call search', 'denied',
  'select count(*) from public.search_resources(''zlt'')');
select pg_temp.t('A4+', 'Signed out: keepalive beat() is allowed', 'rows=1',
  'select count(*) from (select public.beat()) x');

-- ================================================================ ghost
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000000e","role":"authenticated"}', false);

select pg_temp.t('G1', 'No-profile account: read the catalogue', 'rows=0',
  'select count(*) from public.resources');
select pg_temp.t('G2', 'No-profile account: list stored files', 'rows=0',
  'select count(*) from storage.objects where bucket_id = ''resources''');
select pg_temp.t('G3', 'No-profile account: file a borrowing request', 'error',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number)
     values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000e', 'g', 'g')$q$);

-- ================================================================ student A
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}', false);

select pg_temp.t('S1+', 'Student: read the catalogue', 'rows=1',
  $q$select count(*) from public.resources where course_code = 'ZLT 1000'$q$);
select pg_temp.t('S2+', 'Student: search finds the test resource', 'rows=1',
  $q$select count(*) from public.search_resources('zlt1000')$q$);
select pg_temp.t('S3', 'Student: read the student roll', 'rows=0',
  'select count(*) from public.roll');
select pg_temp.t('S4', 'Student: add a record to the roll', 'error',
  $q$insert into public.roll (student_number, surname, programme, department, intake_year)
     values ('ZLTEST99', 'Fake', 'x', 'ICT', 2024)$q$);
select pg_temp.t('S5', 'Student: read another student''s profile', 'rows=0',
  $q$select count(*) from public.profiles where id = '00000000-0000-4000-8000-00000000000b'$q$);
select pg_temp.t('S6', 'Student: make themselves an admin', 'denied',
  $q$update public.profiles set role = 'admin' where id = '00000000-0000-4000-8000-00000000000a'$q$);
select pg_temp.t('S7', 'Student: change their own name or programme', 'error',
  $q$update public.profiles set full_name = 'Someone Else', programme = 'Other'
     where id = '00000000-0000-4000-8000-00000000000a'$q$);
select pg_temp.t('S8', 'Student: add a resource', 'error',
  $q$insert into public.resources (title, type, department, course_code, academic_year, external_url)
     values ('Fake', 'book_link', 'ICT', 'FAK 1000', 2024, 'https://x.invalid')$q$);
select pg_temp.t('S9', 'Student: delete a resource', 'rows=0',
  $q$delete from public.resources where id = '00000000-0000-4000-8000-0000000000f1'$q$);
select pg_temp.t('S10', 'Student: change the copy count', 'rows=0',
  $q$update public.resources set available_copies = 0 where id = '00000000-0000-4000-8000-0000000000f1'$q$);
select pg_temp.t('S11', 'Student: file a request in another student''s name', 'error',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number)
     values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000b', 'Ben Beta', 'ZLTEST02')$q$);
select pg_temp.t('S12', 'Student: file a request already marked approved', 'error',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number, status)
     values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000a', 'a', 'a', 'approved')$q$);
select pg_temp.t('S13+', 'Student: file own request with a forged name and number', 'rows=1',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number, programme)
     values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000a',
             'Forged Name', 'ZLTEST02', 'Forged programme')$q$);
select pg_temp.t('S14', 'Forged identity was replaced by the verified one', 'rows=1',
  $q$select count(*) from public.borrow_requests
     where student_id = '00000000-0000-4000-8000-00000000000a'
       and student_name = 'Ann Alpha' and student_number = 'ZLTEST01'
       and programme = 'Test programme'$q$);
select pg_temp.t('S15', 'Student: second live request for the same item', 'error',
  $q$insert into public.borrow_requests (resource_id, student_id, student_name, student_number)
     values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000a', 'a', 'a')$q$);
select pg_temp.t('S16', 'Student: read another student''s request', 'rows=0',
  $q$select count(*) from public.borrow_requests where id = '00000000-0000-4000-8000-0000000000b1'$q$);
select pg_temp.t('S17', 'Student: cancel another student''s request', 'rows=0',
  $q$update public.borrow_requests set status = 'cancelled' where id = '00000000-0000-4000-8000-0000000000b1'$q$);
select pg_temp.t('S18', 'Student: approve their own request', 'error',
  $q$update public.borrow_requests set status = 'approved'
     where student_id = '00000000-0000-4000-8000-00000000000a'$q$);
select pg_temp.t('S19', 'Student: set their own due date', 'error',
  $q$update public.borrow_requests set due_date = '2099-01-01'
     where student_id = '00000000-0000-4000-8000-00000000000a'$q$);
select pg_temp.t('S20', 'Student: cancel and switch the item in one update', 'error',
  $q$update public.borrow_requests set status = 'cancelled', resource_id = '00000000-0000-4000-8000-0000000000f1'
     where student_id = '00000000-0000-4000-8000-00000000000a'$q$);
select pg_temp.t('S21', 'Student: reserve a copy directly', 'error',
  $q$select count(*) from (select public.reserve_copy('00000000-0000-4000-8000-0000000000f1')) x$q$);
select pg_temp.t('S22', 'Student: read the audit log', 'rows=0',
  'select count(*) from public.audit_entries');
select pg_temp.t('S23', 'Student: write to the audit log', 'error',
  $q$insert into public.audit_entries (action, target_table, target_id) values ('fake', 'x', 'x')$q$);
select pg_temp.t('S24', 'Student: rewrite a notification''s text', 'error',
  $q$update public.notifications set body = 'Edited' where id = '00000000-0000-4000-8000-0000000000e1'$q$);
select pg_temp.t('S25+', 'Student: mark own notification read', 'rows=1',
  $q$update public.notifications set read_at = now() where id = '00000000-0000-4000-8000-0000000000e1'$q$);
select pg_temp.t('S26+', 'Student: cancel own submitted request', 'rows=1',
  $q$update public.borrow_requests set status = 'cancelled'
     where student_id = '00000000-0000-4000-8000-00000000000a' and status = 'submitted'$q$);

-- ================================================================ librarian
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000000c","role":"authenticated"}', false);

select pg_temp.t('L1+', 'Librarian: read every request', 'rows=2',
  $q$select count(*) from public.borrow_requests where resource_id = '00000000-0000-4000-8000-0000000000f1'$q$);
select pg_temp.t('L2', 'Librarian: approve by writing the status directly', 'rows=0',
  $q$update public.borrow_requests set status = 'approved' where id = '00000000-0000-4000-8000-0000000000b1'$q$);
select pg_temp.t('L3', 'Librarian: more copies available than held', 'error',
  $q$update public.resources set available_copies = 99 where id = '00000000-0000-4000-8000-0000000000f1'$q$);
select pg_temp.t('L4', 'Librarian: change someone''s role', 'rows=0',
  $q$update public.profiles set role = 'admin' where id = '00000000-0000-4000-8000-00000000000a'$q$);
select pg_temp.t('L5', 'Librarian: read the student roll', 'rows=0',
  $q$select count(*) from public.roll where student_number like 'ZLTEST%'$q$);

-- ================================================================ admin
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000000d","role":"authenticated"}', false);

select pg_temp.t('M1+', 'Admin: read the student roll', 'rows=2',
  $q$select count(*) from public.roll where student_number like 'ZLTEST%'$q$);
select pg_temp.t('M2+', 'Admin: make a student a librarian', 'rows=1',
  $q$update public.profiles set role = 'librarian' where id = '00000000-0000-4000-8000-00000000000b'$q$);
select pg_temp.t('M3', 'Admin: change their own role', 'error',
  $q$update public.profiles set role = 'student' where id = '00000000-0000-4000-8000-00000000000d'$q$);
select pg_temp.t('M4', 'Admin: store an invalid request status', 'error',
  $q$update public.borrow_requests set status = 'borrowed_forever' where id = '00000000-0000-4000-8000-0000000000b1'$q$);

-- ================================================================ clean up
reset role;
select set_config('request.jwt.claims', '', false);

delete from public.notifications  where user_id in (select id from auth.users where email like 'zl-test-%@example.invalid');
delete from public.borrow_requests where resource_id = '00000000-0000-4000-8000-0000000000f1';
delete from public.resources      where id = '00000000-0000-4000-8000-0000000000f1';
delete from public.profiles       where id in (select id from auth.users where email like 'zl-test-%@example.invalid');
delete from public.roll           where student_number like 'ZLTEST%';
delete from auth.users            where email like 'zl-test-%@example.invalid';

-- ---------------------------------------------------------------- results
select id, test, expected, actual, outcome
from pg_temp.results
order by case left(id, 1) when 'A' then 1 when 'G' then 2 when 'S' then 3
                          when 'L' then 4 else 5 end,
         nullif(regexp_replace(id, '\D', '', 'g'), '')::int;
