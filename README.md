# ZutLib

Academic resource and borrowing management for Zambia University College of
Technology. One Flutter codebase for Android and the web, Supabase for the
backend.

## What it does

Students search past papers, test papers, lecture notes and reading lists by
department, course code, academic year and type. Search matches every word
typed against the title, course code, department, year, type and
description, tolerates small spelling mistakes, and puts an exact course code
first. Digital resources open immediately. Physical copies are borrowed
through a request a librarian approves or rejects; the student sees each
decision in the bell at the top right, and is reminded before a book is due.

Students also get a study assistant (study kits built by AI from a PDF,
YouTube video or notes), a **Plan** tab that turns each exam date into a
day-by-day plan, "For your courses" suggestions on Explore, and reminders on
their phone. Administrators get usage reports and read feedback sent from
the app.

Accounts are separated into three roles. Students sign themselves up, confirm
their email, and then wait on a holding screen until an administrator
approves them. Librarians and administrators are never self-registered: an
administrator invites them, and they choose their own password from the
invite email. Librarians manage books, past papers and borrowing;
administrators manage accounts and can also use every librarian tool.

## Setup

Run everything from the `zutlib` folder with the Supabase CLI logged in and
linked to the project.

### 1. Database

Supabase dashboard -> SQL Editor -> New query. Paste and run each migration
on its own, in order:

    supabase/migrations/0001_schema.sql
    ...
    supabase/migrations/0010_study_assistant.sql
    supabase/migrations/0011_book_type.sql           (one line; must run alone)
    supabase/migrations/0012_accounts_roles_library.sql
    supabase/migrations/0013_study_pdfs.sql
    supabase/migrations/0014_study_kits.sql
    supabase/migrations/0015_planner_notifications.sql
    supabase/migrations/0016_super_admin_enum.sql    (two lines; must run alone)
    supabase/migrations/0017_super_admin.sql
    supabase/migrations/0018_account_tools_settings.sql
    supabase/migrations/0019_announcements_saved.sql
    supabase/migrations/0020_kit_sources.sql
    supabase/migrations/0021_dashboards_view_as.sql
    supabase/migrations/0022_bigger_kits.sql

0011 and 0016 must each be their own run because Postgres will not use a new
enum value in the same transaction that adds it. If 0001 to 0010 are already
applied, start at 0011.

Before 0015, turn on **pg_cron** (Database -> Extensions -> pg_cron -> Enable).
0015 uses it to send due-date and exam reminders every morning at 07:00.

Then run the seven test files the same way. Every row must say PASS:

    supabase/tests/rls_negative.sql     borrowing and catalogue rules
    supabase/tests/study_rls.sql        study notes, PDFs, AI tables
    supabase/tests/roles_rls.sql        sign-up, approval, roles, admin actions
    supabase/tests/study_kits_rls.sql   study kits, guides, progress, tests, games
    supabase/tests/planner_rls.sql      plans, profiles, notifications, feedback, reports
    supabase/tests/super_admin_rls.sql  super admin, role ranks, removal, audit log locked
    supabase/tests/plan_items_rls.sql   account tools, settings, announcements, saved,
                                        kit sources, dashboards, View as

The tests make their own throwaway rows and remove them at the end.

### 2. Edge functions

    supabase functions deploy admin-users
    supabase functions deploy decide-request
    supabase functions deploy study-generate
    supabase functions deploy push --no-verify-jwt
    supabase functions delete register
    supabase secrets set GEMINI_API_KEY=paste-your-free-key-here

`push` sends notifications to phones through Firebase Cloud Messaging. It
works only after the optional step 2b; until then it does nothing.

`register` belonged to the old student-roll sign-up and is no longer used;
deleting it closes that door. The Gemini key is free from aistudio.google.com
and lives only in Supabase secrets.

### 2b. Phone push notifications (optional, free)

Without this, notifications still appear in the app's bell and the phone
still shows study and due-date reminders (scheduled on the phone). This
step adds push for messages the phone cannot know in advance, such as "your
request was approved" or "new paper for EEE 2011", while the app is closed.
See `docs/PUSH_SETUP.md`.

### 3. Authentication settings (dashboard)

Brevo SMTP is already configured under Authentication -> Emails -> SMTP
Settings. Leave that page exactly as it is.

- **Authentication -> Sign In / Providers -> Email**: Enable email provider
  ON, Confirm email ON, Allow new users to sign up ON, Minimum password length
  8 (the app asks for at least 8 too). Leaked password protection needs
  the Pro plan, so it stays off on the free plan.
- **Authentication -> Rate Limits**: keep the defaults. Supabase sends at
  most one email to the same address every 60 seconds; the app shows a
  countdown when this limit is hit instead of an error.
- **Authentication -> URL Configuration**: Site URL is the address of the
  web app with no slash at the end, for example `http://localhost:5000`
  while testing, or the hosted address later. Redirect URLs:
  `http://localhost:5000/**`, `zutlib://login-callback`,
  `zutlib://reset-password` (plus the hosted address followed by `/**`
  once there is one).
- **Authentication -> Emails -> Templates**:
  - Invite user: subject "You have been invited to ZutLib", body the whole
    of `supabase/templates/invite.html`.
  - Confirm signup: subject "Confirm your ZutLib email address", body the
    whole of `supabase/templates/confirmation.html`.
  - Reset password: subject "Choose a new ZutLib password", body the whole
    of `supabase/templates/recovery.html`.

  Each link must stay exactly as written in the file
  (`{{ .SiteURL }}/?token_hash={{ .TokenHash }}&type=...`). The app reads
  that one-time token itself, so the link works in whichever browser opens
  it. Supabase's default links only work in the browser the request was
  made from, which is why an email opened from Gmail in another window used
  to land on the sign-in page.

### 4. First administrator

There are no default accounts or passwords. Make the first administrator
once:

1. Authentication -> Users -> Add user -> Create new user, with your own
   email and a strong password, Auto Confirm User ticked.
2. Put that email in `scripts/bootstrap_accounts.sql`, paste it into the SQL
   Editor and run it.

Every other account is then made from the app: Admin -> Users -> Create
account sends an invite email, and the person chooses their own password.
The administrator never sees or sets anyone's password.

### 4b. Super admin (break glass)

The super admin is the top role: only they can create or remove
administrators, change roles, suspend an administrator, change system
settings and use View as. Everyone acts only on accounts ranked below their
own (student, librarian, admin, super admin), nobody can change their own
role, and the last super admin cannot be demoted, suspended or removed.

Sign-up and the app can never make a super admin. After 0017, make the
first one (or restore one later) from the dashboard: paste
`scripts/restore_super_admin.sql` into the SQL Editor, put the person's email
on the line marked CHANGE THIS, and run it. The change is written to the
audit log.

### 5. Sample and real library data

Sample data is for demonstration only. Every sample row is labelled
"Sample" in the app, and every sample PDF starts with "SAMPLE PAPER. NOT AN
OFFICIAL ZUT EXAMINATION." The service role key goes in the terminal only,
never in `.env`:

    $env:SUPABASE_SERVICE_ROLE_KEY = "..."
    python scripts/sample_data.py seed          # about 40 books, 210 papers 2019 to 2025
    python scripts/sample_data.py import-real   # seed/real-papers/ and seed/real-books.csv
    python scripts/sample_data.py remove        # deletes every sample row and file
    Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY

`seed` and `remove` can be run any number of times. Real files are named
`DEPARTMENT_COURSE CODE_YEAR_exam_Course title.pdf` (or `_test_`), for
example `ICT_ICT 2010_2023_exam_Programming in C.pdf`, and real books use
the header `title,author,isbn,department,course_code,edition,total_copies`.
Librarians can also do both from the app (Library -> Import books, Upload
papers).

The older `scripts/seed_resources.dart` still loads the files listed in
`scripts/seed/resources_manifest.csv`.

For the demo, `scripts/seed_study_demo.sql` and then
`scripts/seed_demo_extras.sql` (SQL Editor, after the super admin exists)
fill every new screen for every role: announcements, saved items, a kit
with several sources, six weeks of quiz attempts for My progress, an overdue
loan, a request waiting for a librarian, and audit entries. Everything is
labelled "Sample" and goes through the same tables and audited functions
the app uses. Both can be run again to reset.

### Running every test locally

Without touching the live project: Postgres 15 or newer, PostgREST 12 and
Deno 2 on the PATH, then

    PGHOST=/tmp PGPORT=54322 PGUSER=postgres bash supabase/tests/local/run_local.sh

builds a throwaway database from every migration, runs the seven SQL
security files, the last-copy race test and every Edge Function test.

### 6. App

    cp .env.example .env        # then paste your anon key
    flutter pub get
    flutter analyze
    flutter test
    flutter run -d chrome --web-port 5000   # web
    flutter run                             # Android

Invite links open the web app, so run the web version for anyone accepting
an invite.

## Study assistant

Notes, summaries, flashcards and quizzes for students, with optional AI
help from the free Gemini API. Setup, demo script and security notes are in
`docs/study-assistant/README.md`; every design choice is in
`docs/study-assistant/DECISIONS.md`.

## How the security works

Four rules, each enforced where it cannot be bypassed. Each claim below is
tested by the files in `supabase/tests/`.

**Deny by default.** Row level security is on for every table. A table with
RLS enabled and no matching policy returns no rows, so a forgotten policy is
a refusal rather than a leak.

**Nobody chooses their own access.** Public sign-up always makes a student
whose account is `pending`, whatever the request contains; a database
trigger on new users decides this, not the app. A pending, rejected or
suspended account can sign in but sees only the waiting screen, and every
policy and edge function also checks that the account is `active`, so a
modified app gets nothing either. Users cannot write their own role or
status. Only the `admin-users` edge function changes them, after checking
the caller is an active administrator, and every change is written to the
audit log. An administrator cannot change their own account and the last
active administrator cannot be removed.

**Identity is copied, never typed.** The name, student number and programme
on a borrowing request (name, department, email) are written by a database
trigger from the verified profile, whatever the client sends. Column privileges limit a student to
creating a request and cancelling it; they cannot edit their own profile,
set a due date or change which item a request is for. An administrator
cannot change their own role, and the last administrator cannot be demoted.

**State changes are server operations.** Approving, reserving, collecting,
returning and releasing an uncollected copy all run in `decide-request`, which validates the transition
against the current state before writing. A modified client cannot reach a
state it is not entitled to.

**Correctness is declared, not enforced procedurally.** Valid statuses are an
enumerated type. The relationship between a request and its resource is a
foreign key. Available copies are constrained between zero and the holding.
The database evaluates all of these on every write.

## Verifying it

    -- available copies cannot exceed the holding
    update resources set available_copies = 99 where id = '...';
    -- ERROR: violates check constraint "resources_copies_within_total"

    -- a request cannot reference a resource that does not exist
    insert into borrow_requests (resource_id, ...) values ('00000000-...', ...);
    -- ERROR: violates foreign key constraint

    -- an invalid status cannot be written by anyone
    update borrow_requests set status = 'borrowed_forever' where id = '...';
    -- ERROR: invalid input value for enum borrow_status

## Structure

    lib/core         theme, router, config, error mapping
    lib/models       profile, resource, borrow request
    lib/data         repositories, the only place that talks to Supabase
    lib/state        Riverpod providers
    lib/ui/widgets   shell, shared components, the four screen states
    lib/ui/screens   auth, student, staff (librarian), admin, study
    supabase         migrations, edge functions, email templates, security tests
    scripts          first administrator, sample and real data, study demo
    test             unit tests (flutter test)
