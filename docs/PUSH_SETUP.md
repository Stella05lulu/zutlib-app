# Phone push notifications (Firebase Cloud Messaging)

ZutLib uses Supabase for everything, and Firebase for one job only:
delivering a notification to a phone while the app is closed. Android only
accepts push through Firebase Cloud Messaging (FCM), which is free.

What already works **without** this setup:

- Every notification appears in the bell at the top right of the app, live
  (Supabase Realtime).
- Study reminders and due-date reminders pop up on the phone, because the
  app schedules them on the phone itself (no server, works offline).

What this setup adds: push for messages the phone cannot know in advance,
such as "Approved", "New past paper for EEE 2011" or "New borrow request",
while the app is closed.

Cost: free on Android and the web. Push to iPhones needs Apple's paid
developer account (about 99 US dollars a year); skip iPhones unless you
demo on one.

## Part A: the server (about 10 minutes)

1. Go to console.firebase.google.com, sign in with a Google account, and
   **Create a project** named `zutlib` (Google Analytics: off).
2. Project settings (gear icon) -> **Service accounts** -> **Generate new
   private key**. A JSON file downloads. Keep it private: never put it in
   the app or the repository.
3. In PowerShell, in the zutlib folder, store it and a webhook secret in
   Supabase (replace the path, and make up any long random text for the
   secret):

        supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(Get-Content -Raw C:\path\to\zutlib-firebase.json)"
        supabase secrets set PUSH_WEBHOOK_SECRET=paste-a-long-random-text-here
        supabase functions deploy push --no-verify-jwt

4. Supabase dashboard -> **Database -> Webhooks -> Create a new hook**:
   - Name: `push`
   - Table: `notifications`, Events: **Insert**
   - Type: **Supabase Edge Functions**, function: `push`, method POST
   - HTTP headers: add `x-zutlib-push-secret` with the same text as
     `PUSH_WEBHOOK_SECRET`
   - Create.

From now on every new notification row calls `push`. Until a phone has
registered (part B), `push` finds no phone and sends nothing, which is fine.

## Part B: the app (needs one command on your computer)

1. Install the FlutterFire tool once:

        dart pub global activate flutterfire_cli

2. In the zutlib folder:

        flutterfire configure --project=<your Firebase project id> --platforms=android,web

   It registers the Android app (`zm.ac.zut.zutlib`) and the web app with
   Firebase and writes `lib/firebase_options.dart` and
   `android/app/google-services.json`.

3. Tell Claude it is done. The app side (asking permission, sending the
   phone's token to Supabase with `register_device`, and opening the right
   screen when a notification is tapped) is about 40 lines that need the
   file from step 2 to compile, so it is added after this step.

## How it fits together

    something happens (approval, new paper, due date, new sign-up)
      -> a row in public.notifications       (database trigger, daily job, or server function)
      -> the bell updates in the app          (Supabase Realtime)
      -> the webhook calls the push function  (Database Webhook)
      -> Firebase delivers it to each phone   (FCM, using the service account)

Phone tokens live in `public.device_tokens`; a phone belongs to whoever
signed in on it last, and tokens Firebase reports as gone are deleted.
The tests are in `supabase/functions/push/tests/push_test.ts`.
