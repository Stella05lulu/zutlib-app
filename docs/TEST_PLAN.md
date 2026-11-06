# ZutLib — test plan and log

Three layers of evidence for Chapter 5.

| Layer | How it runs | Where |
|---|---|---|
| 1. Security (database) | Paste each into Supabase SQL Editor, Run (or all at once locally with `supabase/tests/local/run_local.sh`) | `supabase/tests/`: `rls_negative` 42, `study_rls` 106, `roles_rls` 86, `study_kits_rls` 55, `planner_rls` 80, `super_admin_rls` 51, `plan_items_rls` 82 automated checks, each PASS/FAIL, most of them refusals |
| 1b. Server functions | `run_local.sh` (Deno) | 131 Edge Function tests, including two end-to-end runs against a local database |
| 2. Unit (app logic) | `flutter test` in the zutlib folder | `test/`: models, planner, practice, progress, audit stats, library import, theme |
| 3. System (end to end) | By hand, following the table below | this file |

For layers 1 and 2, screenshot the full result and paste it into the report.
For layer 3, fill in the Actual and Result columns as you run each case,
and screenshot the key screens.

## Layer 3: system test cases

Accounts used: a roll student (S), a second roll student (S2),
`librarian@zutlib.test` (L), `admin@zutlib.test` (A).

### Registration and sign in

| ID | Steps | Expected | Actual | Result |
|---|---|---|---|---|
| ST-01 | Register with a student number that is not on the roll | "That student number is not on the institutional roll." No account created | | |
| ST-02 | Register with a roll number and the wrong surname | "That surname does not match the record for this student number." | | |
| ST-03 | Register S with a correct number and surname | "Account created. Check your email to verify the address." Verification email arrives | | |
| ST-04 | Register again with the same student number | "An account already exists for this student number…" | | |
| ST-05 | Sign in as S before clicking the email link | Taken to the verify screen, no access to the library | | |
| ST-06 | Click the email link, then sign in as S | Lands on Explore, name and programme from the roll shown | | |
| ST-07 | Forgot password for S, open the link, set a new password | New password works, old one does not | | |
| ST-08 | Sign in with a wrong password | "That email and password do not match an account." | | |

### Search and access

| ID | Steps | Expected | Actual | Result |
|---|---|---|---|---|
| ST-09 | As S, search `ict2010` | 5 Introduction to Programming with C++ papers | | |
| ST-10 | Search `eee 2011 2024` | Exactly 1 result, December 2024 | | |
| ST-11 | Search `entreprenuership` (misspelt) | 3 Entrepreneurship papers | | |
| ST-12 | Search `xyzabc` | "No resources match that" with a Clear all filters button | | |
| ST-13 | Choose Department = Engineering | Course list shows only Engineering codes | | |
| ST-14 | Open any paper, tap Open the document | PDF opens; link stops working after 5 minutes | | |

### Borrowing (physical copies)

| ID | Steps | Expected | Actual | Result |
|---|---|---|---|---|
| ST-15 | As L, add a resource with "The library holds physical copies" on, 1 copy | Appears in Resources and in student search as "1 of 1 available" | | |
| ST-16 | As S, apply to borrow it | Request shows Submitted in My borrowing | | |
| ST-17 | As S, apply again for the same item | "You already have a live request for this item." | | |
| ST-18 | As L, open the request | Name, student number and programme match S's roll record | | |
| ST-19 | As L, approve | Status Approved; copies now 0 of 1; S sees "Borrowing request approved" under Updates | | |
| ST-20 | As S2, open the same item | "Every copy is currently on loan", no apply button | | |
| ST-21 | As L, Record collection | Status Collected, due date 14 days ahead | | |
| ST-22 | As L, Record return | Status Returned; copies back to 1 of 1 | | |
| ST-23 | S2 applies, L rejects with a reason | S2 sees Rejected and the reason in My borrowing and Updates | | |
| ST-24 | S applies, L approves, L taps Student did not collect | Request closed, copy back on the shelf, S notified | | |
| ST-25 | S applies, then cancels before a decision | Status Cancelled; L no longer sees it under Pending | | |

### Administration

| ID | Steps | Expected | Actual | Result |
|---|---|---|---|---|
| ST-26 | As A, import `roll.csv` on Student roll | "Imported N records"; numbers searchable | | |
| ST-27 | As the super admin (X), make S2 a librarian on Users | S2 now lands on Today after signing in again | | |
| ST-28 | As A, try to change your own role | "You cannot change your own role. Ask another administrator." | | |
| ST-29 | As L, try to open /admin/roll by typing the address (web) | Sent back to Requests | | |
| ST-30 | As L, remove a resource that has borrowing history | "This is still referenced elsewhere…"; resource stays | | |

### Build plan features (4 November 2026)

Accounts: super admin X (made with `scripts/restore_super_admin.sql`), admin A, librarian L, students S and S2, sample students from `scripts/seed_demo_extras.sql`.

| ID | Steps | Expected | Actual | Result |
|---|---|---|---|---|
| ST-31 | As A, open X's account | "A super admin account can only be changed from the Supabase dashboard." No actions | | |
| ST-32 | As A, open another admin | "Only a super admin can change an administrator's account." | | |
| ST-33 | As A, Create account: look at the Role list | Student and Librarian only | | |
| ST-34 | As X, invite an administrator | Invite sent; new account is an active admin | | |
| ST-35 | As X, remove S2 with a reason, then restore S2 | S2 sees "Account removed", then can use the app again; both in the audit log with the reason | | |
| ST-36 | As X, try to change your own role or suspend yourself | Refused | | |
| ST-37 | As X, edit S's department with a reason | Saved; audit entry shows before and after | | |
| ST-38 | As X, change S's email | New address gets a reset link; S signs in with the new address | | |
| ST-39 | As X, Sign out everywhere on S | S's open session stops working on the next request | | |
| ST-40 | As X, Settings: maximum active borrows 1. S with one active borrow asks for another | Refused by the database with a clear message | | |
| ST-41 | As X, Settings: loan period 7 days. L marks a copy collected | Due date is 7 days later | | |
| ST-42 | As X, Settings: close registration. Try to sign up | Refused; invited accounts still work. Reopen it after | | |
| ST-43 | As A, open Settings by typing /admin/settings (web) | Sent back; the settings function refuses an admin | | |
| ST-44 | Admin menu: badges for pending users, open invites, overdue | Counts match Users, Invitations and Today; hidden at zero | | |
| ST-45 | Overview: Week and Month, activity chart, event breakdown | Live numbers; shares add up to 100% | | |
| ST-46 | Audit log: try every filter chip and search "suspend" | Matching entries only; tapping one shows its details | | |
| ST-47 | As X, View as sample student A, then Exit | Banner "Viewing as ... Read only"; no buttons that change data; no study kits; start and end in the audit log | | |
| ST-48 | As A, call View as (open /admin/view-as/<id>) | Refused | | |
| ST-49 | Sample student A: Home | Greeting, books on loan with next due date, streak, latest announcement, Continue studying, For your courses, Recently added, Saved | | |
| ST-50 | S with no data: Home | Empty sections are hidden; no placeholder text | | |
| ST-51 | S: bookmark a paper, open Saved, search it, pull to refresh, remove it | Works; S2 never sees S's saved items | | |
| ST-52 | S: kit Materials, add a PDF, a library paper, a YouTube link and typed text; try a sixth | Five listed; the sixth refused; 30 MB total enforced | | |
| ST-53 | S: Build the kit with several sources | One request used; guide covers every source | | |
| ST-54 | Sample student A: My progress | Score chart over six weeks; Revise next with reasons such as "Wrong in 3 of your last 4 tries" | | |
| ST-55 | As A, post an announcement for ICT ending next week; edit it; remove it | ICT students see it on Home and Updates, Engineering students do not; three audit entries | | |
| ST-56 | As L, try to post an announcement | No option in the app; the database refuses it | | |
| ST-57 | As L: Today | Waiting requests, collections due today, overdue copies, books with no copy left, all live | | |
