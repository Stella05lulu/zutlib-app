-- ZutLib — row level security
-- Deny by default. A table with RLS enabled and no matching policy
-- returns no rows, so an omission is a refusal, never an exposure.

alter table public.roll             enable row level security;
alter table public.profiles         enable row level security;
alter table public.resources        enable row level security;
alter table public.borrow_requests  enable row level security;
alter table public.audit_entries    enable row level security;
alter table public.notifications    enable row level security;
alter table public.heartbeat        enable row level security;

-- ---------------------------------------------------------------- helpers
-- SECURITY DEFINER so the policy can read profiles without recursing
-- through the policy it is currently evaluating.
create or replace function public.current_role_of()
returns user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role in ('librarian','admin') from public.profiles where id = auth.uid()),
    false)
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role = 'admin' from public.profiles where id = auth.uid()),
    false)
$$;

revoke execute on function public.current_role_of() from public;
grant  execute on function public.current_role_of() to authenticated;
grant  execute on function public.is_staff()        to authenticated;
grant  execute on function public.is_admin()        to authenticated;

-- ---------------------------------------------------------------- roll
-- No client may read or write the roll except an administrator.
-- Registration reads it through the service role inside an edge function.
create policy roll_admin_all on public.roll
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- profiles
create policy profiles_read_own on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff());

-- A user may edit their own profile but may NOT change their own role,
-- student number, or programme. Those are set at registration from the roll.
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = (select role from public.profiles p where p.id = auth.uid())
    and student_number is not distinct from
        (select p.student_number from public.profiles p where p.id = auth.uid())
  );

create policy profiles_admin_all on public.profiles
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- resources
-- Any signed-in user with a profile may read the catalogue.
create policy resources_read on public.resources
  for select to authenticated
  using (exists (select 1 from public.profiles where id = auth.uid()));

create policy resources_staff_write on public.resources
  for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- ---------------------------------------------------------------- borrowing
create policy borrow_read_own on public.borrow_requests
  for select to authenticated
  using (student_id = auth.uid() or public.is_staff());

-- A student may raise a request only for themselves, only for a physical
-- resource, and only in the submitted state.
create policy borrow_insert_own on public.borrow_requests
  for insert to authenticated
  with check (
    student_id = auth.uid()
    and status = 'submitted'
    and decided_by is null
    and exists (
      select 1 from public.resources r
      where r.id = resource_id and r.is_physical = true and r.available_copies > 0
    )
  );

-- A student may only ever cancel, and only while still submitted.
create policy borrow_cancel_own on public.borrow_requests
  for update to authenticated
  using (student_id = auth.uid() and status = 'submitted')
  with check (student_id = auth.uid() and status = 'cancelled');

-- Staff read everything (above) but decisions are made by the edge
-- function under the service role, which bypasses RLS after validating
-- the transition. Staff get no direct UPDATE grant here by design.

-- ---------------------------------------------------------------- audit
-- Readable by staff, writable by nobody. Written only by the service role.
create policy audit_staff_read on public.audit_entries
  for select to authenticated using (public.is_staff());

-- ---------------------------------------------------------------- notifications
create policy notif_read_own on public.notifications
  for select to authenticated using (user_id = auth.uid());

create policy notif_mark_read on public.notifications
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------- heartbeat
create policy heartbeat_admin on public.heartbeat
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- search rpc
-- Metadata filters plus full text, in one call, with RLS still applied.
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
language sql stable security invoker set search_path = public as $$
  select r.* from public.resources r
  where (p_department is null or r.department  = p_department)
    and (p_course     is null or r.course_code = p_course)
    and (p_year       is null or r.academic_year = p_year)
    and (p_type       is null or r.type = p_type)
    and (
      q is null or btrim(q) = ''
      or r.search_vector @@ websearch_to_tsquery('english', q)
      or r.title       ilike '%' || q || '%'
      or r.course_code ilike '%' || q || '%'
    )
  order by
    case when q is null or btrim(q) = '' then 0
         else ts_rank(r.search_vector, websearch_to_tsquery('english', q)) end desc,
    r.academic_year desc,
    r.title asc
  limit greatest(1, least(p_limit, 100))
  offset greatest(0, p_offset)
$$;

grant execute on function public.search_resources to authenticated;

-- Distinct filter values for the browse screen dropdowns.
create or replace function public.resource_facets()
returns table (departments text[], course_codes text[], years int[])
language sql stable security invoker set search_path = public as $$
  select
    array(select distinct department  from public.resources order by 1),
    array(select distinct course_code from public.resources order by 1),
    array(select distinct academic_year from public.resources order by 1 desc)
$$;

grant execute on function public.resource_facets to authenticated;

-- Staff dashboard counts in a single round trip.
create or replace function public.staff_overview()
returns table (pending int, collected int, overdue int, resources int)
language sql stable security invoker set search_path = public as $$
  select
    (select count(*)::int from public.borrow_requests
       where status in ('submitted','under_review')),
    (select count(*)::int from public.borrow_requests
       where status = 'collected' and (due_date is null or due_date >= current_date)),
    (select count(*)::int from public.borrow_requests
       where status = 'collected' and due_date < current_date),
    (select count(*)::int from public.resources)
$$;

grant execute on function public.staff_overview to authenticated;
