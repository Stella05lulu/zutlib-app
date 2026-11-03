-- ZutLib migration 0015: study planner, profiles students can edit,
-- notifications that arrive on their own, feedback and usage reports.
--
-- Run after 0014, in the SQL Editor, as one script. Safe to run twice.
--
--   1. Profiles     year of study, courses, reminder settings, onboarding;
--                   changed only through update_my_profile()
--   2. Activity     what a student studied each day, per kit (feeds the
--                   plan's ticks, streaks and the usage report)
--   3. Plans        one exam plan per kit, plus tasks ticked by hand
--   4. Notifications  kind, link, de-duplication; new uploads, new borrow
--                   requests and new sign-ups notify the right people; a
--                   daily job sends due-date and exam reminders
--   5. Devices      phone tokens for push notifications (Firebase Cloud
--                   Messaging delivers; Supabase decides what and when)
--   6. Feedback     anyone signed in can send it; administrators read it
--   7. Usage        anonymous events (no user id) and admin_reports()
--
-- Dates are in Zambia time (Africa/Lusaka), so "today" matches the clock
-- students see.

-- ================================================================ helpers
create or replace function public.zl_today()
returns date
language sql stable as $$
  select (now() at time zone 'Africa/Lusaka')::date
$$;

-- ================================================================ 1. profiles
alter table public.profiles
  add column if not exists year_of_study  smallint,
  add column if not exists courses        text[] not null default '{}',
  add column if not exists onboarded_at   timestamptz,
  add column if not exists reminder_time  time not null default '18:00',
  add column if not exists notify_uploads boolean not null default true,
  add column if not exists notify_study   boolean not null default true;

alter table public.profiles drop constraint if exists profiles_year_of_study;
alter table public.profiles add constraint profiles_year_of_study
  check (year_of_study is null or year_of_study between 1 and 6);

alter table public.profiles drop constraint if exists profiles_courses;
alter table public.profiles add constraint profiles_courses
  check (array_ndims(courses) is null
         or (array_ndims(courses) = 1 and cardinality(courses) <= 12));

-- Staff and students who were already active have nothing to onboard.
update public.profiles set onboarded_at = coalesce(onboarded_at, now())
 where status = 'active' and role <> 'student';

-- The only way a user changes their own profile. Email, role and status
-- are never touched here; they stay with administrators.
create or replace function public.update_my_profile(
  p_full_name      text,
  p_department     text,
  p_year           int,
  p_courses        text[],
  p_reminder_time  time,
  p_notify_uploads boolean,
  p_notify_study   boolean,
  p_finish_onboarding boolean default false)
returns void
language plpgsql security definer set search_path = public as $$
declare
  me      public.profiles;
  name    text := left(btrim(coalesce(p_full_name, '')), 120);
  clean   text[];
begin
  select * into me from public.profiles where id = auth.uid();
  if not found or me.status <> 'active' then
    raise exception 'Your account is not active' using errcode = '42501';
  end if;
  if name = '' then
    raise exception 'Enter your full name' using errcode = '22023';
  end if;
  if p_department is not null and p_department not in ('ICT', 'Engineering', 'Business') then
    raise exception 'Choose ICT, Engineering or Business' using errcode = '22023';
  end if;
  if p_year is not null and p_year not between 1 and 6 then
    raise exception 'Year of study must be 1 to 6' using errcode = '22023';
  end if;

  -- Courses: trimmed, upper case, single spaces, no duplicates, at most 12.
  select coalesce(array_agg(distinct c order by c), '{}') into clean
    from (select upper(regexp_replace(btrim(x), '\s+', ' ', 'g')) c
            from unnest(coalesce(p_courses, '{}')) x) s
   where c <> '';
  if cardinality(clean) > 12 then
    raise exception 'Choose at most 12 courses' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(clean) c where c !~ '^[A-Z0-9 ]{2,20}$') then
    raise exception 'A course code can only use letters, digits and spaces' using errcode = '22023';
  end if;

  update public.profiles set
    full_name      = name,
    department     = case when me.role = 'student' then p_department else coalesce(p_department, department) end,
    year_of_study  = p_year,
    courses        = clean,
    reminder_time  = coalesce(p_reminder_time, reminder_time),
    notify_uploads = coalesce(p_notify_uploads, notify_uploads),
    notify_study   = coalesce(p_notify_study, notify_study),
    onboarded_at   = case when p_finish_onboarding then coalesce(onboarded_at, now()) else onboarded_at end,
    updated_at     = now()
  where id = me.id;
end $$;

revoke execute on function public.update_my_profile(text, text, int, text[], time, boolean, boolean, boolean)
  from public, anon;
grant execute on function public.update_my_profile(text, text, int, text[], time, boolean, boolean, boolean)
  to authenticated;

-- ================================================================ 2. activity
-- One row per student, kit, day and kind of work: how many cards they
-- rated, questions they answered, tests they took and guide sections they
-- read. Written by the rating functions below, never by the app directly.
create table if not exists public.study_activity (
  user_id     uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  note_id     uuid not null,
  day         date not null default public.zl_today(),
  kind        text not null,
  amount      int  not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (user_id, note_id, day, kind),
  constraint study_activity_kind check (kind in ('cards', 'questions', 'test', 'guide')),
  constraint study_activity_amount check (amount between 0 and 100000),
  constraint study_activity_note foreign key (note_id, user_id)
    references public.study_notes (id, user_id) on delete cascade
);

create index if not exists study_activity_day_idx on public.study_activity (user_id, day desc);

create or replace function public.study_log(p_note uuid, p_kind text, p_amount int)
returns void
language sql volatile security invoker set search_path = public as $$
  insert into public.study_activity (note_id, kind, amount)
  select p_note, p_kind, greatest(p_amount, 0)
   where p_note is not null
  on conflict (user_id, note_id, day, kind)
  do update set amount = public.study_activity.amount + excluded.amount,
                updated_at = now()
$$;

-- Guide sections a student has marked as read. The guide must be the
-- student's own (the pair id, owner points at it).
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'study_guides_id_owner') then
    alter table public.study_guides add constraint study_guides_id_owner unique (id, user_id);
  end if;
end $$;

create table if not exists public.study_guide_reads (
  user_id   uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  guide_id  uuid not null,
  section   smallint not null,
  read_at   timestamptz not null default now(),
  primary key (user_id, guide_id, section),
  constraint study_guide_reads_section check (section between 0 and 11),
  constraint study_guide_reads_guide foreign key (guide_id, user_id)
    references public.study_guides (id, user_id) on delete cascade
);

-- Rating a card or a question also counts as study for the card's kit.
create or replace function public.study_rate_card(p_card uuid, p_box int)
returns void
language sql volatile security invoker set search_path = public as $$
  insert into public.study_card_progress (card_id, box, reviews)
  values (p_card, p_box, 1)
  on conflict (user_id, card_id)
  do update set box = excluded.box,
                reviews = public.study_card_progress.reviews + 1,
                updated_at = now();
  select public.study_log(d.note_id, 'cards', 1)
    from public.study_flashcards c join public.study_decks d on d.id = c.deck_id
   where c.id = p_card;
$$;

create or replace function public.study_rate_question(p_question uuid, p_stars int)
returns void
language sql volatile security invoker set search_path = public as $$
  insert into public.study_question_progress (question_id, stars, seen)
  values (p_question, p_stars, 1)
  on conflict (user_id, question_id)
  do update set stars = excluded.stars,
                seen = public.study_question_progress.seen + 1,
                updated_at = now();
  select public.study_log(z.note_id, 'questions', 1)
    from public.study_quiz_questions q join public.study_quizzes z on z.id = q.quiz_id
   where q.id = p_question;
$$;

-- Marks a guide section read (once) and counts it as study.
create or replace function public.study_mark_read(p_guide uuid, p_section int)
returns void
language plpgsql volatile security invoker set search_path = public as $$
declare
  n uuid;
  added int;
begin
  select note_id into n from public.study_guides where id = p_guide;
  if not found then
    raise exception 'That study guide no longer exists' using errcode = '23503';
  end if;
  insert into public.study_guide_reads (guide_id, section) values (p_guide, p_section)
  on conflict do nothing;
  get diagnostics added = row_count;
  if added > 0 then
    perform public.study_log(n, 'guide', 1);
  end if;
end $$;

-- A finished test counts too.
create or replace function public.study_log_test()
returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  perform public.study_log(
    (select note_id from public.study_tests where id = new.test_id), 'test', 1);
  return new;
end $$;

drop trigger if exists study_test_attempts_log on public.study_test_attempts;
create trigger study_test_attempts_log after insert on public.study_test_attempts
  for each row execute function public.study_log_test();

-- ================================================================ 3. plans
create table if not exists public.study_plans (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  note_id     uuid not null,
  exam_date   date not null,
  study_days  smallint not null default 127,
  minutes     smallint not null default 30,
  start_date  date not null default public.zl_today(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint study_plans_one unique (note_id),
  constraint study_plans_id_owner unique (id, user_id),
  -- Monday = 1, Tuesday = 2, Wednesday = 4 ... Sunday = 64.
  constraint study_plans_days check (study_days between 1 and 127),
  constraint study_plans_minutes check (minutes in (15, 30, 45, 60, 90)),
  constraint study_plans_note foreign key (note_id, user_id)
    references public.study_notes (id, user_id) on delete cascade
);

create index if not exists study_plans_user_idx on public.study_plans (user_id, exam_date);

-- The exam must be from today up to a year ahead. A trigger, because a
-- CHECK cannot depend on today's date.
create or replace function public.study_plan_check()
returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.start_date := public.zl_today();
    new.created_at := now();
  else
    new.start_date := old.start_date;
    new.created_at := old.created_at;
  end if;
  if new.exam_date < public.zl_today() or new.exam_date > public.zl_today() + 366 then
    raise exception 'Choose an exam date from today up to a year ahead' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists study_plans_check on public.study_plans;
create trigger study_plans_check before insert or update on public.study_plans
  for each row execute function public.study_plan_check();

drop trigger if exists study_plans_cap on public.study_plans;
create trigger study_plans_cap before insert on public.study_plans
  for each row execute function public.study_cap_rows('user_id', '30');

-- Tasks a student ticks by hand (most tick themselves from activity).
create table if not exists public.study_plan_checks (
  user_id   uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  plan_id   uuid not null,
  day       date not null,
  task_key  text not null,
  done_at   timestamptz not null default now(),
  primary key (user_id, plan_id, day, task_key),
  constraint study_plan_checks_key check (task_key ~ '^[a-z0-9:_-]{1,60}$'),
  constraint study_plan_checks_plan foreign key (plan_id, user_id)
    references public.study_plans (id, user_id) on delete cascade
);

-- ================================================================ 4. notifications
alter table public.notifications
  add column if not exists kind       text not null default 'general',
  add column if not exists link       text,
  add column if not exists dedupe_key text,
  add column if not exists pushed_at  timestamptz;

alter table public.notifications drop constraint if exists notifications_kind;
alter table public.notifications add constraint notifications_kind
  check (kind in ('general', 'borrow', 'due', 'upload', 'study', 'staff', 'admin'));
alter table public.notifications drop constraint if exists notifications_link;
alter table public.notifications add constraint notifications_link
  check (link is null or (link ~ '^/[A-Za-z0-9/_?=&.-]*$' and length(link) <= 200));

create unique index if not exists notifications_dedupe_idx
  on public.notifications (user_id, dedupe_key) where dedupe_key is not null;

-- Internal: one notification, skipped if the same key was sent before.
create or replace function public.zl_notify(
  p_user uuid, p_kind text, p_subject text, p_body text, p_link text, p_dedupe text)
returns void
language sql volatile security definer set search_path = public as $$
  insert into public.notifications (user_id, kind, subject, body, link, dedupe_key)
  values (p_user, p_kind, left(p_subject, 200), left(p_body, 1000), p_link, p_dedupe)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing
$$;
revoke execute on function public.zl_notify(uuid, text, text, text, text, text) from public, anon, authenticated;

-- A new paper or note: tell active students who take that course and
-- want upload notices. Sample data never notifies anyone.
create or replace function public.zl_notify_upload()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  code text := upper(regexp_replace(btrim(coalesce(new.course_code, '')), '\s+', ' ', 'g'));
  what text := case new.type::text
                 when 'past_paper' then 'past paper'
                 when 'test_paper' then 'test paper'
                 when 'lecture_notes' then 'lecture notes'
                 when 'book' then 'book'
                 else 'resource' end;
begin
  if new.retired_at is not null or coalesce(new.is_sample, false) or code = '' then
    return new;
  end if;
  perform public.zl_notify(p.id, 'upload',
           'New ' || what || ' for ' || code,
           new.title, '/resource/' || new.id, 'upload:' || new.id)
     from public.profiles p
    where p.role = 'student' and p.status = 'active' and p.notify_uploads
      and code = any (p.courses);
  return new;
end $$;

drop trigger if exists resources_notify_upload on public.resources;
create trigger resources_notify_upload after insert on public.resources
  for each row execute function public.zl_notify_upload();

-- A new borrow request: tell the librarians (or administrators, if the
-- library has no active librarian yet).
create or replace function public.zl_notify_borrow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  title text := coalesce((select r.title from public.resources r where r.id = new.resource_id), 'an item');
  who   text := 'librarian';
begin
  if not exists (select 1 from public.profiles where role = 'librarian' and status = 'active') then
    who := 'admin';
  end if;
  perform public.zl_notify(p.id, 'staff', 'New borrow request',
           coalesce(new.student_name, 'A student') || ' asked to borrow ' || title || '.',
           '/staff/request/' || new.id, 'borrow:' || new.id)
     from public.profiles p
    where p.role::text = who and p.status = 'active';
  return new;
end $$;

drop trigger if exists borrow_requests_notify on public.borrow_requests;
create trigger borrow_requests_notify after insert on public.borrow_requests
  for each row execute function public.zl_notify_borrow();

-- A new student sign-up: tell the administrators.
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
      where p.role = 'admin' and p.status = 'active';
  end if;
  return new;
end $$;

drop trigger if exists profiles_notify_signup on public.profiles;
create trigger profiles_notify_signup after insert on public.profiles
  for each row execute function public.zl_notify_signup();

-- The daily job: due-date reminders, overdue notices (day 1, 3, 7, 14),
-- a summary for librarians, and exam reminders from study plans. Each
-- message has a key, so running it twice in a day sends nothing new.
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
      where p.role in ('librarian', 'admin') and p.status = 'active';
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

revoke execute on function public.zl_daily_notices() from public, anon, authenticated;
grant execute on function public.zl_daily_notices() to service_role;

-- Run it every morning at 07:00 Zambia time (05:00 UTC). pg_cron is on in
-- Supabase projects (Database > Extensions); if it is not, this part is
-- skipped and the rest of the migration still applies.
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron is not available here; turn it on in Database > Extensions and run this file again';
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'zutlib-daily-notices';
    perform cron.schedule('zutlib-daily-notices', '0 5 * * *', 'select public.zl_daily_notices()');
  end if;
end $$;

-- The bell updates the moment a notification arrives (Supabase Realtime).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and tablename = 'notifications') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- ================================================================ 5. devices
create table if not exists public.device_tokens (
  token       text primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  platform    text not null,
  updated_at  timestamptz not null default now(),
  constraint device_tokens_platform check (platform in ('android', 'ios', 'web')),
  constraint device_tokens_len check (length(token) between 20 and 4096)
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

-- A phone's token belongs to whoever signed in on it most recently.
create or replace function public.register_device(p_token text, p_platform text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then
    raise exception 'Your account is not active' using errcode = '42501';
  end if;
  insert into public.device_tokens (token, user_id, platform)
  values (p_token, auth.uid(), p_platform)
  on conflict (token) do update set user_id = auth.uid(), platform = excluded.platform, updated_at = now();
end $$;

create or replace function public.unregister_device(p_token text)
returns void
language sql security definer set search_path = public as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid()
$$;

revoke execute on function public.register_device(text, text) from public, anon;
revoke execute on function public.unregister_device(text) from public, anon;
grant execute on function public.register_device(text, text) to authenticated;
grant execute on function public.unregister_device(text) to authenticated;

-- ================================================================ 6. feedback
create table if not exists public.feedback (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  role         user_role,
  message      text not null,
  app_version  text,
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz,
  resolved_by  uuid references public.profiles(id) on delete set null,
  constraint feedback_message_len check (length(btrim(message)) between 1 and 2000),
  constraint feedback_version_len check (app_version is null or length(app_version) <= 40)
);

create index if not exists feedback_created_idx on public.feedback (created_at desc);

create or replace function public.feedback_stamp()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.role := (select role from public.profiles where id = new.user_id);
  new.created_at := now();
  new.resolved_at := null;
  new.resolved_by := null;
  return new;
end $$;

drop trigger if exists feedback_stamp on public.feedback;
create trigger feedback_stamp before insert on public.feedback
  for each row execute function public.feedback_stamp();

drop trigger if exists feedback_cap on public.feedback;
create trigger feedback_cap before insert on public.feedback
  for each row execute function public.study_cap_rows('user_id', '200');

create or replace function public.admin_resolve_feedback(p_id uuid, p_resolved boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only administrators can do this' using errcode = '42501';
  end if;
  update public.feedback
     set resolved_at = case when p_resolved then now() end,
         resolved_by = case when p_resolved then auth.uid() end
   where id = p_id;
end $$;

revoke execute on function public.admin_resolve_feedback(uuid, boolean) from public, anon;
grant execute on function public.admin_resolve_feedback(uuid, boolean) to authenticated;

-- ================================================================ 7. usage
-- Anonymous: what was done, for which course or item, and on which day.
-- No user id is stored, so a report can never point at a person.
create table if not exists public.usage_events (
  id           bigint generated always as identity primary key,
  kind         text not null,
  course_code  text,
  resource_id  uuid references public.resources(id) on delete set null,
  day          date not null default public.zl_today(),
  constraint usage_events_kind check (kind in ('search', 'open_resource', 'kit_built', 'plan_created', 'test_taken')),
  constraint usage_events_course check (course_code is null or length(course_code) <= 20)
);

create index if not exists usage_events_day_idx on public.usage_events (day, kind);

create or replace function public.log_event(p_kind text, p_course text default null, p_resource uuid default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then
    return;
  end if;
  insert into public.usage_events (kind, course_code, resource_id)
  values (p_kind,
          nullif(upper(regexp_replace(btrim(coalesce(p_course, '')), '\s+', ' ', 'g')), ''),
          p_resource);
end $$;

revoke execute on function public.log_event(text, text, uuid) from public, anon;
grant execute on function public.log_event(text, text, uuid) to authenticated;

-- The administrator's reports for the last p_days days (7 to 365).
create or replace function public.admin_reports(p_days int default 30)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  since date;
  out   jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only administrators can see reports' using errcode = '42501';
  end if;
  since := public.zl_today() - greatest(7, least(coalesce(p_days, 30), 365));

  select jsonb_build_object(
    'since', since,
    'searched_courses', coalesce((
      select jsonb_agg(x order by x.n desc) from (
        select course_code as label, count(*)::int as n from public.usage_events
         where kind = 'search' and course_code is not null and day >= since
         group by course_code order by n desc limit 10) x), '[]'::jsonb),
    'opened_items', coalesce((
      select jsonb_agg(x order by x.n desc) from (
        select coalesce(r.title, 'Deleted item') as label, count(*)::int as n
          from public.usage_events e left join public.resources r on r.id = e.resource_id
         where e.kind = 'open_resource' and e.day >= since
         group by r.title order by n desc limit 10) x), '[]'::jsonb),
    'borrowed_items', coalesce((
      select jsonb_agg(x order by x.n desc) from (
        select coalesce(r.title, 'Deleted item') as label, count(*)::int as n
          from public.borrow_requests b left join public.resources r on r.id = b.resource_id
         where b.requested_at::date >= since
         group by r.title order by n desc limit 10) x), '[]'::jsonb),
    'borrowing', (
      select jsonb_build_object(
        'requests',  count(*) filter (where requested_at::date >= since),
        'approved',  count(*) filter (where decided_at::date >= since and status in ('approved', 'collected', 'returned')),
        'rejected',  count(*) filter (where decided_at::date >= since and status = 'rejected'),
        'returned',  count(*) filter (where returned_at::date >= since),
        'on_loan',   count(*) filter (where status = 'collected'),
        'overdue',   count(*) filter (where status = 'collected' and due_date < public.zl_today()))
      from public.borrow_requests),
    'study', jsonb_build_object(
      'kits_built',    (select count(*) from public.study_guides where created_at::date >= since),
      'tests_taken',   (select count(*) from public.study_test_attempts where created_at::date >= since),
      'plans_active',  (select count(*) from public.study_plans where exam_date >= public.zl_today())),
    'weekly', coalesce((
      select jsonb_agg(w order by w.week) from (
        select date_trunc('week', d)::date as week,
               (select count(distinct a.user_id)::int from public.study_activity a
                 where a.day >= date_trunc('week', d)::date and a.day < date_trunc('week', d)::date + 7) as studying,
               (select count(*)::int from public.profiles p
                 where p.role = 'student'
                   and p.created_at >= date_trunc('week', d) and p.created_at < date_trunc('week', d) + interval '7 days') as signups
          from generate_series(public.zl_today() - 49, public.zl_today(), interval '7 days') d) w), '[]'::jsonb)
  ) into out;
  return out;
end $$;

revoke execute on function public.admin_reports(int) from public, anon;
grant execute on function public.admin_reports(int) to authenticated;

-- ================================================================ row security
alter table public.study_activity    enable row level security;
alter table public.study_guide_reads enable row level security;
alter table public.study_plans       enable row level security;
alter table public.study_plan_checks enable row level security;
alter table public.device_tokens     enable row level security;
alter table public.feedback          enable row level security;
alter table public.usage_events      enable row level security;

drop policy if exists study_activity_own on public.study_activity;
create policy study_activity_own on public.study_activity
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

drop policy if exists study_guide_reads_own on public.study_guide_reads;
create policy study_guide_reads_own on public.study_guide_reads
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

drop policy if exists study_plans_own on public.study_plans;
create policy study_plans_own on public.study_plans
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

drop policy if exists study_plan_checks_own on public.study_plan_checks;
create policy study_plan_checks_own on public.study_plan_checks
  for all to authenticated
  using (user_id = auth.uid() and public.is_student())
  with check (user_id = auth.uid() and public.is_student());

drop policy if exists device_tokens_read_own on public.device_tokens;
create policy device_tokens_read_own on public.device_tokens
  for select to authenticated using (user_id = auth.uid());

drop policy if exists feedback_insert_own on public.feedback;
create policy feedback_insert_own on public.feedback
  for insert to authenticated with check (user_id = auth.uid() and public.is_active());
drop policy if exists feedback_read on public.feedback;
create policy feedback_read on public.feedback
  for select to authenticated using ((user_id = auth.uid() and public.is_active()) or public.is_admin());

-- usage_events: no policies, so no direct reads or writes; only
-- log_event() and admin_reports() reach it.

-- ================================================================ privileges
revoke all on public.study_activity, public.study_guide_reads, public.study_plans,
              public.study_plan_checks, public.device_tokens, public.feedback, public.usage_events
  from public, anon, authenticated;

grant select, delete on public.study_activity to authenticated;
grant insert (note_id, kind, amount) on public.study_activity to authenticated;
grant update (amount, updated_at) on public.study_activity to authenticated;

grant select, delete on public.study_guide_reads to authenticated;
grant insert (guide_id, section) on public.study_guide_reads to authenticated;

grant select, delete on public.study_plans to authenticated;
grant insert (note_id, exam_date, study_days, minutes) on public.study_plans to authenticated;
grant update (exam_date, study_days, minutes) on public.study_plans to authenticated;

grant select, delete on public.study_plan_checks to authenticated;
grant insert (plan_id, day, task_key) on public.study_plan_checks to authenticated;

grant select on public.device_tokens to authenticated;

grant select on public.feedback to authenticated;
grant insert (message, app_version) on public.feedback to authenticated;

grant all on public.study_activity, public.study_guide_reads, public.study_plans,
             public.study_plan_checks, public.device_tokens, public.feedback, public.usage_events
  to service_role;

revoke execute on function public.study_log(uuid, text, int) from public, anon;
revoke execute on function public.study_mark_read(uuid, int) from public, anon;
grant execute on function public.study_log(uuid, text, int) to authenticated;
grant execute on function public.study_mark_read(uuid, int) to authenticated;

-- Profiles and notifications are already readable row by row (0004 and
-- the policies in 0012), so their new columns need no extra grant.
