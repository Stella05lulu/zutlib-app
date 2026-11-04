-- ZutLib: the super admin role (build plan item 1)
--
-- Run 0016_super_admin_enum.sql first, on its own.
--
--   1. Ranks          student 0, librarian 1, admin 2, super admin 3.
--                     Everyone acts only on accounts ranked below them.
--   2. Who is who     is_admin() and is_staff() include the super admin;
--                     is_super_admin() is new.
--   3. The guard      a trigger on profiles that no app path can get round:
--                     no one changes their own role or status, a super admin
--                     can only come from the break-glass script, and the
--                     last active super admin cannot be demoted, suspended,
--                     removed or deleted.
--   4. Admin actions  admin_apply checks ranks and who may do what, takes a
--                     reason, and can remove an account (a soft delete).
--                     admin_after_invite refuses to make a super admin, and
--                     only a super admin can invite an administrator.
--   5. Audit log      nobody can edit or delete it through the API.
--   6. Notices        the super admin gets the same notices as admins.
--
-- What each role may do:
--   super admin only        create or remove admins, change anyone's role,
--                           suspend or reinstate an admin, settings, View as
--   admin and super admin   invite librarians and students, approve or
--                           reject students, suspend or reinstate students
--                           and librarians, read the audit log

-- ================================================================ 1. ranks
create or replace function public.zl_role_rank(r public.user_role)
returns int
language sql immutable set search_path = public as $$
  select case r
    when 'student'     then 0
    when 'librarian'   then 1
    when 'admin'       then 2
    when 'super_admin' then 3
  end
$$;

-- ================================================================ 2. who is who
create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role in ('librarian', 'admin', 'super_admin') and status = 'active'
       from public.profiles where id = auth.uid()),
    false)
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role in ('admin', 'super_admin') and status = 'active'
       from public.profiles where id = auth.uid()),
    false)
$$;

create or replace function public.is_super_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role = 'super_admin' and status = 'active'
       from public.profiles where id = auth.uid()),
    false)
$$;

revoke execute on function public.is_super_admin() from public, anon;
grant execute on function public.is_super_admin() to authenticated, service_role;

-- Used by the admin-users Edge Function with the id it verified.
create or replace function public.admin_is_admin(p_user uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                  where id = p_user and role in ('admin', 'super_admin') and status = 'active')
$$;

create or replace function public.admin_is_super(p_user uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                  where id = p_user and role = 'super_admin' and status = 'active')
$$;

-- True when p_actor may act on p_target: an active admin or super admin
-- acting on someone else ranked below them.
create or replace function public.admin_can_manage(p_actor uuid, p_target uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles a, public.profiles t
     where a.id = p_actor and t.id = p_target and a.id <> t.id
       and a.status = 'active' and a.role in ('admin', 'super_admin')
       and public.zl_role_rank(t.role) < public.zl_role_rank(a.role))
$$;

revoke execute on function public.admin_is_super(uuid) from public, anon, authenticated;
revoke execute on function public.admin_can_manage(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_is_super(uuid) to service_role;
grant execute on function public.admin_can_manage(uuid, uuid) to service_role;

-- ================================================================ 3. the guard
-- "Break glass" is a setting only someone with direct database access can
-- turn on (scripts/restore_super_admin.sql does it inside one
-- transaction). The API has no way to set it.
create or replace function public.zl_break_glass()
returns boolean
language sql stable as $$
  select coalesce(current_setting('zutlib.break_glass', true), '') = 'on'
$$;

create or replace function public.guard_admin_roles()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  glass  boolean := public.zl_break_glass();
  supers int;
  admins int;
begin
  if tg_op = 'INSERT' then
    if new.role = 'super_admin' and not glass then
      raise exception 'A super admin can only be restored from the Supabase dashboard'
        using errcode = '42501';
    end if;
    return new;
  end if;

  select count(*) into supers from public.profiles where role = 'super_admin' and status = 'active';

  if tg_op = 'DELETE' then
    if old.role = 'super_admin' and old.status = 'active' and supers <= 1 and not glass then
      raise exception 'The last super admin cannot be deleted' using errcode = '42501';
    end if;
    return old;
  end if;

  if new.role is distinct from old.role or new.status is distinct from old.status then
    if auth.uid() is not null and new.id = auth.uid() then
      raise exception 'You cannot change your own role or status' using errcode = '42501';
    end if;
    if new.role = 'super_admin' and old.role <> 'super_admin' and not glass then
      raise exception 'A super admin can only be restored from the Supabase dashboard'
        using errcode = '42501';
    end if;
    if old.role = 'super_admin' and old.status = 'active'
       and (new.role <> 'super_admin' or new.status <> 'active')
       and supers <= 1 and not glass then
      raise exception 'The last super admin cannot be demoted, suspended or removed'
        using errcode = '42501';
    end if;
    select count(*) into admins from public.profiles
     where role in ('admin', 'super_admin') and status = 'active';
    if old.role in ('admin', 'super_admin') and old.status = 'active'
       and (new.role not in ('admin', 'super_admin') or new.status <> 'active')
       and admins <= 1 and not glass then
      raise exception 'At least one active administrator must remain' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

revoke execute on function public.guard_admin_roles() from public, anon, authenticated;

drop trigger if exists profiles_guard_admin on public.profiles;
create trigger profiles_guard_admin
  before insert or update or delete on public.profiles
  for each row execute function public.guard_admin_roles();

-- ================================================================ 4. admin actions
drop function if exists public.admin_apply(uuid, uuid, text, public.user_role);

-- One administrator action on one account, checked and logged together.
-- Called only by the admin-users Edge Function, with the id it verified
-- from the caller's token as p_actor.
create or replace function public.admin_apply(
  p_actor uuid, p_target uuid, p_action text,
  p_role public.user_role default null, p_reason text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  a          public.profiles;
  t          public.profiles;
  new_status public.account_status;
  new_role   public.user_role;
  why        text := nullif(left(btrim(coalesce(p_reason, '')), 500), '');
begin
  select * into a from public.profiles where id = p_actor;
  if not found or a.status <> 'active' or a.role not in ('admin', 'super_admin') then
    raise exception 'Only an active administrator can do that' using errcode = '42501';
  end if;
  select * into t from public.profiles where id = p_target for update;
  if not found then
    raise exception 'That account no longer exists' using errcode = 'P0002';
  end if;
  if p_target = p_actor then
    raise exception 'You cannot change your own account. Ask another administrator.'
      using errcode = '42501';
  end if;
  if public.zl_role_rank(t.role) >= public.zl_role_rank(a.role) then
    raise exception 'You can only manage accounts below your own role.' using errcode = '42501';
  end if;
  if p_action in ('set_role', 'remove') and a.role <> 'super_admin' then
    raise exception 'Only a super admin can do that.' using errcode = '42501';
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
      if p_role = 'super_admin' then
        raise exception 'A super admin cannot be made from the app.' using errcode = '42501';
      end if;
      if p_role = t.role then
        raise exception 'They already have that role' using errcode = '22023';
      end if;
      new_role := p_role;
    when 'remove' then
      if t.status = 'removed' then
        raise exception 'That account is already removed' using errcode = '22023';
      end if;
      new_status := 'removed';
    else
      raise exception 'Unknown action' using errcode = '22023';
  end case;

  update public.profiles
     set status = new_status, role = new_role, decided_at = now(), updated_at = now()
   where id = p_target;

  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (p_actor, 'admin.' || p_action, 'profiles', p_target::text,
          jsonb_strip_nulls(jsonb_build_object(
            'actor_role', a.role,
            'status_from', t.status, 'status_to', new_status,
            'role_from', t.role, 'role_to', new_role,
            'reason', why)));

  return jsonb_build_object('id', p_target, 'status', new_status, 'role', new_role);
end $$;

-- Give an invited account the role the inviter chose. Only a super admin
-- may invite an administrator; nobody can invite a super admin.
create or replace function public.admin_after_invite(
  p_actor uuid, p_user uuid, p_role public.user_role, p_full_name text,
  p_department text, p_test boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  dept text := case when p_department in ('ICT', 'Engineering', 'Business') then p_department end;
  addr text;
  a    public.profiles;
begin
  select * into a from public.profiles where id = p_actor;
  if not found or a.status <> 'active' or a.role not in ('admin', 'super_admin') then
    raise exception 'Only an active administrator can do that' using errcode = '42501';
  end if;
  if p_role = 'super_admin' then
    raise exception 'A super admin cannot be made from the app.' using errcode = '42501';
  end if;
  if public.zl_role_rank(p_role) >= public.zl_role_rank(a.role) then
    raise exception 'Only a super admin can create an administrator.' using errcode = '42501';
  end if;
  select email into addr from auth.users where id = p_user;
  if addr is null then
    raise exception 'That account no longer exists' using errcode = 'P0002';
  end if;

  insert into public.profiles (id, full_name, department, role, status, email,
                               must_set_password, invited_by, decided_at)
  values (p_user, left(btrim(p_full_name), 120), dept, p_role,
          case when p_test then 'suspended' else 'active' end::public.account_status,
          addr, true, p_actor, now())
  on conflict (id) do update
    set full_name = excluded.full_name, department = excluded.department,
        role = excluded.role, status = excluded.status,
        must_set_password = true, invited_by = excluded.invited_by,
        decided_at = now(), updated_at = now();

  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (p_actor, case when p_test then 'admin.test_invite' else 'admin.create' end,
          'profiles', p_user::text,
          jsonb_build_object('email', addr, 'role', p_role, 'actor_role', a.role));

  return jsonb_build_object('id', p_user, 'email', addr, 'role', p_role,
                            'status', case when p_test then 'suspended' else 'active' end);
end $$;

-- For actions with no profile change of their own, such as resending an
-- invite. The target must be ranked below the actor.
create or replace function public.admin_record(
  p_actor uuid, p_action text, p_target uuid, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if not public.admin_can_manage(p_actor, p_target) then
    raise exception 'You can only manage accounts below your own role.' using errcode = '42501';
  end if;
  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (p_actor, 'admin.' || p_action, 'profiles', p_target::text, coalesce(p_detail, '{}'::jsonb));
end $$;

revoke execute on function public.admin_apply(uuid, uuid, text, public.user_role, text) from public, anon, authenticated;
revoke execute on function public.admin_after_invite(uuid, uuid, public.user_role, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.admin_record(uuid, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_apply(uuid, uuid, text, public.user_role, text) to service_role;
grant execute on function public.admin_after_invite(uuid, uuid, public.user_role, text, text, boolean) to service_role;
grant execute on function public.admin_record(uuid, text, uuid, jsonb) to service_role;

-- ================================================================ 5. audit log
-- Rows are only ever added, by triggers and security definer functions.
-- Nobody can change or delete one through the API, the Edge Functions
-- included. (Direct database access, as the project owner, still can.)
revoke insert, update, delete, truncate on public.audit_entries from anon, authenticated;
revoke update, delete, truncate on public.audit_entries from service_role;

create or replace function public.audit_entries_immutable()
returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('postgres', 'supabase_admin') then
    raise exception 'The audit log cannot be changed' using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists audit_entries_immutable on public.audit_entries;
create trigger audit_entries_immutable
  before update or delete on public.audit_entries
  for each row execute function public.audit_entries_immutable();

-- ================================================================ 6. notices
create or replace function public.zl_notify_borrow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  title text := coalesce((select r.title from public.resources r where r.id = new.resource_id), 'an item');
  staff boolean := exists (select 1 from public.profiles where role = 'librarian' and status = 'active');
begin
  perform public.zl_notify(p.id, 'staff', 'New borrow request',
           coalesce(new.student_name, 'A student') || ' asked to borrow ' || title || '.',
           '/staff/request/' || new.id, 'borrow:' || new.id)
     from public.profiles p
    where p.status = 'active'
      and (case when staff then p.role = 'librarian' else p.role in ('admin', 'super_admin') end);
  return new;
end $$;

create or replace function public.zl_notify_signup()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'student' and new.status = 'pending' then
    perform public.zl_notify(p.id, 'admin', 'New student sign-up',
             new.full_name || coalesce(' (' || new.department || ')', '') ||
             ' signed up. Approve them once they have confirmed their email.',
             '/admin/users', 'signup:' || new.id)
       from public.profiles p
      where p.role in ('admin', 'super_admin') and p.status = 'active';
  end if;
  return new;
end $$;

-- The daily job, unchanged from 0015 except that the overdue summary also
-- goes to the super admin.
create or replace function public.zl_daily_notices()
returns int
language plpgsql security definer set search_path = public as $$
declare
  today date := public.zl_today();
  before_count int;
  after_count int;
  overdue_total int;
begin
  select count(*) into before_count from public.notifications;

  -- Due in two days, and due today.
  perform public.zl_notify(b.student_id, 'due',
           case when b.due_date = today then 'Due back today' else 'Due back in 2 days' end,
           coalesce(r.title, 'Your item') || ' is due back on ' || to_char(b.due_date, 'DD Mon YYYY') || '.',
           '/borrowing',
           case when b.due_date = today then 'due0:' else 'due2:' end || b.id)
     from public.borrow_requests b left join public.resources r on r.id = b.resource_id
    where b.status = 'collected' and b.due_date in (today, today + 2);

  -- Overdue: on the 1st, 3rd, 7th and 14th day late.
  perform public.zl_notify(b.student_id, 'due', 'Overdue: please return it',
           coalesce(r.title, 'Your item') || ' was due on ' || to_char(b.due_date, 'DD Mon YYYY') ||
           ' (' || (today - b.due_date) || ' days ago). Please return it to the library.',
           '/borrowing', 'over' || (today - b.due_date) || ':' || b.id)
     from public.borrow_requests b left join public.resources r on r.id = b.resource_id
    where b.status = 'collected' and b.due_date is not null
      and (today - b.due_date) in (1, 3, 7, 14);

  -- Librarians: one summary a day while anything is overdue.
  select count(*) into overdue_total from public.borrow_requests
   where status = 'collected' and due_date < today;
  if overdue_total > 0 then
    perform public.zl_notify(p.id, 'staff',
             overdue_total || case when overdue_total = 1 then ' loan is' else ' loans are' end || ' overdue',
             'Open Requests and filter by overdue to follow up.',
             '/staff/requests', 'overdue-summary:' || today)
       from public.profiles p
      where p.role in ('librarian', 'admin', 'super_admin') and p.status = 'active';
  end if;

  -- Exams from study plans: three days before, and the day before.
  perform public.zl_notify(s.user_id, 'study',
           case when s.exam_date = today + 1 then 'Exam tomorrow' else 'Exam in 3 days' end,
           n.title || ': ' || case when s.exam_date = today + 1
             then 'do a light review today and rest well.'
             else 'time for a full mock test.' end,
           '/plan/' || s.id,
           case when s.exam_date = today + 1 then 'exam1:' else 'exam3:' end || s.id)
     from public.study_plans s
     join public.study_notes n on n.id = s.note_id
     join public.profiles p on p.id = s.user_id
    where p.status = 'active' and p.notify_study
      and s.exam_date in (today + 1, today + 3);

  select count(*) into after_count from public.notifications;
  return after_count - before_count;
end $$;
