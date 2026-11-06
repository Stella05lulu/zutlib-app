-- ZutLib: bigger, fuller study kits (after feedback on 6 November 2026)
--
--   1. Sources    a kit can have up to 10 sources (still 30 MB of PDFs).
--   2. Guides     up to 30 sections, longer summaries and more points, so a
--                 guide can cover everything in several lectures.
--   3. Banks      up to 100 flashcards and 120 questions per kit (the AI now
--                 writes them in parallel parts; see study-generate).
--   4. Tests      up to 100 questions in one test.
--
-- Nothing is removed or narrowed, so every existing kit stays valid.

-- ================================================================ 1. sources
create or replace function public.study_kit_max_sources() returns int
language sql immutable as $$ select 10 $$;

-- ================================================================ 2. guides
create or replace function public.study_guide_sections_valid(s jsonb)
returns boolean language sql immutable as $$
  select s is not null
     and jsonb_typeof(s) = 'array'
     and jsonb_array_length(s) between 1 and 30
     and not exists (
       select 1 from jsonb_array_elements(s) e
       where jsonb_typeof(e) <> 'object'
          or jsonb_typeof(e -> 'heading') <> 'string'
          or length(btrim(e ->> 'heading')) not between 1 and 160
          or jsonb_typeof(e -> 'summary') <> 'string'
          or length(e ->> 'summary') > 3000
          or jsonb_typeof(e -> 'points') <> 'array'
          or jsonb_array_length(e -> 'points') > 12
          or exists (
               select 1 from jsonb_array_elements(e -> 'points') p
               where jsonb_typeof(p) <> 'string'
                  or length(btrim(p #>> '{}')) not between 1 and 400))
$$;

-- ================================================================ 3. banks
drop trigger if exists study_questions_cap on public.study_quiz_questions;
create trigger study_questions_cap before insert on public.study_quiz_questions
  for each row execute function public.study_cap_rows('quiz_id', '150');

-- ================================================================ 4. tests
alter table public.study_tests drop constraint if exists study_tests_count;
alter table public.study_tests add constraint study_tests_count
  check (array_ndims(question_ids) = 1 and cardinality(question_ids) between 1 and 100);

-- ================================================================ saving a kit
-- study_ai_materialise from 0014, unchanged except the size check on a kit
-- (cards 4 to 100, questions 4 to 120).
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
       or jsonb_array_length(c.result -> 'cards') not between 4 and 100
       or jsonb_typeof(c.result -> 'questions') <> 'array'
       or jsonb_array_length(c.result -> 'questions') not between 4 and 120 then
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
