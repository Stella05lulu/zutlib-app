-- ZutLib: study assistant security tests
--
-- HOW TO RUN: Supabase -> SQL Editor -> New query -> paste this whole file
-- -> Run. The last result is a table of tests with PASS or FAIL.
-- Run it after supabase/migrations/0010_study_assistant.sql.
--
-- Like rls_negative.sql, it creates throwaway accounts, signs in as each
-- of them the way the API does (role + JWT claims), tries what that
-- account must NOT be able to do, records what happened, and deletes
-- everything it made. Safe to run on the live project, and repeatedly.
--
-- Expectations:
--   error     the database must refuse with an error
--   denied    an error, or zero rows (RLS hides rows instead of failing)
--   rows=N    the statement must see or change exactly N rows
--   value=X   the single value returned must be X
-- Tests marked + are positive controls: they prove the fixtures work, so
-- a PASS on a refusal cannot come from a broken setup.
--
-- Accounts: a = student A, b = student B, l = librarian, x = signed out.

-- ---------------------------------------------------------------- harness
drop table if exists pg_temp.results;
create temp table results (
  id text, test text, expected text, actual text, outcome text
);
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
delete from public.profiles where id in (select id from auth.users where email like 'zl-study-%@example.invalid');
delete from public.resources where id in ('00000000-0000-4000-8000-0000000005f1', '00000000-0000-4000-8000-0000000005f2');
delete from storage.objects where bucket_id = 'study-files'
   and name like any (array['00000000-0000-4000-8000-0000000005a0/%', '00000000-0000-4000-8000-0000000005b0/%']);
delete from public.roll     where student_number like 'ZLSTUDY%';
delete from auth.users      where email like 'zl-study-%@example.invalid';
select set_config('storage.allow_delete_query', 'false', false);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000005a0', 'zl-study-a@example.invalid'),
  ('00000000-0000-4000-8000-0000000005b0', 'zl-study-b@example.invalid'),
  ('00000000-0000-4000-8000-0000000005c0', 'zl-study-l@example.invalid');

insert into public.roll (student_number, surname, first_name, programme, department, intake_year) values
  ('ZLSTUDY1', 'Alpha', 'Ann', 'Test programme', 'ICT', 2023),
  ('ZLSTUDY2', 'Beta',  'Ben', 'Test programme', 'ICT', 2023);

-- Since 0012 a trigger makes a pending profile for every new auth user,
-- so the fixtures overwrite it with the account each test needs.
insert into public.profiles (id, full_name, surname, student_number, programme, department, role) values
  ('00000000-0000-4000-8000-0000000005a0', 'Ann Alpha', 'Alpha', 'ZLSTUDY1', 'Test programme', 'ICT', 'student'),
  ('00000000-0000-4000-8000-0000000005b0', 'Ben Beta',  'Beta',  'ZLSTUDY2', 'Test programme', 'ICT', 'student'),
  ('00000000-0000-4000-8000-0000000005c0', 'Lib Study', 'Study', null, null, null, 'librarian')
on conflict (id) do update set full_name = excluded.full_name, surname = excluded.surname,
  student_number = excluded.student_number, programme = excluded.programme,
  department = excluded.department, role = excluded.role, status = 'active';

-- Student B owns one of everything. Written here as the database owner,
-- the way the API never could, so A has something to try to reach.
insert into public.study_notes (id, user_id, title, body) values
  ('00000000-0000-4000-8000-0000000005b1', '00000000-0000-4000-8000-0000000005b0',
   'B private note', 'Only B may read this.');
insert into public.study_summaries (id, user_id, note_id, body) values
  ('00000000-0000-4000-8000-0000000005b2', '00000000-0000-4000-8000-0000000005b0',
   '00000000-0000-4000-8000-0000000005b1', 'B summary');
insert into public.study_decks (id, user_id, note_id, title) values
  ('00000000-0000-4000-8000-0000000005b3', '00000000-0000-4000-8000-0000000005b0',
   '00000000-0000-4000-8000-0000000005b1', 'B deck');
insert into public.study_flashcards (id, user_id, deck_id, front, back) values
  ('00000000-0000-4000-8000-0000000005b4', '00000000-0000-4000-8000-0000000005b0',
   '00000000-0000-4000-8000-0000000005b3', 'Front', 'Back');
insert into public.study_quizzes (id, user_id, note_id, title) values
  ('00000000-0000-4000-8000-0000000005b5', '00000000-0000-4000-8000-0000000005b0',
   '00000000-0000-4000-8000-0000000005b1', 'B quiz');
insert into public.study_quiz_questions (id, user_id, quiz_id, prompt, options, correct_index) values
  ('00000000-0000-4000-8000-0000000005b6', '00000000-0000-4000-8000-0000000005b0',
   '00000000-0000-4000-8000-0000000005b5', 'Pick one', array['Yes', 'No'], 0);
insert into public.study_quiz_attempts (id, user_id, quiz_id, answers) values
  ('00000000-0000-4000-8000-0000000005b7', '00000000-0000-4000-8000-0000000005b0',
   '00000000-0000-4000-8000-0000000005b5',
   '{"00000000-0000-4000-8000-0000000005b6": 0}');
insert into public.study_ai_usage (user_id, day, count) values
  ('00000000-0000-4000-8000-0000000005b0', public.study_today(), 3);
insert into public.study_ai_cache (id, user_id, note_id, kind, content_hash, model, result) values
  ('00000000-0000-4000-8000-0000000005b8', '00000000-0000-4000-8000-0000000005b0',
   '00000000-0000-4000-8000-0000000005b1', 'summary', repeat('a', 64), 'test', '{"summary":"x"}');

-- Library items for studying from a PDF: lecture notes with a PDF, and a
-- physical book with no file. Student B has one uploaded PDF.
insert into public.resources (id, title, type, department, course_code, academic_year, file_path) values
  ('00000000-0000-4000-8000-0000000005f1', 'ZLS lecture notes', 'lecture_notes', 'ICT', 'ZLS 1000', 2024,
   'ICT/ZLS1000/zls-notes.pdf');
insert into public.resources (id, title, type, department, author, is_physical, total_copies, available_copies) values
  ('00000000-0000-4000-8000-0000000005f2', 'ZLS book', 'book', 'ICT', 'A. Author', true, 1, 1);
insert into storage.objects (bucket_id, name) values ('study-files', '00000000-0000-4000-8000-0000000005b0/b-private.pdf');

-- ================================================================ signed out
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);

select pg_temp.t('X1', 'Signed out: read notes', 'denied',
  'select count(*) from public.study_notes');
select pg_temp.t('X2', 'Signed out: add a note', 'error',
  $q$insert into public.study_notes (title, body) values ('t', 'b')$q$);
select pg_temp.t('X3', 'Signed out: read AI usage', 'denied',
  'select count(*) from public.study_ai_usage');
select pg_temp.t('X4', 'Signed out: ask for the AI allowance', 'error',
  'select count(*) from public.study_ai_status()');
select pg_temp.t('X5', 'Signed out: take an AI request from the allowance', 'error',
  $q$select length(public.study_ai_consume('00000000-0000-4000-8000-0000000005a0')::text)$q$);
select pg_temp.t('X6', 'Signed out: store an AI result', 'error',
  $q$select length(public.study_ai_store('00000000-0000-4000-8000-0000000005b0',
     '00000000-0000-4000-8000-0000000005b1', 'summary', repeat('b', 64), 'm', '{"summary":"x"}')::text)$q$);

-- ================================================================ student A
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000005a0","role":"authenticated"}', false);

-- Reading B's rows: RLS hides them, so every count is zero.
select pg_temp.t('R1', 'A reads B''s notes', 'rows=0',
  $q$select count(*) from public.study_notes where user_id = '00000000-0000-4000-8000-0000000005b0'$q$);
select pg_temp.t('R2', 'A reads B''s summaries', 'rows=0',
  'select count(*) from public.study_summaries');
select pg_temp.t('R3', 'A reads B''s decks', 'rows=0',
  'select count(*) from public.study_decks');
select pg_temp.t('R4', 'A reads B''s flashcards', 'rows=0',
  'select count(*) from public.study_flashcards');
select pg_temp.t('R5', 'A reads B''s quizzes', 'rows=0',
  'select count(*) from public.study_quizzes');
select pg_temp.t('R6', 'A reads B''s quiz questions', 'rows=0',
  'select count(*) from public.study_quiz_questions');
select pg_temp.t('R7', 'A reads B''s quiz attempts', 'rows=0',
  'select count(*) from public.study_quiz_attempts');
select pg_temp.t('R8', 'A reads B''s AI usage', 'rows=0',
  'select count(*) from public.study_ai_usage');
select pg_temp.t('R9', 'A reads B''s AI cache', 'rows=0',
  'select count(*) from public.study_ai_cache');

-- Changing B's rows: zero rows match, so nothing changes.
select pg_temp.t('U1', 'A edits B''s note', 'rows=0',
  $q$update public.study_notes set title = 'hacked' where id = '00000000-0000-4000-8000-0000000005b1'$q$);
select pg_temp.t('U2', 'A edits B''s summary', 'rows=0',
  $q$update public.study_summaries set body = 'hacked' where id = '00000000-0000-4000-8000-0000000005b2'$q$);
select pg_temp.t('U3', 'A renames B''s deck', 'rows=0',
  $q$update public.study_decks set title = 'hacked' where id = '00000000-0000-4000-8000-0000000005b3'$q$);
select pg_temp.t('U4', 'A edits B''s flashcard', 'rows=0',
  $q$update public.study_flashcards set front = 'hacked' where id = '00000000-0000-4000-8000-0000000005b4'$q$);
select pg_temp.t('U5', 'A renames B''s quiz', 'rows=0',
  $q$update public.study_quizzes set title = 'hacked' where id = '00000000-0000-4000-8000-0000000005b5'$q$);
select pg_temp.t('U6', 'A changes the answer to B''s question', 'rows=0',
  $q$update public.study_quiz_questions set correct_index = 1 where id = '00000000-0000-4000-8000-0000000005b6'$q$);
select pg_temp.t('U7', 'A changes B''s attempt score', 'error',
  $q$update public.study_quiz_attempts set score = 0 where id = '00000000-0000-4000-8000-0000000005b7'$q$);
select pg_temp.t('U8', 'A resets B''s AI usage', 'error',
  $q$update public.study_ai_usage set count = 0 where user_id = '00000000-0000-4000-8000-0000000005b0'$q$);

-- Deleting B's rows.
select pg_temp.t('D1', 'A deletes B''s note', 'rows=0',
  $q$delete from public.study_notes where id = '00000000-0000-4000-8000-0000000005b1'$q$);
select pg_temp.t('D2', 'A deletes B''s summary', 'rows=0',
  $q$delete from public.study_summaries where id = '00000000-0000-4000-8000-0000000005b2'$q$);
select pg_temp.t('D3', 'A deletes B''s deck', 'rows=0',
  $q$delete from public.study_decks where id = '00000000-0000-4000-8000-0000000005b3'$q$);
select pg_temp.t('D4', 'A deletes B''s flashcard', 'rows=0',
  $q$delete from public.study_flashcards where id = '00000000-0000-4000-8000-0000000005b4'$q$);
select pg_temp.t('D5', 'A deletes B''s quiz', 'rows=0',
  $q$delete from public.study_quizzes where id = '00000000-0000-4000-8000-0000000005b5'$q$);
select pg_temp.t('D6', 'A deletes B''s quiz question', 'rows=0',
  $q$delete from public.study_quiz_questions where id = '00000000-0000-4000-8000-0000000005b6'$q$);
select pg_temp.t('D7', 'A deletes B''s quiz attempt', 'rows=0',
  $q$delete from public.study_quiz_attempts where id = '00000000-0000-4000-8000-0000000005b7'$q$);
select pg_temp.t('D8', 'A deletes B''s AI usage', 'denied',
  $q$delete from public.study_ai_usage where user_id = '00000000-0000-4000-8000-0000000005b0'$q$);
select pg_temp.t('D9', 'A deletes B''s AI cache', 'denied',
  $q$delete from public.study_ai_cache where id = '00000000-0000-4000-8000-0000000005b8'$q$);

-- Writing into B's space or claiming B's identity.
select pg_temp.t('W1', 'A adds a note owned by B', 'error',
  $q$insert into public.study_notes (user_id, title, body)
     values ('00000000-0000-4000-8000-0000000005b0', 'planted', 'planted')$q$);
select pg_temp.t('W2', 'A adds a summary to B''s note', 'error',
  $q$insert into public.study_summaries (note_id, body)
     values ('00000000-0000-4000-8000-0000000005b1', 'planted')$q$);
select pg_temp.t('W3', 'A adds a card to B''s deck', 'error',
  $q$insert into public.study_flashcards (deck_id, front, back)
     values ('00000000-0000-4000-8000-0000000005b3', 'planted', 'planted')$q$);
select pg_temp.t('W4', 'A adds a question to B''s quiz', 'error',
  $q$insert into public.study_quiz_questions (quiz_id, prompt, options, correct_index)
     values ('00000000-0000-4000-8000-0000000005b5', 'planted', array['a','b'], 0)$q$);
select pg_temp.t('W5', 'A records an attempt on B''s quiz', 'error',
  $q$insert into public.study_quiz_attempts (quiz_id, answers)
     values ('00000000-0000-4000-8000-0000000005b5', '{}')$q$);
select pg_temp.t('W6', 'A writes their own AI usage row', 'error',
  $q$insert into public.study_ai_usage (user_id, day, count)
     values ('00000000-0000-4000-8000-0000000005a0', public.study_today(), 0)$q$);
select pg_temp.t('W7', 'A plants a result in the AI cache', 'error',
  $q$insert into public.study_ai_cache (user_id, note_id, kind, content_hash, model, result)
     values ('00000000-0000-4000-8000-0000000005a0', '00000000-0000-4000-8000-0000000005b1',
             'summary', repeat('c', 64), 'fake', '{"summary":"x"}')$q$);
select pg_temp.t('W8', 'A labels their own summary as AI made', 'error',
  $q$insert into public.study_summaries (note_id, body, source)
     values ('00000000-0000-4000-8000-0000000005b1', 'x', 'ai')$q$);

-- The AI functions the edge function uses are not callable by students.
select pg_temp.t('F1', 'A takes from the allowance directly', 'error',
  $q$select length(public.study_ai_consume('00000000-0000-4000-8000-0000000005a0')::text)$q$);
select pg_temp.t('F2', 'A reads B''s note through the AI prepare function', 'error',
  $q$select length(public.study_ai_prepare('00000000-0000-4000-8000-0000000005b0',
     '00000000-0000-4000-8000-0000000005b1', 'summary')::text)$q$);
select pg_temp.t('F3', 'A stores an unvalidated AI result', 'error',
  $q$select length(public.study_ai_store('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005b1', 'summary', repeat('b', 64), 'm', '{"summary":"x"}')::text)$q$);
select pg_temp.t('F4+', 'A sees their own full allowance', 'value=10',
  'select remaining from public.study_ai_status()');

-- Positive controls and shape rules on A's own data.
select pg_temp.t('P1+', 'A adds a note', 'rows=1',
  $q$insert into public.study_notes (title, body)
     values ('A note', 'Ohm''s law: V = I R. Power: P = V I.')$q$);
select pg_temp.t('P2+', 'The new note belongs to A', 'rows=1',
  $q$select count(*) from public.study_notes
     where title = 'A note' and user_id = '00000000-0000-4000-8000-0000000005a0'$q$);
select pg_temp.t('P3', 'A note with a blank title', 'error',
  $q$insert into public.study_notes (title, body) values ('   ', 'x')$q$);
select pg_temp.t('P4', 'A note longer than 20000 characters', 'error',
  $q$insert into public.study_notes (title, body) values ('Long', repeat('x', 20001))$q$);
select pg_temp.t('P5+', 'A adds a summary to their own note', 'rows=1',
  $q$insert into public.study_summaries (note_id, body)
     select id, 'Voltage equals current times resistance.' from public.study_notes where title = 'A note'$q$);
select pg_temp.t('P6+', 'A makes a deck from their note', 'rows=1',
  $q$insert into public.study_decks (note_id, title)
     select id, 'A deck' from public.study_notes where title = 'A note'$q$);
select pg_temp.t('P7+', 'A adds a card', 'rows=1',
  $q$insert into public.study_flashcards (deck_id, front, back)
     select id, 'What is Ohm''s law?', 'V = I R' from public.study_decks where title = 'A deck'$q$);
select pg_temp.t('P8', 'A card with a blank front', 'error',
  $q$insert into public.study_flashcards (deck_id, front, back)
     select id, '', 'x' from public.study_decks where title = 'A deck'$q$);
select pg_temp.t('P9+', 'A makes a quiz from their note', 'rows=1',
  $q$insert into public.study_quizzes (note_id, title)
     select id, 'A quiz' from public.study_notes where title = 'A note'$q$);
select pg_temp.t('P10+', 'A adds a question', 'rows=1',
  $q$insert into public.study_quiz_questions (quiz_id, prompt, options, correct_index)
     select id, 'V = ?', array['I R', 'I / R', 'R / I'], 0
       from public.study_quizzes where title = 'A quiz'$q$);
select pg_temp.t('P11+', 'A adds a second question', 'rows=1',
  $q$insert into public.study_quiz_questions (quiz_id, prompt, options, correct_index, position)
     select id, 'P = ?', array['V I', 'V / I'], 0, 1
       from public.study_quizzes where title = 'A quiz'$q$);
select pg_temp.t('P12', 'A question with two identical options', 'error',
  $q$insert into public.study_quiz_questions (quiz_id, prompt, options, correct_index)
     select id, 'Dup', array['Same', ' same '], 0 from public.study_quizzes where title = 'A quiz'$q$);
select pg_temp.t('P13', 'A question whose correct option does not exist', 'error',
  $q$insert into public.study_quiz_questions (quiz_id, prompt, options, correct_index)
     select id, 'Out', array['a', 'b'], 2 from public.study_quizzes where title = 'A quiz'$q$);
select pg_temp.t('P14', 'A question with one option', 'error',
  $q$insert into public.study_quiz_questions (quiz_id, prompt, options, correct_index)
     select id, 'One', array['only'], 0 from public.study_quizzes where title = 'A quiz'$q$);
select pg_temp.t('P15', 'A sends their own score with an attempt', 'error',
  $q$insert into public.study_quiz_attempts (quiz_id, answers, score, total)
     select id, '{}', 99, 99 from public.study_quizzes where title = 'A quiz'$q$);
select pg_temp.t('P16+', 'A takes the quiz (one right, one wrong)', 'rows=1',
  $q$insert into public.study_quiz_attempts (quiz_id, answers)
     select q.id, jsonb_build_object(
              (select id::text from public.study_quiz_questions where prompt = 'V = ?'), 0,
              (select id::text from public.study_quiz_questions where prompt = 'P = ?'), 1)
       from public.study_quizzes q where q.title = 'A quiz'$q$);
select pg_temp.t('P17+', 'The database marked it 1 out of 2', 'value=1/2',
  $q$select score || '/' || total from public.study_quiz_attempts
     where user_id = '00000000-0000-4000-8000-0000000005a0'$q$);
select pg_temp.t('P18', 'An answer that is not one of the options', 'error',
  $q$insert into public.study_quiz_attempts (quiz_id, answers)
     select q.id, jsonb_build_object(
              (select id::text from public.study_quiz_questions where prompt = 'V = ?'), 7)
       from public.study_quizzes q where q.title = 'A quiz'$q$);
select pg_temp.t('P19', 'An answer to B''s question inside A''s attempt', 'error',
  $q$insert into public.study_quiz_attempts (quiz_id, answers)
     select id, '{"00000000-0000-4000-8000-0000000005b6": 0}' from public.study_quizzes where title = 'A quiz'$q$);
select pg_temp.t('P20', 'A moves their note to B', 'error',
  $q$update public.study_notes set user_id = '00000000-0000-4000-8000-0000000005b0' where title = 'A note'$q$);

-- Studying from a PDF.
select pg_temp.t('PF1+', 'A makes a note from a PDF in their own folder', 'rows=1',
  $q$insert into public.study_notes (title, file_path, file_name)
     values ('A pdf note', '00000000-0000-4000-8000-0000000005a0/lecture-3.pdf', 'Lecture 3.pdf')$q$);
select pg_temp.t('PF2', 'A points a note at a PDF in B''s folder', 'error',
  $q$insert into public.study_notes (title, file_path, file_name)
     values ('Stolen', '00000000-0000-4000-8000-0000000005b0/b-private.pdf', 'b.pdf')$q$);
select pg_temp.t('PF3', 'A attaches a file that is not a PDF', 'error',
  $q$insert into public.study_notes (title, file_path, file_name)
     values ('Exe', '00000000-0000-4000-8000-0000000005a0/tool.exe', 'tool.exe')$q$);
-- Since 0014 an empty kit is allowed ("Proceed without materials"); AI
-- help then has nothing to read (see E25 in study_kits_rls.sql).
select pg_temp.t('PF4+', 'A makes an empty kit with no text and no PDF', 'rows=1',
  $q$insert into public.study_notes (title, body) values ('Empty', '   ')$q$);
select pg_temp.t('PF5+', 'A makes a note from a library PDF', 'rows=1',
  $q$insert into public.study_notes (title, resource_id)
     values ('From the library', '00000000-0000-4000-8000-0000000005f1')$q$);
select pg_temp.t('PF6', 'A makes a note from a library item with no PDF', 'error',
  $q$insert into public.study_notes (title, resource_id)
     values ('Book', '00000000-0000-4000-8000-0000000005f2')$q$);
select pg_temp.t('PF7', 'A swaps the PDF behind an existing note', 'error',
  $q$update public.study_notes set file_path = '00000000-0000-4000-8000-0000000005a0/other.pdf' where title = 'A pdf note'$q$);
select pg_temp.t('PF8+', 'A uploads into their own study folder', 'rows=1',
  $q$insert into storage.objects (bucket_id, name) values ('study-files', '00000000-0000-4000-8000-0000000005a0/lecture-3.pdf')$q$);
select pg_temp.t('PF9', 'A uploads into B''s study folder', 'error',
  $q$insert into storage.objects (bucket_id, name) values ('study-files', '00000000-0000-4000-8000-0000000005b0/planted.pdf')$q$);
select pg_temp.t('PF10', 'A lists B''s uploaded PDFs', 'rows=0',
  $q$select count(*) from storage.objects where bucket_id = 'study-files' and name like '00000000-0000-4000-8000-0000000005b0/%'$q$);
select pg_temp.t('PF11', 'A deletes B''s uploaded PDF', 'denied',
  $q$delete from storage.objects where bucket_id = 'study-files' and name like '00000000-0000-4000-8000-0000000005b0/%'$q$);

-- Deleting a note: summaries go with it, the deck and quiz stay.
select pg_temp.t('N1+', 'A deletes their note', 'rows=1',
  $q$delete from public.study_notes where title = 'A note'$q$);
select pg_temp.t('N2+', 'Its summary was deleted with it', 'rows=0',
  'select count(*) from public.study_summaries');
select pg_temp.t('N3+', 'The deck is kept, no longer linked to a note', 'rows=1',
  $q$select count(*) from public.study_decks where title = 'A deck' and note_id is null$q$);
select pg_temp.t('N4+', 'The quiz and its score history are kept', 'rows=1',
  $q$select count(*) from public.study_quiz_attempts a
     join public.study_quizzes q on q.id = a.quiz_id
     where q.title = 'A quiz' and q.note_id is null$q$);

-- ================================================================ librarian
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000005c0","role":"authenticated"}', false);

select pg_temp.t('L1', 'Librarian reads students'' notes', 'rows=0',
  'select count(*) from public.study_notes');
select pg_temp.t('L2', 'Librarian adds a study note', 'error',
  $q$insert into public.study_notes (title, body) values ('staff', 'staff')$q$);
select pg_temp.t('L3', 'Librarian has no AI allowance', 'value=0',
  'select remaining from public.study_ai_status()');

-- ================================================================ edge function
-- What the study-generate function can do with the service role, and the
-- rules it cannot get round even so.
reset role;
set role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', false);

insert into public.study_notes (id, user_id, title, body) values
  ('00000000-0000-4000-8000-0000000005a1', '00000000-0000-4000-8000-0000000005a0',
   'Circuits', 'Ohm''s law relates voltage, current and resistance.');

select pg_temp.t('E1+', 'Prepare returns A''s typed note with no PDF', 'value=Circuits/',
  $q$select (p ->> 'title') || '/' || coalesce(p ->> 'file_path', '')
       from (select public.study_ai_prepare('00000000-0000-4000-8000-0000000005a0',
             '00000000-0000-4000-8000-0000000005a1', 'summary') as p) x$q$);
select pg_temp.t('E2', 'Prepare for A cannot open B''s note', 'value=not_found',
  $q$select public.study_ai_prepare('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005b1', 'summary') ->> 'error'$q$);
select pg_temp.t('E3', 'Prepare refuses an unknown type', 'value=bad_type',
  $q$select public.study_ai_prepare('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005a1', 'essay') ->> 'error'$q$);
select pg_temp.t('E4', 'Prepare refuses a librarian', 'value=not_student',
  $q$select public.study_ai_prepare('00000000-0000-4000-8000-0000000005c0',
     '00000000-0000-4000-8000-0000000005a1', 'summary') ->> 'error'$q$);

-- Malformed results are refused and nothing is kept.
select pg_temp.t('E5', 'Store a quiz with two correct options', 'error',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005a1', 'quiz',
     public.study_note_hash('Circuits', 'Ohm''s law relates voltage, current and resistance.'), 'm',
     '{"questions":[{"question":"V?","options":[{"text":"IR","is_correct":true},{"text":"I/R","is_correct":true}]}]}')$q$);
select pg_temp.t('E6', 'Store flashcards with an empty card', 'error',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005a1', 'flashcards',
     public.study_note_hash('Circuits', 'Ohm''s law relates voltage, current and resistance.'), 'm',
     '{"cards":[{"question":"","answer":"x"}]}')$q$);
select pg_temp.t('E7', 'Store a result for content the note no longer has', 'error',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005a1', 'summary', repeat('d', 64), 'm', '{"summary":"x"}')$q$);
select pg_temp.t('E8', 'Store against B''s note on A''s behalf', 'error',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005b1', 'summary',
     public.study_note_hash('B private note', 'Only B may read this.'), 'm', '{"summary":"x"}')$q$);
select pg_temp.t('E9', 'Nothing from the refused results was kept', 'rows=0',
  $q$select (select count(*) from public.study_ai_cache where user_id = '00000000-0000-4000-8000-0000000005a0')
          + (select count(*) from public.study_quizzes where source = 'ai')
          + (select count(*) from public.study_decks where source = 'ai')$q$);

select pg_temp.t('E10+', 'Store a valid quiz', 'value=false',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005a1', 'quiz',
     public.study_note_hash('Circuits', 'Ohm''s law relates voltage, current and resistance.'), 'm',
     '{"questions":[{"question":"V = ?","options":[{"text":"I R","is_correct":true},{"text":"I / R","is_correct":false}],"explanation":"Ohm''s law"}]}')
     ->> 'reused'$q$);
select pg_temp.t('E11+', 'The quiz was saved for A, marked AI, with the right answer', 'rows=1',
  $q$select count(*) from public.study_quizzes q
     join public.study_quiz_questions qq on qq.quiz_id = q.id
     where q.user_id = '00000000-0000-4000-8000-0000000005a0' and q.source = 'ai'
       and qq.options = array['I R', 'I / R'] and qq.correct_index = 0$q$);
select pg_temp.t('E12+', 'The cache now answers for this exact content', 'rows=1',
  $q$select count(*) from (select public.study_ai_cache_find('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005a1', 'quiz', '') ->> 'cache_id' as id) x
     where id is not null$q$);
select pg_temp.t('E13+', 'Using the cached result again gives back the same quiz', 'value=true',
  $q$select (public.study_ai_materialise('00000000-0000-4000-8000-0000000005a0',
     (public.study_ai_cache_find('00000000-0000-4000-8000-0000000005a0',
       '00000000-0000-4000-8000-0000000005a1', 'quiz', '') ->> 'cache_id')::uuid)
     ->> 'reused')::boolean$q$);

-- Where the Edge Function finds each note's PDF.
select pg_temp.t('E21+', 'Prepare points at A''s upload in study-files', 'value=study-files',
  $q$select public.study_ai_prepare('00000000-0000-4000-8000-0000000005a0', id, 'quiz') ->> 'file_bucket'
       from public.study_notes where title = 'A pdf note'$q$);
select pg_temp.t('E22+', 'Prepare points at the library PDF in resources', 'value=resources ICT/ZLS1000/zls-notes.pdf',
  $q$select (p ->> 'file_bucket') || ' ' || (p ->> 'file_path')
       from (select public.study_ai_prepare('00000000-0000-4000-8000-0000000005a0', id, 'quiz') as p
               from public.study_notes where title = 'From the library') x$q$);
select pg_temp.t('E23+', 'A different PDF gives a different cache key', 'value=true',
  $q$select (public.study_ai_cache_find('00000000-0000-4000-8000-0000000005a0', id, 'quiz', repeat('1', 64)) ->> 'content_hash')
         <> (public.study_ai_cache_find('00000000-0000-4000-8000-0000000005a0', id, 'quiz', repeat('2', 64)) ->> 'content_hash')
       from public.study_notes where title = 'A pdf note'$q$);
select pg_temp.t('E24', 'A result for one PDF cannot be stored against another', 'error',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000005a0', id, 'summary',
       public.study_ai_cache_find('00000000-0000-4000-8000-0000000005a0', id, 'summary', repeat('1', 64)) ->> 'content_hash',
       'm', '{"summary":"x"}', repeat('2', 64))
       from public.study_notes where title = 'A pdf note'$q$);

-- The daily limit: ten requests, then refusals.
select pg_temp.t('E14+', 'First request of the day leaves 9', 'value=9',
  $q$select public.study_ai_consume('00000000-0000-4000-8000-0000000005a0')$q$);
select pg_temp.t('E15+', 'Requests two to ten are allowed', 'value=0',
  $q$select min(public.study_ai_consume('00000000-0000-4000-8000-0000000005a0')) from generate_series(1, 9)$q$);
select pg_temp.t('E16', 'The eleventh request is refused', 'value=-1',
  $q$select public.study_ai_consume('00000000-0000-4000-8000-0000000005a0')$q$);
select pg_temp.t('E17', 'Prepare now reports the limit', 'value=limit_reached',
  $q$select public.study_ai_prepare('00000000-0000-4000-8000-0000000005a0',
     '00000000-0000-4000-8000-0000000005a1', 'summary') ->> 'error'$q$);
select pg_temp.t('E18+', 'B''s allowance is separate (3 used, 1 more leaves 6)', 'value=6',
  $q$select public.study_ai_consume('00000000-0000-4000-8000-0000000005b0')$q$);

reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000005a0","role":"authenticated"}', false);
select pg_temp.t('E19+', 'A sees 0 left today', 'value=0',
  'select remaining from public.study_ai_status()');
select pg_temp.t('E20+', 'A can read the AI quiz made for them', 'rows=1',
  $q$select count(*) from public.study_quizzes where source = 'ai'$q$);

-- ================================================================ clean up
reset role;
select set_config('request.jwt.claims', '', false);

-- Supabase blocks DELETE on storage.objects unless the Storage API asks
-- for it with this setting; the clean-up removes only the test's own file
-- records, then turns it off again.
select set_config('storage.allow_delete_query', 'true', false);
delete from public.profiles where id in (select id from auth.users where email like 'zl-study-%@example.invalid');
delete from public.resources where id in ('00000000-0000-4000-8000-0000000005f1', '00000000-0000-4000-8000-0000000005f2');
delete from storage.objects where bucket_id = 'study-files'
   and name like any (array['00000000-0000-4000-8000-0000000005a0/%', '00000000-0000-4000-8000-0000000005b0/%']);
delete from public.roll     where student_number like 'ZLSTUDY%';
delete from auth.users      where email like 'zl-study-%@example.invalid';
select set_config('storage.allow_delete_query', 'false', false);

-- ---------------------------------------------------------------- results
select id, test, expected, actual, outcome
from pg_temp.results
order by case left(id, 1) when 'X' then 1 when 'R' then 2 when 'U' then 3
                          when 'D' then 4 when 'W' then 5 when 'F' then 6
                          when 'P' then 7 when 'N' then 8 when 'L' then 9 else 10 end,
         nullif(regexp_replace(id, '\D', '', 'g'), '')::int;
