-- ZutLib: super admin account tools and system settings (plan items 2, 3)
--
-- Run after 0017_super_admin.sql.
--
--   1. admin_apply     adds "restore" for a removed account. Removing and
--                      restoring both need a reason.
--   2. Account tools   super admin only, each with a reason, each audited:
--                      edit name, department and student number; record an
--                      email change or password link (the admin-users Edge
--                      Function does the Auth part); sign out everywhere.
--   3. Settings        one row the app and the database both read: the
--                      borrowing period, the most active borrows a student
--                      may have, and whether sign-up is open. Only a super
--                      admin changes it, and every change is audited with
--                      the values before and after.
--   4. Enforcement     the due date is set by the database when a copy is
--                      collected; a borrow request over the limit is
--                      refused; sign-up is refused while registration is
--                      closed (invited accounts still work).

-- ================================================================ 1. admin_apply
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
  if p_action in ('set_role', 'remove', 'restore') and a.role <> 'super_admin' then
    raise exception 'Only a super admin can do that.' using errcode = '42501';
  end if;
  if p_action in ('remove', 'restore') and why is null then
    raise exception 'Give a reason. It is kept in the audit log.' using errcode = '22023';
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
    when 'restore' then
      if t.status <> 'removed' then
        raise exception 'Only a removed account can be restored' using errcode = '22023';
      end if;
      new_status := 'active';
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


-- ================================================================ 2. account tools
-- Checks that p_actor is an active super admin acting on someone ranked
-- below them, and that a reason was given. Returns the target's profile.
create or replace function public.zl_super_target(p_actor uuid, p_target uuid, p_reason text)
returns public.profiles
language plpgsql stable security definer set search_path = public as $$
declare
  t public.profiles;
begin
  if not public.admin_is_super(p_actor) then
    raise exception 'Only a super admin can do that.' using errcode = '42501';
  end if;
  select * into t from public.profiles where id = p_target;
  if not found then
    raise exception 'That account no longer exists' using errcode = 'P0002';
  end if;
  if not public.admin_can_manage(p_actor, p_target) then
    raise exception 'You can only manage accounts below your own role.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Give a reason. It is kept in the audit log.' using errcode = '22023';
  end if;
  return t;
end $$;

-- Edit name, department and student number.
create or replace function public.admin_edit_profile(
  p_actor uuid, p_target uuid, p_full_name text, p_department text,
  p_student_number text, p_reason text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  t    public.profiles := public.zl_super_target(p_actor, p_target, p_reason);
  name text := btrim(regexp_replace(coalesce(p_full_name, ''), '[[:space:]]+', ' ', 'g'));
  dept text := nullif(btrim(coalesce(p_department, '')), '');
  num  text := nullif(upper(btrim(coalesce(p_student_number, ''))), '');
begin
  if length(name) not between 2 and 120 then
    raise exception 'Enter a full name of 2 to 120 characters' using errcode = '22023';
  end if;
  if dept is not null and dept not in ('ICT', 'Engineering', 'Business') then
    raise exception 'Choose ICT, Engineering or Business' using errcode = '22023';
  end if;
  if num is not null and num !~ '^[A-Z0-9/-]{3,20}$' then
    raise exception 'A student number is 3 to 20 letters, digits, / or -' using errcode = '22023';
  end if;
  if num is not null and exists (select 1 from public.profiles where student_number = num and id <> p_target) then
    raise exception 'Another account already has that student number' using errcode = '22023';
  end if;

  update public.profiles
     set full_name = name, department = dept, student_number = num, updated_at = now()
   where id = p_target;

  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (p_actor, 'admin.edit_profile', 'profiles', p_target::text,
          jsonb_build_object(
            'actor_role', 'super_admin', 'reason', btrim(p_reason),
            'before', jsonb_build_object('full_name', t.full_name, 'department', t.department,
                                         'student_number', t.student_number),
            'after', jsonb_build_object('full_name', name, 'department', dept, 'student_number', num)));

  return jsonb_build_object('id', p_target, 'full_name', name, 'department', dept, 'student_number', num);
end $$;

-- Writes the audit entry for an account tool whose work happens in
-- Supabase Auth (change email, send a password link). The Edge Function
-- calls this first, so a refused request never reaches Auth.
create or replace function public.admin_super_record(
  p_actor uuid, p_target uuid, p_action text, p_reason text, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  t public.profiles := public.zl_super_target(p_actor, p_target, p_reason);
begin
  if p_action not in ('change_email', 'password_link') then
    raise exception 'Unknown action' using errcode = '22023';
  end if;
  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (p_actor, 'admin.' || p_action, 'profiles', p_target::text,
          coalesce(p_detail, '{}'::jsonb) ||
          jsonb_build_object('actor_role', 'super_admin', 'reason', btrim(p_reason), 'email', t.email));
end $$;

-- Sign out everywhere: ends every sign-in session, so each device has to
-- sign in again once its current access token runs out (at most an hour;
-- the account's data is already protected by its status in the meantime).
create or replace function public.admin_revoke_sessions(p_actor uuid, p_target uuid, p_reason text)
returns int
language plpgsql volatile security definer set search_path = public, auth as $$
declare
  t public.profiles := public.zl_super_target(p_actor, p_target, p_reason);
  n int;
begin
  delete from auth.sessions where user_id = p_target;
  get diagnostics n = row_count;
  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (p_actor, 'admin.sign_out_everywhere', 'profiles', p_target::text,
          jsonb_build_object('actor_role', 'super_admin', 'reason', btrim(p_reason), 'sessions', n));
  return n;
end $$;

revoke execute on function public.zl_super_target(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.admin_edit_profile(uuid, uuid, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.admin_super_record(uuid, uuid, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.admin_revoke_sessions(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.admin_edit_profile(uuid, uuid, text, text, text, text) to service_role;
grant execute on function public.admin_super_record(uuid, uuid, text, text, jsonb) to service_role;
grant execute on function public.admin_revoke_sessions(uuid, uuid, text) to service_role;


-- ================================================================ 3. settings
create table if not exists public.settings (
  id                  boolean primary key default true,
  loan_days           int not null default 14,
  max_active_borrows  int not null default 3,
  registration_open   boolean not null default true,
  updated_at          timestamptz not null default now(),
  updated_by          uuid references public.profiles(id) on delete set null,
  constraint settings_one_row check (id),
  constraint settings_loan_days check (loan_days between 1 and 90),
  constraint settings_max_borrows check (max_active_borrows between 1 and 20)
);

insert into public.settings (id) values (true) on conflict (id) do nothing;

alter table public.settings enable row level security;

-- Every active account may read the settings (the app shows the borrowing
-- period and limit). Nobody writes the table directly.
drop policy if exists settings_read on public.settings;
create policy settings_read on public.settings
  for select to authenticated using (public.is_active());

revoke all on public.settings from anon, authenticated;
grant select on public.settings to authenticated;
grant all on public.settings to service_role;

create or replace function public.zl_settings()
returns public.settings
language sql stable security definer set search_path = public as $$
  select * from public.settings where id
$$;
revoke execute on function public.zl_settings() from public, anon, authenticated;

-- The sign-up screen asks this before showing the form.
create or replace function public.registration_open()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select registration_open from public.settings where id), true)
$$;
revoke execute on function public.registration_open() from public;
grant execute on function public.registration_open() to anon, authenticated;

-- Super admin only. Every change is audited with before and after.
create or replace function public.admin_set_settings(
  p_loan_days int, p_max_active_borrows int, p_registration_open boolean, p_reason text default null)
returns public.settings
language plpgsql volatile security definer set search_path = public as $$
declare
  before public.settings;
  after  public.settings;
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can change system settings.' using errcode = '42501';
  end if;
  if p_loan_days is null or p_loan_days not between 1 and 90 then
    raise exception 'The borrowing period must be 1 to 90 days' using errcode = '22023';
  end if;
  if p_max_active_borrows is null or p_max_active_borrows not between 1 and 20 then
    raise exception 'The borrowing limit must be 1 to 20' using errcode = '22023';
  end if;
  if p_registration_open is null then
    raise exception 'Choose whether registration is open' using errcode = '22023';
  end if;
  select * into before from public.settings where id for update;
  update public.settings
     set loan_days = p_loan_days, max_active_borrows = p_max_active_borrows,
         registration_open = p_registration_open, updated_at = now(), updated_by = auth.uid()
   where id
  returning * into after;
  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (auth.uid(), 'admin.settings', 'settings', 'system',
          jsonb_strip_nulls(jsonb_build_object(
            'actor_role', 'super_admin',
            'reason', nullif(btrim(coalesce(p_reason, '')), ''),
            'before', jsonb_build_object('loan_days', before.loan_days,
                        'max_active_borrows', before.max_active_borrows,
                        'registration_open', before.registration_open),
            'after', jsonb_build_object('loan_days', after.loan_days,
                        'max_active_borrows', after.max_active_borrows,
                        'registration_open', after.registration_open))));
  return after;
end $$;
revoke execute on function public.admin_set_settings(int, int, boolean, text) from public, anon;
grant execute on function public.admin_set_settings(int, int, boolean, text) to authenticated;

-- ================================================================ 4. enforcement
-- The due date: set when a copy is collected, from the borrowing period;
-- and the most active borrows a student may have.
create or replace function public.zl_borrow_settings()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  s public.settings := public.zl_settings();
  active int;
begin
  if tg_op = 'INSERT' then
    select count(*) into active from public.borrow_requests
     where student_id = new.student_id
       and status in ('submitted', 'under_review', 'approved', 'collected');
    if active >= coalesce(s.max_active_borrows, 3) then
      raise exception 'You can have at most % active borrows at a time. Return or cancel one first.',
        coalesce(s.max_active_borrows, 3) using errcode = '22023';
    end if;
  elsif new.status = 'collected' and old.status is distinct from 'collected'
        -- Requests through the API (the app and the Edge Functions). Work
        -- done directly in the database, such as seeding overdue demo
        -- loans, keeps the date it gives.
        and current_setting('role', true) in ('authenticated', 'service_role', 'anon') then
    new.due_date := public.zl_today() + coalesce(s.loan_days, 14);
  end if;
  return new;
end $$;
revoke execute on function public.zl_borrow_settings() from public, anon, authenticated;

drop trigger if exists borrow_requests_settings on public.borrow_requests;
create trigger borrow_requests_settings
  before insert or update on public.borrow_requests
  for each row execute function public.zl_borrow_settings();

-- Sign-up: refused while registration is closed. Supabase marks an invited
-- user with invited_at, so invites from an administrator still work.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta  jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  name  text  := left(btrim(coalesce(meta ->> 'full_name', '')), 120);
  dept  text  := meta ->> 'department';
begin
  if new.invited_at is null and not public.registration_open() then
    raise exception 'Registration is closed. Ask the library for an invite.' using errcode = '42501';
  end if;
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
