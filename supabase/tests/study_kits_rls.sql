-- ZutLib: study kit security tests (0014_study_kits.sql)
--
-- HOW TO RUN: Supabase -> SQL Editor -> New query -> paste this whole file
-- -> Run, after migration 0014. The last result is a table of tests with
-- PASS or FAIL. Like the other test files it makes throwaway accounts,
-- acts as each of them the way the API does, and deletes everything it
-- made. Safe to run on the live project, and repeatedly.
--
-- Expectations: error | denied (error or no rows) | rows=N | value=X.
-- Tests marked + are positive controls.
--
-- Accounts: a = student A, b = student B, l = librarian.

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

-- A valid AI kit result, as study-generate would store it.
create or replace function pg_temp.kit(n_cards int, n_questions int, two_correct boolean default false,
                                       bad_heading boolean default false)
returns jsonb language sql as $$
  select jsonb_build_object(
    'guide', jsonb_build_object(
      'overview', 'Ohm''s law links voltage, current and resistance.',
      'sections', jsonb_build_array(
        jsonb_build_object('heading', case when bad_heading then '' else 'Ohm''s law' end,
                           'summary', 'V equals I times R.',
                           'points', jsonb_build_array('V = I R', 'Units: volts, amps, ohms')),
        jsonb_build_object('heading', 'Power', 'summary', 'P equals V times I.',
                           'points', jsonb_build_array()))),
    'cards', (select jsonb_agg(jsonb_build_object('term', 'Term ' || i, 'definition', 'Meaning ' || i))
                from generate_series(1, n_cards) i),
    'questions', (select jsonb_agg(jsonb_build_object(
                    'question', 'Question ' || i,
                    'options', jsonb_build_array(
                      jsonb_build_object('text', 'Right', 'is_correct', true),
                      jsonb_build_object('text', 'Wrong one', 'is_correct', two_correct),
                      jsonb_build_object('text', 'Wrong two', 'is_correct', false),
                      jsonb_build_object('text', 'Wrong three', 'is_correct', false)),
                    'explanation', 'Because.',
                    'difficulty', case i % 3 when 0 then 'hard' when 1 then 'easy' else 'medium' end))
                  from generate_series(1, n_questions) i))
$$;

-- ---------------------------------------------------------------- fixtures
-- First remove anything a stopped earlier run left behind.
delete from public.profiles where id in (select id from auth.users where email like 'zl-kit-%@example.invalid');
delete from auth.users where email like 'zl-kit-%@example.invalid';

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000009a0', 'zl-kit-a@example.invalid', '{"full_name": "Kit Student A", "department": "ICT"}'),
  ('00000000-0000-4000-8000-0000000009b0', 'zl-kit-b@example.invalid', '{"full_name": "Kit Student B", "department": "ICT"}'),
  ('00000000-0000-4000-8000-0000000009c0', 'zl-kit-l@example.invalid', '{"full_name": "Kit Librarian"}');
update public.profiles set status = 'active'
 where id in ('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009b0');
update public.profiles set role = 'librarian', status = 'active'
 where id = '00000000-0000-4000-8000-0000000009c0';

-- A's text kit (the AI will be "run" on it below) and B's own deck, card,
-- bank and question, written as the owner so A has something to reach for.
insert into public.study_notes (id, user_id, title, body) values
  ('00000000-0000-4000-8000-0000000009a1', '00000000-0000-4000-8000-0000000009a0',
   'Circuits kit', 'Ohm''s law: V = I R. Power: P = V I.');
insert into public.study_decks (id, user_id, title) values
  ('00000000-0000-4000-8000-0000000009b2', '00000000-0000-4000-8000-0000000009b0', 'B deck');
insert into public.study_flashcards (id, user_id, deck_id, front, back) values
  ('00000000-0000-4000-8000-0000000009b3', '00000000-0000-4000-8000-0000000009b0',
   '00000000-0000-4000-8000-0000000009b2', 'Front', 'Back');
insert into public.study_quizzes (id, user_id, title) values
  ('00000000-0000-4000-8000-0000000009b4', '00000000-0000-4000-8000-0000000009b0', 'B bank');
insert into public.study_quiz_questions (id, user_id, quiz_id, prompt, options, correct_index) values
  ('00000000-0000-4000-8000-0000000009b5', '00000000-0000-4000-8000-0000000009b0',
   '00000000-0000-4000-8000-0000000009b4', 'B question', array['Yes', 'No'], 0);

-- ================================================================ kits (student A)
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000009a0","role":"authenticated"}', false);

select pg_temp.t('K1+', 'A makes a green kit from a YouTube video', 'rows=1',
  $q$insert into public.study_notes (title, body, color, youtube_url)
     values ('Video kit', '', 'green', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ')$q$);
select pg_temp.t('K2', 'A YouTube link in any other form', 'error',
  $q$insert into public.study_notes (title, body, youtube_url)
     values ('Bad link', '', 'https://evil.example/watch?v=dQw4w9WgXcQ')$q$);
select pg_temp.t('K3', 'A kit with both a video and an uploaded PDF', 'error',
  $q$insert into public.study_notes (title, body, youtube_url, file_path, file_name)
     values ('Two sources', '', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
             '00000000-0000-4000-8000-0000000009a0/x.pdf', 'x.pdf')$q$);
select pg_temp.t('K4', 'A colour that is not in the palette', 'error',
  $q$insert into public.study_notes (title, body, color) values ('Purple', 'x', 'purple')$q$);
select pg_temp.t('K5+', 'A changes the colour of their own kit', 'rows=1',
  $q$update public.study_notes set color = 'orange' where id = '00000000-0000-4000-8000-0000000009a1'$q$);
select pg_temp.t('K7+', 'A makes an empty kit (Proceed without materials)', 'rows=1',
  $q$insert into public.study_notes (title, body) values ('Blank kit', '')$q$);
select pg_temp.t('K6', 'A swaps the video behind a kit afterwards', 'error',
  $q$update public.study_notes set youtube_url = 'https://www.youtube.com/watch?v=aaaaaaaaaaa'
     where title = 'Video kit'$q$);

-- ================================================================ the AI makes the kit
reset role;
set role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', false);

select pg_temp.t('E1', 'Prepare returns the YouTube link of a video kit', 'value=https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  $q$select public.study_ai_prepare('00000000-0000-4000-8000-0000000009a0', id, 'kit') ->> 'youtube_url'
       from public.study_notes where title = 'Video kit'$q$);
select pg_temp.t('E2', 'Prepare refuses an empty kit: nothing to read', 'value=no_source',
  $q$select public.study_ai_prepare('00000000-0000-4000-8000-0000000009a0', id, 'kit') ->> 'error'
       from public.study_notes where title = 'Blank kit'$q$);
select pg_temp.t('E3', 'A kit result with two correct options is refused', 'error',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009a1',
       'kit', public.study_note_hash('Circuits kit', 'Ohm''s law: V = I R. Power: P = V I.', ''), 'm',
       pg_temp.kit(6, 6, true), '')$q$);
select pg_temp.t('E4', 'A kit result with an empty section heading is refused', 'error',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009a1',
       'kit', public.study_note_hash('Circuits kit', 'Ohm''s law: V = I R. Power: P = V I.', ''), 'm',
       pg_temp.kit(6, 6, false, true), '')$q$);
select pg_temp.t('E5', 'A kit result with too few cards is refused', 'error',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009a1',
       'kit', public.study_note_hash('Circuits kit', 'Ohm''s law: V = I R. Power: P = V I.', ''), 'm',
       pg_temp.kit(2, 6), '')$q$);
select pg_temp.t('E6', 'Nothing from the refused results was kept', 'rows=0',
  $q$select (select count(*) from public.study_guides where note_id = '00000000-0000-4000-8000-0000000009a1')
          + (select count(*) from public.study_decks where note_id = '00000000-0000-4000-8000-0000000009a1')$q$);
select pg_temp.t('E7+', 'A valid kit is stored', 'value=false',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009a1',
       'kit', public.study_note_hash('Circuits kit', 'Ohm''s law: V = I R. Power: P = V I.', ''), 'm',
       pg_temp.kit(8, 9), '') ->> 'reused'$q$);
select pg_temp.t('E8+', 'One guide, linked to the deck and bank it came with', 'rows=1',
  $q$select count(*) from public.study_guides g
       join public.study_decks d on d.id = g.deck_id
       join public.study_quizzes q on q.id = g.quiz_id
      where g.note_id = '00000000-0000-4000-8000-0000000009a1'
        and jsonb_array_length(g.sections) = 2 and d.source = 'ai' and q.source = 'ai'$q$);
select pg_temp.t('E9+', 'All 8 cards were saved as term and definition', 'rows=8',
  $q$select count(*) from public.study_flashcards f
       join public.study_guides g on g.deck_id = f.deck_id
      where g.note_id = '00000000-0000-4000-8000-0000000009a1' and f.front like 'Term %'$q$);
select pg_temp.t('E10+', 'Questions keep their difficulty (3 of 9 are hard)', 'rows=3',
  $q$select count(*) from public.study_quiz_questions qq
       join public.study_guides g on g.quiz_id = qq.quiz_id
      where g.note_id = '00000000-0000-4000-8000-0000000009a1' and qq.difficulty = 3$q$);
select pg_temp.t('E11+', 'The same kit again is reused, not copied', 'value=true',
  $q$select public.study_ai_materialise('00000000-0000-4000-8000-0000000009a0',
       (select cache_id from public.study_guides where note_id = '00000000-0000-4000-8000-0000000009a1')) ->> 'reused'$q$);

-- The note changes and the kit is made again: the old AI deck and bank go.
update public.study_notes set body = 'Ohm''s law and Kirchhoff''s laws.'
 where id = '00000000-0000-4000-8000-0000000009a1';
select pg_temp.t('E12+', 'A changed kit replaces the previous AI kit', 'value=false',
  $q$select public.study_ai_store('00000000-0000-4000-8000-0000000009a0', '00000000-0000-4000-8000-0000000009a1',
       'kit', public.study_note_hash('Circuits kit', 'Ohm''s law and Kirchhoff''s laws.', ''), 'm',
       pg_temp.kit(5, 6), '') ->> 'reused'$q$);
select pg_temp.t('E13+', 'Only one AI deck and one AI bank remain for the kit', 'value=1 1',
  $q$select (select count(*) from public.study_decks where note_id = '00000000-0000-4000-8000-0000000009a1' and source = 'ai')
          || ' ' ||
            (select count(*) from public.study_quizzes where note_id = '00000000-0000-4000-8000-0000000009a1' and source = 'ai')$q$);

-- ================================================================ student A
reset role;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000009a0","role":"authenticated"}', false);

select pg_temp.t('G1+', 'A reads their own study guide', 'rows=1', 'select count(*) from public.study_guides');
select pg_temp.t('G2', 'A writes a study guide directly', 'error',
  $q$insert into public.study_guides (note_id, overview, sections)
     values ('00000000-0000-4000-8000-0000000009a1', 'x', '[{"heading":"h","summary":"","points":[]}]')$q$);
select pg_temp.t('G3', 'A edits the study guide', 'error',
  $q$update public.study_guides set overview = 'changed'$q$);

-- Flashcard boxes
select pg_temp.t('C1+', 'A rates one of their cards Known', 'rows=1',
  $q$select count(*) from (select public.study_rate_card(f.id, 2)
       from public.study_flashcards f join public.study_guides g on g.deck_id = f.deck_id limit 1) x$q$);
select pg_temp.t('C2+', 'A rates the same card again', 'rows=1',
  $q$select count(*) from (select public.study_rate_card(card_id, 3) from public.study_card_progress) x$q$);
select pg_temp.t('C2b+', 'The card moved to Mastered and the review was counted', 'value=3 2',
  $q$select box || ' ' || reviews from public.study_card_progress$q$);
select pg_temp.t('C3', 'A box outside 0 to 3', 'error',
  $q$select count(*) from (select public.study_rate_card(card_id, 7) from public.study_card_progress) x$q$);
select pg_temp.t('C4', 'A rates B''s card', 'error',
  $q$select count(*) from (select public.study_rate_card('00000000-0000-4000-8000-0000000009b3', 1)) x$q$);

-- Smart study stars
select pg_temp.t('Q1+', 'A earns a star on one of their questions', 'rows=1',
  $q$select count(*) from (select public.study_rate_question(qq.id, 1)
       from public.study_quiz_questions qq join public.study_guides g on g.quiz_id = qq.quiz_id limit 1) x$q$);
select pg_temp.t('Q2', 'More than 3 stars', 'error',
  $q$select count(*) from (select public.study_rate_question(question_id, 4) from public.study_question_progress) x$q$);
select pg_temp.t('Q3', 'A rates B''s question', 'error',
  $q$select count(*) from (select public.study_rate_question('00000000-0000-4000-8000-0000000009b5', 1)) x$q$);

-- Tests
select pg_temp.t('T1+', 'A makes a 10 minute test of 3 questions from their bank', 'rows=1',
  $q$insert into public.study_tests (note_id, quiz_id, title, question_ids, time_limit_s)
     select g.note_id, g.quiz_id, 'Practice test',
            (select array_agg(id) from (select id from public.study_quiz_questions
                                         where quiz_id = g.quiz_id order by position limit 3) s), 600
       from public.study_guides g$q$);
select pg_temp.t('T2', 'A test that borrows B''s question', 'error',
  $q$insert into public.study_tests (quiz_id, title, question_ids)
     select quiz_id, 'Borrowed', array['00000000-0000-4000-8000-0000000009b5'::uuid] from public.study_guides$q$);
select pg_temp.t('T3', 'A test with the same question twice', 'error',
  $q$insert into public.study_tests (quiz_id, title, question_ids)
     select g.quiz_id, 'Twice', array[q.id, q.id]
       from public.study_guides g join public.study_quiz_questions q on q.quiz_id = g.quiz_id limit 1$q$);
select pg_temp.t('T4', 'A 30 second time limit', 'error',
  $q$insert into public.study_tests (quiz_id, title, question_ids, time_limit_s)
     select g.quiz_id, 'Short', array[q.id], 30
       from public.study_guides g join public.study_quiz_questions q on q.quiz_id = g.quiz_id limit 1$q$);
select pg_temp.t('T5+', 'Answering all three correctly scores 3/3', 'value=3/3',
  $q$with ins as (
       insert into public.study_test_attempts (test_id, answers, seconds_taken)
       select t.id, (select jsonb_object_agg(q::text, 0) from unnest(t.question_ids) q), 95
         from public.study_tests t where t.title = 'Practice test'
       returning score, total)
     select score || '/' || total from ins$q$);
select pg_temp.t('T6', 'A sends their own score with an attempt', 'error',
  $q$insert into public.study_test_attempts (test_id, answers, score, total)
     select id, '{}', 99, 99 from public.study_tests where title = 'Practice test'$q$);
select pg_temp.t('T7', 'An answer to a question that is not in the test', 'error',
  $q$insert into public.study_test_attempts (test_id, answers)
     select id, '{"00000000-0000-4000-8000-0000000009b5": 0}' from public.study_tests where title = 'Practice test'$q$);
select pg_temp.t('T8', 'A changes a recorded test score', 'error',
  $q$update public.study_test_attempts set score = 0$q$);

-- Games
select pg_temp.t('S1+', 'A saves a matching game score', 'rows=1',
  $q$insert into public.study_game_scores (deck_id, game, score, seconds)
     select deck_id, 'matching', 120, 34 from public.study_guides$q$);
select pg_temp.t('S2', 'A game that does not exist', 'error',
  $q$insert into public.study_game_scores (deck_id, game, score, seconds)
     select deck_id, 'chess', 1, 1 from public.study_guides$q$);
select pg_temp.t('S3', 'A saves a score on B''s deck', 'error',
  $q$insert into public.study_game_scores (deck_id, game, score, seconds)
     values ('00000000-0000-4000-8000-0000000009b2', 'matching', 9999, 1)$q$);
select pg_temp.t('S4', 'A raises a saved score', 'error',
  $q$update public.study_game_scores set score = 9999$q$);

-- ================================================================ student B
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000009b0","role":"authenticated"}', false);
select pg_temp.t('B1', 'B reads A''s study guide', 'rows=0', 'select count(*) from public.study_guides');
select pg_temp.t('B2', 'B reads A''s card progress', 'rows=0', 'select count(*) from public.study_card_progress');
select pg_temp.t('B3', 'B reads A''s stars', 'rows=0', 'select count(*) from public.study_question_progress');
select pg_temp.t('B4', 'B reads A''s tests', 'rows=0', 'select count(*) from public.study_tests');
select pg_temp.t('B5', 'B reads A''s test scores', 'rows=0', 'select count(*) from public.study_test_attempts');
select pg_temp.t('B6', 'B reads A''s game scores', 'rows=0', 'select count(*) from public.study_game_scores');
select pg_temp.t('B7', 'B deletes A''s study guide', 'rows=0', 'delete from public.study_guides');
select pg_temp.t('B8', 'B records an attempt on A''s test', 'error',
  $q$insert into public.study_test_attempts (test_id, answers)
     select id, '{}' from public.study_tests limit 1
     union all select gen_random_uuid(), '{}'$q$);

-- ================================================================ librarian
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000009c0","role":"authenticated"}', false);
select pg_temp.t('L1', 'A librarian reads study guides', 'rows=0', 'select count(*) from public.study_guides');
select pg_temp.t('L2', 'A librarian makes a test', 'error',
  $q$insert into public.study_tests (quiz_id, title, question_ids)
     values ('00000000-0000-4000-8000-0000000009b4', 'Staff', array['00000000-0000-4000-8000-0000000009b5'::uuid])$q$);

-- ================================================================ signed out
reset role;
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
select pg_temp.t('X1', 'Signed out: study guides', 'denied', 'select count(*) from public.study_guides');
select pg_temp.t('X2', 'Signed out: rate a card', 'error',
  $q$select count(*) from (select public.study_rate_card('00000000-0000-4000-8000-0000000009b3', 1)) x$q$);

-- ================================================================ clean up
reset role;
select set_config('request.jwt.claims', '', false);
delete from public.profiles where id in (select id from auth.users where email like 'zl-kit-%@example.invalid');
delete from auth.users where email like 'zl-kit-%@example.invalid';

-- ---------------------------------------------------------------- results
select id, test, expected, actual, outcome
from pg_temp.results
order by case left(id, 1) when 'K' then 1 when 'E' then 2 when 'G' then 3 when 'C' then 4
                          when 'Q' then 5 when 'T' then 6 when 'S' then 7 when 'B' then 8
                          when 'L' then 9 else 10 end,
         nullif(regexp_replace(id, '\D', '', 'g'), '')::int;
