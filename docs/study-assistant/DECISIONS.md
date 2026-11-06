# Study assistant: decisions

Every choice made while building the module, one line each, with the reason. Recorded instead of asking.

## Data and database

- **Tables are prefixed `study_`** (study_notes, study_summaries, study_decks, study_flashcards, study_quizzes, study_quiz_questions, study_quiz_attempts, study_ai_usage, study_ai_cache): keeps the module visibly separate from the borrowing tables in the same schema.
- **One migration, `0010_study_assistant.sql`**: the existing project numbers its migrations; the next number keeps them in order and existing files untouched.
- **`user_id` defaults to `auth.uid()` and students cannot write the column** (column privileges): ownership comes from the signed request, never from the app.
- **Child rows carry the owner too, joined by a two-column foreign key `(parent_id, user_id)`**: a card can never point at another student's deck even if a policy were wrong. This is defence in depth on top of RLS.
- **Owner is `profiles(id)`, not `auth.users(id)`**: matches the existing tables and means only accounts with a profile can own study data.
- **Study features are for active students only** (`is_student()`, which since 0012 also requires status `active`, in every policy, a router guard in the app): the brief describes a student feature; staff get no rows and the tab is hidden.
- **Deleting a note: summaries are deleted with it; decks and quizzes are kept with `note_id` set to null; AI cache entries are deleted**: a summary only makes sense beside its note, but cards a student studied and scores they earned should not vanish.
- **`ON DELETE SET NULL (note_id)` column list**: needs Postgres 15 or newer; the project's config.toml says major_version 17, and the local test ran on 16.
- **Length limits**: note title 200, note body 20,000, course code 20, summary 5,000, deck and quiz titles 200, card front 500, card back 1,000, question 500, option 200, explanation 1,000 characters. Long enough for real lecture notes, short enough to keep rows small on the free database.
- **Quiz options are a `text[]` of 2 to 6 distinct, non-blank entries, and the correct answer is one integer `correct_index`**: "exactly one correct option" is then true by construction; a CHECK keeps the index inside the list.
- **Quiz attempts are marked by a database trigger**: the app sends only the chosen options; the trigger checks each answer belongs to the quiz and is a real option, counts the correct ones and writes `score` and `total`. Students cannot write `score` and attempts have no update policy, so a score cannot be forged or edited.
- **Unanswered questions count as wrong**: the simplest honest rule; the app warns before marking.
- **Row caps per owner or parent** (300 notes, 100 decks, 100 quizzes, 200 cards per deck, 50 questions per quiz, 20 summaries per note, 200 attempts per quiz): without them one account could fill the free 500 MB database through the public API.
- **Explicit `revoke all` before the grants**: some Supabase projects expose new tables to every API role automatically; this project's 0004 says it does not, but the migration must be safe either way. The local test deliberately ran with the permissive defaults.
- **Students may read but never write `study_ai_usage` and `study_ai_cache`**: writing usage would reset the limit; writing cache would plant unvalidated "AI" content.
- **The `source` column ('manual' or 'ai') is not writable by students**: the AI label on screen is therefore trustworthy.
- **`updated_at` reuses the existing `touch_updated_at()` trigger function**: no duplicate code.

## AI layer

- **Model: `gemini-3.5-flash-lite`**, in `supabase/functions/study-generate/config.ts` as `GEMINI_MODEL`. Checked on 22 October 2026 at ai.google.dev/gemini-api/docs/models (stable; the page recommends "3.5 Flash-Lite or 3.8 Flash" for new projects) and ai.google.dev/gemini-api/docs/pricing (Free Tier: input and output "Free of charge"). Flash-Lite is the cheaper and faster of the two, which suits short study tasks and a free quota.
- **API: REST `models/{model}:generateContent`** with the key in the `x-goog-api-key` header and `generationConfig.responseMimeType: "application/json"` plus `responseSchema`. Checked against ai.google.dev/api/generate-content and the generateContent example in ai.google.dev/gemini-api/docs/migrate-to-interactions, which says "generateContent remains fully supported". The newer Interactions API was not used: its default `store=true` keeps conversations on Google's side, which this feature does not need.
- **Thinking settings, temperature and safety settings are left at Gemini's defaults**: the field names for thinking on generateContent were not confirmed in the pages read, so nothing was guessed.
- **`maxOutputTokens` 8,192, timeout 45 seconds**: a cut-off answer is invalid JSON and would be thrown away, so the cap is generous.
- **Free-tier limits could not be read from the docs**: ai.google.dev/gemini-api/docs/rate-limits (updated 15 October 2026) says per-model free limits are shown in AI Studio, are applied per project, and daily quotas reset at midnight Pacific time. So the module sets its own, conservative caps instead of relying on Google's.
- **Daily limits: 10 requests per student, 150 for the whole project**, stored only in the database (`study_ai_daily_limit()`, `study_ai_project_daily_limit()` in 0010). The project cap keeps all students together well inside a free quota whatever its exact size; if AI Studio shows a lower daily figure for this model, lower the project cap there. The app reads both numbers back through `study_ai_status()`.
- **"Today" is the calendar day in Africa/Lusaka**: students' allowance renews at their own midnight.
- **A request counts against the limit when Gemini is actually called**, including calls that then fail or return unusable output: each call costs free quota either way. Cache hits cost nothing.
- **The limit is checked before the cache, as the brief orders**: a student at their limit is refused even for an unchanged note.
- **Limit consumption is atomic** (an advisory lock in `study_ai_consume`): two requests at once cannot both take the last slot.
- **Input cap: 12,000 characters of title plus body per request** (`MAX_INPUT_CHARS`): roughly 3,000 tokens, a full set of notes. Notes may be longer (20,000); those are refused for AI with a message to split them, and still work manually.
- **Cache key: note id + SHA-256 of (title, newline, body) + type**, with the hash computed by the database (`study_note_hash`) so the edge function and the cache can never disagree. When a note changes, the old cache entry for that type is replaced.
- **A cache hit returns the existing item if it still exists, or recreates it from the cached result**: pressing the button twice never makes two copies, and deleting an AI summary then asking again costs nothing.
- **If the note is edited while Gemini works, the result is not saved** (hash re-checked in `study_ai_store`): a result is never filed against content it was not made from.
- **All edge-function database work goes through `study_ai_*` functions callable only with the service role**, each taking the user id the function has just verified and checking ownership itself. Students cannot call them (tested).
- **The edge function uses plain `fetch` to Supabase's REST endpoints rather than supabase-js**: five calls only, no external download at deploy time, and it could be tested end to end locally against real PostgREST.
- **Output schemas**: summary `{summary}`; flashcards `{cards: [{question, answer}]}` (1 to 20); quiz `{questions: [{question, options: [{text, is_correct}], explanation}]}` (1 to 15 questions, 2 to 6 options, exactly one `is_correct: true`, no repeated options). Extra fields, wrong types, empty text or anything over the database limits are rejected and nothing is stored. The database checks the same shapes again when saving.
- **Titles of AI decks and quizzes come from the note title, not from the model**: less model text reaches the database.
- **Prompt injection**: the note is wrapped in `<note>` tags, any `<note>` or `</note>` inside it is neutralised, and the system instruction says to treat it as untrusted and ignore instructions in it. The end-to-end test note contains "Ignore all previous instructions"; the validator would reject anything off-schema regardless.
- **Logs**: one JSON line per request with event name, type and outcome code. No note text, no model output, no keys (tested).
- **Errors return `{error, message}`**, the same shape as the existing functions, so the app's existing `Failure.from` shows the message. Gemini HTTP 429 becomes "busy" (503); other failures 502.
- **The edge function keeps Supabase's default JWT verification at the gateway and also checks the token itself** with `/auth/v1/user`.

## App

- **New theme file `lib/core/theme/app_theme.dart`, applied only to study screens through `StudyScope`**: the brief's visual rules (IBM Plex, no gradients, no shadows, no pure white or black) conflict with the existing `lib/core/theme.dart` (Inter, gradients, pure white and black). Rewriting the existing theme would change every existing screen, which the brief forbids, so the study module gets its own theme without touching the rest of the app. (Superseded in version 2: the whole app now uses this theme; see "One look for the whole app".)
- **Palette**: greys for structure, light blue (`sky`) only for AI labels, the correct answer and the back of a flashcard, and one accent (burnt orange) for the main action, the selected tab and errors. Burnt orange is not purple, neon or pastel and reads clearly in both modes.
- **Errors use the accent colour and correct answers use the light blue**: keeps to one accent instead of adding red and green.
- **Messages stay inline (`InlineNotice`) next to what they are about**, not in SnackBars.
- **Rows are a custom `StudyRow` inside a bordered `RowGroup`**, not ListTile or elevated Cards.
- **The Study tab sits between "My borrowing" and "Updates"** in the student bottom bar; detail screens open full screen above it, like the existing resource screens.
- **The app repeats the database's text length limits in `StudyLimits`** (lib/models/study.dart) only to show a character counter while typing. The database remains the authority; the AI input cap and daily limits are not repeated anywhere.
- **Study mode is practice only and saves nothing**: cards marked "Not yet" come round again until each is known once; the result is shown on screen.
- **Seed data is SQL (`scripts/seed_study_demo.sql`) after creating two users in the dashboard**: the same pattern as `scripts/bootstrap_accounts.sql`, and no password is stored in the repository. The script also sets both demo students to active.
- **No new packages were added**: everything uses packages already in pubspec.yaml.

## One look for the whole app, and a logo (version 2)

- **Every screen now uses the flat study theme** (`lib/core/theme/app_theme.dart`): IBM Plex, grey structure, one blue accent, no gradients, glass, glows or shadows. This replaces the earlier decision to keep the study module's theme separate: the student asked for the whole app's UI and UX to be fixed, and two visual languages in one app (glass on Explore, flat on Study) was the biggest consistency problem. `lib/core/theme.dart` keeps its `Palette`, `Insets` and `Corners` names so no screen had to be rewritten; they now point at the study colours and radii.
- **Bottom navigation is a standard labelled bar** instead of a floating icon-only glass pill: every tab is named, the unread count is a badge rather than part of the label, and pages no longer scroll under the bar.
- **Explore leads with search.** The large avatar greeting and the promo banner (which repeated the search hint) are gone; the page title and one line of context sit above the search box.
- **Catalogue tiles use one solid colour per resource type**, from the same palette as study kits.
- **Resource details put the actions under the title**, before the details list, so "Open the PDF", "Ask to borrow" and "Study this with AI" are visible without scrolling on a phone.
- **Logo: concept B, a bookmark with a Z cut through it**, chosen by the student from three concepts. Drawn in code (`ZutLibMark`), with SVG masters and rendered icons in `docs/brand/`.

## Build plan of 4 November 2026 (migrations 0016 to 0021)

- **Four ranked roles: student, librarian, admin, super admin.** Everyone acts only on accounts ranked below them, and nobody changes their own role or status. The rule is in `admin_apply` and a trigger on `profiles`, so the app, the Edge Function and even a direct API call all meet it.
- **A super admin is never made by the app.** Sign-up always makes a pending student, `admin_apply` and `admin_after_invite` refuse the role, and the trigger refuses it unless "break glass" is on for the current transaction, which only `scripts/restore_super_admin.sql`, run in the dashboard, does. The last active super admin cannot be demoted, suspended, removed or deleted.
- **Removal is a soft delete** (status `removed`). Nothing is deleted, so the audit log keeps its actors and a super admin can restore the account. Removing and restoring need a reason.
- **Account tools are super admin only and each needs a reason**: edit name, department and student number; change email (the new address gets a reset link); send a reset link; sign out everywhere; restore. Admins never see or set passwords. The Auth part runs in `admin-users` with the service role; the database part and the audit entry are one `security definer` call.
- **The audit log is append-only.** Insert, update and delete are revoked from every API role, the service role included for update and delete, and a trigger refuses changes from anyone but the database owner. Every entry is written by a trigger or a `security definer` function, never by the app.
- **System settings are one row** (`settings`): loan period, most active borrows per student, sign-up open. The database sets due dates and refuses an extra borrow request from these values, and sign-up is refused in the `auth.users` trigger when closed (invited accounts still work). Each change is audited with the values before and after.
- **Multi-source kits keep the old source where it was.** A kit made before 0020 keeps its one source on `study_notes`, and that counts as the first source; extra sources go in `study_note_sources`, which has the same owner rules as every study table. Limits: 5 sources and 30 MB of PDFs per kit. Nothing is copied or moved, so no existing kit can lose data.
- **One build is one request, however many sources.** `study-generate` sends every source in one Gemini call and counts it once against the 10-a-day allowance. Counting per source would make a five-source kit cost half a day's allowance for one build, which would push students towards one big PDF instead of the right materials. The cache key fingerprints all sources together, in order, so a kit with unchanged sources is answered from the cache and costs nothing.
- **Dashboards are live queries** (`admin_dashboard`, `librarian_today`, `admin_badges`), each checking the caller's role. Nothing is stored or precomputed.
- **The audit activity panel is worked out on the phone** from the last seven days of entries (`lib/study/audit_stats.dart`, unit tested): events per day, the week's total, the busiest day, and a breakdown by kind with each share. It follows the flat style: one accent colour and a thin line, no donut of many colours.
- **My progress and "Revise next" are rules, not AI** (`lib/study/progress.dart`): a question is suggested when it was wrong in at least half of the student's recent tries, with the reason in words.
- **View as is read-only data, not a session.** `view_as_start` checks the caller is an active super admin, writes an audit entry, and returns what that student or librarian would see: profile, loans, saved items, announcements. It never returns study notes or kits, and never makes a token for the other person. The screen shows a "Viewing as" banner and has no buttons that change anything; the data comes from a function that changes nothing.

## Plans, notifications and the rest of the proposal (migration 0015)

These close the gaps between the proposal's requirements and the app (multi-tenancy is future work).

- **Plan is a main tab, built from a study kit.** One plan per kit: exam date, study days (a 7-bit mask), minutes per session (15 to 90). The plan is never stored as tasks. It is worked out each time by `lib/study/planner.dart` from the settings, the kit's content and progress, and what the student did each day, so it adapts by itself: sections missed earlier come back as catch-up. Phases: the first ~40% of study days Learn (read the guide, learn cards), the next ~40% Practise (Smart study weakest first, review cards), the last ~20% Test (practice tests, a mock exam two study days before, a light review on the last day). Every task carries a one-line reason, as the literature review's point on explainable recommendations requires.
- **Tasks tick themselves from activity.** `study_activity` counts cards rated, questions answered, tests taken and guide sections read per kit and day. It is written inside the existing rating functions and a trigger on test attempts, never by the app, so the counts cannot be inflated by hand. Students can also tick a task by hand (`study_plan_checks`).
- **The bell replaces the Updates tab.** It sits at the top right of every main screen, for every role, and updates live through Supabase Realtime. Tapping a notification opens its link.
- **Notifications come from the database where possible.** Triggers notify students of new papers for their courses (never for sample data), librarians of new borrow requests, and administrators of new sign-ups. A daily pg_cron job at 07:00 Zambia time sends due-in-2-days, due-today and overdue (days 1, 3, 7, 14) reminders, a daily overdue summary for librarians, and exam reminders 3 days and 1 day before. Every message has a de-duplication key, so the job can run twice safely. Overdue loans are not given a new status, because a return is only allowed from "collected".
- **Push: Supabase decides, Firebase delivers.** Android only accepts push through Firebase Cloud Messaging, so Firebase is used for delivery alone (the proposal names FCM). A Database Webhook calls the `push` function, which signs in to Google with the service account kept in Supabase secrets. Study and due-date reminders are scheduled on the phone with flutter_local_notifications, so they work without Firebase and offline.
- **Students edit their own profile through one function** (`update_my_profile`): name, department, year, courses, reminder time and notification switches. Email, role and status stay with administrators.
- **Onboarding** runs once for students: three short pages, then year, courses and reminder time, which seed recommendations (the cold-start answer from the literature). Staff skip it.
- **Recommendations are rules, not AI**: an upcoming exam for the course scores highest and rises as it nears, then courses the student takes, courses studied recently, and same department and year level; newer papers break ties. Free, instant, testable, and each suggestion says why.
- **Usage events have no user id** (`usage_events`): searches by course, items opened, kits built, plans created, tests taken. Reports are aggregates only, from `admin_reports()`, with a PDF download.
- **Offline**: the last copy of the study kits, catalogue home, borrowing and notifications is kept per account on the device (shared_preferences) and shown with an "Offline" strip when the network fails. It is cleared on sign-out. Writes always need a connection.
- **Re-authentication**: deciding a borrow request or changing an account asks for the password again when the last sign-in was over 15 minutes ago.
- **Packages added**: flutter_local_notifications 19.5.0 (pinned: version 20 renamed its parameters) and timezone. Both free. Android needed core library desugaring and two notification permissions.

## Study kits (migration 0014)

- **A note is now a "study kit"**: the same `study_notes` row with a `color` and an optional `youtube_url`. No new parent table, so every earlier note, deck and quiz keeps working; decks and quizzes with no kit show under "Other decks and question banks".
- **One AI request builds the whole kit** (kind `kit`): study guide, 4 to 40 flashcards and 4 to 30 questions with difficulty, in one Gemini call, validated in the function and again in `study_ai_materialise`. This keeps a kit inside the 10-a-day free allowance (one kit costs one request instead of three).
- **Empty kits are allowed**: "Proceed without materials" makes a kit with no source. This replaces the 0013 rule that a note must have a source; the 0013 trigger now checks only that a library PDF is still studyable.
- **YouTube is sent as a `fileData` part with the video URL**, which Gemini reads on Google's side, so ZutLib downloads nothing. Only `https://www.youtube.com/watch?v=<11 chars>` is stored (the app normalises youtu.be and shorts links). The cache key is the URL's SHA-256.
- **Progress lives in the database** (`study_card_progress` boxes 0 to 3, `study_question_progress` stars 0 to 3), written only through `study_rate_card` and `study_rate_question`, so it follows the student between phone and web.
- **Tests are stored as a list of question ids** and marked by a trigger (`study_score_test`), like quizzes. Time limits are 0 (none) or 1 to 180 minutes; the app hands in when time runs out.
- **Games are Matching and True or false**, scored in the app and saved per deck; a top-10 board per game. Scores are capped and only ever the student's own.
- **The accent colour changed from green to blue** to match a learning product; colours are still flat, with no gradients or shadows, and no purple. Red, green and amber are kept for wrong, right and warning.
- **Guide download uses the `pdf` and `printing` packages** (free, open source), the only packages added.

## Study from PDFs (migration 0013)

- **A note has exactly one source: typed text, an uploaded PDF, or a library item**, enforced by a CHECK and a trigger. A typed note may still have text alongside nothing else; a PDF note may carry the student's own typed text as well, which is sent with the PDF.
- **Uploaded PDFs go to a new private bucket `study-files`, path `<user id>/<file name>.pdf`**, max 10 MB, `application/pdf` only, with storage policies on the first folder. Kept apart from the library's `resources` bucket so a student's files never mix with the catalogue.
- **Library PDFs are referenced, not copied** (`resource_id`, `on delete set null`): no duplicate storage on the free 1 GB. If the item is deleted the note stays and says its PDF is gone; a retired item cannot be studied.
- **Gemini receives the PDF inline as base64** (`inlineData`, `application/pdf`), checked at ai.google.dev/gemini-api/docs/document-processing on 22 October 2026. Inline is used instead of the Files API because the file is used once and inline needs no extra upload call or cleanup on Google's side.
- **10 MB cap** (`MAX_PDF_BYTES`) although Gemini accepts more: the Edge Function has 256 MB of memory and must hold the file plus its base64 copy.
- **The function checks the first bytes are `%PDF-`** before sending anything, so a renamed file is refused without using a request.
- **Gemini timeout raised to 100 seconds**: a PDF takes longer than text, and Supabase's free Edge limit is 150 seconds of wall time.
- **Cache key adds the SHA-256 of the PDF's bytes** (`study_note_hash(title, body, file_sha)`): replacing a library PDF with a corrected one makes a fresh result instead of returning the old one.
- **"Study this with AI" on a library item makes a note and opens it**, rather than generating straight away: the student chooses summary, cards or quiz, and the allowance is not spent by a mis-tap.

## Accounts and roles (migration 0012)

- **One `status` per profile: pending, active, rejected, suspended**, a Postgres enum. Every existing profile became active when the migration ran, so nobody already using the app was locked out.
- **`is_active()`, `is_student()`, `is_staff()`, `is_admin()` all require status active**, so every existing policy that used them now refuses pending, rejected and suspended accounts without being rewritten.
- **A trigger on `auth.users` makes the profile**, always as a pending student, reading only full name and department from the sign-up data. Anything else in the request, such as a role, is ignored. Invited accounts are then set to their role by the `admin-users` function.
- **Users cannot write `profiles` at all through the API** (insert, update and delete revoked). The only self-service change is `mark_password_set()`, which clears the "choose your password" flag after an invite.
- **A pending account can sign in.** It is shown the waiting screen, and the router sends every other path there. Blocking sign-in instead would leave the person unsure whether their sign-up worked.
- **Rejected and suspended accounts see the same waiting screen with the matching wording**, not an error.
- **Departments at sign-up are ICT, Engineering and Business**, the same list the catalogue uses.
- **All administrator actions go through one Edge Function, `admin-users`**, which checks the caller is an active administrator with the service role before acting. The database functions it calls (`admin_apply`, `admin_after_invite`) are callable only by the service role and check the actor again, so neither layer trusts the other.
- **Every administrator action writes an `audit_entries` row** (actor, target, action, detail) in the same transaction as the change; administrators can read the log, nobody can edit it.
- **An administrator cannot change their own role or status, and the last active administrator cannot be demoted or suspended** (trigger `guard_admin_roles`), so the project cannot be locked out by mistake.
- **New staff are invited, never given a password.** `admin-users` calls Supabase's invite endpoint; the person chooses their password on the Set password screen. The administrator never sees it.
- **The invite email links to the web app with `token_hash` and `type=invite`**, and the app calls `verifyOTP`, instead of using `{{ .ConfirmationURL }}`. The confirmation URL logs the person in through a redirect that loses the session on some browsers and gives the app no way to tell an invite from a password reset; the token hash keeps both under the app's control.
- **"Send test invite" invites the given address as a suspended student with a note in the audit log**, so the administrator can see a real email arrive without creating a usable account. It can then be deleted from Authentication -> Users.
- **Rate limits are shown as a countdown**, not an error: Supabase's 429 answers and the function's `rate_limited` code carry the wait in seconds, and the button counts down.
- **The first administrator is made by `scripts/bootstrap_accounts.sql`** after creating the user in the dashboard. No default email or password exists anywhere in the repository.
- **Administrators also see the librarian tools** (Library, Requests): the brief says administrators manage the system, and a small college may not have a separate librarian on the day.
- **`decide-request` now also requires the acting librarian or administrator to be active.**

## Library (migrations 0011 and 0012)

- **Books are rows of `resources` with type `book`**, not a separate table: search, detail, borrowing and copy counts already work on `resources`, and one catalogue keeps one search.
- **`book` is added to the enum in its own migration (0011)** because Postgres will not use a new enum value in the transaction that adds it.
- **Course code and academic year are optional for books and required for papers** (CHECK `resources_paper_fields`); author and total copies are required for books (`resources_book_fields`).
- **ISBN is optional, stored as digits only (and a final X), 10 or 13 characters**; a trigger cleans spaces and dashes so the CSV can be pasted from anywhere.
- **Copy counts change only through `set_book_copies()`**, which refuses a total lower than the copies currently on loan. Available copies are still bounded by CHECK constraints.
- **Books are retired, not deleted** (`retired_at`): borrowing history keeps pointing at a real row. Retired items leave search and cannot be requested, and can be brought back.
- **CSV import checks every row on the device first and reports each line**, then inserts the good rows; the database checks the same rules again, and a row the database refuses is reported by line too.
- **Bulk paper upload is a set of PDFs plus a CSV naming each file**, so department, course code, title, year and type are explicit rather than guessed from file names.
- **Search now includes author, ISBN and course title**, and skips retired items.

## Sample data

- **Every sample row has `is_sample = true`, a title starting "Sample", and a visible "Sample" label in the app**; every sample PDF starts with "SAMPLE PAPER. NOT AN OFFICIAL ZUT EXAMINATION." Nothing sample can be mistaken for real.
- **The loader is a Python script using only the standard library** (`scripts/sample_data.py`): the PDFs are written by a small built-in writer, so it runs on any machine with Python and needs no installs.
- **Sample rows use fixed ids (uuid5)**: seeding twice updates instead of duplicating, and `remove` deletes exactly those rows and files.
- **210 sample papers** (15 courses, 2019 to 2025, an exam and a test each year) with questions written for this project, and **40 sample books, 10 with no copies available**, so the "every copy is on loan" state can be shown.
- **Real data has its own command** (`import-real`) and is never flagged as sample.

## Requirement text this replaces

The addendum overrides these earlier statements. They no longer describe the system:

- "Eligibility is proved once, at registration, against the institutional roll." and the README principle "Eligibility precedes identity": students now sign up with name, department, email and password and are approved by an administrator. The `roll` table from 0001 is left in place but unused.
- "An account cannot exist unless the student number is on the roll, the surname matches it, and the record is unclaimed": removed; sign-up asks for neither student number nor surname, and the roll's claimed flag is no longer checked.
- Registration through the `register` Edge Function: the function is deleted (`supabase functions delete register`); sign-up uses Supabase Auth directly and a database trigger.
- The Student roll import screen and `scripts/generate_roll.py`: removed.
- "Staff accounts are made in the dashboard and given a role with `scripts/create_staff.sql`": replaced by the invite flow, with `scripts/bootstrap_accounts.sql` for the first administrator only.
- "The name, student number and programme on a borrowing request": requests now carry name, department and email.
- The old resource manager, upload and preview screens: replaced by the Library screen, book form, CSV import and paper upload.
- Study assistant limitation "One note at a time, text only. AI works from a single typed note; it cannot read PDFs": AI now reads uploaded and library PDFs.
