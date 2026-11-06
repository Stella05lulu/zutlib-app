# ZutLib study assistant

## 1. Setup

The full project setup (migrations 0001 to 0021, the seven security test files, edge functions, Authentication settings, email templates, the first administrator and the sample data) is in the main `README.md` under Setup. The study assistant needs, in addition:

1. **Gemini key** (free from aistudio.google.com, no payment method): `supabase secrets set GEMINI_API_KEY=paste-your-key-here`, then `supabase functions deploy study-generate`.
2. **Demo students with study material.** Authentication -> Users -> Add user, twice: `sample.student.a@zutlib.test` and `sample.student.b@zutlib.test`, each with a password you choose and "Auto Confirm User" ticked. Then run `scripts/seed_study_demo.sql` in the SQL Editor. It approves both accounts and gives them sample notes, a deck and a quiz. Then run `scripts/seed_demo_extras.sql`: sample announcements, saved items, a kit with several sources, six weeks of quiz attempts (for My progress), an overdue loan, a request waiting for a librarian, and real audit entries. Run both again before each demo to reset them.

Sample data is for demonstration only. Every sample book and paper shows a "Sample" label in the app, and every sample PDF opens with "SAMPLE PAPER. NOT AN OFFICIAL ZUT EXAMINATION." Remove all of it with `python scripts/sample_data.py remove`.

### Before the demo

Do these the day before, then tick them again an hour before.

- [ ] All 21 migrations applied; all seven test files in `supabase/tests/` PASS (`rls_negative`, `study_rls`, `roles_rls`, `study_kits_rls`, `planner_rls`, `super_admin_rls`, `plan_items_rls`).
- [ ] `scripts/restore_super_admin.sql` run with your email: you are the super admin.
- [ ] One study kit already built with AI from your lecture-notes PDF (so the demo does not wait on Gemini), and one public YouTube lecture link copied.
- [ ] `admin-users`, `decide-request` and `study-generate` deployed; `register` deleted; `GEMINI_API_KEY` set.
- [ ] Authentication: Confirm email ON, sign-ups ON, minimum password 8, Site URL is the web app address, redirect URLs added, all three email templates pasted (invite, confirm signup, reset password). SMTP settings untouched.
- [ ] You can sign in as your super admin, and as a second administrator invited from the app.
- [ ] Admin -> Create account -> **Send test invite** to your own second inbox shows "sent", and the email arrives with the ZutLib wording.
- [ ] A librarian account invited from the app, invite accepted, password chosen, signed in once.
- [ ] One student signed up from the app with a real inbox, email confirmed, left **waiting** (not approved) to approve live.
- [ ] `python scripts/sample_data.py seed` run; Browse shows sample books (some with 0 available) and papers from 2019 to 2025.
- [ ] `scripts/seed_study_demo.sql`, then `scripts/seed_demo_extras.sql` run.
- [ ] One short PDF of your own lecture notes saved on the demo device.
- [ ] Backup accounts in case email is slow: a second approved student and a second librarian, made the same way and listed in `scripts/bootstrap_accounts.sql`.
- [ ] Sample student A signed in in a spare browser profile, as a fallback if Gemini is busy.
- [ ] Web app running at the Site URL (`flutter run -d chrome --web-port 5000`), each account in its own browser profile so switching takes one click.

## 2. Demo script (about 4 minutes)

| Time | Do | Say |
|---|---|---|
| 0:00 | Show the sign-up screen: full name, department, email, password. | "Anyone can sign up, but only as a student, only after confirming their email, and only while the super admin keeps sign-up open." |
| 0:10 | Sign in as the waiting student. The waiting screen appears. | "Until an administrator approves them they see only this. The database refuses them everything else, not just the app." |
| 0:20 | Super admin window: **Overview**. Point at the stat row, the activity chart and the event breakdown. **Approve** the waiting student from Pending approvals. | "Every number is a live query. The audit log has a week of activity, and every approval lands in it." |
| 0:40 | Open the menu: Workspace, Library, Governance. Open **Users**, a librarian, and show the tools: edit details, send a reset link, sign out everywhere. Each asks for a reason. | "I never see a password. Each tool needs a reason, and the reason goes in the audit log." |
| 1:00 | **Audit log**: open the newest entry. | "Nobody can edit or delete these, not from the app and not from the server functions." |
| 1:10 | **Settings**: loan period and maximum borrows. | "The database reads these. A student over the limit is refused by the database, not by a hidden button." |
| 1:20 | On a student, **View as**. Point at the banner. **Exit**. | "Read only. The server checks I am the super admin and logs the start and end. It never shows their private study kits." |
| 1:35 | Admin window (not super admin): open the super admin's account. | "An admin manages only accounts below them. Only the dashboard can make a super admin." |
| 1:45 | Librarian window: **Today**. Waiting requests, collections due, overdue, no copies left. Approve the waiting request. | "The librarian starts the day with what needs doing." |
| 2:00 | Student window (sample student A): **Home**. Greeting, books on loan with the next due date, streak, latest announcement, Continue studying, For your courses. | "Home is built from their own data. Sections with nothing in them are hidden." |
| 2:20 | Open a paper with the **Sample** label, tap the bookmark, then **Saved**. | "Saved items are private to the student, by row level security." |
| 2:30 | Open the kit with several sources, **Materials**: a formula sheet and a library paper. Add a YouTube link. | "One build reads every source in a single request, so it costs one of the ten daily requests." |
| 2:50 | **Study guide**, then **Smart study**: answer one, rate it. | "Smart study keeps asking what you get wrong until you master it." |
| 3:05 | **Test**: 5 questions, **Create test**, answer two, **Hand in**. | "The database marks the test, so a score cannot be faked." |
| 3:20 | **My progress**: the score chart and Revise next. | "Rules, not AI: wrong in three of the last four tries means revise it next, and it says so." |
| 3:35 | **Plan** from the Home drawer: the exam countdown and today's tasks. | "The plan adapts to what they actually did." |
| 3:50 | Optional: show `super_admin_rls.sql` results, all PASS. | "Every rule I described is tested, including what each role is refused." |

If Gemini is slow or busy at 1:50, say so (the app shows the reason in plain words), switch to the browser profile signed in as sample student A, and carry on with the kit you built the day before.

## 3. How it is kept secure

**Who can use it.** Study features are for active students only. Every study policy checks the account is an approved student, so a pending, rejected or suspended account, a librarian or an administrator gets no study rows, and the `study-generate` function refuses them too.

**Row level security.** Every study table has row level security switched on, which means "deny unless a rule allows it". You may see and change a row only if you own it. The owner is filled in by the database from your sign-in and the app cannot write it. Cards, questions and attempts carry the same owner as their deck or quiz, linked so one student's card can never sit in another student's deck. `supabase/tests/study_rls.sql` signs in as two students and proves A cannot read, change or delete anything of B's.

**Uploaded PDFs are private.** A student's PDFs go to the private `study-files` bucket, in a folder named after their own account; storage rules allow only that student to read, add or delete there, and only PDFs up to 10 MB. Library PDFs are read by the server function with the service role after it has checked the student may see that item and that it has not been retired. Nothing is public.

**The key stays on the server.** The Gemini API key is a Supabase secret read only by `study-generate`. It is not in the app, the repository or any log. The app sends only "make a quiz from note X"; the function checks who is asking and that note X is theirs, downloads the PDF itself, and sends it to Gemini.

**A daily limit in the database.** Each student has 10 AI requests a day and the whole of ZutLib has 150, counted in the database and taken in one locked step, so two requests at once cannot both get the last one. An unchanged note or PDF is answered from a cache (keyed on the note and a fingerprint of the file), so it is never sent twice.

**AI output is checked before it is kept.** Gemini's answer must be JSON in exactly the expected shape: the right fields and nothing else, nothing empty or too long, every quiz question with exactly one correct option. If anything is wrong nothing is saved and the student is told plainly; the database checks the same rules again as it saves. The note and the PDF are treated as untrusted: Gemini is told to ignore any instructions written inside them.

## 4. Known limitations

- **YouTube videos.** Gemini's YouTube reading is a preview feature: public videos only (not private or unlisted), free, up to 8 hours of video a day per project. If Google refuses a video the student is told to try a public one or upload the notes as a PDF.
- **Five sources per kit.** A kit holds up to five sources (uploaded PDFs, library PDFs, YouTube links, typed text), with at most 30 MB of PDFs in total.
- **Building again replaces.** "Build again" makes a new guide, deck and question bank and removes the old ones, with their progress.
- **PDF download.** The study guide downloads as a PDF using the IBM Plex font fetched from Google Fonts; offline it falls back to the built-in font.

- **Free-tier limits.** Gemini's free quotas are per project and shown only in Google AI Studio. If many students use AI at once Gemini may answer "busy"; the app says so. If AI Studio shows a daily quota below 150, lower `study_ai_project_daily_limit()` in migration 0010.
- **Large or scanned PDFs.** PDFs over 10 MB are refused. A scanned PDF is read as images, which works but is slower; a very long PDF may take longer than the 100 second wait, in which case the student is told the AI did not answer and can try one chapter instead.
- **AI can be wrong.** Summaries, cards and quiz answers can contain mistakes. The app says so next to the AI buttons, and students can edit or delete anything AI writes.
- **Free-tier privacy.** Google states that content sent on the free tier is used to improve its products. Students should not upload personal or confidential material for AI. Notes and PDFs never sent to AI stay in ZutLib only.
- **Counted even when it fails.** A request that reaches Gemini uses one of the day's requests even if the answer is then rejected, because it used free quota either way.
- **Invites open on the web.** The invite link opens the web app. On Android, a new librarian or administrator accepts the invite in a browser first, then signs in on the phone.
- **Not run against the live project.** The database rules, edge functions and sample loader were tested against a local Postgres 16 and PostgREST with a stand-in for Supabase Auth and Storage, and Gemini was replaced by a fake in tests. The Flutter code could not be compiled where it was written; run `flutter analyze` and `flutter test`.
