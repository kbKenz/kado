# Google Calendar integration research

Researched on 2026-10-04 against official Google and Apple documentation.

## Recommendation

Use Google's official **GoogleSignIn-iOS** SDK for account authorization and credential renewal, and a small Swift `URLSession` client for the Calendar REST API. Import the primary Google calendar into local tasks and schedule blocks. Keep completion local and independent of calendar event status. This is the implementation recommendation for the fork; the explicit request for Google connectivity supersedes the upstream project's older restriction on dependencies and networking.

The SDK is available through Swift Package Manager and has a SwiftUI sign-in button. The latest verified release is **10.0.0**, whose iOS 15 minimum is below Kadō's iOS 18 deployment target. Its dependency graph includes AppAuth, GTMAppAuth, GTMSessionFetcher and AppCheckCore. The getting-started page still shows an older version, so the release page and package manifest are the version references. [Official SDK repository](https://github.com/google/GoogleSignIn-iOS), [10.0.0 release](https://github.com/google/GoogleSignIn-iOS/releases/tag/10.0.0), [package manifest](https://github.com/google/GoogleSignIn-iOS/blob/10.0.0/Package%40swift-5.7.swift).

## Existing modules compared

| Approach | What it supplies | Fit for this app |
|---|---|---|
| GoogleSignIn-iOS + Calendar REST | OAuth, Keychain credentials, token refresh; we decode the events we use | Recommended for a direct Google connection with a small app-owned client |
| Google APIs Client Library for Objective-C for REST | Generated Calendar objects and API query classes, fetcher support | Official and valid, but a larger Objective-C API surface for this initial read/import feature |
| Apple EventKit | Events from accounts already configured in iOS Calendar | Useful later as a separate device-calendar integration; no Google OAuth project needed, but the account must be installed in device Settings |

Google's REST Objective-C client supports Swift Package Manager and generated service interfaces, including Calendar. It still needs authentication. Using it is reasonable if the app later needs a broad collection of Google API operations. Choosing the smaller native Swift REST client here is an engineering recommendation, rather than a Google requirement. [Official REST client](https://github.com/google/google-api-objectivec-client-for-rest).

For EventKit, iOS has no read-only calendar permission: fetching events requires full access and `NSCalendarsFullAccessUsageDescription`. The app can choose to perform only reads after receiving that access. Apple's store-change notification lets an active app refresh imported events. [EventKit access levels](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [EventKit access example](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui).

Google calendars can already sync into Apple Calendar through a Google account added in iPhone Settings. That makes EventKit an indirect Google path, with freshness controlled by the OS account sync. A direct SDK connection supports users who do not have their Google account configured in iOS Calendar. [Google instructions for Apple Calendar](https://support.google.com/calendar/answer/99358?co=GENIE.Platform%3DiOS&hl=en).

## Authorization and setup

Create a Google Cloud project, enable Calendar API, configure the OAuth consent screen, and create an **iOS** OAuth client for the app's bundle ID. Supply the client ID as `GIDClientID` and register its reversed client ID as a URL scheme. Route the SwiftUI app's `.onOpenURL` callback to `GIDSignIn.sharedInstance.handle(url)`. A device-only integration does not require a server client ID or an embedded client secret. [Google iOS setup](https://developers.google.com/identity/sign-in/ios/start-integrating), [SwiftUI integration guide](https://developers.google.com/identity/sign-in/ios/sign-in).

For personal local use, select an External audience in Testing and add the owner's Google account as a test user. Public distribution requires the relevant consent and scope verification steps. [OAuth consent configuration](https://developers.google.com/workspace/guides/configure-oauth-consent).

Request `https://www.googleapis.com/auth/calendar.events.readonly` for importing primary-calendar events. It grants event reads; a future calendar picker would additionally need an appropriate calendar-list scope. Broader event write access is unnecessary for importing meetings. [Calendar scopes](https://developers.google.com/workspace/calendar/api/auth), [calendar-list scopes](https://developers.google.com/workspace/calendar/api/v3/reference/calendarList/list).

Check `grantedScopes` after consent. Before API calls, ask the SDK to refresh tokens if necessary and put the resulting access token in the Bearer authorization header. Use the SDK's credential storage; never put OAuth tokens in SwiftData, CloudKit, JSON, CSV, logs, or committed files. [Google client API access](https://developers.google.com/identity/sign-in/ios/api-access).

## Initial sync shape

The initial implementation should fetch a bounded snapshot, from 30 calendar days before today through 180 calendar days after today, using `singleEvents=true` and `showDeleted=true`. Follow every page before reconciling local records. A recurring meeting becomes one imported task and schedule block per occurrence. Use account ID + calendar ID + Google event ID as the source identity; never use the title or current start time as identity. These choices are app design decisions.

`events.list` supports RFC3339 `timeMin` and `timeMax`, expanded single occurrences, paging, and cancelled results. `timeMin` filters the event's end and `timeMax` filters its start, which includes events overlapping the window. A `syncToken` query **cannot** be combined with `timeMin`, `timeMax`, `orderBy`, or several other filters. Therefore a moving bounded window must be a full snapshot refresh rather than a query pretending to use incremental sync. [Events list reference](https://developers.google.com/workspace/calendar/api/v3/reference/events/list).

If a future release needs incremental sync, maintain an event-source cache separately from local task completion. Fully page the initial collection, store `nextSyncToken` only after the last page, then apply subsequent changes with that token and consistent supported filters. A `410 Gone` invalidates the token and requires a fresh source-cache sync. Do not wipe the user's tasks, notes, or completion history. [Incremental sync guide](https://developers.google.com/workspace/calendar/api/guides/sync).

Recurring instances have a `recurringEventId` and `originalStartTime`. The original time identifies the occurrence even if it moves. Store this provenance if series editing is added; use the instance's current start/end for display. Avoid implementing recurrence arithmetic locally for the first version, since the API can expand occurrences. [Recurring events guide](https://developers.google.com/workspace/calendar/api/guides/recurringevents).

Cancellation payloads can contain little beyond an ID. A cancelled exception means the occurrence disappears, while other cancellations represent deleted events. Parse optional fields accordingly. All-day dates use a date-only start and an exclusive end date. Preserve these semantics without treating midnight as a timed appointment. [Event resource reference](https://developers.google.com/workspace/calendar/api/v3/reference/events).

On a successful snapshot, update source-owned titles and planned times in place. Mark an imported item removed from that snapshot's account/calendar/window as externally cancelled and hide its active plan. Preserve local completion history and task identity. Repeating a sync must not duplicate tasks; a failure or partial page fetch must not reconcile deletions. These are the app's sync safety rules.

## Refresh and privacy expectations

The local implementation syncs after connecting, on app foreground with a one-minute throttle, every minute while the app remains active, and through a manual Sync now action. The active-app loop waits one minute after each attempt, so request duration can lengthen the interval. This automatically creates local tasks after the app fetches new Google events. Backgrounding the app cancels the loop. It does not promise immediate delivery while the app is closed.

Google push notifications require a publicly reachable HTTPS webhook receiver and expiring watch channels. Notifications signal that a collection changed rather than supplying event bodies, so another API fetch is needed. A later server integration would also need APNs delivery and channel renewal. That adds hosting and account-data handling that the local-first version does not need. [Google push guide](https://developers.google.com/workspace/calendar/api/guides/push).

iOS decides when background refresh runs and can end it early. `BGAppRefreshTask` is suitable for opportunistic freshness, not an exact polling schedule or a realtime guarantee. Foreground and manual refresh remain necessary. [Apple background execution explanation](https://developer.apple.com/videos/play/wwdc2019/707/).

Disconnect should remove this device's credentials and stop imports, while retaining already imported tasks for history/export. Google access can also be revoked in the Google Account permissions page. Completion and actual time remain app-owned; a meeting ending or being accepted does not mark a task complete. Keep integration optional so offline task and calendar use remain functional.

The SDK's published privacy manifest includes service analytics for identifiers and other usage information, although it declares no cross-app tracking. Therefore retain the narrower claim that the app adds no developer analytics, and disclose the optional SDK's data practices. Update the release's App Store privacy answers using the aggregated privacy report; an upstream blanket statement that no personal data is collected is no longer accurate for this integration. [Google SDK disclosure](https://developers.google.com/identity/sign-in/ios/app-privacy), [SDK 10.0.0 privacy manifest](https://github.com/google/GoogleSignIn-iOS/blob/10.0.0/GoogleSignIn/Sources/Resources/PrivacyInfo.xcprivacy).

See [Google Calendar setup](google-calendar-setup.md) for the local configuration and verification steps.
