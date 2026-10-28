-- ZutLib: SAMPLE DATA for demonstrating the study assistant
--
-- Creates two clearly labelled demo students and gives them sample notes,
-- a flashcard deck and a quiz, so the Study tab is not empty in front of
-- the judges. Everything it creates has "Sample" in its title.
--
--   Sample Student A (demo)   sample.student.a@zutlib.test   owns 3 notes, 1 deck, 1 quiz
--   Sample Student B (demo)   sample.student.b@zutlib.test   owns 1 note (to show A cannot see it)
--
-- HOW TO RUN (same pattern as scripts/bootstrap_accounts.sql):
--   1. Supabase dashboard -> Authentication -> Users -> Add user -> Create new user
--        Email: sample.student.a@zutlib.test, a password of your choice,
--        tick "Auto Confirm User". Repeat for sample.student.b@zutlib.test.
--      (The passwords live only in your dashboard, never in this repository.)
--   2. SQL Editor -> New query -> paste this file -> Run.
--
-- Safe to run again: it removes the demo students' previous study data
-- and recreates it, so the demo always starts from the same state. It
-- never touches any other account.

-- ---------------------------------------------------------------- accounts
-- Stop with a clear message if step 1 was skipped.
do $$
begin
  if (select count(*) from auth.users
       where lower(email) in ('sample.student.a@zutlib.test', 'sample.student.b@zutlib.test')) <> 2 then
    raise exception 'Create both demo users in Authentication -> Users first (see step 1 at the top of this file).';
  end if;
end $$;

-- Since 0012 signing up makes a pending student profile automatically.
-- These two are demo accounts, so approve them and name them clearly.
update public.profiles p
   set full_name = s.full_name, department = 'ICT', role = 'student', status = 'active', decided_at = now()
  from (values
    ('sample.student.a@zutlib.test', 'Sample Student A (demo)'),
    ('sample.student.b@zutlib.test', 'Sample Student B (demo)')
  ) as s(email, full_name)
  join auth.users u on lower(u.email) = s.email
 where p.id = u.id;

-- ---------------------------------------------------------------- reset
-- Start from a clean slate for the two demo accounts only.
delete from public.study_notes          where user_id in (select id from auth.users where lower(email) like 'sample.student._@zutlib.test');
delete from public.study_decks          where user_id in (select id from auth.users where lower(email) like 'sample.student._@zutlib.test');
delete from public.study_quizzes        where user_id in (select id from auth.users where lower(email) like 'sample.student._@zutlib.test');
delete from public.study_ai_usage       where user_id in (select id from auth.users where lower(email) like 'sample.student._@zutlib.test');

-- ---------------------------------------------------------------- student A
with a as (select id from auth.users where lower(email) = 'sample.student.a@zutlib.test'),
notes as (
  insert into public.study_notes (user_id, title, course_code, body)
  select a.id, n.title, n.course, n.body from a, (values
    ('Sample: Ohm''s law and resistors', 'EEE 2021',
     'Ohm''s law states that the current through a conductor is directly proportional to the voltage across it, provided the temperature stays constant. It is written V = I R, where V is the voltage in volts, I is the current in amperes and R is the resistance in ohms.' || E'\n\n' ||
     'Resistors in series carry the same current. Their total resistance is the sum of the individual resistances: R = R1 + R2 + R3. The voltage divides between them in proportion to their resistance.' || E'\n\n' ||
     'Resistors in parallel share the same voltage. The total resistance is found from 1/R = 1/R1 + 1/R2 + 1/R3, so the total is always smaller than the smallest resistor. For two resistors this simplifies to R = (R1 x R2) / (R1 + R2).' || E'\n\n' ||
     'Power dissipated in a resistor is P = V I, which can also be written P = I squared R or P = V squared / R. Power is measured in watts.'),
    ('Sample: The business model canvas', 'BSS 4020',
     'The business model canvas is a one page tool for describing how a business creates, delivers and captures value. It has nine building blocks.' || E'\n\n' ||
     'Customer segments are the groups of people the business serves. Value propositions are the bundle of products and services that solve a problem for each segment. Channels describe how the value reaches customers, and customer relationships describe the kind of relationship kept with each segment.' || E'\n\n' ||
     'Revenue streams show how money is earned from each segment. Key resources, key activities and key partnerships are what the business needs, what it must do well, and who helps it. The cost structure lists the most important costs of running the model.' || E'\n\n' ||
     'Entrepreneurs use the canvas to test assumptions quickly before committing money, and to compare different ways of running the same idea.'),
    ('Sample: Loops in C', 'ICT 2010',
     'A loop repeats a block of statements. C has three loops: for, while and do while.' || E'\n\n' ||
     'A for loop is used when the number of repetitions is known. It has an initialisation, a condition and an update, for example for (int i = 0; i < 10; i++). The condition is checked before every repetition.' || E'\n\n' ||
     'A while loop checks its condition before each repetition, so its body may run zero times. A do while loop checks its condition after the body, so its body always runs at least once.' || E'\n\n' ||
     'The break statement leaves the loop immediately. The continue statement skips the rest of the current repetition and moves to the next one. A loop whose condition never becomes false is an infinite loop.')
  ) as n(title, course, body)
  returning id, title, user_id
),
deck as (
  insert into public.study_decks (user_id, note_id, title)
  select user_id, id, 'Sample: Ohm''s law flashcards' from notes where title = 'Sample: Ohm''s law and resistors'
  returning id, user_id
),
cards as (
  insert into public.study_flashcards (user_id, deck_id, front, back, position)
  select deck.user_id, deck.id, c.front, c.back, c.pos from deck, (values
    ('State Ohm''s law as a formula.', 'V = I R', 0),
    ('What is the unit of resistance?', 'The ohm', 1),
    ('Total resistance of resistors in series?', 'The sum: R = R1 + R2 + R3', 2),
    ('Is the total resistance of resistors in parallel larger or smaller than the smallest one?', 'Smaller', 3)
  ) as c(front, back, pos)
  returning 1
),
quiz as (
  insert into public.study_quizzes (user_id, note_id, title)
  select user_id, id, 'Sample: Loops in C quiz' from notes where title = 'Sample: Loops in C'
  returning id, user_id
)
insert into public.study_quiz_questions (user_id, quiz_id, prompt, options, correct_index, explanation, position)
select quiz.user_id, quiz.id, q.prompt, q.options, q.correct, q.why, q.pos from quiz, (values
  ('Which loop always runs its body at least once?',
   array['for', 'while', 'do while', 'none of them'], 2,
   'A do while loop checks its condition after the body.', 0),
  ('What does the continue statement do?',
   array['Leaves the loop', 'Skips to the next repetition', 'Restarts the program', 'Ends the function'], 1,
   'continue skips the rest of the current repetition.', 1),
  ('When is a for loop the natural choice?',
   array['When the number of repetitions is known', 'When the loop must run forever', 'Only for reading files'], 0,
   'A for loop bundles the start, the condition and the update.', 2)
) as q(prompt, options, correct, why, pos);

-- ---------------------------------------------------------------- student B
insert into public.study_notes (user_id, title, course_code, body)
select id, 'Sample: Student B''s private note', 'ICT 2010',
       'This note belongs to Sample Student B. Signed in as Sample Student A, it must not appear anywhere.'
from auth.users where lower(email) = 'sample.student.b@zutlib.test';

-- ---------------------------------------------------------------- check
-- Expect: A has 3 notes, 1 deck with 4 cards, 1 quiz with 3 questions; B has 1 note.
select p.full_name,
       (select count(*) from public.study_notes n where n.user_id = p.id) as notes,
       (select count(*) from public.study_flashcards f where f.user_id = p.id) as flashcards,
       (select count(*) from public.study_quiz_questions q where q.user_id = p.id) as quiz_questions
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) in ('sample.student.a@zutlib.test', 'sample.student.b@zutlib.test')
order by u.email;
