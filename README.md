# ZutLib

Academic resource and borrowing management for Zambia University College of
Technology. One Flutter codebase for Android and the web, Supabase for the
backend.

## What it does

Students search past papers, test papers, lecture notes and reading lists by
department, course code, academic year and type, with full text search over
titles. Digital resources open immediately. Physical copies are borrowed
through a request a librarian approves or rejects, with the outcome emailed.

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

Then create a **private** storage bucket named `resources`.

### 2. Edge functions

    supabase functions deploy register
    supabase functions deploy decide-request

`register` must be callable without a session, since the caller has no
account yet. `decide-request` requires one.

### 3. Roll

    python scripts/generate_roll.py > roll.csv

Sign in as an administrator and import it from the Student roll screen.
To make the first administrator, register normally, then in the SQL editor:

    update public.profiles set role = 'admin' where student_number = '2300339';

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
    flutter run -d chrome       # web
    flutter run                 # Android

## How the security works

Four rules, each enforced where it cannot be bypassed.

**Deny by default.** Row level security is on for every table. A table with
RLS enabled and no matching policy returns no rows, so a forgotten policy is
a refusal rather than a leak.

**Eligibility precedes identity.** An account cannot exist unless the student
number is on the roll, the surname matches it, and the record is unclaimed.
The roll is not readable by any client; the check runs in an edge function
under the service role.

**State changes are server operations.** Approving, reserving, collecting
and returning all run in `decide-request`, which validates the transition
against the current state before writing. A modified client cannot reach a
state it is not entitled to.

**Correctness is declared, not enforced procedurally.** Valid statuses are a
check constraint. The relationship between a request and its resource is a
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
    supabase         migrations and edge functions
