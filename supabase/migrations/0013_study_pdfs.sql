-- ZutLib: study from a PDF
--
-- A study note can now be built on a PDF instead of (or as well as) typed
-- text:
--   - a PDF the student uploads, kept in the private "study-files" bucket
--     under a folder named after their own account id, or
--   - a PDF already in the library (a past paper or lecture notes).
-- The study-generate Edge Function sends that PDF to Gemini, so AI can
-- summarise it, make flashcards from it and write a quiz about it.
--
-- Also here: every AI helper now requires an ACTIVE student account, and
-- the AI cache key includes a fingerprint of the PDF's bytes, so a changed
-- PDF is never answered from an old result.

-- ================================================================ notes on PDFs
alter table public.study_notes
  add column if not exists file_path   text,
  add column if not exists file_name   text,
  add column if not exists resource_id uuid references public.resources(id) on delete set null;

alter table public.study_notes alter column body set default '';

-- Typed text may now be empty when a PDF is attached (checked by the
-- trigger below, so that a library PDF being removed later does not make
-- the note impossible to store).
alter table public.study_notes drop constraint if exists study_notes_body_len;
alter table public.study_notes add constraint study_notes_body_len
  check (length(body) <= 20000);

alter table public.study_notes drop constraint if exists study_notes_one_source;
alter table public.study_notes add constraint study_notes_one_source
  check (file_path is null or resource_id is null);

-- An uploaded file must sit in the owner's own folder and be a PDF.
alter table public.study_notes drop constraint if exists study_notes_file_path;
alter table public.study_notes add constraint study_notes_file_path check (
  file_path is null or (
    split_part(file_path, '/', 1) = user_id::text
    and file_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}\.pdf$'
  )
);
alter table public.study_notes drop constraint if exists study_notes_file_name;
alter table public.study_notes add constraint study_notes_file_name
  check (file_name is null or length(file_name) between 1 and 200);

create index if not exists study_notes_resource_idx on public.study_notes (resource_id);

-- A note needs something to study: typed text, an uploaded PDF, or a
-- library PDF. A library item linked to a note must be a PDF that has not
-- been retired.
create or replace function public.study_note_check_source()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.resource_id is not null and new.resource_id is null
     and new.file_path is null and btrim(new.body) = ''
     and new.title = old.title and new.body = old.body then
    -- The library removed the PDF this note pointed at. Keep the note
    -- (its decks and quizzes still link to it); it simply has no source now.
    return new;
  end if;
  if btrim(new.body) = '' and new.file_path is null and new.resource_id is null then
    raise exception 'Add some text or attach a PDF' using errcode = '23514';
  end if;
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

drop trigger if exists study_notes_source on public.study_notes;
create trigger study_notes_source
  before insert or update on public.study_notes
  for each row execute function public.study_note_check_source();

-- Students choose the source when they make the note; it cannot be
-- swapped afterwards.
grant insert (title, body, course_code, file_path, file_name, resource_id)
  on public.study_notes to authenticated;

-- ================================================================ private uploads
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('study-files', 'study-files', false, 10485760, array['application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- A student reaches only the folder named after their own account id.
drop policy if exists study_files_read on storage.objects;
create policy study_files_read on storage.objects
  for select to authenticated
  using (bucket_id = 'study-files'
         and (storage.foldername(name))[1] = auth.uid()::text
         and public.is_student());

drop policy if exists study_files_insert on storage.objects;
create policy study_files_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'study-files'
              and (storage.foldername(name))[1] = auth.uid()::text
              and public.is_student());

drop policy if exists study_files_delete on storage.objects;
create policy study_files_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'study-files'
         and (storage.foldername(name))[1] = auth.uid()::text
         and public.is_student());

-- ================================================================ AI helpers
-- The note's fingerprint now has a third part: the SHA-256 of the PDF's
-- bytes ('' when there is no PDF, which gives exactly the old value, so
-- results already cached for typed notes stay valid).
drop function if exists public.study_note_hash(text, text);
create or replace function public.study_note_hash(p_title text, p_body text, p_file_sha text default '')
returns text language sql immutable as $$
  select encode(sha256(convert_to(
    p_title || E'\n' || p_body ||
    case when coalesce(p_file_sha, '') = '' then '' else E'\nfile:' || p_file_sha end,
    'UTF8')), 'hex')
$$;

-- Daily limit, then the note and where its PDF is, for an ACTIVE student.
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
  if p_kind not in ('summary', 'flashcards', 'quiz') then
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
  if btrim(n.body) = '' and n.file_path is null and lib_path is null then
    return jsonb_build_object('error', 'no_source');
  end if;

  return jsonb_build_object(
    'title', n.title,
    'body', n.body,
    'remaining', least(left_mine, left_all),
    'file_bucket', case when n.file_path is not null then 'study-files'
                        when lib_path is not null then 'resources' end,
    'file_path', coalesce(n.file_path, lib_path));
end $$;

-- Is there a validated result for exactly this content? The content hash
-- is worked out here from the note as it is now plus the PDF fingerprint
-- the Edge Function computed from the bytes it downloaded.
drop function if exists public.study_ai_cache_find(uuid, uuid, text, text);
create or replace function public.study_ai_cache_find(
  p_user uuid, p_note uuid, p_kind text, p_file_sha text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  n    public.study_notes;
  h    text;
  hit  uuid;
begin
  if coalesce(p_file_sha, '') !~ '^([0-9a-f]{64})?$' then
    raise exception 'Bad file fingerprint' using errcode = '22023';
  end if;
  select * into n from public.study_notes where id = p_note and user_id = p_user;
  if not found then
    raise exception 'Note not found' using errcode = '42501';
  end if;
  h := public.study_note_hash(n.title, n.body, coalesce(p_file_sha, ''));
  select id into hit from public.study_ai_cache
   where user_id = p_user and note_id = p_note and kind = p_kind and content_hash = h;
  return jsonb_build_object('content_hash', h, 'cache_id', hit);
end $$;

drop function if exists public.study_ai_store(uuid, uuid, text, text, text, jsonb);
create or replace function public.study_ai_store(
  p_user uuid, p_note uuid, p_kind text, p_hash text, p_model text, p_result jsonb,
  p_file_sha text default '')
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
  if public.study_note_hash(n.title, n.body, coalesce(p_file_sha, '')) <> p_hash then
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

revoke execute on function public.study_note_hash(text, text, text) from public, anon, authenticated;
grant execute on function public.study_note_hash(text, text, text) to service_role;
revoke execute on function public.study_ai_prepare(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.study_ai_prepare(uuid, uuid, text) to service_role;
revoke execute on function public.study_ai_cache_find(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.study_ai_cache_find(uuid, uuid, text, text) to service_role;
revoke execute on function public.study_ai_store(uuid, uuid, text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.study_ai_store(uuid, uuid, text, text, text, jsonb, text) to service_role;

-- study_ai_status and the policies already use is_student(), which (from
-- 0012) means an active student.
