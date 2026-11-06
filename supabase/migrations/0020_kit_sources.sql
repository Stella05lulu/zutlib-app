-- ZutLib: study kits with several sources (plan item 7)
--
-- Run after 0019_announcements_saved.sql.
--
-- Until now a kit had at most one source, kept on the kit itself
-- (study_notes.file_path, resource_id or youtube_url, rule
-- study_notes_one_source). A kit can now have up to five sources: uploaded
-- PDFs, library PDFs, YouTube links and typed text, at most 30 MB of PDFs
-- in total.
--
-- Existing kits keep their source exactly where it is, so nothing has to
-- be moved and nothing can be lost; it counts as the kit's first source.
-- Extra sources go in study_note_sources, which follows the same rules as
-- every other study table: deny by default, a student sees and changes only
-- their own rows, the owner is filled in by the database, and each row
-- carries its kit's owner through a two-column foreign key.
-- (See docs/study-assistant/DECISIONS.md.)

create or replace function public.study_kit_max_sources() returns int
language sql immutable as $$ select 5 $$;
create or replace function public.study_kit_max_bytes() returns bigint
language sql immutable as $$ select 30::bigint * 1024 * 1024 $$;

create table if not exists public.study_note_sources (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  note_id      uuid not null,
  kind         text not null,
  label        text not null,
  file_path    text,
  file_name    text,
  resource_id  uuid references public.resources(id) on delete cascade,
  youtube_url  text,
  body         text,
  file_bytes   bigint not null default 0,
  position     int not null default 0,
  created_at   timestamptz not null default now(),

  constraint study_note_sources_kind check (kind in ('upload', 'library', 'youtube', 'text')),
  constraint study_note_sources_label check (length(btrim(label)) between 1 and 120),
  constraint study_note_sources_shape check (
    case kind
      when 'upload'  then file_path is not null and file_name is not null
                          and num_nonnulls(resource_id, youtube_url, body) = 0
      when 'library' then resource_id is not null
                          and num_nonnulls(file_path, youtube_url, body) = 0
      when 'youtube' then youtube_url ~ '^https://www\.youtube\.com/watch\?v=[A-Za-z0-9_-]{11}$'
                          and num_nonnulls(file_path, resource_id, body) = 0
      when 'text'    then length(btrim(body)) between 1 and 12000
                          and num_nonnulls(file_path, resource_id, youtube_url) = 0
    end),
  constraint study_note_sources_note foreign key (note_id, user_id)
    references public.study_notes (id, user_id) on delete cascade
);

create index if not exists study_note_sources_note_idx on public.study_note_sources (note_id, position);

alter table public.study_note_sources enable row level security;

drop policy if exists study_note_sources_own on public.study_note_sources;
create policy study_note_sources_own on public.study_note_sources
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

revoke all on public.study_note_sources from anon, authenticated;
grant select, delete on public.study_note_sources to authenticated;
grant insert (note_id, kind, label, file_path, file_name, resource_id, youtube_url, body)
  on public.study_note_sources to authenticated;
grant all on public.study_note_sources to service_role;

-- Size of a stored file, from Storage's own record of it.
create or replace function public.zl_object_bytes(p_bucket text, p_path text)
returns bigint
language sql stable security definer set search_path = public, storage as $$
  select coalesce((select (o.metadata ->> 'size')::bigint from storage.objects o
                    where o.bucket_id = p_bucket and o.name = p_path limit 1), 0)
$$;
revoke execute on function public.zl_object_bytes(text, text) from public, anon, authenticated;

-- How many sources a kit has and how many PDF bytes, counting the kit's
-- original source on study_notes as well.
create or replace function public.study_kit_usage(p_note uuid, out sources int, out bytes bigint)
language plpgsql stable security definer set search_path = public as $$
declare
  n public.study_notes;
begin
  select * into n from public.study_notes where id = p_note;
  select count(*)::int, coalesce(sum(file_bytes), 0) into sources, bytes
    from public.study_note_sources where note_id = p_note;
  if n.file_path is not null then
    sources := sources + 1;
    bytes := bytes + public.zl_object_bytes('study-files', n.file_path);
  elsif n.resource_id is not null then
    sources := sources + 1;
    bytes := bytes + public.zl_object_bytes('resources',
               (select r.file_path from public.resources r where r.id = n.resource_id));
  elsif n.youtube_url is not null then
    sources := sources + 1;
  end if;
end $$;
revoke execute on function public.study_kit_usage(uuid) from public, anon;
grant execute on function public.study_kit_usage(uuid) to authenticated;

create or replace function public.study_note_sources_check()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  u    record;
  path text;
begin
  -- The kit must be the caller's own (the foreign key checks the pair; this
  -- gives a clear message instead).
  if not exists (select 1 from public.study_notes where id = new.note_id and user_id = new.user_id) then
    raise exception 'That study kit could not be found' using errcode = '42501';
  end if;

  select * into u from public.study_kit_usage(new.note_id);
  if u.sources >= public.study_kit_max_sources() then
    raise exception 'A kit can have at most % sources. Remove one first.', public.study_kit_max_sources()
      using errcode = '22023';
  end if;

  new.file_bytes := 0;
  if new.kind = 'upload' then
    if (storage.foldername(new.file_path))[1] is distinct from new.user_id::text
       or new.file_path not ilike '%.pdf' then
      raise exception 'Upload the PDF to your own folder first' using errcode = '42501';
    end if;
    if not exists (select 1 from storage.objects where bucket_id = 'study-files' and name = new.file_path) then
      raise exception 'That file has not finished uploading' using errcode = '22023';
    end if;
    new.file_bytes := public.zl_object_bytes('study-files', new.file_path);
  elsif new.kind = 'library' then
    select r.file_path into path from public.resources r
     where r.id = new.resource_id and r.retired_at is null and r.file_path ilike '%.pdf';
    if path is null then
      raise exception 'That library item has no PDF to study from' using errcode = '23514';
    end if;
    new.file_bytes := public.zl_object_bytes('resources', path);
  end if;

  if u.bytes + new.file_bytes > public.study_kit_max_bytes() then
    raise exception 'A kit can hold at most 30 MB of PDFs. Remove a file first.' using errcode = '22023';
  end if;

  new.label := left(btrim(new.label), 120);
  new.created_at := now();
  new.position := coalesce((select max(position) + 1 from public.study_note_sources where note_id = new.note_id), 1);
  return new;
end $$;
revoke execute on function public.study_note_sources_check() from public, anon, authenticated;

drop trigger if exists study_note_sources_check on public.study_note_sources;
create trigger study_note_sources_check before insert on public.study_note_sources
  for each row execute function public.study_note_sources_check();

-- The kit's original source can now be removed too (so every source can be
-- removed from the materials tab). Only the owner, only to clear it.
create or replace function public.study_remove_main_source(p_note uuid)
returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if not public.is_student() then
    raise exception 'Only students have study kits' using errcode = '42501';
  end if;
  update public.study_notes
     set file_path = null, file_name = null, resource_id = null, youtube_url = null, updated_at = now()
   where id = p_note and user_id = auth.uid();
  if not found then
    raise exception 'That study kit could not be found' using errcode = 'P0002';
  end if;
end $$;
revoke execute on function public.study_remove_main_source(uuid) from public, anon;
grant execute on function public.study_remove_main_source(uuid) to authenticated;

-- ================================================================ AI: read every source
-- As in 0014, plus "sources": every source in order, the kit's original
-- one first. The old single-source fields stay for the first PDF or video,
-- so an older study-generate keeps working.
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
  srcs      jsonb := '[]'::jsonb;
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
  if n.file_path is not null then
    srcs := srcs || jsonb_build_object('kind', 'upload', 'label', coalesce(n.file_name, 'PDF'),
                      'bucket', 'study-files', 'path', n.file_path);
  elsif lib_path is not null then
    srcs := srcs || jsonb_build_object('kind', 'library', 'label', 'Library PDF',
                      'bucket', 'resources', 'path', lib_path);
  elsif n.youtube_url is not null then
    srcs := srcs || jsonb_build_object('kind', 'youtube', 'label', 'Video', 'youtube_url', n.youtube_url);
  end if;

  select srcs || coalesce(jsonb_agg(
           jsonb_strip_nulls(jsonb_build_object(
             'kind', s.kind, 'label', s.label,
             'bucket', case s.kind when 'upload' then 'study-files' when 'library' then 'resources' end,
             'path', case s.kind when 'upload' then s.file_path when 'library' then r.file_path end,
             'youtube_url', s.youtube_url,
             'body', s.body))
           order by s.position), '[]'::jsonb)
    into srcs
    from public.study_note_sources s
    left join public.resources r on r.id = s.resource_id and r.retired_at is null
   where s.note_id = p_note and s.user_id = p_user
     and (s.kind <> 'library' or r.id is not null);

  if btrim(n.body) = '' and jsonb_array_length(srcs) = 0 then
    return jsonb_build_object('error', 'no_source');
  end if;

  return jsonb_build_object(
    'title', n.title,
    'body', n.body,
    'remaining', least(left_mine, left_all),
    'file_bucket', case when n.file_path is not null then 'study-files'
                        when lib_path is not null then 'resources' end,
    'file_path', coalesce(n.file_path, lib_path),
    'youtube_url', n.youtube_url,
    'sources', srcs);
end $$;

revoke execute on function public.study_ai_prepare(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.study_ai_prepare(uuid, uuid, text) to service_role;
