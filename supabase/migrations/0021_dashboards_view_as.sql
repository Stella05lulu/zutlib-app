-- ZutLib: admin overview, librarian today, drawer badges, View as
-- (plan items 4, 5, 11, 12)
--
-- Run after 0020_kit_sources.sql. Every function checks the caller's role
-- itself and reads live data; nothing here is stored.
--
--   admin_badges()         pending users, open invitations, overdue loans
--   admin_dashboard(p)     the Overview screen: stats, borrowing trend by
--                          week or month, status breakdown, resources by
--                          department, latest pending approvals and audit
--   librarian_today()      requests waiting, collections due today, overdue
--                          copies, books with no copy on the shelf
--   view_as_start/end(u)   super admin only: a read-only picture of what one
--                          student or librarian sees. It returns data; it
--                          never makes a session or token for that person,
--                          and it never includes their study notes or kits.
--                          Starting and ending are both audited.

-- ================================================================ badges
create or replace function public.admin_badges()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see these counts' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'pending_users', (select count(*) from profiles where status = 'pending'),
    'open_invitations', (select count(*) from profiles where must_set_password and status = 'active'),
    'overdue', (select count(*) from borrow_requests where status = 'collected' and due_date < public.zl_today()));
end $$;
revoke execute on function public.admin_badges() from public, anon;
grant execute on function public.admin_badges() to authenticated;

-- ================================================================ overview
create or replace function public.admin_dashboard(p_period text default 'week')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  today   date := public.zl_today();
  monthly boolean := p_period = 'month';
  trend   jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see the overview' using errcode = '42501';
  end if;

  -- Borrow requests made per week (last 8) or per month (last 6), with
  -- empty buckets kept so the chart has no gaps.
  if monthly then
    select jsonb_agg(jsonb_build_object('start', b.start, 'count', coalesce(c.n, 0)) order by b.start) into trend
      from (select (date_trunc('month', today) - make_interval(months => g))::date as start
              from generate_series(0, 5) g) b
      left join (select date_trunc('month', (requested_at at time zone 'Africa/Lusaka'))::date as start, count(*) n
                   from borrow_requests group by 1) c using (start);
  else
    select jsonb_agg(jsonb_build_object('start', b.start, 'count', coalesce(c.n, 0)) order by b.start) into trend
      from (select (date_trunc('week', today) - make_interval(weeks => g))::date as start
              from generate_series(0, 7) g) b
      left join (select date_trunc('week', (requested_at at time zone 'Africa/Lusaka'))::date as start, count(*) n
                   from borrow_requests group by 1) c using (start);
  end if;

  return jsonb_build_object(
    'period', case when monthly then 'month' else 'week' end,
    'stats', jsonb_build_object(
      'total_users', (select count(*) from profiles where status <> 'removed'),
      'pending', (select count(*) from profiles where status = 'pending'),
      'active_borrows', (select count(*) from borrow_requests where status = 'collected'),
      'overdue', (select count(*) from borrow_requests where status = 'collected' and due_date < today),
      'resources', (select count(*) from resources where retired_at is null)),
    'trend', coalesce(trend, '[]'::jsonb),
    'statuses', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) from (
        select case when status = 'collected' and due_date < today then 'overdue' else status::text end s, count(*) n
          from borrow_requests group by 1) x),
    'departments', (select coalesce(jsonb_agg(jsonb_build_object('department', department, 'count', n) order by n desc), '[]'::jsonb)
        from (select department, count(*) n from resources where retired_at is null group by department) x),
    'pending_users', (select coalesce(jsonb_agg(row_to_json(x) order by x.created_at desc), '[]'::jsonb) from (
        select id, full_name, email, department, created_at from profiles
         where status = 'pending' order by created_at desc limit 5) x),
    'audit', (select coalesce(jsonb_agg(row_to_json(x) order by x.occurred_at desc), '[]'::jsonb) from (
        select a.action, a.target_table, a.target_id, a.detail, a.occurred_at, p.full_name as actor_name
          from audit_entries a left join profiles p on p.id = a.actor_id
         order by a.occurred_at desc limit 10) x));
end $$;
revoke execute on function public.admin_dashboard(text) from public, anon;
grant execute on function public.admin_dashboard(text) to authenticated;

-- ================================================================ librarian today
create or replace function public.zl_library_today()
returns jsonb
language sql stable security definer set search_path = public as $$
  with t as (select public.zl_today() as today)
  select jsonb_build_object(
    'waiting', (select coalesce(jsonb_agg(row_to_json(x) order by x.requested_at), '[]'::jsonb) from (
        select b.id, b.student_name, b.status, b.requested_at, b.collection_date, r.title
          from borrow_requests b join resources r on r.id = b.resource_id
         where b.status in ('submitted', 'under_review') order by b.requested_at limit 30) x),
    'waiting_count', (select count(*) from borrow_requests where status in ('submitted', 'under_review')),
    'collections', (select coalesce(jsonb_agg(row_to_json(x) order by x.student_name), '[]'::jsonb) from (
        select b.id, b.student_name, b.status, b.collection_date, r.title
          from borrow_requests b join resources r on r.id = b.resource_id, t
         where b.status = 'approved' and b.collection_date <= t.today limit 30) x),
    'collections_count', (select count(*) from borrow_requests, t
                           where status = 'approved' and collection_date <= t.today),
    'overdue', (select coalesce(jsonb_agg(row_to_json(x) order by x.due_date), '[]'::jsonb) from (
        select b.id, b.student_name, b.due_date, r.title
          from borrow_requests b join resources r on r.id = b.resource_id, t
         where b.status = 'collected' and b.due_date < t.today order by b.due_date limit 30) x),
    'overdue_count', (select count(*) from borrow_requests, t where status = 'collected' and due_date < t.today),
    'low_stock', (select coalesce(jsonb_agg(row_to_json(x) order by x.title), '[]'::jsonb) from (
        select id, title, author, total_copies from resources
         where is_physical and retired_at is null and available_copies = 0 order by title limit 30) x),
    'low_stock_count', (select count(*) from resources where is_physical and retired_at is null and available_copies = 0))
$$;
revoke execute on function public.zl_library_today() from public, anon, authenticated;

create or replace function public.librarian_today()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then
    raise exception 'Only library staff can see this' using errcode = '42501';
  end if;
  return public.zl_library_today();
end $$;
revoke execute on function public.librarian_today() from public, anon;
grant execute on function public.librarian_today() to authenticated;

-- ================================================================ view as
create or replace function public.zl_view_as_target(p_target uuid)
returns public.profiles
language plpgsql stable security definer set search_path = public as $$
declare
  t public.profiles;
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can use View as.' using errcode = '42501';
  end if;
  select * into t from public.profiles where id = p_target;
  if not found then
    raise exception 'That account no longer exists' using errcode = 'P0002';
  end if;
  if t.id = auth.uid() or t.role not in ('student', 'librarian') then
    raise exception 'View as works for student and librarian accounts only.' using errcode = '42501';
  end if;
  return t;
end $$;
revoke execute on function public.zl_view_as_target(uuid) from public, anon, authenticated;

-- What that person sees. Study notes, kits, plans and progress are private
-- and are left out on purpose.
create or replace function public.zl_view_as_data(t public.profiles)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('id', t.id, 'full_name', t.full_name, 'role', t.role, 'status', t.status,
                                  'department', t.department, 'year_of_study', t.year_of_study,
                                  'courses', to_jsonb(t.courses)),
    'borrows', case when t.role = 'student' then (
        select coalesce(jsonb_agg(row_to_json(x) order by x.requested_at desc), '[]'::jsonb) from (
          select b.id, b.status, b.requested_at, b.collection_date, b.due_date, r.title
            from borrow_requests b join resources r on r.id = b.resource_id
           where b.student_id = t.id order by b.requested_at desc limit 50) x) end,
    'saved', case when t.role = 'student' then (
        select coalesce(jsonb_agg(row_to_json(x) order by x.created_at desc), '[]'::jsonb) from (
          select s.created_at, r.id, r.title, r.type, r.course_code
            from saved_resources s join resources r on r.id = s.resource_id
           where s.user_id = t.id and r.retired_at is null order by s.created_at desc limit 50) x) end,
    'announcements', (select coalesce(jsonb_agg(row_to_json(x) order by x.created_at desc), '[]'::jsonb) from (
        select id, title, body, department, ends_on, created_at from announcements
         where removed_at is null and (ends_on is null or ends_on >= public.zl_today())
           and (department is null or t.role <> 'student' or department = t.department)
         order by created_at desc limit 10) x),
    'updates', (select coalesce(jsonb_agg(row_to_json(x) order by x.created_at desc), '[]'::jsonb) from (
        select subject, body, kind, created_at, read_at from notifications
         where user_id = t.id order by created_at desc limit 20) x),
    'library', case when t.role = 'librarian' then public.zl_library_today() end)
$$;
revoke execute on function public.zl_view_as_data(public.profiles) from public, anon, authenticated;

create or replace function public.view_as_start(p_target uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  t public.profiles := public.zl_view_as_target(p_target);
begin
  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (auth.uid(), 'admin.view_as_start', 'profiles', p_target::text,
          jsonb_build_object('actor_role', 'super_admin', 'role', t.role, 'name', t.full_name));
  return public.zl_view_as_data(t);
end $$;

-- Reloading the picture while the session is open (pull to refresh).
create or replace function public.view_as_data(p_target uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return public.zl_view_as_data(public.zl_view_as_target(p_target));
end $$;

create or replace function public.view_as_end(p_target uuid)
returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  t public.profiles := public.zl_view_as_target(p_target);
begin
  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (auth.uid(), 'admin.view_as_end', 'profiles', p_target::text,
          jsonb_build_object('actor_role', 'super_admin', 'role', t.role, 'name', t.full_name));
end $$;

revoke execute on function public.view_as_start(uuid) from public, anon;
revoke execute on function public.view_as_data(uuid) from public, anon;
revoke execute on function public.view_as_end(uuid) from public, anon;
grant execute on function public.view_as_start(uuid) to authenticated;
grant execute on function public.view_as_data(uuid) to authenticated;
grant execute on function public.view_as_end(uuid) to authenticated;
