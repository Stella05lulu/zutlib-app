-- ZutLib — core schema
-- Academic resource and borrowing management system
-- Every correctness rule that can live in the database, lives in the database.

create extension if not exists "pgcrypto";
create extension if not exists "unaccent";

-- ---------------------------------------------------------------- enums
create type user_role as enum ('student', 'librarian', 'admin');

create type resource_type as enum (
  'past_paper', 'test_paper', 'lecture_notes', 'book_link'
);

create type borrow_status as enum (
  'submitted', 'under_review', 'approved', 'rejected',
  'collected', 'returned', 'overdue', 'cancelled'
);

-- ---------------------------------------------------------------- roll
-- Institutional student roll. Administrator managed. Never client writable.
-- Eligibility is established here, before any account can exist.
create table public.roll (
  student_number  text primary key,
  surname         text        not null check (length(btrim(surname)) > 0),
  first_name      text,
  programme       text        not null,
  department      text        not null,
  intake_year     int         not null check (intake_year between 2000 and 2100),
  claimed         boolean     not null default false,
  claimed_by      uuid        references auth.users(id) on delete set null,
  claimed_at      timestamptz,
  created_at      timestamptz not null default now(),

  -- a record is claimed if and only if it has a claimant
  constraint roll_claim_consistent check (
    (claimed = false and claimed_by is null and claimed_at is null)
    or
    (claimed = true  and claimed_by is not null and claimed_at is not null)
  )
);

create unique index roll_claimed_by_uniq on public.roll (claimed_by)
  where claimed_by is not null;

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  full_name       text        not null,
  surname         text        not null,
  student_number  text        unique references public.roll(student_number),
  programme       text,
  department      text,
  role            user_role   not null default 'student',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index profiles_role_idx on public.profiles (role);

-- ---------------------------------------------------------------- resources
create table public.resources (
  id                uuid primary key default gen_random_uuid(),
  title             text          not null check (length(btrim(title)) > 0),
  type              resource_type not null,
  department        text          not null check (length(btrim(department)) > 0),
  course_code       text          not null check (length(btrim(course_code)) > 0),
  academic_year     int           not null check (academic_year between 1990 and 2100),
  semester          int           check (semester between 1 and 3),
  description       text,

  -- exactly one of: a stored file, or an external link
  file_path         text,
  external_url      text,

  is_physical       boolean       not null default false,
  total_copies      int           not null default 0 check (total_copies >= 0),
  available_copies  int           not null default 0 check (available_copies >= 0),

  uploaded_by       uuid          references public.profiles(id) on delete set null,
  created_at        timestamptz   not null default now(),
  updated_at        timestamptz   not null default now(),

  -- A copy count can never exceed the holding.
  constraint resources_copies_within_total
    check (available_copies <= total_copies),

  -- Anything borrowable must have at least one copy; anything not
  -- borrowable must have none.
  constraint resources_physical_has_copies check (
    (is_physical = true  and total_copies > 0) or
    (is_physical = false and total_copies = 0 and available_copies = 0)
  ),

  -- A catalogue entry must actually point at something.
  constraint resources_has_a_target check (
    file_path is not null or external_url is not null or is_physical = true
  ),

  -- A book link needs a link.
  constraint resources_book_link_has_url check (
    type <> 'book_link' or external_url is not null
  )
);

-- Full text search over title and course code, maintained by the database.
alter table public.resources
  add column search_vector tsvector
  generated always as (
    setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(course_code, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(description, '')), 'C')
  ) stored;

create index resources_search_idx on public.resources using gin (search_vector);
create index resources_filter_idx on public.resources
  (department, course_code, academic_year, type);
create index resources_recent_idx on public.resources (created_at desc);

-- ---------------------------------------------------------------- borrowing
create table public.borrow_requests (
  id                uuid primary key default gen_random_uuid(),
  resource_id       uuid          not null references public.resources(id) on delete restrict,
  student_id        uuid          not null references public.profiles(id) on delete restrict,

  -- verified identity, copied at write time so staff never re-check it
  student_name      text          not null,
  student_number    text          not null,
  programme         text,

  status            borrow_status not null default 'submitted',
  requested_at      timestamptz   not null default now(),
  collection_date   date,

  decided_by        uuid          references public.profiles(id) on delete set null,
  decided_at        timestamptz,
  rejection_reason  text,

  collected_at      timestamptz,
  due_date          date,
  returned_at       timestamptz,
  cancelled_at      timestamptz,

  -- A rejection must say why.
  constraint borrow_rejection_has_reason check (
    status <> 'rejected' or (rejection_reason is not null
                             and length(btrim(rejection_reason)) > 0)
  ),
  -- A decision must record who made it.
  constraint borrow_decision_has_decider check (
    status not in ('approved', 'rejected') or decided_by is not null
  ),
  -- Anything collected has a due date.
  constraint borrow_collected_has_due_date check (
    status not in ('collected', 'returned', 'overdue') or due_date is not null
  )
);

create index borrow_student_idx  on public.borrow_requests (student_id, requested_at desc);
create index borrow_status_idx   on public.borrow_requests (status, requested_at desc);
create index borrow_resource_idx on public.borrow_requests (resource_id);
create index borrow_due_idx      on public.borrow_requests (due_date)
  where status = 'collected';

-- One live request per student per resource. A student cannot queue
-- five requests for the same book.
create unique index borrow_one_live_per_pair
  on public.borrow_requests (student_id, resource_id)
  where status in ('submitted', 'under_review', 'approved', 'collected', 'overdue');

-- ---------------------------------------------------------------- audit
create table public.audit_entries (
  id            uuid primary key default gen_random_uuid(),
  actor_id      uuid references public.profiles(id) on delete set null,
  action        text not null,
  target_table  text not null,
  target_id     text not null,
  detail        jsonb,
  occurred_at   timestamptz not null default now()
);

create index audit_occurred_idx on public.audit_entries (occurred_at desc);
create index audit_actor_idx    on public.audit_entries (actor_id, occurred_at desc);

-- ---------------------------------------------------------------- notifications
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  subject     text not null,
  body        text not null,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);

-- ---------------------------------------------------------------- heartbeat
-- Free projects pause after 7 days without database activity.
-- A scheduled job writes here twice weekly.
create table public.heartbeat (
  id         int primary key default 1 check (id = 1),
  beat_at    timestamptz not null default now()
);
insert into public.heartbeat (id) values (1) on conflict do nothing;

-- ---------------------------------------------------------------- updated_at
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger profiles_touch  before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger resources_touch before update on public.resources
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------- overdue
-- Overdue is derived, not scheduled. Reading a collected row whose due
-- date has passed reports it as overdue without a cron job.
create or replace function public.effective_status(r public.borrow_requests)
returns borrow_status language sql stable as $$
  select case
    when r.status = 'collected' and r.due_date < current_date then 'overdue'::borrow_status
    else r.status
  end
$$;
