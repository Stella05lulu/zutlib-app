# ZutLib — test plan and log

Three layers of evidence for Chapter 5.

| Layer | How it runs | Where |
|---|---|---|
| 1. Security (database) | Paste into Supabase SQL Editor, Run | `supabase/tests/rls_negative.sql` — 42 automated checks, each PASS/FAIL |
| 2. Unit (app logic) | `flutter test` in the zutlib folder | `test/models_test.dart` — 17 tests |
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
| ST-27 | As A, make S2 a librarian on Users | S2 now lands on Requests after signing in again | | |
| ST-28 | As A, try to change your own role | "You cannot change your own role. Ask another administrator." | | |
| ST-29 | As L, try to open /admin/roll by typing the address (web) | Sent back to Requests | | |
| ST-30 | As L, remove a resource that has borrowing history | "This is still referenced elsewhere…"; resource stays | | |
