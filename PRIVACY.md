# Kadō — Privacy Policy

The personal fork stores your planning data on your device. Its developer
does not operate a server that receives your habits, tasks, calendar events,
or completion history. Google Calendar is an optional connection described
below.

## What Kadō stores

Your habits, tasks, completions, planned schedule blocks, reminders, and
settings are stored locally using Apple's SwiftData framework and system
preferences. Imported Google Calendar content becomes part of this local
planning data.

## iCloud sync (optional)

If you enable iCloud sync, your data is replicated across your own
Apple devices using Apple's CloudKit framework. It is stored in your
private iCloud container under your Apple account. The developer has no
access to the private planning records. Imported task/event content is
included when iCloud sync is enabled; Google authorization credentials
are not stored in SwiftData or CloudKit.

## Google Calendar (optional)

Connecting Google Calendar opens Google's account consent flow through
the official Google Sign-In SDK. The app requests read access to Calendar
events and reads the connected account's primary calendar directly from
Google over HTTPS. It imports event titles, notes, dates/times, all-day
status, event links, and source identifiers as local tasks and planned
schedule blocks. The connection displays your Google account email and
uses your account identifier to keep event imports distinct.

The Google Sign-In SDK stores authorization credentials in the device's
Keychain and refreshes them with Google when needed. The app does not
include access or refresh tokens in its local planning database,
CloudKit records, or JSON/CSV backups. Google receives the API requests
needed to authorize and fetch your calendar.

Google's SDK has its own authentication and service-use data practices.
Its privacy manifest declares account/contact information, identifiers,
coarse location, and usage information for functionality and SDK analytics,
and declares that it does not track users across apps. Refer to
[Google's SDK data disclosure](https://developers.google.com/identity/sign-in/ios/app-privacy),
the [SDK privacy manifest](https://github.com/google/GoogleSignIn-iOS/blob/10.0.0/GoogleSignIn/Sources/Resources/PrivacyInfo.xcprivacy),
and [Google's Privacy Policy](https://policies.google.com/privacy).

Sync runs after connecting, on app foreground, and when you choose Sync
now. The current integration does not send local task completion back to
Google. Disconnect removes this device's saved SDK credentials and stops
imports. Imported tasks and completion history remain until you delete
them. You can additionally revoke the app's Google authorization through
[Google Account connections](https://myaccount.google.com/connections).

## Dictation and text cleanup (optional)

Text fields can offer a microphone button for dictation and a cleanup
button that tidies grammar and filler words. Both run entirely on your
device:

- **Dictation** uses Apple's Speech framework with on-device recognition
  required. Audio is processed in memory while you dictate and is never
  stored or sent, to the developer or to Apple's speech servers. Where
  your device has no on-device speech model, the microphone button is not
  shown. The first use asks for microphone and speech recognition access;
  you can change either at any time in Settings.
- **Cleanup** uses Apple's on-device Foundation Models (iOS 26 with
  Apple Intelligence turned on). The text you choose to clean up is sent
  to the model on your device only. Nothing is stored beyond the text
  you keep in the field.

## Export and import

JSON and CSV backups include your planning records, including imported
event content and source identifiers. They exclude Google credentials.
You choose where to save or share the backup; protect it as you would
the underlying calendar and task data.

## Third-party services

The app adds no developer analytics, advertising, or crash reporting
services. Dictation and text cleanup use only Apple frameworks running on
your device. The optional Google Sign-In SDK is used for Google account
authorization; its own data practices are described above. Local tasks,
habits, and the internal calendar remain usable without a Google account.

## Contact

Questions about this fork can be raised at
[kbKenz/kado issues](https://github.com/kbKenz/kado/issues).

Last updated: 2026-10-04
