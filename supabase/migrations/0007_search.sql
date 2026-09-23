-- ZutLib — search that behaves the way students actually type
--
-- Problems this fixes in 0002's search_resources:
--   1. "ict2010", "ICT-2010" and "ict 2010" did not all find ICT 2010.
--   2. A query mixing fields ("eee 2011 2024", "programming 2023") returned
--      nothing, because the whole string had to appear in one column.
--   3. Department, year and resource type were not searchable as words.
--   4. A small typo ("entreprenuership", "microproccessors") returned nothing.
--   5. Course codes typed differently at upload ("eee2011" vs "EEE 2011")
--      showed up as two different courses in the filter dropdown.
--
-- How it works now, in one sentence you can defend:
--   the query is normalised and split into words, and a resource matches
--   only if EVERY word is found in it, either as a substring, as an English
--   word stem, or as a close spelling (trigram similarity); results are
--   ranked exact course code first, then full text rank, then closeness.
--
-- Row level security is unchanged: the function is SECURITY INVOKER, so the
-- caller's policies still decide which rows exist for them.

create extension if not exists pg_trgm with schema extensions;

-- pg_trgm may live in "extensions" (Supabase default) or "public";
-- this lets the operator class and word_similarity resolve in either.
set search_path = public, extensions;

-- Signed-in users call search_resources, which calls pg_trgm's
-- word_similarity. Without USAGE on the schema holding pg_trgm, every
-- search from the app fails with "function word_similarity does not exist".
grant usage on schema extensions to authenticated;

-- ---------------------------------------------------------------- normaliser
-- Lower case, every run of non letters/digits becomes one space.
-- "EEE-2011 (Dec)" -> "eee 2011 dec". Immutable so it can feed a stored column.
create or replace function public.zl_norm(t text)
returns text
language sql immutable parallel safe as $$
  select btrim(regexp_replace(lower(coalesce(t, '')), '[^a-z0-9]+', ' ', 'g'))
$$;

grant execute on function public.zl_norm(text) to authenticated;

-- ---------------------------------------------------------------- tidy input
-- One spelling per course code: "eee2011", "EEE-2011", " eee 2011 " all
-- become "EEE 2011". Runs before the generated columns are computed.
create or replace function public.normalise_resource_fields()
returns trigger language plpgsql as $$
begin
  new.course_code := regexp_replace(
    upper(btrim(new.course_code)), '^([A-Z]+)[[:space:]._-]*([0-9]+)$', '\1 \2');
  new.department  := btrim(regexp_replace(new.department, '[[:space:]]+', ' ', 'g'));
  new.title       := btrim(regexp_replace(new.title,      '[[:space:]]+', ' ', 'g'));
  return new;
end $$;

drop trigger if exists resources_normalise on public.resources;
create trigger resources_normalise before insert or update on public.resources
  for each row execute function public.normalise_resource_fields();

-- Bring rows already in the table into the same shape.
update public.resources set course_code = course_code;

-- ---------------------------------------------------------------- haystack
-- Everything a student might type, in one normalised column, kept current
-- by the database. The course code is stored twice, with and without the
-- space, so "eee2011" and "eee 2011" both hit.
alter table public.resources drop column if exists search_text;
alter table public.resources
  add column search_text text generated always as (
    public.zl_norm(title) || ' ' ||
    public.zl_norm(course_code) || ' ' ||
    replace(public.zl_norm(course_code), ' ', '') || ' ' ||
    public.zl_norm(department) || ' ' ||
    academic_year::text || ' ' ||
    public.zl_norm(description)
  ) stored;

create index if not exists resources_search_text_trgm
  on public.resources using gin (search_text gin_trgm_ops);

-- ---------------------------------------------------------------- search rpc
-- Same name, same parameters and same return type as 0002, so the app's
-- call does not change.
create or replace function public.search_resources(
  q            text default null,
  p_department text default null,
  p_course     text default null,
  p_year       int  default null,
  p_type       resource_type default null,
  p_limit      int  default 50,
  p_offset     int  default 0
)
returns setof public.resources
language plpgsql stable security invoker
set search_path = public, extensions as $$
declare
  nq     text    := public.zl_norm(q);
  toks   text[];
  tsq    tsquery;
  course text    := replace(public.zl_norm(p_course), ' ', '');
  raw    text    := replace(replace(lower(btrim(coalesce(q, ''))), '%', ''), '_', '');
begin
  -- Words that carry no meaning are dropped so "past papers for eee 2011"
  -- is judged on "past papers eee 2011".
  select coalesce(array_agg(t), '{}') into toks
  from unnest(string_to_array(nullif(nq, ''), ' ')) as t
  where length(t) >= 2
    and t not in ('the','of','and','for','in','to','on','with','an','by','at');

  if cardinality(toks) > 0 then
    tsq := websearch_to_tsquery('english', q);
  end if;

  return query
  select r.*
  from public.resources r
  cross join lateral (
    select r.search_text || ' ' ||
      case r.type
        when 'past_paper'    then 'past paper exam examination'
        when 'test_paper'    then 'test paper'
        when 'lecture_notes' then 'lecture notes'
        else                      'recommended book reading link'
      end as hay
  ) h
  where (p_department is null or lower(r.department) = lower(btrim(p_department)))
    and (p_course     is null or replace(public.zl_norm(r.course_code), ' ', '') = course)
    and (p_year       is null or r.academic_year = p_year)
    and (p_type       is null or r.type = p_type)
    and (
      -- nothing typed: everything passes
      raw = ''
      -- only symbols or one-letter words typed (for example "c++"):
      -- match the literal text against the title instead
      or (cardinality(toks) = 0 and lower(r.title) like '%' || raw || '%')
      -- otherwise every word must be found, one way or another
      or (cardinality(toks) > 0 and not exists (
      select 1 from unnest(toks) t
      where not (
        h.hay like '%' || t || '%'
        or r.search_vector @@ plainto_tsquery('english', t)
        or (length(t) >= 4 and t ~ '[a-z]'
            and word_similarity(t, h.hay) >= 0.5)
      )
    ))
    )
  order by
    -- typing the exact course code puts that course first
    (cardinality(toks) > 0
      and replace(public.zl_norm(r.course_code), ' ', '') = replace(nq, ' ', '')) desc,
    coalesce(ts_rank(r.search_vector, tsq), 0) desc,
    (select coalesce(sum(word_similarity(t, h.hay)), 0)
       from unnest(toks) t) desc,
    r.academic_year desc,
    r.title asc
  limit greatest(1, least(p_limit, 100))
  offset greatest(0, p_offset);
end $$;

grant execute on function public.search_resources(
  text, text, text, int, resource_type, int, int) to authenticated;

-- ---------------------------------------------------------------- facets
-- Course and year lists now follow the chosen department, so an
-- Engineering student is not offered Business course codes.
drop function if exists public.resource_facets();
drop function if exists public.resource_facets(text);
create function public.resource_facets(p_department text default null)
returns table (departments text[], course_codes text[], years int[])
language sql stable security invoker set search_path = public as $$
  select
    array(select distinct department from public.resources order by 1),
    array(select distinct course_code from public.resources
            where p_department is null or lower(department) = lower(p_department)
            order by 1),
    array(select distinct academic_year from public.resources
            where p_department is null or lower(department) = lower(p_department)
            order by 1 desc)
$$;

grant execute on function public.resource_facets(text) to authenticated;

-- ---------------------------------------------------------------- checks
-- Run these after the seed to see it working (as postgres in the SQL editor,
-- RLS does not apply there):
--   select title from search_resources('ict2010');
--   select title from search_resources('eee 2011 2024');
--   select title from search_resources('entreprenuership');      -- typo
--   select title from search_resources('microprocessors june');
--   select title from search_resources('test papers', null, 'EEE 2021');
--   select * from resource_facets('Engineering');
