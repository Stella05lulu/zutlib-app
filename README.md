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

Nobody surrenders a student card. Eligibility is proved once, at
registration, against the institutional roll.

## Setup

### 1. Database

Run the migrations in order in the Supabase SQL editor:

    supabase/migrations/0001_schema.sql
    supabase/migrations/0002_rls.sql
    supabase/migrations/0003_copy_functions.sql
    supabase/migrations/0004_grants.sql
    supabase/migrations/0005_service_role_grants.sql
    supabase/migrations/0006_storage.sql
    supabase/migrations/0007_search.sql
    supabase/migrations/0008_keepalive.sql
    supabase/migrations/0009_hardening.sql

0006 creates the private `resources` storage bucket.

Then prove the security rules hold by running
`supabase/tests/rls_negative.sql` in the SQL editor. Every row of the result
must say PASS.

### 2. Edge functions

    supabase functions deploy register
    supabase functions deploy decide-request

`register` must be callable without a session, since the caller has no
account yet. `decide-request` requires one. Redeploy both after any change
to `supabase/functions/`.

### 3. Roll

    python scripts/generate_roll.py > roll.csv

Sign in as an administrator and import it from the Student roll screen.

Staff are not on the roll, so their accounts are made in the dashboard
(Authentication -> Users -> Add user, tick Auto Confirm User) and given a
role with `scripts/create_staff.sql`.

### 4. Seed the catalogue

The real past papers are listed in `scripts/seed/resources_manifest.csv`
(one row per file: title, type, department, course code, year, semester).
The service role key goes in the terminal only, never in `.env`:

    $env:SUPABASE_SERVICE_ROLE_KEY = "..."
    dart run scripts/seed_resources.dart --dry-run
    dart run scripts/seed_resources.dart
    Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY

Running it twice skips rows already catalogued.

### 5. App

    cp .env.example .env        # then paste your anon key
    flutter pub get
    flutter run -d chrome --web-port 5000   # web
    flutter run                             # Android
    flutter test                            # unit tests

On the web, account email links return to http://localhost:5000, so add
`http://localhost:5000/**` to Authentication -> URL Configuration ->
Redirect URLs next to `zutlib://login-callback` and `zutlib://reset-password`.

## How the security works

Four rules, each enforced where it cannot be bypassed. Each claim below is
tested by `supabase/tests/rls_negative.sql`.

**Deny by default.** Row level security is on for every table. A table with
RLS enabled and no matching policy returns no rows, so a forgotten policy is
a refusal rather than a leak.

**Eligibility precedes identity.** An account cannot exist unless the student
number is on the roll, the surname matches it, and the record is unclaimed.
The roll is not readable by any client; the check runs in an edge function
under the service role.

**Identity is copied, never typed.** The name, student number and programme
on a borrowing request are written by a database trigger from the verified
profile, whatever the client sends. Column privileges limit a student to
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
    lib/ui/screens   auth, student, staff, admin
    supabase         migrations, edge functions, security tests
    scripts          roll generator, catalogue seed, staff accounts
    test             unit tests (flutter test)
