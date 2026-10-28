-- ZutLib: open sign-up with admin approval, protected roles, library books
--
-- Replaces registration against the student roll (see DECISIONS.md):
--
--   1. Account status   every profile is pending, active, rejected or
--                       suspended. Only active accounts can use anything.
--   2. Sign-up          a database trigger makes the profile when Supabase
--                       Auth creates a user. It is always a pending student;
--                       nothing a person types can make it anything else.
--   3. Who is who       is_active, is_student, is_staff, is_admin all now
--                       require an active account.
--   4. Locked columns   no client can change any profile column. Admin
--                       actions go through the admin-users Edge Function,
--                       which calls admin_apply below.
--   5. Admin actions    approve, reject, suspend, reactivate, change role,
--                       each written to the audit log in the same step.
--   6. Policies         every existing read and write rule now requires an
--                       active account.
--   7. Borrowing        requests also carry the student's email and
--                       department, copied from the profile.
--   8. Library          books (author, ISBN, edition, copies), past paper
--                       course titles, a sample flag, retiring a book.
--   9. Search           retired items are left out; authors and ISBNs are
--                       searchable.
--
-- Run 0011_book_type.sql first, on its own.

-- ================================================================ 1. status
do $$ begin
  create type public.account_status as enum ('pending', 'active', 'rejected', 'suspended');
exception when duplicate_object then null;
end $$;

alter table public.profiles
  add column if not exists status account_status not null default 'pending',
  add column if not exists email text,
  add column if not exists must_set_password boolean not null default false,
  add column if not exists invited_by uuid references public.profiles(id) on delete set null,
  add column if not exists decided_at timestamptz;

-- Everyone who already has a profile was either checked against the roll
-- or set up by staff, so they stay able to use the app.
update public.profiles set status = 'active' where status = 'pending';
update public.profiles p set email = u.email from auth.users u
 where u.id = p.id and p.email is distinct from u.email;

-- Student numbers and surnames are no longer collected.
alter table public.profiles alter column surname drop not null;
alter table public.profiles drop constraint if exists profiles_student_number_fkey;

create index if not exists profiles_status_idx on public.profiles (status, role);

-- ================================================================ 2. sign-up
-- Supabase Auth inserts into auth.users when someone signs up (or is
-- invited). This makes the matching profile. It reads only the name and
-- department from the sign-up form, and always makes a PENDING STUDENT:
-- the form cannot ask for any other role, because role is not read here.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta  jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  name  text  := left(btrim(coalesce(meta ->> 'full_name', '')), 120);
  dept  text  := meta ->> 'department';
begin
  if name = '' then
    name := split_part(coalesce(new.email, 'New user'), '@', 1);
  end if;
  if dept is null or dept not in ('ICT', 'Engineering', 'Business') then
    dept := null;
  end if;
  insert into public.profiles (id, full_name, department, role, status, email)
  values (new.id, name, dept, 'student', 'pending', new.email)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Keep the profile's copy of the email address current.
create or replace function public.sync_profile_email()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set email = new.email where id = new.id;
  return new;
end $$;

drop trigger if exists on_auth_user_email on auth.users;
create trigger on_auth_user_email
  after update of email on auth.users
  for each row when (old.email is distinct from new.email)
  execute function public.sync_profile_email();

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.sync_profile_email() from public, anon, authenticated;

-- ================================================================ 3. who is who
create or replace function public.is_active()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'active' from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role in ('librarian', 'admin') and status = 'active'
       from public.profiles where id = auth.uid()),
    false)
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role = 'admin' and status = 'active' from public.profiles where id = auth.uid()),
    false)
$$;

create or replace function public.is_student()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role = 'student' and status = 'active' from public.profiles where id = auth.uid()),
    false)
$$;

revoke execute on function public.is_active() from public, anon;
grant execute on function public.is_active() to authenticated, service_role;

-- ================================================================ 4. locked columns
-- No signed-in user may write any profile column, their own included.
-- (0009 had left "role" writable for administrators; that now goes
-- through admin_apply so it is checked and logged.)
revoke insert, update, delete on public.profiles from authenticated, anon;

-- An invited user clears their own "set a password" flag once they have
-- chosen one. It is the only change anyone can make to their own profile,
-- and it can only switch the flag off.
create or replace function public.mark_password_set()
returns void
language sql volatile security definer set search_path = public as $$
  update public.profiles set must_set_password = false
   where id = auth.uid() and must_set_password
$$;

revoke execute on function public.mark_password_set() from public, anon;
grant execute on function public.mark_password_set() to authenticated;

-- The last active administrator can be neither demoted nor switched off,
-- and no administrator can change their own role or status from the app.
create or replace function public.guard_admin_roles()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role or new.status is distinct from old.status then
    if auth.uid() is not null and new.id = auth.uid() then
      raise exception 'You cannot change your own role or status'
        using errcode = '42501';
    end if;
    if old.role = 'admin' and old.status = 'active'
       and (new.role <> 'admin' or new.status <> 'active')
       and (select count(*) from public.profiles where role = 'admin' and status = 'active') <= 1 then
      raise exception 'At least one active administrator must remain'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

-- ================================================================ 5. admin actions
-- The audit log is for administrators only now.
drop policy if exists audit_staff_read on public.audit_entries;
drop policy if exists audit_admin_read on public.audit_entries;
create policy audit_admin_read on public.audit_entries
  for select to authenticated using (public.is_admin());

create or replace function public.admin_is_admin(p_user uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                  where id = p_user and role = 'admin' and status = 'active')
$$;

-- One administrator action on one account, checked and logged together.
-- Called only by the admin-users Edge Function, with the id it verified
-- from the caller's token as p_actor.
create or replace function public.admin_apply(
  p_actor uuid, p_target uuid, p_action text, p_role user_role default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  t          public.profiles;
  new_status account_status;
  new_role   user_role;
begin
  if not public.admin_is_admin(p_actor) then
    raise exception 'Only an active administrator can do that' using errcode = '42501';
  end if;
  select * into t from public.profiles where id = p_target for update;
  if not found then
    raise exception 'That account no longer exists' using errcode = 'P0002';
  end if;
  if p_target = p_actor and p_action in ('reject', 'suspend', 'set_role') then
    raise exception 'You cannot change your own account. Ask another administrator.'
      using errcode = '42501';
  end if;

  new_status := t.status;
  new_role := t.role;
  case p_action
    when 'approve' then
      if t.status <> 'pending' then
        raise exception 'Only a pending account can be approved' using errcode = '22023';
      end if;
      new_status := 'active';
    when 'reject' then
      if t.status <> 'pending' then
        raise exception 'Only a pending account can be rejected' using errcode = '22023';
      end if;
      new_status := 'rejected';
    when 'suspend' then
      if t.status <> 'active' then
        raise exception 'Only an active account can be suspended' using errcode = '22023';
      end if;
      new_status := 'suspended';
    when 'reactivate' then
      if t.status not in ('suspended', 'rejected') then
        raise exception 'Only a suspended or rejected account can be reactivated' using errcode = '22023';
      end if;
      new_status := 'active';
    when 'set_role' then
      if p_role is null then
        raise exception 'Choose a role' using errcode = '22023';
      end if;
      new_role := p_role;
    else
      raise exception 'Unknown action' using errcode = '22023';
  end case;

  update public.profiles
     set status = new_status, role = new_role, decided_at = now(), updated_at = now()
   where id = p_target;

  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (p_actor, 'admin.' || p_action, 'profiles', p_target::text,
          jsonb_build_object('status_from', t.status, 'status_to', new_status,
                             'role_from', t.role, 'role_to', new_role));

  return jsonb_build_object('id', p_target, 'status', new_status, 'role', new_role);
end $$;

-- After Supabase Auth has sent an invite (and the trigger above has made a
-- pending student profile), give the account the role the administrator
-- chose. Invited accounts are approved straight away. A test invite makes
-- a suspended account, so the address can receive the email but the
-- account can do nothing.
create or replace function public.admin_after_invite(
  p_actor uuid, p_user uuid, p_role user_role, p_full_name text,
  p_department text, p_test boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  dept text := case when p_department in ('ICT', 'Engineering', 'Business') then p_department end;
  addr text;
begin
  if not public.admin_is_admin(p_actor) then
    raise exception 'Only an active administrator can do that' using errcode = '42501';
  end if;
  select email into addr from auth.users where id = p_user;
  if addr is null then
    raise exception 'That account no longer exists' using errcode = 'P0002';
  end if;

  insert into public.profiles (id, full_name, department, role, status, email,
                               must_set_password, invited_by, decided_at)
  values (p_user, left(btrim(p_full_name), 120), dept, p_role,
          case when p_test then 'suspended' else 'active' end::account_status,
          addr, true, p_actor, now())
  on conflict (id) do update
    set full_name = excluded.full_name, department = excluded.department,
        role = excluded.role, status = excluded.status,
        must_set_password = true, invited_by = excluded.invited_by,
        decided_at = now(), updated_at = now();

  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (p_actor, case when p_test then 'admin.test_invite' else 'admin.create' end,
          'profiles', p_user::text,
          jsonb_build_object('email', addr, 'role', p_role));

  return jsonb_build_object('id', p_user, 'email', addr, 'role', p_role,
                            'status', case when p_test then 'suspended' else 'active' end);
end $$;

-- For actions with no profile change of their own, such as resending an
-- invite.
create or replace function public.admin_record(
  p_actor uuid, p_action text, p_target uuid, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if not public.admin_is_admin(p_actor) then
    raise exception 'Only an active administrator can do that' using errcode = '42501';
  end if;
  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (p_actor, 'admin.' || p_action, 'profiles', p_target::text, coalesce(p_detail, '{}'::jsonb));
end $$;

revoke execute on function public.admin_is_admin(uuid) from public, anon, authenticated;
revoke execute on function public.admin_apply(uuid, uuid, text, user_role) from public, anon, authenticated;
revoke execute on function public.admin_after_invite(uuid, uuid, user_role, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.admin_record(uuid, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_is_admin(uuid) to service_role;
grant execute on function public.admin_apply(uuid, uuid, text, user_role) to service_role;
grant execute on function public.admin_after_invite(uuid, uuid, user_role, text, text, boolean) to service_role;
grant execute on function public.admin_record(uuid, text, uuid, jsonb) to service_role;

-- ================================================================ 6. policies
-- (retired_at is described in part 8; it is needed by a policy here.)
alter table public.resources add column if not exists retired_at timestamptz;
drop policy if exists resources_read on public.resources;
create policy resources_read on public.resources
  for select to authenticated using (public.is_active());

drop policy if exists resources_files_read on storage.objects;
create policy resources_files_read on storage.objects
  for select to authenticated
  using (bucket_id = 'resources' and public.is_active());

drop policy if exists borrow_read_own on public.borrow_requests;
create policy borrow_read_own on public.borrow_requests
  for select to authenticated
  using ((student_id = auth.uid() and public.is_active()) or public.is_staff());

-- Only an active student may ask to borrow, only for themselves, only a
-- physical copy that is on the shelf and not retired.
drop policy if exists borrow_insert_own on public.borrow_requests;
create policy borrow_insert_own on public.borrow_requests
  for insert to authenticated
  with check (
    student_id = auth.uid()
    and public.is_student()
    and status = 'submitted'
    and decided_by is null
    and exists (
      select 1 from public.resources r
      where r.id = resource_id and r.is_physical = true
        and r.available_copies > 0 and r.retired_at is null
    )
  );

drop policy if exists borrow_cancel_own on public.borrow_requests;
create policy borrow_cancel_own on public.borrow_requests
  for update to authenticated
  using (student_id = auth.uid() and status = 'submitted' and public.is_active())
  with check (student_id = auth.uid() and status = 'cancelled');

drop policy if exists notif_read_own on public.notifications;
create policy notif_read_own on public.notifications
  for select to authenticated using (user_id = auth.uid() and public.is_active());

drop policy if exists notif_mark_read on public.notifications;
create policy notif_mark_read on public.notifications
  for update to authenticated
  using (user_id = auth.uid() and public.is_active())
  with check (user_id = auth.uid());

-- ================================================================ 7. borrowing
alter table public.borrow_requests
  add column if not exists student_email text,
  add column if not exists student_department text;

create or replace function public.stamp_borrow_identity()
returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = new.student_id;
  if not found then
    raise exception 'No profile for this account' using errcode = '42501';
  end if;
  new.student_name       := p.full_name;
  new.student_number     := coalesce(p.student_number, '');
  new.programme          := p.programme;
  new.student_email      := p.email;
  new.student_department := p.department;
  new.requested_at       := now();
  return new;
end $$;

-- ================================================================ 8. library
alter table public.resources
  add column if not exists author       text,
  add column if not exists isbn         text,
  add column if not exists edition      text,
  add column if not exists course_title text,
  add column if not exists is_sample    boolean not null default false,
  add column if not exists retired_at   timestamptz;

-- A book has no academic year and may have no course code.
alter table public.resources alter column course_code drop not null;
alter table public.resources alter column academic_year drop not null;
alter table public.resources drop constraint if exists resources_course_code_check;

alter table public.resources drop constraint if exists resources_paper_fields;
alter table public.resources add constraint resources_paper_fields check (
  type = 'book' or (course_code is not null and length(btrim(course_code)) > 0
                    and academic_year is not null)
);
alter table public.resources drop constraint if exists resources_book_fields;
alter table public.resources add constraint resources_book_fields check (
  type <> 'book' or (is_physical and author is not null and length(btrim(author)) > 0)
);
alter table public.resources drop constraint if exists resources_text_lengths;
alter table public.resources add constraint resources_text_lengths check (
  length(title) <= 300
  and (author is null or length(author) <= 200)
  and (edition is null or length(edition) <= 40)
  and (course_title is null or length(course_title) <= 200)
);
alter table public.resources drop constraint if exists resources_isbn_shape;
alter table public.resources add constraint resources_isbn_shape check (
  isbn is null or isbn ~ '^([0-9]{9}[0-9X]|[0-9]{13})$'
);

-- Tidy what staff type: course codes "eee2011" -> "EEE 2011", spaces in
-- names, ISBNs stripped to digits (and a final X).
create or replace function public.normalise_resource_fields()
returns trigger language plpgsql as $$
begin
  if new.course_code is not null then
    new.course_code := nullif(regexp_replace(
      upper(btrim(new.course_code)), '^([A-Z]+)[[:space:]._-]*([0-9]+)$', '\1 \2'), '');
  end if;
  new.department  := btrim(regexp_replace(new.department, '[[:space:]]+', ' ', 'g'));
  new.title       := btrim(regexp_replace(new.title,      '[[:space:]]+', ' ', 'g'));
  if new.author is not null then
    new.author := nullif(btrim(regexp_replace(new.author, '[[:space:]]+', ' ', 'g')), '');
  end if;
  if new.isbn is not null then
    new.isbn := nullif(upper(regexp_replace(new.isbn, '[^0-9Xx]', '', 'g')), '');
  end if;
  if new.edition is not null then new.edition := nullif(btrim(new.edition), ''); end if;
  if new.course_title is not null then new.course_title := nullif(btrim(new.course_title), ''); end if;
  return new;
end $$;

-- Search columns, rebuilt so that a book with no year or course code is
-- still searchable, and so authors and ISBNs can be found.
set search_path = public, extensions;

drop index if exists public.resources_search_text_trgm;
alter table public.resources drop column if exists search_text;
alter table public.resources
  add column search_text text generated always as (
    public.zl_norm(title) || ' ' ||
    public.zl_norm(coalesce(course_code, '')) || ' ' ||
    replace(public.zl_norm(coalesce(course_code, '')), ' ', '') || ' ' ||
    public.zl_norm(department) || ' ' ||
    coalesce(academic_year::text, '') || ' ' ||
    public.zl_norm(coalesce(author, '')) || ' ' ||
    coalesce(isbn, '') || ' ' ||
    public.zl_norm(coalesce(course_title, '')) || ' ' ||
    public.zl_norm(coalesce(description, ''))
  ) stored;
create index resources_search_text_trgm on public.resources using gin (search_text gin_trgm_ops);

drop index if exists public.resources_search_idx;
alter table public.resources drop column if exists search_vector;
alter table public.resources
  add column search_vector tsvector generated always as (
    setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(course_code, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(course_title, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(author, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(description, '')), 'C')
  ) stored;
create index resources_search_idx on public.resources using gin (search_vector);

create index if not exists resources_live_idx on public.resources (type, department, academic_year desc)
  where retired_at is null;
create index if not exists resources_sample_idx on public.resources (is_sample);

-- Changing how many copies the library owns. The shelf count moves by the
-- same amount in one statement, and is refused if more copies are out on
-- loan than the new total, so the count can never go below zero.
create or replace function public.set_book_copies(p_resource uuid, p_total int)
returns public.resources
language plpgsql volatile security invoker set search_path = public as $$
declare r public.resources;
begin
  if not public.is_staff() then
    raise exception 'Only library staff can change copy counts' using errcode = '42501';
  end if;
  if p_total is null or p_total < 1 or p_total > 1000 then
    raise exception 'The total must be between 1 and 1000' using errcode = '22023';
  end if;
  update public.resources
     set total_copies = p_total,
         available_copies = available_copies + (p_total - total_copies)
   where id = p_resource and is_physical
     and available_copies + (p_total - total_copies) >= 0
  returning * into r;
  if not found then
    raise exception 'More copies are on loan than that total. Wait for returns first.'
      using errcode = '22023';
  end if;
  return r;
end $$;

revoke execute on function public.set_book_copies(uuid, int) from public, anon;
grant execute on function public.set_book_copies(uuid, int) to authenticated;

-- ================================================================ 9. search
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
        when 'book'          then 'book textbook library'
        else                      'recommended book reading link'
      end as hay
  ) h
  where r.retired_at is null
    and (p_department is null or lower(r.department) = lower(btrim(p_department)))
    and (p_course     is null or replace(public.zl_norm(r.course_code), ' ', '') = course)
    and (p_year       is null or r.academic_year = p_year)
    and (p_type       is null or r.type = p_type)
    and (
      raw = ''
      or (cardinality(toks) = 0 and lower(r.title) like '%' || raw || '%')
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
    (cardinality(toks) > 0
      and replace(public.zl_norm(coalesce(r.course_code, '')), ' ', '') = replace(nq, ' ', '')) desc,
    coalesce(ts_rank(r.search_vector, tsq), 0) desc,
    (select coalesce(sum(word_similarity(t, h.hay)), 0)
       from unnest(toks) t) desc,
    r.academic_year desc nulls last,
    r.title asc
  limit greatest(1, least(p_limit, 100))
  offset greatest(0, p_offset);
end $$;

grant execute on function public.search_resources(
  text, text, text, int, resource_type, int, int) to authenticated;

drop function if exists public.resource_facets(text);
create function public.resource_facets(p_department text default null)
returns table (departments text[], course_codes text[], years int[])
language sql stable security invoker set search_path = public as $$
  select
    array(select distinct department from public.resources
            where retired_at is null order by 1),
    array(select distinct course_code from public.resources
            where retired_at is null and course_code is not null
              and (p_department is null or lower(department) = lower(p_department))
            order by 1),
    array(select distinct academic_year from public.resources
            where retired_at is null and academic_year is not null
              and (p_department is null or lower(department) = lower(p_department))
            order by 1 desc)
$$;

grant execute on function public.resource_facets(text) to authenticated;

-- ================================================================ dashboard
create or replace function public.admin_overview()
returns table (
  pending_students int, active_students int, suspended_accounts int,
  librarians int, admins int,
  books int, sample_books int, papers int, sample_papers int,
  open_requests int, overdue_requests int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see the dashboard' using errcode = '42501';
  end if;
  return query select
    (select count(*)::int from profiles where role = 'student' and status = 'pending'),
    (select count(*)::int from profiles where role = 'student' and status = 'active'),
    (select count(*)::int from profiles where status in ('suspended', 'rejected')),
    (select count(*)::int from profiles where role = 'librarian' and status = 'active'),
    (select count(*)::int from profiles where role = 'admin' and status = 'active'),
    (select count(*)::int from resources where type = 'book' and retired_at is null),
    (select count(*)::int from resources where type = 'book' and retired_at is null and is_sample),
    (select count(*)::int from resources where type in ('past_paper', 'test_paper') and retired_at is null),
    (select count(*)::int from resources where type in ('past_paper', 'test_paper') and retired_at is null and is_sample),
    (select count(*)::int from borrow_requests where status in ('submitted', 'under_review', 'approved')),
    (select count(*)::int from borrow_requests where status = 'collected' and due_date < current_date);
end $$;

revoke execute on function public.admin_overview() from public, anon;
grant execute on function public.admin_overview() to authenticated;

-- The old staff dashboard counts now need an active staff account.
create or replace function public.staff_overview()
returns table (pending int, collected int, overdue int, resources int)
language plpgsql stable security invoker set search_path = public as $$
begin
  if not public.is_staff() then
    raise exception 'Only library staff can see these counts' using errcode = '42501';
  end if;
  return query select
    (select count(*)::int from public.borrow_requests
       where status in ('submitted','under_review')),
    (select count(*)::int from public.borrow_requests
       where status = 'collected' and (due_date is null or due_date >= current_date)),
    (select count(*)::int from public.borrow_requests
       where status = 'collected' and due_date < current_date),
    (select count(*)::int from public.resources where retired_at is null);
end $$;
