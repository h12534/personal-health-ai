# Privacy and Data Handling Baseline

This file is the engineering privacy baseline for Personal Health OS. It is not
the final public privacy policy or legal advice. Before TestFlight external
testing or App Store submission, the product owner must publish a policy URL
whose wording matches the deployed backend, AI providers, retention settings,
and App Store Connect privacy answers.

## Data categories

The system may process account credentials, profile and goal settings, body
measurements, nutrition and meal records, activity summaries, user-entered
notes, coach conversations, and optional meal photos. Later phases may add
training, sleep, report, examination, notification, and Apple Health data.

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

HealthKit is not enabled in the current build. The code contains a provider seam
only. A later HealthKit change must:

- add only the read/write types required by the feature;
- show an in-app explanation immediately before Apple's authorization sheet;
- keep manual entry available when access is denied;
- support partial authorization, revocation, source attribution, deduplication,
  and incremental sync;
- never use HealthKit data for advertising, data brokerage, or unrelated
  profiling;
- update this file, App Store privacy disclosures, entitlements, and device
  tests before release.

The intended source order on iPhone is
`AppleHealthProvider → ManualHealthProvider`.

## Notifications

Notification permission is not requested at first launch. The product must
first show a contextual rationale after the user enables a reminder.

Delivery order:

1. local iOS notifications for user-created on-device reminders;
2. APNs only for server-originated or cross-device events.

The Linux scheduler supervises due events and idempotency. The iOS app must not
be designed as a permanently resident background process. Notification payloads
must avoid sensitive health details on the lock screen by default.

No notification plugin, APNs entitlement, or background mode is included in
this readiness change.

## Network and transport

- Staging and production API endpoints must use HTTPS.
- No global ATS bypass is allowed.
- Temporary development HTTP, if unavoidable, must use a narrowly scoped local
  Debug configuration and never ship.
- An iPhone cannot use `localhost` to reach the development Mac.
- AI provider keys and Apple push credentials remain server-side.

## User control and lifecycle

Users must be able to:

- decline camera, photo, future HealthKit, and notification permissions without
  losing unrelated features;
- use manual meal and health entry;
- enable/disable third-party image analysis and image retention separately;
- log out and clear private local state;
- understand whether a value came from manual entry, Apple Health, deterministic
  rules, or an AI-generated draft.

Backend deletion/export workflows and final retention periods must be defined
and tested before App Store release. Backups require encryption, access
controls, an expiry policy, and restoration testing.

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
