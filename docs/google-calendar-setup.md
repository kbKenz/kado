# Local Google Calendar setup

The local implementation connects one Google account and imports its primary calendar. OAuth credentials must be created in your Google Cloud project before the Connect button is enabled. Task creation and the internal Calendar tab work without Google configuration.

## Configure your Google project

1. Open [Google Cloud Console](https://console.cloud.google.com/) and select or create the project's Google Cloud project.
2. Enable **Google Calendar API** in APIs & Services.
3. In **Google Auth platform**, configure Branding and choose an External audience for a personal Google account. Keep the app in Testing and add your Google account under Audience → Test users.
4. In Data Access, add `https://www.googleapis.com/auth/calendar.events.readonly`. This implementation reads events and does not write to Google Calendar.
5. Create an **iOS** OAuth client. Its bundle ID must match the main app's `PRODUCT_BUNDLE_IDENTIFIER`. The current upstream project uses `dev.scastiel.kado`; configure the credentials again when the fork receives its independent bundle ID and signing team.
6. Copy the iOS client ID and its reversed client ID from the client details. The iOS client ID is a public app identifier. Do not create or embed a client secret, access token, or refresh token in this repo.

The official setup guides explain [iOS client configuration](https://developers.google.com/identity/sign-in/ios/start-integrating), [consent and test users](https://developers.google.com/workspace/guides/configure-oauth-consent), and [Calendar scopes](https://developers.google.com/workspace/calendar/api/auth).

## Supply local build configuration

Create **`Config/GoogleCalendar.local.xcconfig`** with these values, replacing the example identifiers:

```xcconfig
GOOGLE_CALENDAR_CLIENT_ID = 1234567890-example.apps.googleusercontent.com
GOOGLE_CALENDAR_REVERSED_CLIENT_ID = com.googleusercontent.apps.1234567890-example
```

This file is ignored by Git. The committed `Config/GoogleCalendar.xcconfig` includes it optionally and is the base configuration for both Debug and Release of the main app target. The `Info.plist` resolves these settings into `GIDClientID` and `CFBundleURLSchemes`. Runtime validation checks that the ID and registered reversed URL scheme match, and keeps connection disabled if configuration is missing.

Open `Kado.xcodeproj` in Xcode with an appropriate Apple signing team. Resolve packages: the app links the official [GoogleSignIn-iOS 10.0.0](https://github.com/google/GoogleSignIn-iOS/releases/tag/10.0.0) `GoogleSignIn` and `GoogleSignInSwift` products. Widgets do not link these products. The SDK manages the browser consent flow and Keychain token storage; the app does not serialize credentials into backups or CloudKit.

## Connect and check the behavior

1. Run the signed app on a device or supported simulator.
2. Open Settings → Google Calendar and use the Google sign-in button. Select your configured test account and grant the requested Calendar access.
3. Create **Meeting with Thomas** in the connected Google account's **primary** calendar, dated within the next 180 days.
4. Return to the app, wait for its next active-app refresh, or tap **Sync now**. The meeting should appear as an imported task and planned Calendar item with its original title/start/end.
5. Sync again. There should still be one task for the occurrence.
6. Change its time and title in Google Calendar; sync again. The existing task and block should update.
7. Complete the task in the app; sync again. Completion should remain set. Completing it does not modify the Google event.
8. Cancel or delete the Google event; sync again. Its task and planned block should leave the active planner. The stored task and blocks retain completion history, with remote cancellation recorded separately from your local archive choice.
9. Check an all-day event and a recurring meeting, including one rescheduled occurrence.
10. Disconnect. Local imported tasks remain available for history and export. To additionally revoke the consent grant at Google, use [Google Account connections](https://myaccount.google.com/connections).

This is a validation checklist to run once credentials and a usable iOS runtime are available; it does not claim a live Google account was tested during development.

## Current sync limits

- One connected account, primary calendar only.
- Bounded snapshot: 30 calendar days before today through the next 180 days inclusive.
- Every page must load successfully before importing and reconciling the snapshot.
- Sync after connecting, when the app opens or returns to the foreground (throttled to at most once per minute), every minute while it remains active, and on manual refresh. The active-app loop waits one minute after each attempt; request duration can lengthen the interval.
- Google meetings become local tasks. Changes made in Google own the imported title and planned time. Completion stays local.
- Dev mode pauses imports and account connection so external events do not populate the disposable demo dataset.
- No webhook server or realtime delivery while the app is closed. Background refresh can be added later, subject to iOS scheduling.
- Disconnect signs out this device and removes local SDK credentials. It keeps imported history and does not revoke Google's server-side permission grant automatically.

For a calendar picker later, add the specific calendar-list permission and keep source identity scoped by account and calendar. For incremental sync, build a separate source cache; the Calendar API disallows combining `syncToken` with the bounded time filters used here. See [the research notes](google-calendar-research.md).

## Common setup problems

| Symptom | Check |
|---|---|
| Setup required in the app | Confirm the local xcconfig exists, the iOS client ID has the expected suffix, and the registered URL scheme is the exact reversed ID; rebuild |
| Google rejects sign-in | Check bundle ID, test-user email, enabled Calendar API, audience, and requested scope in your Google project |
| Account connects but Calendar access is missing | Reconnect and grant the Calendar scope; declining it leaves local tasks usable |
| A meeting is absent | Confirm it is on the primary calendar, inside the imported date window, and that the last sync succeeded |
| Data is stale while the app is closed | Open the app or use Sync now; the current implementation syncs in the foreground |
| Signing or Keychain errors | Use the correct Apple development team and a signed native build |

Public release requires a final independent app identity, applicable Google OAuth verification, accurate App Store privacy answers for Google's optional SDK (including its disclosed SDK analytics), and CloudKit schema deployment for the new task/schedule entities. See [the fork's updated privacy policy](../PRIVACY.md).

## French localization review

The new task, Calendar, Google connection, and backup strings have contextual
English entries and French drafts in `Kado/Resources/Localizable.xcstrings`.
Every newly added French string is marked **needs_review**. Existing French
translations were preserved. A native French review of the new copy is pending;
these drafts are for local development and are not approved release translations.
Check Google connection guidance, optional time labels, imported task removal,
VoiceOver actions, and the expanded backup summary before committing a release.
