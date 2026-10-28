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
decision on their Updates screen.

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

0011 must be its own run because Postgres will not use a new enum value in
the same transaction that adds it. If 0001 to 0010 are already applied,
start at 0011.

Then run the three test files the same way. Every row must say PASS:

    supabase/tests/rls_negative.sql     borrowing and catalogue rules
    supabase/tests/study_rls.sql        study notes, PDFs, AI tables
    supabase/tests/roles_rls.sql        sign-up, approval, roles, admin actions

The tests make their own throwaway rows and remove them at the end.

### 2. Edge functions

    supabase functions deploy admin-users
    supabase functions deploy decide-request
    supabase functions deploy study-generate
    supabase functions delete register
    supabase secrets set GEMINI_API_KEY=paste-your-free-key-here

`register` belonged to the old student-roll sign-up and is no longer used;
deleting it closes that door. The Gemini key is free from aistudio.google.com
and lives only in Supabase secrets.

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

  The invite link must stay exactly as written in the file
  (`{{ .SiteURL }}/?token_hash={{ .TokenHash }}&type=invite`): the app reads
  that token and signs the new person in to choose a password.

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
