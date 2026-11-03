-- ZutLib: study kits
--
-- A study note becomes a "study kit": one set of materials (an uploaded
-- PDF, a library PDF, a YouTube video, or typed or pasted text) with
-- everything a student needs to revise it:
--
--   Study guide    an AI-written guide with headings, made in the same
--                  Gemini call as the cards and questions (kind 'kit')
--   Smart study    adaptive practice over the kit's questions; each
--                  question earns up to 3 stars (study_question_progress)
--   Flashcards     a deck the student rates red, yellow or green, moving
--                  each card between Learning, Reviewing, Known and
--                  Mastered (study_card_progress)
--   Games          matching and true-or-false rounds with a scoreboard
--                  (study_game_scores)
--   Tests          timed tests drawn from the question bank, marked by the
--                  database (study_tests, study_test_attempts)
--
-- The rules from 0010 still hold everywhere: deny by default, a student
-- sees and changes only their own rows, ownership is filled in by the
-- database, child rows carry their parent's owner through two-column
-- foreign keys, and scores are worked out by the database, never sent by
-- the app. Run after 0013_study_pdfs.sql.

-- ================================================================ notes as kits
alter table public.study_notes
  add column if not exists color       text not null default 'blue',
  add column if not exists youtube_url text;

alter table public.study_notes drop constraint if exists study_notes_color;
alter table public.study_notes add constraint study_notes_color
  check (color in ('blue', 'red', 'yellow', 'green', 'orange', 'teal', 'slate'));

-- The app stores every YouTube link in one standard form, so the check can
-- be exact: a public watch link with an 11 character video id.
alter table public.study_notes drop constraint if exists study_notes_youtube;
alter table public.study_notes add constraint study_notes_youtube
  check (youtube_url is null
         or youtube_url ~ '^https://www\.youtube\.com/watch\?v=[A-Za-z0-9_-]{11}$');

-- Still one source per kit: an upload, a library PDF or a video.
alter table public.study_notes drop constraint if exists study_notes_one_source;
alter table public.study_notes add constraint study_notes_one_source
  check (num_nonnulls(file_path, resource_id, youtube_url) <= 1);

-- A kit needs something to study, or nothing at all when the student
-- chose "Proceed without materials" and will add cards and questions by
-- hand. Typed text may be empty either way; AI help then has nothing to
-- read and says so (study_ai_prepare returns no_source).
create or replace function public.study_note_check_source()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.resource_id is not null
     and (tg_op = 'INSERT' or new.resource_id is distinct from old.resource_id) then
    if not exists (select 1 from public.resources r
                    where r.id = new.resource_id and r.retired_at is null
                      and r.file_path ilike '%.pdf') then
      raise exception 'That library item has no PDF to study from' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;

grant insert (title, body, course_code, file_path, file_name, resource_id, youtube_url, color)
  on public.study_notes to authenticated;
grant update (title, body, course_code, color) on public.study_notes to authenticated;

-- ================================================================ child rows
-- Progress rows point at (card, owner) and (question, owner) pairs, like
-- every other child table, so they need these pairs to be unique.
alter table public.study_flashcards drop constraint if exists study_flashcards_id_owner;
alter table public.study_flashcards add constraint study_flashcards_id_owner unique (id, user_id);
alter table public.study_quiz_questions drop constraint if exists study_questions_id_owner;
alter table public.study_quiz_questions add constraint study_questions_id_owner unique (id, user_id);

-- How hard a question is: 1 easy, 2 medium, 3 hard. Tests can be drawn
-- from one level.
alter table public.study_quiz_questions
  add column if not exists difficulty smallint not null default 2;
alter table public.study_quiz_questions drop constraint if exists study_questions_difficulty;
alter table public.study_quiz_questions add constraint study_questions_difficulty
  check (difficulty between 1 and 3);

grant insert (quiz_id, prompt, options, correct_index, explanation, position, difficulty)
  on public.study_quiz_questions to authenticated;
grant update (prompt, options, correct_index, explanation, position, difficulty)
  on public.study_quiz_questions to authenticated;

-- ================================================================ study guides
-- One AI study guide per kit, plus which deck and question bank the same
-- AI call made, so making the kit again replaces exactly those. Written
-- only by study_ai_materialise; a student can read it and delete it.
create or replace function public.study_guide_sections_valid(s jsonb)
returns boolean language sql immutable as $$
  select s is not null
     and jsonb_typeof(s) = 'array'
     and jsonb_array_length(s) between 1 and 12
     and not exists (
       select 1 from jsonb_array_elements(s) e
       where jsonb_typeof(e) <> 'object'
          or jsonb_typeof(e -> 'heading') <> 'string'
          or length(btrim(e ->> 'heading')) not between 1 and 160
          or jsonb_typeof(e -> 'summary') <> 'string'
          or length(e ->> 'summary') > 1500
          or jsonb_typeof(e -> 'points') <> 'array'
          or jsonb_array_length(e -> 'points') > 10
          or exists (
               select 1 from jsonb_array_elements(e -> 'points') p
               where jsonb_typeof(p) <> 'string'
                  or length(btrim(p #>> '{}')) not between 1 and 300))
$$;

create table if not exists public.study_guides (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  note_id     uuid not null,
  cache_id    uuid,
  deck_id     uuid,
  quiz_id     uuid,
  overview    text not null,
  sections    jsonb not null,
  created_at  timestamptz not null default now(),

  constraint study_guides_overview_len check (length(btrim(overview)) between 1 and 2000),
  constraint study_guides_sections check (public.study_guide_sections_valid(sections)),
  constraint study_guides_one unique (note_id),
  constraint study_guides_note foreign key (note_id, user_id)
    references public.study_notes (id, user_id) on delete cascade,
  constraint study_guides_cache foreign key (cache_id, user_id)
    references public.study_ai_cache (id, user_id) on delete set null (cache_id),
  constraint study_guides_deck foreign key (deck_id, user_id)
    references public.study_decks (id, user_id) on delete set null (deck_id),
  constraint study_guides_quiz foreign key (quiz_id, user_id)
    references public.study_quizzes (id, user_id) on delete set null (quiz_id)
);

create index if not exists study_guides_user_idx on public.study_guides (user_id);

-- ================================================================ progress
-- Flashcard boxes: 0 Learning, 1 Reviewing, 2 Known, 3 Mastered.
create table if not exists public.study_card_progress (
  user_id     uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  card_id     uuid not null,
  box         smallint not null default 0,
  reviews     int not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (user_id, card_id),
  constraint study_card_progress_box check (box between 0 and 3),
  constraint study_card_progress_reviews check (reviews between 0 and 100000),
  constraint study_card_progress_card foreign key (card_id, user_id)
    references public.study_flashcards (id, user_id) on delete cascade
);

create index if not exists study_card_progress_card_idx on public.study_card_progress (card_id);

-- Smart study: 0 to 3 stars per question.
create table if not exists public.study_question_progress (
  user_id      uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  question_id  uuid not null,
  stars        smallint not null default 0,
  seen         int not null default 0,
  updated_at   timestamptz not null default now(),
  primary key (user_id, question_id),
  constraint study_question_progress_stars check (stars between 0 and 3),
  constraint study_question_progress_seen check (seen between 0 and 100000),
  constraint study_question_progress_question foreign key (question_id, user_id)
    references public.study_quiz_questions (id, user_id) on delete cascade
);

create index if not exists study_question_progress_q_idx on public.study_question_progress (question_id);

-- ================================================================ tests
create table if not exists public.study_tests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  note_id       uuid,
  quiz_id       uuid not null,
  title         text not null,
  question_ids  uuid[] not null,
  difficulty    text not null default 'mixed',
  time_limit_s  int not null default 0,
  created_at    timestamptz not null default now(),

  constraint study_tests_title_len check (length(btrim(title)) between 1 and 200 and length(title) <= 200),
  constraint study_tests_count check (array_ndims(question_ids) = 1 and cardinality(question_ids) between 1 and 50),
  constraint study_tests_difficulty check (difficulty in ('easy', 'mixed', 'hard')),
  constraint study_tests_time check (time_limit_s = 0 or time_limit_s between 60 and 10800),
  constraint study_tests_quiz foreign key (quiz_id, user_id)
    references public.study_quizzes (id, user_id) on delete cascade,
  constraint study_tests_note foreign key (note_id, user_id)
    references public.study_notes (id, user_id) on delete set null (note_id),
  constraint study_tests_id_owner unique (id, user_id)
);

create index if not exists study_tests_user_idx on public.study_tests (user_id, created_at desc);
create index if not exists study_tests_note_idx on public.study_tests (note_id);

-- Every question in a test must be a question of its bank, once.
create or replace function public.study_test_check()
returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if (select count(distinct q) from unnest(new.question_ids) q) <> cardinality(new.question_ids) then
    raise exception 'A question appears twice in this test' using errcode = '23514';
  end if;
  if (select count(*) from public.study_quiz_questions qq
       where qq.quiz_id = new.quiz_id and qq.id = any (new.question_ids))
     <> cardinality(new.question_ids) then
    raise exception 'A test question is not in this question bank' using errcode = '23514';
  end if;
  new.created_at := now();
  return new;
end $$;

drop trigger if exists study_tests_check on public.study_tests;
create trigger study_tests_check before insert on public.study_tests
  for each row execute function public.study_test_check();

create table if not exists public.study_test_attempts (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  test_id        uuid not null,
  answers        jsonb not null,
  score          int not null default 0,
  total          int not null default 0,
  seconds_taken  int not null default 0,
  created_at     timestamptz not null default now(),

  constraint study_test_attempts_answers check (jsonb_typeof(answers) = 'object'),
  constraint study_test_attempts_score check (total >= 1 and score between 0 and total),
  constraint study_test_attempts_seconds check (seconds_taken between 0 and 86400),
  constraint study_test_attempts_test foreign key (test_id, user_id)
    references public.study_tests (id, user_id) on delete cascade
);

create index if not exists study_test_attempts_test_idx on public.study_test_attempts (test_id, created_at desc);

-- Marks a test attempt, like study_score_attempt does for a quiz. Questions
-- deleted since the test was made simply drop out of the total.
create or replace function public.study_score_test()
returns trigger
language plpgsql security invoker set search_path = public as $$
declare
  t          public.study_tests;
  q          record;
  chosen     jsonb;
  n_correct  int := 0;
  n_total    int := 0;
begin
  select * into t from public.study_tests where id = new.test_id;
  if not found then
    raise exception 'That test no longer exists' using errcode = '23503';
  end if;
  if exists (select 1 from jsonb_object_keys(new.answers) k
              where not (k = any (select x::text from unnest(t.question_ids) x))) then
    raise exception 'An answer refers to a question that is not in this test'
      using errcode = '23514';
  end if;

  for q in
    select id, correct_index, cardinality(options) as n_options
      from public.study_quiz_questions where id = any (t.question_ids)
  loop
    n_total := n_total + 1;
    chosen := new.answers -> q.id::text;
    if chosen is null or jsonb_typeof(chosen) = 'null' then
      continue;   -- left blank: counts as wrong
    end if;
    if jsonb_typeof(chosen) <> 'number'
       or (chosen #>> '{}') !~ '^[0-9]+$'
       or (chosen #>> '{}')::int >= q.n_options then
      raise exception 'An answer is not one of the question''s options' using errcode = '23514';
    end if;
    if (chosen #>> '{}')::int = q.correct_index then
      n_correct := n_correct + 1;
    end if;
  end loop;

  if n_total = 0 then
    raise exception 'This test has no questions left' using errcode = '23514';
  end if;
  new.score := n_correct;
  new.total := n_total;
  new.created_at := now();
  return new;
end $$;

drop trigger if exists study_test_attempts_score on public.study_test_attempts;
create trigger study_test_attempts_score before insert on public.study_test_attempts
  for each row execute function public.study_score_test();

-- ================================================================ games
create table if not exists public.study_game_scores (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  deck_id     uuid not null,
  game        text not null,
  score       int not null,
  seconds     int not null,
  created_at  timestamptz not null default now(),

  constraint study_game_scores_game check (game in ('matching', 'true_false')),
  constraint study_game_scores_score check (score between 0 and 10000),
  constraint study_game_scores_seconds check (seconds between 0 and 36000),
  constraint study_game_scores_deck foreign key (deck_id, user_id)
    references public.study_decks (id, user_id) on delete cascade
);

create index if not exists study_game_scores_deck_idx on public.study_game_scores (deck_id, game, score desc);

-- ================================================================ caps
drop trigger if exists study_tests_cap on public.study_tests;
create trigger study_tests_cap before insert on public.study_tests
  for each row execute function public.study_cap_rows('user_id', '200');
drop trigger if exists study_test_attempts_cap on public.study_test_attempts;
create trigger study_test_attempts_cap before insert on public.study_test_attempts
  for each row execute function public.study_cap_rows('test_id', '100');
drop trigger if exists study_game_scores_cap on public.study_game_scores;
create trigger study_game_scores_cap before insert on public.study_game_scores
  for each row execute function public.study_cap_rows('deck_id', '500');

-- ================================================================ row security
alter table public.study_guides            enable row level security;
alter table public.study_card_progress     enable row level security;
alter table public.study_question_progress enable row level security;
alter table public.study_tests             enable row level security;
alter table public.study_test_attempts     enable row level security;
alter table public.study_game_scores       enable row level security;

drop policy if exists study_guides_read on public.study_guides;
create policy study_guides_read on public.study_guides
  for select to authenticated using (user_id = auth.uid() and public.is_student());
drop policy if exists study_guides_delete on public.study_guides;
create policy study_guides_delete on public.study_guides
  for delete to authenticated using (user_id = auth.uid() and public.is_student());

drop policy if exists study_card_progress_own on public.study_card_progress;
create policy study_card_progress_own on public.study_card_progress
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

drop policy if exists study_question_progress_own on public.study_question_progress;
create policy study_question_progress_own on public.study_question_progress
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

drop policy if exists study_tests_read on public.study_tests;
create policy study_tests_read on public.study_tests
  for select to authenticated using (user_id = auth.uid() and public.is_student());
drop policy if exists study_tests_insert on public.study_tests;
create policy study_tests_insert on public.study_tests
  for insert to authenticated with check (user_id = auth.uid() and public.is_student());
drop policy if exists study_tests_delete on public.study_tests;
create policy study_tests_delete on public.study_tests
  for delete to authenticated using (user_id = auth.uid() and public.is_student());

-- Attempts and scores: recorded and read, never edited.
drop policy if exists study_test_attempts_read on public.study_test_attempts;
create policy study_test_attempts_read on public.study_test_attempts
  for select to authenticated using (user_id = auth.uid() and public.is_student());
drop policy if exists study_test_attempts_insert on public.study_test_attempts;
create policy study_test_attempts_insert on public.study_test_attempts
  for insert to authenticated with check (user_id = auth.uid() and public.is_student());
drop policy if exists study_test_attempts_delete on public.study_test_attempts;
create policy study_test_attempts_delete on public.study_test_attempts
  for delete to authenticated using (user_id = auth.uid() and public.is_student());

drop policy if exists study_game_scores_read on public.study_game_scores;
create policy study_game_scores_read on public.study_game_scores
  for select to authenticated using (user_id = auth.uid() and public.is_student());
drop policy if exists study_game_scores_insert on public.study_game_scores;
create policy study_game_scores_insert on public.study_game_scores
  for insert to authenticated with check (user_id = auth.uid() and public.is_student());
drop policy if exists study_game_scores_delete on public.study_game_scores;
create policy study_game_scores_delete on public.study_game_scores
  for delete to authenticated using (user_id = auth.uid() and public.is_student());

-- ================================================================ privileges
revoke all on public.study_guides, public.study_card_progress, public.study_question_progress,
              public.study_tests, public.study_test_attempts, public.study_game_scores
  from public, anon, authenticated;

grant select, delete on public.study_guides to authenticated;

grant select, delete on public.study_card_progress to authenticated;
grant insert (card_id, box, reviews) on public.study_card_progress to authenticated;
grant update (box, reviews, updated_at) on public.study_card_progress to authenticated;

grant select, delete on public.study_question_progress to authenticated;
grant insert (question_id, stars, seen) on public.study_question_progress to authenticated;
grant update (stars, seen, updated_at) on public.study_question_progress to authenticated;

grant select, delete on public.study_tests to authenticated;
grant insert (note_id, quiz_id, title, question_ids, difficulty, time_limit_s)
  on public.study_tests to authenticated;

grant select, delete on public.study_test_attempts to authenticated;
grant insert (test_id, answers, seconds_taken) on public.study_test_attempts to authenticated;

grant select, delete on public.study_game_scores to authenticated;
grant insert (deck_id, game, score, seconds) on public.study_game_scores to authenticated;

grant all on public.study_guides, public.study_card_progress, public.study_question_progress,
             public.study_tests, public.study_test_attempts, public.study_game_scores
  to service_role;

-- Rating a card or a question in one call: insert the first time, update
-- after that. SECURITY INVOKER, so row security and the column grants
-- above apply exactly as if the app had written the row itself.
create or replace function public.study_rate_card(p_card uuid, p_box int)
returns void
language sql volatile security invoker set search_path = public as $$
  insert into public.study_card_progress (card_id, box, reviews)
  values (p_card, p_box, 1)
  on conflict (user_id, card_id)
  do update set box = excluded.box,
                reviews = public.study_card_progress.reviews + 1,
                updated_at = now()
$$;

create or replace function public.study_rate_question(p_question uuid, p_stars int)
returns void
language sql volatile security invoker set search_path = public as $$
  insert into public.study_question_progress (question_id, stars, seen)
  values (p_question, p_stars, 1)
  on conflict (user_id, question_id)
  do update set stars = excluded.stars,
                seen = public.study_question_progress.seen + 1,
                updated_at = now()
$$;

revoke execute on function public.study_rate_card(uuid, int) from public, anon;
revoke execute on function public.study_rate_question(uuid, int) from public, anon;
grant execute on function public.study_rate_card(uuid, int) to authenticated;
grant execute on function public.study_rate_question(uuid, int) to authenticated;

-- ================================================================ AI: kind 'kit'
alter table public.study_ai_cache drop constraint if exists study_ai_cache_kind;
alter table public.study_ai_cache add constraint study_ai_cache_kind
  check (kind in ('summary', 'flashcards', 'quiz', 'kit'));

-- As in 0013, plus kind 'kit' and a kit's YouTube video.
create or replace function public.study_ai_prepare(p_user uuid, p_note uuid, p_kind text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  n         public.study_notes;
  mine      int;
  everyone  int;
  left_mine int;
  left_all  int;
  lib_path  text;
begin
  if p_kind not in ('summary', 'flashcards', 'quiz', 'kit') then
    return jsonb_build_object('error', 'bad_type');
  end if;
  if not exists (select 1 from public.profiles
                  where id = p_user and role = 'student' and status = 'active') then
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

  if n.resource_id is not null then
    select file_path into lib_path from public.resources
     where id = n.resource_id and retired_at is null;
  end if;
  if btrim(n.body) = '' and n.file_path is null and lib_path is null and n.youtube_url is null then
    return jsonb_build_object('error', 'no_source');
  end if;

  return jsonb_build_object(
    'title', n.title,
    'body', n.body,
    'remaining', least(left_mine, left_all),
    'file_bucket', case when n.file_path is not null then 'study-files'
                        when lib_path is not null then 'resources' end,
    'file_path', coalesce(n.file_path, lib_path),
    'youtube_url', n.youtube_url);
end $$;

revoke execute on function public.study_ai_prepare(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.study_ai_prepare(uuid, uuid, text) to service_role;

-- As in 0010, plus kind 'kit': one study guide, one deck and one question
-- bank from a single AI result. Making the kit again from changed content
-- replaces the previous AI guide, deck and bank (with their progress);
-- cards and questions the student added to other decks are untouched.
create or replace function public.study_ai_materialise(p_user uuid, p_cache uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  c        public.study_ai_cache;
  g        public.study_guides;
  n_title  text;
  item_id  uuid;
  v_deck   uuid;
  v_quiz   uuid;
  el       jsonb;
  pos      int := 0;
  opts     text[];
  correct  bigint;
  n_marked bigint;
  diff     int;
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

  elsif c.kind = 'kit' then
    select * into g from public.study_guides where note_id = c.note_id and user_id = p_user;
    if found and g.cache_id = c.id then
      return jsonb_build_object('kind', c.kind, 'id', c.note_id, 'guide_id', g.id,
                                'deck_id', g.deck_id, 'quiz_id', g.quiz_id, 'reused', true);
    end if;
    if jsonb_typeof(c.result -> 'guide') <> 'object'
       or jsonb_typeof(c.result -> 'guide' -> 'overview') <> 'string'
       or jsonb_typeof(c.result -> 'cards') <> 'array'
       or jsonb_array_length(c.result -> 'cards') not between 4 and 40
       or jsonb_typeof(c.result -> 'questions') <> 'array'
       or jsonb_array_length(c.result -> 'questions') not between 4 and 30 then
      raise exception 'Study kit result has the wrong shape' using errcode = '23514';
    end if;

    -- Replace what the previous AI kit for this note made.
    if g.id is not null then
      delete from public.study_decks where id = g.deck_id and user_id = p_user;
      delete from public.study_quizzes where id = g.quiz_id and user_id = p_user;
      delete from public.study_guides where id = g.id;
    end if;

    insert into public.study_decks (user_id, note_id, title, source, cache_id)
    values (p_user, c.note_id, left(n_title, 200), 'ai', c.id)
    returning id into v_deck;
    pos := 0;
    for el in select * from jsonb_array_elements(c.result -> 'cards') loop
      if jsonb_typeof(el -> 'term') <> 'string' or jsonb_typeof(el -> 'definition') <> 'string' then
        raise exception 'Study kit card has the wrong shape' using errcode = '23514';
      end if;
      insert into public.study_flashcards (user_id, deck_id, front, back, position)
      values (p_user, v_deck, btrim(el ->> 'term'), btrim(el ->> 'definition'), pos);
      pos := pos + 1;
    end loop;

    insert into public.study_quizzes (user_id, note_id, title, source, cache_id)
    values (p_user, c.note_id, left(n_title, 185) || ' question bank', 'ai', c.id)
    returning id into v_quiz;
    pos := 0;
    for el in select * from jsonb_array_elements(c.result -> 'questions') loop
      if jsonb_typeof(el -> 'question') <> 'string'
         or jsonb_typeof(el -> 'options') <> 'array' then
        raise exception 'Study kit question has the wrong shape' using errcode = '23514';
      end if;
      select array_agg(btrim(o ->> 'text') order by i),
             count(*) filter (where o -> 'is_correct' = 'true'::jsonb),
             min(i - 1) filter (where o -> 'is_correct' = 'true'::jsonb)
        into opts, n_marked, correct
        from jsonb_array_elements(el -> 'options') with ordinality as t(o, i);
      if n_marked <> 1 then
        raise exception 'A question must have exactly one correct option' using errcode = '23514';
      end if;
      diff := case el ->> 'difficulty' when 'easy' then 1 when 'hard' then 3 else 2 end;
      insert into public.study_quiz_questions
        (user_id, quiz_id, prompt, options, correct_index, explanation, position, difficulty)
      values (p_user, v_quiz, btrim(el ->> 'question'), opts, correct::int,
              nullif(btrim(coalesce(el ->> 'explanation', '')), ''), pos, diff);
      pos := pos + 1;
    end loop;

    insert into public.study_guides (user_id, note_id, cache_id, deck_id, quiz_id, overview, sections)
    values (p_user, c.note_id, c.id, v_deck, v_quiz,
            btrim(c.result -> 'guide' ->> 'overview'), c.result -> 'guide' -> 'sections')
    returning id into item_id;

    return jsonb_build_object('kind', c.kind, 'id', c.note_id, 'guide_id', item_id,
                              'deck_id', v_deck, 'quiz_id', v_quiz, 'reused', false);
  end if;

  return jsonb_build_object('kind', c.kind, 'id', item_id, 'reused', false);
end $$;

revoke execute on function public.study_ai_materialise(uuid, uuid) from public, anon, authenticated;
grant execute on function public.study_ai_materialise(uuid, uuid) to service_role;
