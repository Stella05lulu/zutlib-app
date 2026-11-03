-- ZutLib: planner, notification, feedback and report security tests
-- (0015_planner_notifications.sql)
--
-- HOW TO RUN: Supabase -> SQL Editor -> New query -> paste this whole file
-- -> Run, after migration 0015. The last result is a table of tests with
-- PASS or FAIL. Like the other test files it makes throwaway accounts and
-- items, acts as each account the way the API does, and deletes everything
-- it made. Safe to run on the live project, and repeatedly.
--
-- Expectations: error | denied (error or no rows) | rows=N | value=X.
-- Tests marked + are positive controls.
--
-- Accounts: a = student A, b = student B, c = pending student,
--           l = librarian, d = administrator.

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

create or replace function pg_temp.as_user(p_id text)
returns void language sql as $$
  select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000' || p_id || '","role":"authenticated"}', false)
$$;

-- A valid AI kit, as study-generate would store it.
create or replace function pg_temp.kit()
returns jsonb language sql as $$
  select jsonb_build_object(
    'guide', jsonb_build_object(
      'overview', 'Loops repeat work.',
      'sections', jsonb_build_array(
        jsonb_build_object('heading', 'For loops', 'summary', 'Counted loops.', 'points', jsonb_build_array('for i in range')),
        jsonb_build_object('heading', 'While loops', 'summary', 'Loops on a condition.', 'points', jsonb_build_array()))),
    'cards', (select jsonb_agg(jsonb_build_object('term', 'Term ' || i, 'definition', 'Meaning ' || i))
                from generate_series(1, 6) i),
    'questions', (select jsonb_agg(jsonb_build_object(
                    'question', 'Question ' || i,
                    'options', jsonb_build_array(
                      jsonb_build_object('text', 'Right', 'is_correct', true),
                      jsonb_build_object('text', 'Wrong', 'is_correct', false)),
                    'explanation', 'Because.', 'difficulty', 'medium'))
                  from generate_series(1, 6) i))
$$;

-- ---------------------------------------------------------------- fixtures
-- First remove anything a stopped earlier run left behind.
delete from public.borrow_requests where resource_id in
  ('00000000-0000-4000-8000-0000000008f1', '00000000-0000-4000-8000-0000000008f2', '00000000-0000-4000-8000-0000000008f3');
delete from public.resources where id in
  ('00000000-0000-4000-8000-0000000008f1', '00000000-0000-4000-8000-0000000008f2', '00000000-0000-4000-8000-0000000008f3');
delete from public.profiles where id in (select id from auth.users where email like 'zl-plan-%@example.invalid');
delete from auth.users where email like 'zl-plan-%@example.invalid';

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000008a0', 'zl-plan-a@example.invalid', '{"full_name": "Plan Student A", "department": "ICT"}'),
  ('00000000-0000-4000-8000-0000000008b0', 'zl-plan-b@example.invalid', '{"full_name": "Plan Student B", "department": "ICT"}'),
  ('00000000-0000-4000-8000-0000000008c0', 'zl-plan-c@example.invalid', '{"full_name": "Plan Pending C", "department": "ICT"}'),
  ('00000000-0000-4000-8000-0000000008e0', 'zl-plan-l@example.invalid', '{"full_name": "Plan Librarian"}');
update public.profiles set status = 'active'
 where id in ('00000000-0000-4000-8000-0000000008a0', '00000000-0000-4000-8000-0000000008b0');
update public.profiles set role = 'librarian', status = 'active'
 where id = '00000000-0000-4000-8000-0000000008e0';

-- The administrator is made last, so the sign-up notices for A, B and C
-- above went to whatever administrators the project already has, not to D.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000008d0', 'zl-plan-d@example.invalid', '{"full_name": "Plan Admin"}');
update public.profiles set role = 'admin', status = 'active'
 where id = '00000000-0000-4000-8000-0000000008d0';

-- A's kit, built by the AI as the server would.
insert into public.study_notes (id, user_id, title, body) values
  ('00000000-0000-4000-8000-0000000008a1', '00000000-0000-4000-8000-0000000008a0', 'Loops kit', 'Loops repeat work.');
select public.study_ai_store('00000000-0000-4000-8000-0000000008a0', '00000000-0000-4000-8000-0000000008a1',
  'kit', public.study_note_hash('Loops kit', 'Loops repeat work.', ''), 'm', pg_temp.kit(), '');

-- A physical book for borrowing.
insert into public.resources (id, title, type, department, author, is_physical, total_copies, available_copies) values
  ('00000000-0000-4000-8000-0000000008f1', 'ZLP Programming in C', 'book', 'ICT', 'K. Writer', true, 3, 3);

-- ================================================================ profiles (student A)
set role authenticated;
select pg_temp.as_user('8a0');

select pg_temp.t('P1+', 'A saves their year, courses and reminder time', 'rows=1',
  $q$select count(*) from (select public.update_my_profile('Plan Student A', 'ICT', 2,
       array['eee 2011', ' ict   2010', 'EEE 2011'], '19:30', true, true, false)) x$q$);
select pg_temp.t('P1b+', 'Courses are cleaned and de-duplicated', 'value={"EEE 2011","ICT 2010"}',
  $q$select courses::text from public.profiles where id = auth.uid()$q$);
select pg_temp.t('P2', 'A writes their own profile row directly', 'error',
  $q$update public.profiles set courses = array['X 1'] where id = auth.uid()$q$);
select pg_temp.t('P3', 'A department that does not exist', 'error',
  $q$select public.update_my_profile('A', 'Medicine', 2, '{}', null, null, null, false)$q$);
select pg_temp.t('P4', 'Thirteen courses', 'error',
  $q$select public.update_my_profile('A', 'ICT', 2,
       (select array_agg('ICT ' || (1000 + i)) from generate_series(1, 13) i), null, null, null, false)$q$);
select pg_temp.t('P5', 'Year of study 9', 'error',
  $q$select public.update_my_profile('A', 'ICT', 9, '{}', null, null, null, false)$q$);
select pg_temp.t('P6', 'A course code with symbols', 'error',
  $q$select public.update_my_profile('A', 'ICT', 2, array['DROP;TABLE'], null, null, null, false)$q$);
select pg_temp.t('P7+', 'A finishes onboarding', 'rows=1',
  $q$select count(*) from (select public.update_my_profile('Plan Student A', 'ICT', 2,
       array['EEE 2011', 'ICT 2010'], null, null, null, true)) x$q$);
select pg_temp.t('P7b+', 'Onboarding is recorded; role and reminder time are untouched', 'value=student true 19:30:00',
  $q$select role || ' ' || (onboarded_at is not null) || ' ' || reminder_time
       from public.profiles where id = auth.uid()$q$);

select pg_temp.as_user('8c0');
select pg_temp.t('P8', 'A pending student cannot change their profile', 'error',
  $q$select public.update_my_profile('C', 'ICT', 1, '{}', null, null, null, true)$q$);

-- ================================================================ activity (student A)
select pg_temp.as_user('8a0');

select pg_temp.t('A1+', 'A rates two cards', 'rows=2',
  $q$select count(*) from (select public.study_rate_card(f.id, 1)
       from public.study_flashcards f join public.study_guides g on g.deck_id = f.deck_id limit 2) x$q$);
select pg_temp.t('A1b+', 'That counts as 2 cards of study today', 'value=2',
  $q$select amount::text from public.study_activity where kind = 'cards' and day = public.zl_today()$q$);
select pg_temp.t('A2+', 'A answers a question', 'rows=1',
  $q$select count(*) from (select public.study_rate_question(q.id, 1)
       from public.study_quiz_questions q join public.study_guides g on g.quiz_id = q.quiz_id limit 1) x$q$);
select pg_temp.t('A2b+', 'That counts as question study', 'value=1',
  $q$select amount::text from public.study_activity where kind = 'questions'$q$);
select pg_temp.t('A3+', 'A marks guide section 1 read', 'rows=1',
  $q$select count(*) from (select public.study_mark_read(id, 0) from public.study_guides) x$q$);
select pg_temp.t('A3b+', 'Marking it again', 'rows=1',
  $q$select count(*) from (select public.study_mark_read(id, 0) from public.study_guides) x$q$);
select pg_temp.t('A3c+', 'A section read counts once, however often it is marked', 'value=1',
  $q$select amount::text from public.study_activity where kind = 'guide'$q$);
select pg_temp.t('A4', 'Section 15 of a guide', 'error',
  $q$select public.study_mark_read(id, 15) from public.study_guides$q$);
select pg_temp.t('A5+', 'Finishing a test counts as test study', 'value=1',
  $q$with t as (insert into public.study_tests (note_id, quiz_id, title, question_ids)
                select g.note_id, g.quiz_id, 'Plan test',
                       (select array_agg(id) from public.study_quiz_questions where quiz_id = g.quiz_id)
                  from public.study_guides g returning id)
     select count(*)::text from t$q$);
select pg_temp.t('A5b+', 'The test attempt was logged', 'value=1',
  $q$with a as (insert into public.study_test_attempts (test_id, answers)
                select id, '{}' from public.study_tests where title = 'Plan test' returning id)
     select (select count(*) from a)::text$q$);
select pg_temp.t('A5c+', 'Activity now shows a test today', 'value=1',
  $q$select amount::text from public.study_activity where kind = 'test'$q$);
select pg_temp.t('A6', 'A writes activity for a kit that is not theirs', 'error',
  $q$insert into public.study_activity (note_id, kind, amount) values (gen_random_uuid(), 'cards', 500)$q$);

-- ================================================================ plans (student A)
select pg_temp.t('N1+', 'A plans an exam 20 days away', 'rows=1',
  $q$insert into public.study_plans (note_id, exam_date, study_days, minutes)
     values ('00000000-0000-4000-8000-0000000008a1', public.zl_today() + 20, 31, 30)$q$);
select pg_temp.t('N2', 'A second plan for the same kit', 'error',
  $q$insert into public.study_plans (note_id, exam_date) values ('00000000-0000-4000-8000-0000000008a1', public.zl_today() + 5)$q$);
select pg_temp.t('N3', 'Moving the exam to yesterday', 'error',
  $q$update public.study_plans set exam_date = public.zl_today() - 1$q$);
select pg_temp.t('N4', '20 minutes a day (not an offered length)', 'error',
  $q$update public.study_plans set minutes = 20$q$);
select pg_temp.t('N5', 'No study days at all', 'error',
  $q$update public.study_plans set study_days = 0$q$);
select pg_temp.t('N6+', 'A moves the exam 3 days away (the start date stays)', 'value=3',
  $q$with u as (update public.study_plans set exam_date = public.zl_today() + 3 returning exam_date - start_date d)
     select d::text from u$q$);
select pg_temp.t('N7+', 'A ticks a task by hand', 'rows=1',
  $q$insert into public.study_plan_checks (plan_id, day, task_key)
     select id, public.zl_today(), 'guide:1' from public.study_plans$q$);
select pg_temp.t('N8', 'A task key with symbols', 'error',
  $q$insert into public.study_plan_checks (plan_id, day, task_key)
     select id, public.zl_today(), 'x; drop table' from public.study_plans$q$);

-- ================================================================ student B
select pg_temp.as_user('8b0');
select pg_temp.t('B1', 'B reads A''s plans', 'rows=0', 'select count(*) from public.study_plans');
select pg_temp.t('B2', 'B reads A''s activity', 'rows=0', 'select count(*) from public.study_activity');
select pg_temp.t('B3', 'B ticks a task on A''s plan', 'error',
  $q$insert into public.study_plan_checks (plan_id, day, task_key)
     select id, public.zl_today(), 'x' from public.study_plans
     union all select gen_random_uuid(), public.zl_today(), 'x'$q$);
select pg_temp.t('B4', 'B marks a section of A''s guide read', 'error',
  $q$insert into public.study_guide_reads (guide_id, section)
     select id, 1 from public.study_guides
     union all select gen_random_uuid(), 1$q$);
select pg_temp.t('B5', 'B plans an exam on A''s kit', 'error',
  $q$insert into public.study_plans (note_id, exam_date) values ('00000000-0000-4000-8000-0000000008a1', public.zl_today() + 9)$q$);

select pg_temp.as_user('8e0');
select pg_temp.t('L1', 'A librarian makes a study plan', 'error',
  $q$insert into public.study_plans (note_id, exam_date) values ('00000000-0000-4000-8000-0000000008a1', public.zl_today() + 9)$q$);

-- ================================================================ notifications
-- New uploads (made as the database owner, like a librarian upload).
reset role;
insert into public.resources (id, title, type, department, course_code, academic_year, file_path) values
  ('00000000-0000-4000-8000-0000000008f2', 'ZLP EEE 2011 examination 2025', 'past_paper', 'Engineering', 'eee  2011', 2025, 'x/eee.pdf');
insert into public.resources (id, title, type, department, course_code, academic_year, file_path, is_sample) values
  ('00000000-0000-4000-8000-0000000008f3', 'ZLP sample paper', 'past_paper', 'Engineering', 'EEE 2011', 2019, 'x/s.pdf', true);
-- A asks to borrow the book.
insert into public.borrow_requests (resource_id, student_id, student_name, student_number) values
  ('00000000-0000-4000-8000-0000000008f1', '00000000-0000-4000-8000-0000000008a0', 'x', 'x');

set role authenticated;
select pg_temp.as_user('8a0');
select pg_temp.t('M1+', 'A is told about the new EEE 2011 paper, with a link to it', 'value=upload /resource/00000000-0000-4000-8000-0000000008f2',
  $q$select kind || ' ' || link from public.notifications where kind = 'upload'$q$);
select pg_temp.t('M2', 'Sample papers notify nobody', 'rows=0',
  $q$select count(*) from public.notifications where link like '%8f3'$q$);
select pg_temp.t('M3', 'A writes a notification directly', 'error',
  $q$insert into public.notifications (user_id, subject, body) values (auth.uid(), 'x', 'y')$q$);
select pg_temp.t('M4', 'A sends a notification through the internal function', 'error',
  $q$select public.zl_notify(auth.uid(), 'general', 'x', 'y', null, null)$q$);
select pg_temp.t('M5', 'A runs the daily job', 'error', $q$select public.zl_daily_notices()$q$);

select pg_temp.as_user('8b0');
select pg_temp.t('M6', 'B (no courses) was not told about the paper', 'rows=0',
  $q$select count(*) from public.notifications where kind = 'upload'$q$);

select pg_temp.as_user('8e0');
select pg_temp.t('M7+', 'The librarian is told about A''s borrow request', 'value=staff New borrow request',
  $q$select kind || ' ' || subject from public.notifications where kind = 'staff'$q$);

select pg_temp.as_user('8d0');
select pg_temp.t('M8', 'The administrator is not sent the librarian''s request notice', 'rows=0',
  $q$select count(*) from public.notifications where subject = 'New borrow request'$q$);

-- A new sign-up after D exists: D is told.
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000008c9', 'zl-plan-new@example.invalid', '{"full_name": "Plan Newcomer", "department": "Business"}');
set role authenticated;
select pg_temp.as_user('8d0');
select pg_temp.t('M9+', 'The administrator is told about the new sign-up', 'value=admin /admin/users',
  $q$select kind || ' ' || link from public.notifications where subject = 'New student sign-up' and body like 'Plan Newcomer%'$q$);

-- The daily job: a loan due in 2 days, one 3 days overdue, and A's exam in 3 days.
reset role;
update public.borrow_requests set status = 'collected', due_date = public.zl_today() + 2
 where resource_id = '00000000-0000-4000-8000-0000000008f1' and student_id = '00000000-0000-4000-8000-0000000008a0';
insert into public.borrow_requests (resource_id, student_id, student_name, student_number, status, collected_at, due_date) values
  ('00000000-0000-4000-8000-0000000008f1', '00000000-0000-4000-8000-0000000008b0', 'x', 'x', 'collected', now(), public.zl_today() - 3);
set role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', false);
select pg_temp.t('M10+', 'The daily job sends its notices', 'rows=1',
  $q$select count(*) from (select public.zl_daily_notices() n) x where n >= 4$q$);
select pg_temp.t('M11+', 'Running it again the same day sends nothing new', 'value=0',
  $q$select public.zl_daily_notices()::text$q$);

set role authenticated;
select pg_temp.as_user('8a0');
select pg_temp.t('M12+', 'A is reminded the book is due in 2 days', 'rows=1',
  $q$select count(*) from public.notifications where kind = 'due' and subject = 'Due back in 2 days'$q$);
select pg_temp.t('M13+', 'A is reminded the exam is in 3 days, with a link to the plan', 'rows=1',
  $q$select count(*) from public.notifications where kind = 'study' and subject = 'Exam in 3 days' and link like '/plan/%'$q$);
select pg_temp.as_user('8b0');
select pg_temp.t('M14+', 'B is told their loan is 3 days overdue', 'rows=1',
  $q$select count(*) from public.notifications where kind = 'due' and subject like 'Overdue%'$q$);
select pg_temp.as_user('8e0');
select pg_temp.t('M15+', 'The librarian gets one overdue summary', 'value=1 loan is overdue',
  $q$select subject from public.notifications where dedupe_key like 'overdue-summary:%'$q$);
select pg_temp.t('M16+', 'The librarian marks a notification read', 'rows=1',
  $q$update public.notifications set read_at = now()
     where id = (select id from public.notifications where subject = 'New borrow request' limit 1)$q$);
select pg_temp.t('M17', 'The librarian rewrites a notification', 'error',
  $q$update public.notifications set subject = 'changed'$q$);

-- ================================================================ devices
select pg_temp.as_user('8a0');
select pg_temp.t('D1+', 'A registers their phone for push', 'rows=1',
  $q$select count(*) from (select public.register_device('tok-0123456789-abcdefghij-A', 'android')) x$q$);
select pg_temp.t('D2', 'A token that is too short', 'error',
  $q$select public.register_device('short', 'android')$q$);
select pg_temp.t('D3', 'An unknown platform', 'error',
  $q$select public.register_device('tok-0123456789-abcdefghij-Z', 'nokia')$q$);
select pg_temp.t('D4', 'A writes a device token directly', 'error',
  $q$insert into public.device_tokens (token, user_id, platform)
     values ('tok-0123456789-abcdefghij-X', auth.uid(), 'web')$q$);
select pg_temp.as_user('8b0');
select pg_temp.t('D5+', 'B signs in on the same phone: the token moves to B', 'rows=1',
  $q$select count(*) from (select public.register_device('tok-0123456789-abcdefghij-A', 'android')) x$q$);
select pg_temp.as_user('8a0');
select pg_temp.t('D6', 'A no longer owns that phone''s token', 'rows=0',
  $q$select count(*) from public.device_tokens$q$);
select pg_temp.t('D7', 'A removes B''s token', 'rows=0',
  $q$select count(*) from (select public.unregister_device('tok-0123456789-abcdefghij-A')) x
     where exists (select 1 from public.device_tokens)$q$);

-- ================================================================ feedback
select pg_temp.t('F1+', 'A sends feedback; it is stamped as a student''s', 'value=student',
  $q$with f as (insert into public.feedback (message, app_version) values ('Add dark mode to the PDF viewer', '1.0.0')
                returning role) select role::text from f$q$);
select pg_temp.t('F2', 'Empty feedback', 'error',
  $q$insert into public.feedback (message) values ('   ')$q$);
select pg_temp.t('F3', 'A claims to be an administrator in feedback', 'error',
  $q$insert into public.feedback (message, role) values ('x', 'admin')$q$);
select pg_temp.t('F4', 'A marks their feedback resolved', 'error',
  $q$select public.admin_resolve_feedback(id, true) from public.feedback$q$);
select pg_temp.as_user('8b0');
select pg_temp.t('F5', 'B reads A''s feedback', 'rows=0', 'select count(*) from public.feedback');
select pg_temp.as_user('8d0');
select pg_temp.t('F6+', 'The administrator reads A''s feedback', 'rows=1',
  $q$select count(*) from public.feedback where message = 'Add dark mode to the PDF viewer'$q$);
select pg_temp.t('F7+', 'The administrator marks it resolved', 'rows=1',
  $q$select count(*) from (select public.admin_resolve_feedback(id, true) from public.feedback
       where message = 'Add dark mode to the PDF viewer') x$q$);
select pg_temp.t('F7b+', 'It shows as resolved', 'value=true',
  $q$select (resolved_at is not null)::text from public.feedback where message = 'Add dark mode to the PDF viewer'$q$);

-- ================================================================ usage reports
select pg_temp.as_user('8a0');
select pg_temp.t('U1+', 'A searches EEE 2011 (recorded without their name)', 'rows=1',
  $q$select count(*) from (select public.log_event('search', 'eee 2011', null)) x$q$);
select pg_temp.t('U2', 'A reads the usage log', 'denied', 'select count(*) from public.usage_events');
select pg_temp.t('U3', 'A writes the usage log directly', 'error',
  $q$insert into public.usage_events (kind) values ('search')$q$);
select pg_temp.t('U4', 'An event kind that does not exist', 'error',
  $q$select public.log_event('steal', null, null)$q$);
select pg_temp.t('U5', 'A opens the administrator reports', 'error',
  $q$select public.admin_reports(30)$q$);
select pg_temp.as_user('8d0');
select pg_temp.t('U6+', 'The report lists EEE 2011 among searched courses', 'rows=1',
  $q$select count(*) from jsonb_array_elements(public.admin_reports(30) -> 'searched_courses') e
      where e ->> 'label' = 'EEE 2011'$q$);
select pg_temp.t('U7+', 'The report counts A''s kit and the overdue loan', 'value=true',
  $q$select ((r -> 'study' ->> 'kits_built')::int >= 1 and (r -> 'borrowing' ->> 'overdue')::int >= 1)::text
       from (select public.admin_reports(30) r) x$q$);
select pg_temp.t('U8+', 'The weekly chart has 8 weeks', 'value=8',
  $q$select jsonb_array_length(public.admin_reports(30) -> 'weekly')::text$q$);

-- ================================================================ signed out
reset role;
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
select pg_temp.t('X1', 'Signed out: edit a profile', 'error',
  $q$select public.update_my_profile('x', null, null, '{}', null, null, null, false)$q$);
select pg_temp.t('X2', 'Signed out: register a phone', 'error',
  $q$select public.register_device('tok-0123456789-abcdefghij-Q', 'web')$q$);
select pg_temp.t('X3', 'Signed out: study plans', 'denied', 'select count(*) from public.study_plans');
select pg_temp.t('X4', 'Signed out: send feedback', 'error',
  $q$insert into public.feedback (message) values ('x')$q$);

-- ================================================================ clean up
reset role;
select set_config('request.jwt.claims', '', false);
delete from public.borrow_requests where resource_id in
  ('00000000-0000-4000-8000-0000000008f1', '00000000-0000-4000-8000-0000000008f2', '00000000-0000-4000-8000-0000000008f3');
delete from public.usage_events where resource_id in
  ('00000000-0000-4000-8000-0000000008f1', '00000000-0000-4000-8000-0000000008f2', '00000000-0000-4000-8000-0000000008f3');
delete from public.resources where id in
  ('00000000-0000-4000-8000-0000000008f1', '00000000-0000-4000-8000-0000000008f2', '00000000-0000-4000-8000-0000000008f3');
delete from public.notifications where dedupe_key like 'signup:00000000-0000-4000-8000-0000000008%';
delete from public.profiles where id in (select id from auth.users where email like 'zl-plan-%@example.invalid');
delete from auth.users where email like 'zl-plan-%@example.invalid';

-- ---------------------------------------------------------------- results
select id, test, expected, actual, outcome
from pg_temp.results
order by case left(id, 1) when 'P' then 1 when 'A' then 2 when 'N' then 3 when 'B' then 4
                          when 'L' then 5 when 'M' then 6 when 'D' then 7 when 'F' then 8
                          when 'U' then 9 else 10 end,
         id;
