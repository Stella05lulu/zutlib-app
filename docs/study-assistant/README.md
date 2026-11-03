# ZutLib study assistant

## 1. Setup

The full project setup (migrations 0001 to 0014, the four security test files, edge functions, Authentication settings, email templates, the first administrator and the sample data) is in the main `README.md` under Setup. The study assistant needs, in addition:

1. **Gemini key** (free from aistudio.google.com, no payment method): `supabase secrets set GEMINI_API_KEY=paste-your-key-here`, then `supabase functions deploy study-generate`.
2. **Demo students with study material.** Authentication -> Users -> Add user, twice: `sample.student.a@zutlib.test` and `sample.student.b@zutlib.test`, each with a password you choose and "Auto Confirm User" ticked. Then run `scripts/seed_study_demo.sql` in the SQL Editor. It approves both accounts and gives them sample notes, a deck and a quiz. Run it again before each demo to reset them.

Sample data is for demonstration only. Every sample book and paper shows a "Sample" label in the app, and every sample PDF opens with "SAMPLE PAPER. NOT AN OFFICIAL ZUT EXAMINATION." Remove all of it with `python scripts/sample_data.py remove`.

### Before the demo

Do these the day before, then tick them again an hour before.

- [ ] All 14 migrations applied; `rls_negative.sql`, `study_rls.sql`, `roles_rls.sql` and `study_kits_rls.sql` all PASS.
- [ ] One study kit already built with AI from your lecture-notes PDF (so the demo does not wait on Gemini), and one public YouTube lecture link copied.
- [ ] `admin-users`, `decide-request` and `study-generate` deployed; `register` deleted; `GEMINI_API_KEY` set.
- [ ] Authentication: Confirm email ON, sign-ups ON, minimum password 8, Site URL is the web app address, redirect URLs added, all three email templates pasted (invite, confirm signup, reset password). SMTP settings untouched.
- [ ] You can sign in as your administrator (made with `scripts/bootstrap_accounts.sql`).
- [ ] Admin -> Create account -> **Send test invite** to your own second inbox shows "sent", and the email arrives with the ZutLib wording.
- [ ] A librarian account invited from the app, invite accepted, password chosen, signed in once.
- [ ] One student signed up from the app with a real inbox, email confirmed, left **waiting** (not approved) to approve live.
- [ ] `python scripts/sample_data.py seed` run; Browse shows sample books (some with 0 available) and papers from 2019 to 2025.
- [ ] `scripts/seed_study_demo.sql` run.
- [ ] One short PDF of your own lecture notes saved on the demo device.
- [ ] Backup accounts in case email is slow: a second approved student and a second librarian, made the same way and listed in `scripts/bootstrap_accounts.sql`.
- [ ] Sample student A signed in in a spare browser profile, as a fallback if Gemini is busy.
- [ ] Web app running at the Site URL (`flutter run -d chrome --web-port 5000`), each account in its own browser profile so switching takes one click.

## 2. Demo script (under 3 minutes)

| Time | Do | Say |
|---|---|---|
| 0:00 | Show the sign-up screen: full name, department, email, password. | "Anyone can sign up, but only as a student, and only after confirming their email." |
| 0:10 | Sign in as the waiting student. The waiting screen appears. | "Until an administrator approves them they see only this. The database refuses them everything else, not just the app." |
| 0:25 | Administrator window: **Dashboard**, then **Review waiting students**, **Approve**. | "Staff accounts are never self-made. Every approval, rejection and suspension is in the audit log." |
| 0:40 | **Create account**, role Librarian. Point at the text under the form. | "The new librarian gets an invite email and picks their own password. I never see it." |
| 0:55 | Librarian window: **Library**, **Add a book** with 2 copies; then **Import books from CSV** and show the per-row report. | "The database will not allow more copies on loan than exist." |
| 1:15 | Student window (now approved): search "ICT 2010", filter by year. Open a paper with the **Sample** label. | "Full-text search with filters. The PDF opens through a link that expires in five minutes." |
| 1:30 | Open a book with copies left, **Ask to borrow a copy**. Librarian approves it. | "The request carries the student's name, department and email from their verified profile, not from what the app sends." |
| 1:50 | Back on the paper, tap **Study this with AI**. The kit opens and builds: one request makes the guide, flashcards and questions. | "Gemini reads the PDF on the server. The key never leaves Supabase, and the student has 10 requests a day." |
| 2:05 | Open the kit you built yesterday. **Study guide**, then **Smart study**: answer one, rate it. | "Smart study keeps asking what you get wrong until you master it. The level bar is saved in the database." |
| 2:20 | **Flashcards**, **Deck**: flip a card, **Got it**. Then **Games**, **Matching**. | "Spaced boxes, plus two games with a scoreboard." |
| 2:35 | **Test**: 5 questions, Hard, 5 minutes, **Create test**, answer two, **Hand in**. | "The database marks the test, so a score cannot be faked." |
| 2:50 | Optional: show `roles_rls.sql` results, all PASS. | "Every rule I described is tested." |

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
- **One source per kit.** A kit holds one PDF, one video or one library item, plus typed notes. Several PDFs need several kits.
- **Building again replaces.** "Build again" makes a new guide, deck and question bank and removes the old ones, with their progress.
- **PDF download.** The study guide downloads as a PDF using the IBM Plex font fetched from Google Fonts; offline it falls back to the built-in font.

- **Free-tier limits.** Gemini's free quotas are per project and shown only in Google AI Studio. If many students use AI at once Gemini may answer "busy"; the app says so. If AI Studio shows a daily quota below 150, lower `study_ai_project_daily_limit()` in migration 0010.
- **Large or scanned PDFs.** PDFs over 10 MB are refused. A scanned PDF is read as images, which works but is slower; a very long PDF may take longer than the 100 second wait, in which case the student is told the AI did not answer and can try one chapter instead.
- **AI can be wrong.** Summaries, cards and quiz answers can contain mistakes. The app says so next to the AI buttons, and students can edit or delete anything AI writes.
- **Free-tier privacy.** Google states that content sent on the free tier is used to improve its products. Students should not upload personal or confidential material for AI. Notes and PDFs never sent to AI stay in ZutLib only.
- **Counted even when it fails.** A request that reaches Gemini uses one of the day's requests even if the answer is then rejected, because it used free quota either way.
- **Invites open on the web.** The invite link opens the web app. On Android, a new librarian or administrator accepts the invite in a browser first, then signs in on the phone.
- **Not run against the live project.** The database rules, edge functions and sample loader were tested against a local Postgres 16 and PostgREST with a stand-in for Supabase Auth and Storage, and Gemini was replaced by a fake in tests. The Flutter code could not be compiled where it was written; run `flutter analyze` and `flutter test`.
