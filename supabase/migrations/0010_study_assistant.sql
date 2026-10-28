-- ZutLib: study assistant (notes, summaries, flashcards, quizzes, AI help)
--
-- Read this file top to bottom in the defence. It is in seven parts:
--
--   1. Settings      the AI daily limits, written once, here
--   2. Helpers       is_student(), the shape check for quiz options,
--                    and a row cap that stops one account filling the database
--   3. Tables        nine tables, every rule on lengths and shapes written as
--                    a CHECK constraint so the database refuses bad data no
--                    matter which client sent it
--   4. Row security  deny by default; a student sees and changes only rows
--                    whose user_id is their own account
--   5. Privileges    which columns a student may write at all
--   6. Quiz scoring  the database marks a quiz attempt, the phone cannot
--   7. AI functions  called only by the study-generate edge function with
--                    the service role; no student can call them
--
-- Ownership is never trusted from the app. user_id defaults to auth.uid()
-- (the account in the signed request), students are not allowed to write
-- the column at all, and every child row (a flashcard, a quiz question, an
-- attempt) carries the same user_id as its parent through a two-column
-- foreign key. A card can therefore never be attached to another student's
-- deck, even if a policy were written wrongly.
--
-- What happens when a note is deleted (see DECISIONS.md):
--   summaries of it      deleted with it (a summary only means something
--                        next to its note)
--   decks and quizzes    kept, with note_id set to null, so cards a student
--                        has studied and quiz scores they earned survive
--   AI cache entries     deleted with it

-- ================================================================ 1. settings
-- The only place these numbers exist. The app reads them back through
-- study_ai_status(); the edge function never repeats them.
--
-- Per student: 10 AI requests a day. Whole project: 150 a day, which keeps
-- every student together well inside the Gemini free tier's per-project
-- daily quota (see DECISIONS.md for how the figure was chosen).
create or replace function public.study_ai_daily_limit()
returns int language sql immutable as $$ select 10 $$;

create or replace function public.study_ai_project_daily_limit()
returns int language sql immutable as $$ select 150 $$;

-- "Today" is the calendar day in Zambia, so a student's allowance renews at
-- local midnight rather than at some hour that means nothing to them.
create or replace function public.study_today()
returns date language sql stable as $$
  select (now() at time zone 'Africa/Lusaka')::date
$$;

-- ================================================================ 2. helpers
-- True only for a signed-in account whose profile says student. The study
-- assistant is a student feature; staff accounts get nothing from it.
-- SECURITY DEFINER so it can read profiles without going through the
-- profiles policy (the same pattern as is_staff in 0002_rls.sql).
create or replace function public.is_student()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role = 'student' from public.profiles where id = auth.uid()),
    false)
$$;

-- A multiple choice question needs 2 to 6 options, none blank, none longer
-- than 200 characters, and no two the same (ignoring case and spaces).
create or replace function public.study_options_valid(opts text[])
returns boolean language sql immutable as $$
  select opts is not null
     and array_ndims(opts) = 1
     and cardinality(opts) between 2 and 6
     and not exists (
       select 1 from unnest(opts) o
       where o is null or length(btrim(o)) = 0 or length(o) > 200)
     and (select count(distinct lower(btrim(o))) from unnest(opts) o)
         = cardinality(opts)
$$;

-- Caps how many rows one owner (or one parent, such as a deck) may hold.
-- Without it a student with the public API could insert millions of rows
-- and fill the free database for everyone.
--   TG_ARGV[0]  the column that groups the rows (user_id, deck_id, ...)
--   TG_ARGV[1]  the most rows allowed in one group
create or replace function public.study_cap_rows()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  group_value uuid := (to_jsonb(new) ->> tg_argv[0])::uuid;
  max_rows    int  := tg_argv[1]::int;
  existing    int;
begin
  execute format('select count(*) from %I.%I where %I = $1',
                 tg_table_schema, tg_table_name, tg_argv[0])
    into existing using group_value;
  if existing >= max_rows then
    raise exception 'You have reached the limit of % for this list', max_rows
      using errcode = '54000';
  end if;
  return new;
end $$;

revoke execute on function public.study_cap_rows() from public;

-- ================================================================ 3. tables

-- ---------------------------------------------------------------- notes
create table public.study_notes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid()
               references public.profiles(id) on delete cascade,
  title        text not null,
  body         text not null,
  course_code  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint study_notes_title_len
    check (length(btrim(title)) between 1 and 200 and length(title) <= 200),
  constraint study_notes_body_len
    check (length(btrim(body)) >= 1 and length(body) <= 20000),
  constraint study_notes_course_len
    check (course_code is null or length(btrim(course_code)) between 1 and 20),
  -- lets child tables point at (note, owner) as a pair
  constraint study_notes_id_owner unique (id, user_id)
);

create index study_notes_user_idx on public.study_notes (user_id, updated_at desc);

-- ---------------------------------------------------------------- AI cache
-- One validated AI result per note, kind and exact note content. If the
-- note has not changed, the same request is answered from here and Gemini
-- is not called again. Written only by the edge function.
create table public.study_ai_cache (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  note_id       uuid not null,
  kind          text not null,
  content_hash  text not null,
  model         text not null,
  result        jsonb not null,
  created_at    timestamptz not null default now(),

  constraint study_ai_cache_kind check (kind in ('summary', 'flashcards', 'quiz')),
  constraint study_ai_cache_hash check (content_hash ~ '^[0-9a-f]{64}$'),
  constraint study_ai_cache_model check (length(model) between 1 and 100),
  constraint study_ai_cache_result check (jsonb_typeof(result) = 'object'),
  constraint study_ai_cache_note foreign key (note_id, user_id)
    references public.study_notes (id, user_id) on delete cascade,
  constraint study_ai_cache_one unique (note_id, kind, content_hash),
  constraint study_ai_cache_id_owner unique (id, user_id)
);

create index study_ai_cache_user_idx on public.study_ai_cache (user_id);

-- ---------------------------------------------------------------- summaries
create table public.study_summaries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
              references public.profiles(id) on delete cascade,
  note_id     uuid not null,
  body        text not null,
  source      text not null default 'manual',
  cache_id    uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint study_summaries_body_len
    check (length(btrim(body)) >= 1 and length(body) <= 5000),
  constraint study_summaries_source check (source in ('manual', 'ai')),
  constraint study_summaries_note foreign key (note_id, user_id)
    references public.study_notes (id, user_id) on delete cascade,
  constraint study_summaries_cache foreign key (cache_id, user_id)
    references public.study_ai_cache (id, user_id) on delete set null (cache_id)
);

create index study_summaries_note_idx on public.study_summaries (note_id, created_at desc);
create index study_summaries_user_idx on public.study_summaries (user_id);
create index study_summaries_cache_idx on public.study_summaries (cache_id);

-- ---------------------------------------------------------------- decks
create table public.study_decks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
              references public.profiles(id) on delete cascade,
  note_id     uuid,
  title       text not null,
  source      text not null default 'manual',
  cache_id    uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint study_decks_title_len
    check (length(btrim(title)) between 1 and 200 and length(title) <= 200),
  constraint study_decks_source check (source in ('manual', 'ai')),
  constraint study_decks_note foreign key (note_id, user_id)
    references public.study_notes (id, user_id) on delete set null (note_id),
  constraint study_decks_cache foreign key (cache_id, user_id)
    references public.study_ai_cache (id, user_id) on delete set null (cache_id),
  constraint study_decks_id_owner unique (id, user_id)
);

create index study_decks_user_idx on public.study_decks (user_id, updated_at desc);
create index study_decks_note_idx on public.study_decks (note_id);
create index study_decks_cache_idx on public.study_decks (cache_id);

-- ---------------------------------------------------------------- flashcards
create table public.study_flashcards (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
              references public.profiles(id) on delete cascade,
  deck_id     uuid not null,
  front       text not null,
  back        text not null,
  position    int  not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint study_flashcards_front_len
    check (length(btrim(front)) between 1 and 500 and length(front) <= 500),
  constraint study_flashcards_back_len
    check (length(btrim(back)) between 1 and 1000 and length(back) <= 1000),
  constraint study_flashcards_position check (position between 0 and 1000),
  constraint study_flashcards_deck foreign key (deck_id, user_id)
    references public.study_decks (id, user_id) on delete cascade
);

create index study_flashcards_deck_idx on public.study_flashcards (deck_id, position);
create index study_flashcards_user_idx on public.study_flashcards (user_id);

-- ---------------------------------------------------------------- quizzes
create table public.study_quizzes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
              references public.profiles(id) on delete cascade,
  note_id     uuid,
  title       text not null,
  source      text not null default 'manual',
  cache_id    uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint study_quizzes_title_len
    check (length(btrim(title)) between 1 and 200 and length(title) <= 200),
  constraint study_quizzes_source check (source in ('manual', 'ai')),
  constraint study_quizzes_note foreign key (note_id, user_id)
    references public.study_notes (id, user_id) on delete set null (note_id),
  constraint study_quizzes_cache foreign key (cache_id, user_id)
    references public.study_ai_cache (id, user_id) on delete set null (cache_id),
  constraint study_quizzes_id_owner unique (id, user_id)
);

create index study_quizzes_user_idx on public.study_quizzes (user_id, updated_at desc);
create index study_quizzes_note_idx on public.study_quizzes (note_id);
create index study_quizzes_cache_idx on public.study_quizzes (cache_id);

-- ---------------------------------------------------------------- questions
-- Every question is multiple choice with exactly one correct option. The
-- correct option is stored as its position in the options list, so "two
-- correct answers" or "no correct answer" cannot even be written down.
create table public.study_quiz_questions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid()
                 references public.profiles(id) on delete cascade,
  quiz_id        uuid not null,
  prompt         text not null,
  options        text[] not null,
  correct_index  int  not null,
  explanation    text,
  position       int  not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint study_questions_prompt_len
    check (length(btrim(prompt)) between 1 and 500 and length(prompt) <= 500),
  constraint study_questions_options check (public.study_options_valid(options)),
  constraint study_questions_correct
    check (correct_index >= 0 and correct_index < cardinality(options)),
  constraint study_questions_explanation_len
    check (explanation is null or length(explanation) <= 1000),
  constraint study_questions_position check (position between 0 and 1000),
  constraint study_questions_quiz foreign key (quiz_id, user_id)
    references public.study_quizzes (id, user_id) on delete cascade
);

create index study_questions_quiz_idx on public.study_quiz_questions (quiz_id, position);
create index study_questions_user_idx on public.study_quiz_questions (user_id);

-- ---------------------------------------------------------------- attempts
-- answers is {"<question id>": <chosen option index>, ...}. score and total
-- are filled in by the database (part 6), never by the phone.
create table public.study_quiz_attempts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
              references public.profiles(id) on delete cascade,
  quiz_id     uuid not null,
  answers     jsonb not null,
  score       int  not null default 0,
  total       int  not null default 0,
  created_at  timestamptz not null default now(),

  constraint study_attempts_answers check (jsonb_typeof(answers) = 'object'),
  constraint study_attempts_score check (total >= 1 and score between 0 and total),
  constraint study_attempts_quiz foreign key (quiz_id, user_id)
    references public.study_quizzes (id, user_id) on delete cascade
);

create index study_attempts_quiz_idx on public.study_quiz_attempts (quiz_id, created_at desc);
create index study_attempts_user_idx on public.study_quiz_attempts (user_id);

-- ---------------------------------------------------------------- AI usage
-- One row per student per day, counting AI requests that reached Gemini.
-- Students may read their own row; only the edge function writes it.
create table public.study_ai_usage (
  user_id  uuid not null references public.profiles(id) on delete cascade,
  day      date not null,
  count    int  not null default 0,
  primary key (user_id, day),
  constraint study_ai_usage_count check (count >= 0)
);

create index study_ai_usage_day_idx on public.study_ai_usage (day);

-- ---------------------------------------------------------------- triggers
create trigger study_notes_touch     before update on public.study_notes
  for each row execute function public.touch_updated_at();
create trigger study_summaries_touch before update on public.study_summaries
  for each row execute function public.touch_updated_at();
create trigger study_decks_touch     before update on public.study_decks
  for each row execute function public.touch_updated_at();
create trigger study_flashcards_touch before update on public.study_flashcards
  for each row execute function public.touch_updated_at();
create trigger study_quizzes_touch   before update on public.study_quizzes
  for each row execute function public.touch_updated_at();
create trigger study_questions_touch before update on public.study_quiz_questions
  for each row execute function public.touch_updated_at();

-- Row caps (see study_cap_rows above).
create trigger study_notes_cap      before insert on public.study_notes
  for each row execute function public.study_cap_rows('user_id', '300');
create trigger study_summaries_cap  before insert on public.study_summaries
  for each row execute function public.study_cap_rows('note_id', '20');
create trigger study_decks_cap      before insert on public.study_decks
  for each row execute function public.study_cap_rows('user_id', '100');
create trigger study_flashcards_cap before insert on public.study_flashcards
  for each row execute function public.study_cap_rows('deck_id', '200');
create trigger study_quizzes_cap    before insert on public.study_quizzes
  for each row execute function public.study_cap_rows('user_id', '100');
create trigger study_questions_cap  before insert on public.study_quiz_questions
  for each row execute function public.study_cap_rows('quiz_id', '50');
create trigger study_attempts_cap   before insert on public.study_quiz_attempts
  for each row execute function public.study_cap_rows('quiz_id', '200');

-- ================================================================ 4. row security
-- Deny by default: with RLS on and no matching policy, a query sees no
-- rows and a write is refused. Each policy below says "only your own rows,
-- and only if you are a student".
alter table public.study_notes          enable row level security;
alter table public.study_ai_cache       enable row level security;
alter table public.study_summaries      enable row level security;
alter table public.study_decks          enable row level security;
alter table public.study_flashcards     enable row level security;
alter table public.study_quizzes        enable row level security;
alter table public.study_quiz_questions enable row level security;
alter table public.study_quiz_attempts  enable row level security;
alter table public.study_ai_usage       enable row level security;

-- Tables a student fully manages: read, add, change and delete own rows.
create policy study_notes_own on public.study_notes
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

create policy study_summaries_own on public.study_summaries
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

create policy study_decks_own on public.study_decks
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

create policy study_flashcards_own on public.study_flashcards
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

create policy study_quizzes_own on public.study_quizzes
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

create policy study_questions_own on public.study_quiz_questions
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

-- Attempts: a student records and reads their own, and may delete them.
-- There is no update policy, so a score can never be edited afterwards.
create policy study_attempts_read on public.study_quiz_attempts
  for select to authenticated
  using (user_id = auth.uid() and public.is_student());
create policy study_attempts_insert on public.study_quiz_attempts
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_student());
create policy study_attempts_delete on public.study_quiz_attempts
  for delete to authenticated
  using (user_id = auth.uid() and public.is_student());

-- Usage and cache: a student may look at their own rows, nothing more.
-- If a student could write the usage row they could reset their own
-- limit; if they could write the cache they could plant unvalidated "AI"
-- content. So neither table has a write policy for students.
create policy study_ai_usage_read on public.study_ai_usage
  for select to authenticated
  using (user_id = auth.uid() and public.is_student());
create policy study_ai_cache_read on public.study_ai_cache
  for select to authenticated
  using (user_id = auth.uid() and public.is_student());

-- ================================================================ 5. privileges
-- A policy picks WHICH rows; a privilege picks WHICH columns and actions.
-- First take everything away (some projects hand new tables to every API
-- role automatically), then give back exactly what the app needs.
-- user_id, source and cache_id are never writable by a student, so a
-- student cannot claim another owner or label their own text "AI".
revoke all on public.study_notes, public.study_ai_cache, public.study_summaries,
              public.study_decks, public.study_flashcards, public.study_quizzes,
              public.study_quiz_questions, public.study_quiz_attempts,
              public.study_ai_usage
  from public, anon, authenticated;

grant select, delete on public.study_notes to authenticated;
grant insert (title, body, course_code) on public.study_notes to authenticated;
grant update (title, body, course_code) on public.study_notes to authenticated;

grant select, delete on public.study_summaries to authenticated;
grant insert (note_id, body) on public.study_summaries to authenticated;
grant update (body) on public.study_summaries to authenticated;

grant select, delete on public.study_decks to authenticated;
grant insert (note_id, title) on public.study_decks to authenticated;
grant update (title) on public.study_decks to authenticated;

grant select, delete on public.study_flashcards to authenticated;
grant insert (deck_id, front, back, position) on public.study_flashcards to authenticated;
grant update (front, back, position) on public.study_flashcards to authenticated;

grant select, delete on public.study_quizzes to authenticated;
grant insert (note_id, title) on public.study_quizzes to authenticated;
grant update (title) on public.study_quizzes to authenticated;

grant select, delete on public.study_quiz_questions to authenticated;
grant insert (quiz_id, prompt, options, correct_index, explanation, position)
  on public.study_quiz_questions to authenticated;
grant update (prompt, options, correct_index, explanation, position)
  on public.study_quiz_questions to authenticated;

grant select, delete on public.study_quiz_attempts to authenticated;
grant insert (quiz_id, answers) on public.study_quiz_attempts to authenticated;

grant select on public.study_ai_usage to authenticated;
grant select on public.study_ai_cache to authenticated;

grant all on public.study_notes, public.study_ai_cache, public.study_summaries,
             public.study_decks, public.study_flashcards, public.study_quizzes,
             public.study_quiz_questions, public.study_quiz_attempts,
             public.study_ai_usage
  to service_role;

-- ================================================================ 6. quiz scoring
-- Runs before an attempt is saved. It checks every answer belongs to this
-- quiz and is a real option, then counts the correct ones. Whatever score
-- the phone might send is overwritten.
create or replace function public.study_score_attempt()
returns trigger
language plpgsql security invoker set search_path = public as $$
declare
  q          record;
  chosen     jsonb;
  n_correct  int := 0;
  n_total    int := 0;
  known_ids  int;
begin
  -- every key must be a question of this quiz
  select count(*) into known_ids
    from jsonb_object_keys(new.answers) k
    join public.study_quiz_questions qq
      on qq.id::text = k and qq.quiz_id = new.quiz_id;
  if known_ids <> (select count(*) from jsonb_object_keys(new.answers)) then
    raise exception 'An answer refers to a question that is not in this quiz'
      using errcode = '23514';
  end if;

  for q in
    select id, correct_index, cardinality(options) as n_options
      from public.study_quiz_questions where quiz_id = new.quiz_id
  loop
    n_total := n_total + 1;
    chosen := new.answers -> q.id::text;
    if chosen is null or jsonb_typeof(chosen) = 'null' then
      continue;   -- left blank: counts as wrong
    end if;
    if jsonb_typeof(chosen) <> 'number'
       or (chosen #>> '{}') !~ '^[0-9]+$'
       or (chosen #>> '{}')::int >= q.n_options then
      raise exception 'An answer is not one of the question''s options'
        using errcode = '23514';
    end if;
    if (chosen #>> '{}')::int = q.correct_index then
      n_correct := n_correct + 1;
    end if;
  end loop;

  if n_total = 0 then
    raise exception 'This quiz has no questions yet' using errcode = '23514';
  end if;

  new.score := n_correct;
  new.total := n_total;
  new.created_at := now();
  return new;
end $$;

create trigger study_attempts_score
  before insert on public.study_quiz_attempts
  for each row execute function public.study_score_attempt();

-- ================================================================ 7. AI functions
-- How many AI requests the signed-in student has left today. Called by the
-- app to show "7 of 10 left today". It also accounts for the project-wide
-- limit, which is why it needs SECURITY DEFINER (it counts every row).
create or replace function public.study_ai_status()
returns table (used int, daily_limit int, remaining int)
language plpgsql stable security definer set search_path = public as $$
declare
  mine     int;
  everyone int;
begin
  if not public.is_student() then
    return query select 0, 0, 0;
    return;
  end if;
  select coalesce(sum(u.count), 0) into mine
    from public.study_ai_usage u
   where u.user_id = auth.uid() and u.day = public.study_today();
  select coalesce(sum(u.count), 0) into everyone
    from public.study_ai_usage u where u.day = public.study_today();
  return query select
    mine,
    public.study_ai_daily_limit(),
    greatest(0, least(public.study_ai_daily_limit() - mine,
                      public.study_ai_project_daily_limit() - everyone));
end $$;

-- The fingerprint of a note's content. The edge function never computes
-- it; it always comes from here, so the cache key cannot drift.
create or replace function public.study_note_hash(p_title text, p_body text)
returns text language sql immutable as $$
  select encode(sha256(convert_to(p_title || E'\n' || p_body, 'UTF8')), 'hex')
$$;

-- Step 2 and the note read of the edge function, in one call.
-- p_user is the account id the edge function has just verified from the
-- caller's token; it is never taken from the request body.
-- Returns {"error": "..."} or the note with its content hash and the
-- requests left today.
create or replace function public.study_ai_prepare(p_user uuid, p_note uuid, p_kind text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  n         public.study_notes;
  mine      int;
  everyone  int;
  left_mine int;
  left_all  int;
begin
  if p_kind not in ('summary', 'flashcards', 'quiz') then
    return jsonb_build_object('error', 'bad_type');
  end if;
  if not exists (select 1 from public.profiles where id = p_user and role = 'student') then
    return jsonb_build_object('error', 'not_student');
  end if;

  select coalesce(sum(count), 0) into mine from public.study_ai_usage
   where user_id = p_user and day = public.study_today();
  select coalesce(sum(count), 0) into everyone from public.study_ai_usage
   where day = public.study_today();
  left_mine := public.study_ai_daily_limit() - mine;
  left_all  := public.study_ai_project_daily_limit() - everyone;
  if left_mine <= 0 then
    return jsonb_build_object('error', 'limit_reached', 'remaining', 0);
  end if;
  if left_all <= 0 then
    return jsonb_build_object('error', 'project_limit_reached', 'remaining', 0);
  end if;

  select * into n from public.study_notes where id = p_note and user_id = p_user;
  if not found then
    return jsonb_build_object('error', 'not_found');
  end if;

  return jsonb_build_object(
    'title', n.title,
    'body', n.body,
    'content_hash', public.study_note_hash(n.title, n.body),
    'remaining', least(left_mine, left_all));
end $$;

-- Step 4: is there already a validated result for exactly this content?
create or replace function public.study_ai_cache_find(
  p_user uuid, p_note uuid, p_kind text, p_hash text)
returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.study_ai_cache
   where user_id = p_user and note_id = p_note
     and kind = p_kind and content_hash = p_hash
$$;

-- Step 5, just before Gemini is called: take one request from today's
-- allowance. The lock makes two requests arriving together queue up, so
-- neither limit can be overshot. Returns how many are left afterwards, or
-- -1 when the student's limit is used up, -2 when the project's is.
create or replace function public.study_ai_consume(p_user uuid)
returns int
language plpgsql volatile security definer set search_path = public as $$
declare
  mine     int;
  everyone int;
begin
  perform pg_advisory_xact_lock(hashtext('study_ai_consume'));
  select coalesce(sum(count), 0) into mine from public.study_ai_usage
   where user_id = p_user and day = public.study_today();
  select coalesce(sum(count), 0) into everyone from public.study_ai_usage
   where day = public.study_today();
  if mine >= public.study_ai_daily_limit() then return -1; end if;
  if everyone >= public.study_ai_project_daily_limit() then return -2; end if;

  insert into public.study_ai_usage (user_id, day, count)
  values (p_user, public.study_today(), 1)
  on conflict (user_id, day) do update set count = public.study_ai_usage.count + 1;

  return least(public.study_ai_daily_limit() - mine - 1,
               public.study_ai_project_daily_limit() - everyone - 1);
end $$;

-- Turns a cached result into the student's summary, deck or quiz.
-- If one made from this cache entry still exists it is returned as is,
-- so pressing the button twice does not make two copies.
-- Every row written here still has to pass the table constraints in part
-- 3, so a result of the wrong shape makes the whole call fail and nothing
-- is kept.
create or replace function public.study_ai_materialise(p_user uuid, p_cache uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  c        public.study_ai_cache;
  n_title  text;
  item_id  uuid;
  el       jsonb;
  pos      int := 0;
  opts     text[];
  correct  bigint;
  n_marked bigint;
begin
  select * into c from public.study_ai_cache where id = p_cache and user_id = p_user;
  if not found then
    raise exception 'No such cached result' using errcode = '42501';
  end if;
  select title into n_title from public.study_notes where id = c.note_id;

  if c.kind = 'summary' then
    select id into item_id from public.study_summaries
     where cache_id = c.id and user_id = p_user limit 1;
    if item_id is not null then
      return jsonb_build_object('kind', c.kind, 'id', item_id, 'reused', true);
    end if;
    if jsonb_typeof(c.result -> 'summary') <> 'string' then
      raise exception 'Summary result has the wrong shape' using errcode = '23514';
    end if;
    insert into public.study_summaries (user_id, note_id, body, source, cache_id)
    values (p_user, c.note_id, btrim(c.result ->> 'summary'), 'ai', c.id)
    returning id into item_id;

  elsif c.kind = 'flashcards' then
    select id into item_id from public.study_decks
     where cache_id = c.id and user_id = p_user limit 1;
    if item_id is not null then
      return jsonb_build_object('kind', c.kind, 'id', item_id, 'reused', true);
    end if;
    if jsonb_typeof(c.result -> 'cards') <> 'array'
       or jsonb_array_length(c.result -> 'cards') not between 1 and 20 then
      raise exception 'Flashcard result has the wrong shape' using errcode = '23514';
    end if;
    insert into public.study_decks (user_id, note_id, title, source, cache_id)
    values (p_user, c.note_id, left(n_title, 188) || ' flashcards', 'ai', c.id)
    returning id into item_id;
    for el in select * from jsonb_array_elements(c.result -> 'cards') loop
      if jsonb_typeof(el -> 'question') <> 'string'
         or jsonb_typeof(el -> 'answer') <> 'string' then
        raise exception 'Flashcard result has the wrong shape' using errcode = '23514';
      end if;
      insert into public.study_flashcards (user_id, deck_id, front, back, position)
      values (p_user, item_id, btrim(el ->> 'question'), btrim(el ->> 'answer'), pos);
      pos := pos + 1;
    end loop;

  elsif c.kind = 'quiz' then
    select id into item_id from public.study_quizzes
     where cache_id = c.id and user_id = p_user limit 1;
    if item_id is not null then
      return jsonb_build_object('kind', c.kind, 'id', item_id, 'reused', true);
    end if;
    if jsonb_typeof(c.result -> 'questions') <> 'array'
       or jsonb_array_length(c.result -> 'questions') not between 1 and 15 then
      raise exception 'Quiz result has the wrong shape' using errcode = '23514';
    end if;
    insert into public.study_quizzes (user_id, note_id, title, source, cache_id)
    values (p_user, c.note_id, left(n_title, 194) || ' quiz', 'ai', c.id)
    returning id into item_id;
    for el in select * from jsonb_array_elements(c.result -> 'questions') loop
      if jsonb_typeof(el -> 'question') <> 'string'
         or jsonb_typeof(el -> 'options') <> 'array' then
        raise exception 'Quiz result has the wrong shape' using errcode = '23514';
      end if;
      -- the option texts in order, how many are marked correct, and where
      -- the correct one is (options are numbered from 0)
      select array_agg(btrim(o ->> 'text') order by i),
             count(*) filter (where o -> 'is_correct' = 'true'::jsonb),
             min(i - 1) filter (where o -> 'is_correct' = 'true'::jsonb)
        into opts, n_marked, correct
        from jsonb_array_elements(el -> 'options') with ordinality as t(o, i);
      if n_marked <> 1 then
        raise exception 'A quiz question must have exactly one correct option'
          using errcode = '23514';
      end if;
      insert into public.study_quiz_questions
        (user_id, quiz_id, prompt, options, correct_index, explanation, position)
      values (p_user, item_id, btrim(el ->> 'question'), opts, correct::int,
              nullif(btrim(coalesce(el ->> 'explanation', '')), ''), pos);
      pos := pos + 1;
    end loop;
  end if;

  return jsonb_build_object('kind', c.kind, 'id', item_id, 'reused', false);
end $$;

-- Steps 7 and 8: keep a result that the edge function has already
-- validated, then turn it into the student's item. It refuses if the note
-- changed while Gemini was working (the hash would no longer match), so a
-- result is never filed against content it was not made from. Older cache
-- entries for the same note and kind are dropped, since that content no
-- longer exists.
create or replace function public.study_ai_store(
  p_user uuid, p_note uuid, p_kind text, p_hash text, p_model text, p_result jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  n        public.study_notes;
  cache_id uuid;
begin
  select * into n from public.study_notes where id = p_note and user_id = p_user;
  if not found then
    raise exception 'Note not found' using errcode = '42501';
  end if;
  if public.study_note_hash(n.title, n.body) <> p_hash then
    raise exception 'The note changed while the result was being made'
      using errcode = '40001';
  end if;

  delete from public.study_ai_cache
   where note_id = p_note and kind = p_kind and content_hash <> p_hash;

  insert into public.study_ai_cache (user_id, note_id, kind, content_hash, model, result)
  values (p_user, p_note, p_kind, p_hash, p_model, p_result)
  on conflict (note_id, kind, content_hash) do update set result = excluded.result
  returning id into cache_id;

  return public.study_ai_materialise(p_user, cache_id);
end $$;

-- Who may call what. Functions are executable by everyone unless revoked,
-- so revoke first, then grant one by one.
revoke execute on function public.study_ai_status()                         from public, anon;
revoke execute on function public.study_ai_prepare(uuid, uuid, text)        from public, anon, authenticated;
revoke execute on function public.study_ai_cache_find(uuid, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.study_ai_consume(uuid)                    from public, anon, authenticated;
revoke execute on function public.study_ai_materialise(uuid, uuid)          from public, anon, authenticated;
revoke execute on function public.study_ai_store(uuid, uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.is_student()                              from public, anon;

grant execute on function public.study_ai_status() to authenticated, service_role;
grant execute on function public.is_student()      to authenticated, service_role;
grant execute on function public.study_ai_prepare(uuid, uuid, text)          to service_role;
grant execute on function public.study_ai_cache_find(uuid, uuid, text, text) to service_role;
grant execute on function public.study_ai_consume(uuid)                      to service_role;
grant execute on function public.study_ai_materialise(uuid, uuid)            to service_role;
grant execute on function public.study_ai_store(uuid, uuid, text, text, text, jsonb) to service_role;
