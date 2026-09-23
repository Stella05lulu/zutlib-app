# ZutLib — defence readiness diagnosis (23 September 2026)

## Status after the fixes of 23 September 2026

| Item | Status | Where |
|---|---|---|
| B1 SMTP | Your action (dashboard) | see chat checklist |
| B2 GitHub backup + keepalive | Done in code (anon-key `beat()`); push and secrets are your action | `0008_keepalive.sql`, `.github/workflows/keepalive.yml` |
| B3 Emails promised, not sent | Fixed: Updates screen for students, honest messages | `notifications_screen.dart`, `notification_repository.dart` |
| B4 Staff accounts | Fixed: dashboard + script | `scripts/create_staff.sql` |
| B5 Links on web | Fixed: web returns to its own address | `auth_repository.dart`, `register/index.ts` |
| S1 Forged identity on requests | Fixed: trigger copies it from the profile | `0009_hardening.sql` |
| S2 Files readable without a profile | Fixed in policy; turning sign-up off is your action | `0009_hardening.sql` |
| S3 Students editing own profile | Fixed: column privileges, policy removed | `0009_hardening.sql` |
| S4 Cancel rewriting the row | Fixed: column privileges | `0009_hardening.sql` |
| S5 Registration race | Fixed | `register/index.ts` |
| S6 Rate limit on register | Open: enable CAPTCHA or name as a limitation | |
| S7 Admin self-demotion | Fixed in database and UI | `0009_hardening.sql`, `users_screen.dart` |
| S8 Package id | Fixed: `zm.ac.zut.zutlib`, app label ZutLib | `android/app/build.gradle.kts` |
| Search failing for signed-in users | Found and fixed while testing: `authenticated` lacked USAGE on the `extensions` schema | `0007_search.sql`, `0009_hardening.sql` |
| F1 Uncollected copy stuck | Fixed: "Student did not collect" | `decide-request`, `request_detail_screen.dart` |
| F2 Copy count drift on return | Fixed: release after the update | `decide-request` |
| F3 Staff resources screen | Fixed: own search, limit 100 | `resource_manager_screen.dart` |
| F4 Delete leaves file / raw error | Fixed | `resource_repository.dart`, `failure.dart` |
| F5 Upload form | Fixed: department list, semester, course code check, PDF only | `upload_resource_screen.dart` |
| F6 Orphan file on failed upload | Fixed | `resource_repository.dart` |
| F7 Roll CSV | Fixed: quote-aware reader, Excel BOM | `core/csv.dart` |
| Stale data after switching accounts | Found and fixed: providers now reload per signed-in account | `state/providers.dart` |
| U1 to U5 visual contract | Open: your decision (see chat) | |
| U3 Spinner on load | Fixed: skeleton placeholders | `state_views.dart`, `browse_screen.dart` |
| T1 Security tests | Done: 42 checks, all PASS on a local copy of the schema | `supabase/tests/rls_negative.sql` |
| T3 Unit tests | Done: 17 tests | `test/models_test.dart` |
| T4 Test plan | Done: 30 system cases to run and log | `docs/TEST_PLAN.md` |
| D1 to D4 Documentation | Fixed | `README.md` |

Scope: every file in `lib/`, `supabase/migrations/`, `supabase/functions/`,
`supabase/config.toml`, `android/`, `.github/`, `scripts/`.
Not checked: the live Supabase project, because the cloud can't be reached from
this session. Section 0 lists what to confirm in the dashboard.

Severity: **Blocker** = the demo fails or an examiner can break it live.
**High** = weakens the security story you are defending.
**Medium** = a visible gap or a break from your own contract. **Low** = polish.

---

## 0. Confirm in the Supabase dashboard (10 minutes)

| # | Check | Where | Expected |
|---|---|---|---|
| 0.1 | Migrations 0001 to 0007 all applied | Table Editor, Database → Functions | Tables roll, profiles, resources, borrow_requests, audit_entries, notifications, heartbeat; functions search_resources, resource_facets, staff_overview, reserve_copy, release_copy |
| 0.2 | Both edge functions deployed | Edge Functions | `register`, `decide-request` listed |
| 0.3 | Private bucket exists | Storage | `resources`, Public = off |
| 0.4 | Email confirmation on | Authentication → Sign In / Providers → Email | "Confirm email" = on |
| 0.5 | Redirect URLs listed | Authentication → URL Configuration | `zutlib://login-callback` and `zutlib://reset-password` |
| 0.6 | At least one admin and one librarian exist | Table Editor → profiles | role column |

---

## 1. Blockers

| ID | Problem | Evidence | Fix |
|---|---|---|---|
| B1 | **Students will not receive the verification email.** Supabase's built-in email service only delivers to your project's team members and is heavily rate-limited, so a student who registers cannot verify and cannot sign in. | `register/index.ts` relies on `auth.resend`; no SMTP configured in `config.toml` | Authentication → Emails → SMTP Settings: add a free SMTP provider (Brevo, Resend, or Gmail with an app password). Test by registering with an address that is not yours. |
| B2 | **The project will pause before the defence.** Free projects pause after 7 days without activity. The keepalive workflow only runs from a GitHub repository, and this folder is not a git repository. It also has no version control or backup. | no `.git`; `.github/workflows/keepalive.yml` | Push the project to a private GitHub repo (exclude `.env`). Add secrets `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. Run the workflow once by hand from the Actions tab. |
| B3 | **The app promises emails that are never sent.** The UI says "the student has been emailed", "You will get an email once a librarian decides", and the README says "with the outcome emailed". `decide-request` only writes a row to `notifications`, and no screen ever reads that table. | `request_detail_screen.dart`, `borrow_request_screen.dart`, `decide-request/index.ts` line "The email itself is sent by…" | Minimum: add a Notifications screen for students that reads `notifications`, and change the three messages to say "notified in the app". Optional: send email from `decide-request` through the same SMTP/Resend provider. |
| B4 | **No way to create a librarian or admin.** Registration requires a student number on the roll. The README's "register normally, then set role" only works for someone on the roll, and staff are not students. | `register/index.ts`, README step 3 | Documented procedure: Authentication → Users → Add user (auto-confirm), then insert a `profiles` row with `role = 'librarian'` and `student_number` null. A SQL snippet can be added as `scripts/create_staff.sql`. |
| B5 | **Email links only work on Android.** Verify and reset links return to `zutlib://…`, which a browser cannot open. If you demo on Chrome, the link opens nothing. | `auth_repository.dart` redirect constants | Demo on the Android build. State it in the scope: web is supported for browsing, account emails complete on the device. |

---

## 2. Security (your primary objective)

| ID | Sev | Problem | Where | Fix |
|---|---|---|---|---|
| S1 | High | **A student can file a borrowing request under someone else's name and student number.** The client sends `student_name`, `student_number` and `programme`, and the insert policy never checks them against the profile. The librarian's screen then shows them as "Verified requester". | `borrow_repository.dart apply()`, policy `borrow_insert_own` | A `BEFORE INSERT` trigger on `borrow_requests` that overwrites those three fields from `profiles` for `auth.uid()`. |
| S2 | High | **The roll can be bypassed to get an account, and that account can read files.** Sign-up is on in `config.toml` and on by default in the dashboard, so anyone with the public anon key can call `signUp` directly. The storage read policy only requires "authenticated", not "has a profile". | `config.toml enable_signup = true`, `0006_storage.sql resources_files_read` | Turn off "Allow new users to sign up" in the dashboard (`register` uses `admin.createUser`, which still works). Change the storage read policy to require a row in `profiles`. |
| S3 | High | **Students can edit their own name, surname, programme and department.** The comment on `profiles_update_own` says these are locked, but the policy only locks `role` and `student_number`. Together with S1, this makes the "verified identity" claim untrue. | `0002_rls.sql` | The app never edits a profile, so revoke `update` on `profiles` from `authenticated` and leave admin edits to `profiles_admin_all` through a column grant or trigger. |
| S4 | Medium | **Cancelling lets a student rewrite the rest of the row.** The cancel policy checks only `student_id` and the new status, so the same UPDATE can change `resource_id`, `collection_date` or the names. | `borrow_cancel_own` + table-wide `grant update` in `0004_grants.sql` | Column-level grant: `revoke update on borrow_requests from authenticated; grant update (status, cancelled_at) on borrow_requests to authenticated;` |
| S5 | Medium | **Concurrent registration can wrongly un-claim another student.** The claim `update … eq('claimed', false)` returns no error when zero rows change, so the losing request continues. It then fails on the profile insert and its "unwind" sets the winner's record back to unclaimed. | `register/index.ts` claim block | Add `.select()` to the claim update and fail when zero rows come back. |
| S6 | Low | **No rate limit on `register`.** Surnames can be guessed per student number, and the error text confirms whether a number is on the roll. | `register/index.ts` | Name it as a known limitation, or enable CAPTCHA (Authentication → Attack Protection) and return one generic message for not-on-roll and surname mismatch. |
| S7 | Low | **An admin can demote themselves or the last admin**, locking everyone out of the roll and roles screens. | `users_screen.dart`, `admin_repository.setRole` | Block changing your own role in the UI. Optionally add a DB check that at least one admin remains. |
| S8 | Low | Package id `com.example.zutlib`; release build signed with the debug key. | `android/app/build.gradle*` | Rename to `zm.ac.zut.zutlib` (or similar) before building the defence APK. |

---

## 3. Functional gaps

| ID | Sev | Problem | Where | Fix |
|---|---|---|---|---|
| F1 | High | **An approved request that is never collected keeps its copy forever.** A student can only cancel while `submitted`, and staff have no "release" action for `approved`. | `decide-request LEGAL`, `request_detail_screen.dart` | Add a `cancel` action for staff (`approved → cancelled` plus `release_copy`) with a "Student did not collect" button. |
| F2 | Medium | **Copy count can drift on return.** `return` calls `release_copy` before the status update. If the update then conflicts, the copy was freed but the loan is still open. | `decide-request/index.ts` return branch | Release the copy only after the update succeeds. |
| F3 | Medium | **Staff Resources screen is tied to the student search.** It reuses `searchProvider`, so it inherits whatever filters were set on Explore, is capped at 50 rows, and has no search box. With 40 seeded papers this cap is reached quickly. | `resource_manager_screen.dart` | Give it its own provider with a search field and a higher limit or paging. |
| F4 | Medium | **Removing a resource leaves its file in storage.** Removing one that has borrowing history fails with a raw foreign-key message (code 23503 is not mapped). | `resource_repository.delete`, `failure.dart` | Delete the storage object after the row. Map 23503 to "This resource has borrowing history and cannot be removed." |
| F5 | Medium | **The upload form doesn't match your decisions.** Department is free text (you fixed it to ICT, Engineering, Business). There is no semester field. It accepts `.doc`/`.docx`, which phones open poorly. | `upload_resource_screen.dart` | Department dropdown from a constant list, a semester field, PDF only. |
| F6 | Low | **A failed catalogue insert after a successful upload leaves an orphan file.** | `resource_repository.upload` | Remove the uploaded object in the catch. |
| F7 | Low | **Roll CSV import breaks on quoted fields or commas in names.** | `admin_repository.importRoll` | Reuse the CSV reader from `scripts/seed_resources.dart`. |

---

## 4. Your own build contract (examiners will see the UI)

| ID | Rule you set | What the code does | Where |
|---|---|---|---|
| U1 | IBM Plex Sans + IBM Plex Mono, explicitly not Inter | `GoogleFonts.interTextTheme` | `core/theme.dart` line 175 |
| U2 | No gradients, no drop shadows, no pure white/black | about 40 uses of `Gradient`, `BoxShadow`, `Colors.white` | `browse_screen.dart`, `glass.dart`, `common.dart`, `shell.dart`, `auth_scaffold.dart`, `theme.dart` |
| U3 | No bare centred `CircularProgressIndicator`; skeletons shaped like content | spinner on first load of Explore and in request detail | `browse_screen.dart`, `request_detail_screen.dart` |
| U4 | Not SnackBar as the response to everything | every action ends in `showMessage` | all screens |
| U5 | Theme in one file at `lib/core/theme/app_theme.dart`, no colours elsewhere | theme is `lib/core/theme.dart`; `Color(0xFF2563EB)` and `Colors.white` appear inline | `browse_screen.dart _Banner` |

---

## 5. Testing evidence (needed for Chapter 5)

| ID | Gap | What to produce |
|---|---|---|
| T1 | There is no `test/` folder. Your contract requires negative tests written in the module that introduced the rules. | `supabase/tests/rls_negative.sql`: sign in as student, librarian and admin via `set local role` / `request.jwt.claims` and prove each refusal (student reads roll → 0 rows; student inserts resource → error; student approves own request → error; student updates role → error; student cancels someone else's request → 0 rows). |
| T2 | No constraint tests recorded. The README lists three but there is no output. | Run them, screenshot the errors, put them in the report as evidence. |
| T3 | No app-level tests | `test/models_test.dart` (status parsing, overdue derivation, course code/label mapping) and one widget test for the four states of Explore. |
| T4 | No written test plan | A table of test cases (ID, requirement FR/NFR number, steps, expected, actual, pass/fail) covering register, verify, sign in, search, open file, borrow, approve, reject, collect, return, overdue, role change, roll import. |

---

## 6. Documentation mismatches

| ID | Statement | Reality |
|---|---|---|
| D1 | README: "with the outcome emailed" | Not implemented (B3) |
| D2 | README: "full text search over titles" | Now: word-by-word match over title, course code, department, year, type and description, with typo tolerance (0007) |
| D3 | README setup lists only 0001 to 0003 before my update | Now lists 0001 to 0007 |
| D4 | `profiles_update_own` comment says programme is locked | It is not (S3) |

---

## 7. Recommended order

| Day | Do |
|---|---|
| 1 | Section 0 checks. B1 SMTP. B2 GitHub + keepalive. B4 create librarian and admin. |
| 2 | S1, S2, S3, S4, S5 as one migration `0008_hardening.sql` plus the `register` fix. F1 and F2 in `decide-request`. |
| 3 | B3 notifications screen and message text. F3, F4, F5. |
| 4 | T1 to T4 test evidence. |
| 5 | U1 to U5 visual contract. S7, S8. Build the release APK and install it on the demo phone. |
