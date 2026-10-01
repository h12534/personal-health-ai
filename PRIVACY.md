# Privacy and Data Handling Baseline

This file is the engineering privacy baseline for Personal Health OS. It is not
the final public privacy policy or legal advice. Before TestFlight external
testing or App Store submission, the product owner must publish a policy URL
whose wording matches the deployed backend, AI providers, retention settings,
and App Store Connect privacy answers.

## Data categories

The system may process account credentials, profile and goal settings, body
measurements, nutrition and meal records, training, activity and sleep
summaries, user-entered notes, coach conversations, optional meal photos,
confirmed examination results, notification delivery metadata, reports and
Apple Health summaries explicitly enabled by the user.

Collect only fields needed for an enabled feature. Medical diagnosis, medication
changes, ad-network tracking, contacts, location, microphone, and advertising
identifiers are not part of the current application.

## Device storage

- Access and refresh tokens use iOS Keychain via
  `flutter_secure_storage`, with
  `KeychainAccessibility.first_unlock_this_device`.
- Drift/SQLite data stays in the application sandbox. Its established database
  location is retained to avoid silently losing existing installs.
- Pending meal-photo uploads use Application Support because they are durable
  app-private state, not user documents.
- Picker/cache source files are copied to an app-private, EXIF-stripped JPEG
  before upload. Completed/cancelled task cleanup removes the private copy.
- Logout clears Keychain session values and invokes the local private-data
  cleanup path.

Do not place health data, tokens, image paths, full coach text, or API keys in
analytics, crash breadcrumbs, or ordinary logs.

## Photos and AI processing

Camera and photo-library access is requested only after a user chooses the meal
photo action. A selected image first creates an editable analysis draft; it
never becomes a formal meal record until the user confirms it.

Permission to use the camera or photo library is separate from permission to
send an image to a third-party AI provider. Remote third-party analysis is off
by default and requires an explicit, revocable in-app opt-in. The screen must
name the processing purpose, explain that the server controls the provider API
key, and allow the user to continue with manual entry.

The application removes EXIF metadata, resizes images, and uses the configured
server retention policy. Long-term image retention is a separate user setting;
turning it off does not delete the confirmed nutrition facts.

## Apple Health

HealthKit is enabled behind `AppleHealthProvider`, with manual fallback. The app
requests steps, walking/running distance, active energy, resting heart rate,
sleep and workout read access only after the user enables the corresponding
switch. It does not write to Apple Health. Partial authorization and denial do
not disable manual entry.

The server receives only daily summaries or sleep/training segments needed for
activity and recovery. Raw sample streams, routes and continuous heart-rate
samples are not uploaded. Source record IDs and incremental cursors prevent
duplicate summaries. A user can disable each type independently and delete
server-synced provider data without deleting manual records. HealthKit data is
never used for advertising, data brokerage or unrelated profiling.

## Notifications

Notification permission is not requested at first launch. The product must
first show a contextual rationale after the user enables a reminder.

Delivery order:

1. local iOS notifications for user-created on-device reminders;
2. APNs only for server-originated or cross-device events.

The Linux scheduler supervises due events and idempotency. The iOS app must not
be designed as a permanently resident background process. Notification payloads
must avoid sensitive health details on the lock screen by default.

The iOS implementation uses `flutter_local_notifications` for user-enabled
fixed reminders and deliberately requests no background-resident execution.
Remote delivery remains behind `PushProvider`; without Apple credentials the
server uses `MockPushProvider`. Notification logs store delivery metadata and
interaction timing, not the sensitive body text.

Lab follow-up lock-screen text is reduced to a generic health reminder. It must
not include a condition, lab value, document title, full question or image
path.

## Network and transport

- Staging and production API endpoints must use HTTPS.
- No global ATS bypass is allowed.
- Temporary development HTTP, if unavoidable, must use a narrowly scoped local
  Debug configuration and never ship.
- An iPhone cannot use `localhost` to reach the development Mac.
- AI provider keys and Apple push credentials remain server-side.

## User control and lifecycle

Users must be able to:

- decline camera, photo, HealthKit, and notification permissions without
  losing unrelated features;
- use manual meal and health entry;
- enable/disable third-party image analysis and image retention separately;
- log out and clear private local state;
- understand whether a value came from manual entry, Apple Health, deterministic
  rules, or an AI-generated draft.

The authenticated user can export a JSON or flattened CSV copy of profile,
weight, nutrition, training, sleep, steps, labs, tasks, follow-ups and settings.
`Delete My Data` requires the exact second-confirmation phrase and removes the
account, cascade-owned database rows and private meal/lab objects. Existing
encrypted backups expire under the documented 7 daily / 4 weekly / 3 monthly
policy instead of being silently rewritten in place. Production backups still
require encryption, access control, off-host replication and restore drills.

The optional Face ID / Touch ID lock is off by default. Enabling it stores only
the preference in secure storage; authentication remains on-device, and the
session token remains in Keychain. After a two-minute background grace period,
the app gates the authenticated surface without prompting on every sensitive
screen tap.

## App Store privacy preparation

Before TestFlight external testing, reconcile actual production behavior with:

- App Store Connect App Privacy data-type declarations;
- the published privacy-policy and support URLs;
- the nutrition/fitness/health purpose wording;
- every enabled third-party AI processor and its data region/retention terms;
- account deletion and data export behavior;
- camera/photo permission strings and any future HealthKit purpose strings.

Any change to data collection, a native entitlement, a third-party processor, or
retention must update this document in the same pull request.
## Apple Health / HealthKit

HealthKit data is sensitive. The App requests each type only after the user enables its switch. Phase 5 reads steps, walking/running distance, active energy, resting heart rate, sleep and workouts; it does not write to Apple Health.

The server receives only daily summaries or sleep/training segments needed for activity and recovery features. Raw HealthKit sample streams, routes and continuous heart-rate samples are not uploaded. Provider record IDs prevent duplicate summaries. Users can disable each type independently and delete server-synced provider data without deleting manual records.

## Lab reports and health knowledge

Lab reports are high-sensitivity health data. Camera, Photos, and Files access occurs only after an explicit upload action. PDF selection uses the iOS system picker; the app reads the selected temporary copy during upload and releases security-scoped access without saving an external path.

OCR output remains an editable draft until the user confirms it. Only confirmed values may enter trends and Health AI context. Remote third-party OCR is separately opt-in for that upload; file retention is separately configurable. Deleting a report removes its private original and hides associated values from trends and context.

Knowledge search uses the server's vetted, versioned corpus and does not automatically search the public internet. Health questions are sent with only intent-selected personal fields. Saved offline lab history contains structured values and trends in the app sandbox, not the original report. Provider keys remain server-side, and ordinary logs/analytics must not include report text, OCR payloads, complete conversations, or citations tied to a person.
