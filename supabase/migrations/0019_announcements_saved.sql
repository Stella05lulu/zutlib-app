-- ZutLib: announcements and saved resources (plan items 10, 9)
--
-- Run after 0018_account_tools_settings.sql.
--
--   1. Announcements  written only by administrators and the super admin,
--                     through the functions below, each audited. Students
--                     read only active ones (not ended, not removed, for
--                     everyone or for their department). Removing keeps the
--                     row, so the audit log still points at something.
--   2. Saved          a student's own bookmarks of catalogue items. Each
--                     person sees and changes only their own.

-- ================================================================ 1. announcements
create table if not exists public.announcements (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  body        text not null,
  department  text,
  ends_on     date,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  removed_at  timestamptz,
  is_sample   boolean not null default false,
  constraint announcements_title_len check (length(btrim(title)) between 3 and 120),
  constraint announcements_body_len check (length(btrim(body)) between 3 and 2000),
  constraint announcements_department check (department is null or department in ('ICT', 'Engineering', 'Business'))
);

create index if not exists announcements_live_idx on public.announcements (created_at desc) where removed_at is null;

alter table public.announcements enable row level security;

-- Active announcements for the reader's department (or for everyone);
-- administrators also see ended and targeted ones, but never removed ones
-- through this policy.
drop policy if exists announcements_read on public.announcements;
create policy announcements_read on public.announcements
  for select to authenticated
  using (
    removed_at is null
    and (
      public.is_admin()
      or (public.is_active()
          and (ends_on is null or ends_on >= public.zl_today())
          and (department is null
               or public.is_staff()
               or department = (select p.department from public.profiles p where p.id = auth.uid())))
    )
  );

revoke all on public.announcements from anon, authenticated;
grant select on public.announcements to authenticated;
grant all on public.announcements to service_role;

-- Create (p_id null) or edit (p_id given). Returns the row.
create or replace function public.admin_save_announcement(
  p_id uuid, p_title text, p_body text, p_department text default null, p_ends_on date default null)
returns public.announcements
language plpgsql volatile security definer set search_path = public as $$
declare
  before public.announcements;
  after  public.announcements;
  dept   text := nullif(btrim(coalesce(p_department, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can post announcements.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'The title must be 3 to 120 characters' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_body, ''))) not between 3 and 2000 then
    raise exception 'The message must be 3 to 2000 characters' using errcode = '22023';
  end if;
  if dept is not null and dept not in ('ICT', 'Engineering', 'Business') then
    raise exception 'Choose ICT, Engineering, Business or everyone' using errcode = '22023';
  end if;
  if p_ends_on is not null and p_ends_on < public.zl_today() then
    raise exception 'The end date cannot be in the past' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.announcements (title, body, department, ends_on, created_by)
    values (btrim(p_title), btrim(p_body), dept, p_ends_on, auth.uid())
    returning * into after;
    insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
    values (auth.uid(), 'admin.announcement_create', 'announcements', after.id::text,
            jsonb_strip_nulls(jsonb_build_object('title', after.title, 'department', dept, 'ends_on', p_ends_on)));
  else
    select * into before from public.announcements where id = p_id and removed_at is null for update;
    if not found then
      raise exception 'That announcement no longer exists' using errcode = 'P0002';
    end if;
    update public.announcements
       set title = btrim(p_title), body = btrim(p_body), department = dept,
           ends_on = p_ends_on, updated_at = now()
     where id = p_id
    returning * into after;
    insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
    values (auth.uid(), 'admin.announcement_edit', 'announcements', p_id::text,
            jsonb_build_object(
              'before', jsonb_build_object('title', before.title, 'department', before.department, 'ends_on', before.ends_on),
              'after', jsonb_build_object('title', after.title, 'department', after.department, 'ends_on', after.ends_on)));
  end if;
  return after;
end $$;

create or replace function public.admin_remove_announcement(p_id uuid)
returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  a public.announcements;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can remove announcements.' using errcode = '42501';
  end if;
  update public.announcements set removed_at = now(), updated_at = now()
   where id = p_id and removed_at is null
  returning * into a;
  if not found then
    raise exception 'That announcement no longer exists' using errcode = 'P0002';
  end if;
  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (auth.uid(), 'admin.announcement_remove', 'announcements', p_id::text,
          jsonb_build_object('title', a.title));
end $$;

revoke execute on function public.admin_save_announcement(uuid, text, text, text, date) from public, anon;
revoke execute on function public.admin_remove_announcement(uuid) from public, anon;
grant execute on function public.admin_save_announcement(uuid, text, text, text, date) to authenticated;
grant execute on function public.admin_remove_announcement(uuid) to authenticated;

-- ================================================================ 2. saved
create table if not exists public.saved_resources (
  user_id      uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  resource_id  uuid not null references public.resources(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (user_id, resource_id)
);

create index if not exists saved_resources_user_idx on public.saved_resources (user_id, created_at desc);

alter table public.saved_resources enable row level security;

drop policy if exists saved_own on public.saved_resources;
create policy saved_own on public.saved_resources
  for all to authenticated
  using (user_id = auth.uid() and public.is_active())
  with check (user_id = auth.uid() and public.is_active());

revoke all on public.saved_resources from anon, authenticated;
grant select, delete on public.saved_resources to authenticated;
grant insert (resource_id) on public.saved_resources to authenticated;
grant all on public.saved_resources to service_role;

drop trigger if exists saved_resources_cap on public.saved_resources;
create trigger saved_resources_cap before insert on public.saved_resources
  for each row execute function public.study_cap_rows('user_id', '500');
