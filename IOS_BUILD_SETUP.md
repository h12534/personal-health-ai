# iOS Build, Device, Signing, and TestFlight Setup

The iPhone app is the primary mobile deliverable. Android remains supported as
a secondary compatibility target. The committed `mobile/ios` directory was
generated with Flutter 3.47.5 and must not be recreated during normal work.

This repository uses Flutter's generated Swift Package Manager integration as
the primary native dependency manager. Flutter automatically falls back to
CocoaPods for a plugin that has not migrated to SwiftPM, so CocoaPods is a
required compatibility tool on build Macs.

## 1. Required Mac and Apple access

- A supported Mac with current macOS security updates.
- Xcode capable of building an iOS 16.0 deployment target.
- Flutter 3.47.5 stable for reproducible local/CI results.
- An Apple ID added to Xcode.
- Paid Apple Developer Program membership for TestFlight/App Store
  distribution. A free Personal Team can be used for limited device testing.
- A registered App ID whose identifier matches `IOS_BUNDLE_ID`.

Information that must come from the Apple account owner:

- Apple Developer Team ID and the team to select in Xcode.
- Final bundle identifier; default placeholder is
  `com.personal.healthcoach`.
- Final App Store display name, App Store Connect SKU, primary language, and
  category.
- Distribution certificate/provisioning access or permission for Xcode to
  manage signing.
- Final app icon, screenshots, support URL, privacy-policy URL, age rating, and
  App Privacy answers.
- APNs key/certificate only when remote notifications are implemented later.

Never commit certificates, private keys, provisioning profiles, API secrets, or
an `AppConfig.local.xcconfig` file.

## 2. Install the toolchain

1. Install Xcode from the Mac App Store.
2. Launch Xcode once, accept its license, and install requested platform
   components.
3. Select its command-line tools:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   xcodebuild -version
   ```

4. Install Flutter 3.47.5 and place `flutter/bin` on `PATH`:

   ```bash
   flutter --version
   flutter doctor -v
   ```

5. Install CocoaPods for plugin compatibility, even though this Runner
   currently uses Swift Package Manager:

   ```bash
   brew install cocoapods
   pod --version
   ```

   Flutter wires SwiftPM packages and any CocoaPods fallback during the native
   build. If `mobile/ios/Podfile` exists, run `pod install --repo-update`
   from `mobile/ios` when dependency resolution requires it. Always open
   `Runner.xcworkspace`, never `Runner.xcodeproj`.

## 3. Configure app identity

Committed, non-secret defaults live in
`mobile/ios/Flutter/AppConfig.xcconfig`. Override them locally from
environment variables:

```bash
cd mobile
export IOS_BUNDLE_ID=com.yourcompany.personalhealth
export APP_DISPLAY_NAME='私人健康'
dart run tool/configure_ios.dart
```

This writes ignored `ios/Flutter/AppConfig.local.xcconfig`. The bundle ID and
display name flow into all Debug, Profile, and Release configurations. The
minimum deployment target is iOS 16.0.

Open `ios/Runner.xcworkspace` in Xcode and select:

1. Runner target → Signing & Capabilities.
2. The correct Apple Developer Team.
3. “Automatically manage signing” unless the organization mandates manual
   profiles.
4. Confirm the resolved bundle identifier matches the registered App ID.

Do not add HealthKit, Push Notifications, Background Modes, App Groups, or
Keychain Sharing capabilities until the corresponding feature is implemented
and reviewed.

## 4. Configure the API endpoint

The Flutter application accepts:

- `APP_ENV=dev|staging|prod`
- `API_BASE_URL=https://host/api/v1`

Development may explicitly use scoped HTTP, but staging and production reject
non-HTTPS URLs. No broad ATS exception is committed. Prefer a trusted HTTPS
development hostname or tunnel.

An iPhone cannot reach a Mac service through `localhost` or `127.0.0.1`;
those addresses point back to the phone. Use an HTTPS hostname reachable from
the device, or a Mac LAN IP only for an explicitly temporary development HTTP
setup. Any narrow ATS exception needed for such a setup must remain in a local,
uncommitted Debug configuration.

Example:

```bash
flutter run \
  --dart-define=APP_ENV=dev \
  --dart-define=API_BASE_URL=https://dev-api.example.com/api/v1
```

The `.invalid` defaults are deliberate non-routable placeholders, preventing a
build from silently sending health data to an unintended host.

## 5. Install dependencies and run static checks

```bash
cd mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build ios --release --no-codesign \
  --dart-define=APP_ENV=staging \
  --dart-define=API_BASE_URL=https://staging-api.example.com/api/v1
```

`flutter build ios --no-codesign` verifies compilation only. It does not
prove signing, installation, camera/photo behavior, Keychain persistence, or
App Store acceptance.

## 6. Run in Simulator

```bash
open -a Simulator
flutter devices
flutter run -d '<simulator id>' \
  --dart-define=APP_ENV=dev \
  --dart-define=API_BASE_URL=https://dev-api.example.com/api/v1
```

Check at minimum:

- iPhone SE-sized and current notched/Dynamic Island layouts.
- Home indicator and five-item bottom navigation.
- System light/dark appearance and larger Dynamic Type.
- Keyboard avoidance, form submission, dialogs, bottom sheets, and back-swipe.
- Photo selection denial, limited-library access, and permission recovery.

The Simulator is not a substitute for camera, Keychain upgrade, memory
pressure, HEIC input, or background/foreground tests on hardware.

## 7. Run on a physical iPhone

1. Connect the phone by cable, trust the Mac, and enable Developer Mode when
   prompted.
2. In Xcode, select the Runner scheme and the phone.
3. Select the signing team and allow Xcode to create a development profile.
4. Run from Xcode once, or use:

   ```bash
   flutter devices
   flutter run -d '<device id>' \
     --dart-define=APP_ENV=dev \
     --dart-define=API_BASE_URL=https://dev-api.example.com/api/v1
   ```

5. Verify:

   - fresh-install and upgrade login token behavior;
   - Keychain logout/delete behavior;
   - camera capture and photo-library selection;
   - denied/restricted permission recovery through Settings;
   - HEIC/JPEG rotation, 2048-pixel resizing, EXIF removal, and upload retry;
   - offline pending photos after app termination and device restart;
   - no first-launch notification prompt;
   - third-party image analysis stays off until explicit in-app consent;
   - status bar, notch/Dynamic Island, home indicator, keyboard, modal sheets,
     native back gesture, and light/dark mode.

## 8. Create a signed archive

Before archiving, replace placeholder icons and endpoints, set the release
version in `mobile/pubspec.yaml`, and confirm the production bundle ID.

```bash
cd mobile
flutter build ipa --release \
  --build-name=0.1.0 \
  --build-number=1 \
  --dart-define=APP_ENV=prod \
  --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

Alternatively open `ios/Runner.xcworkspace`, choose “Any iOS Device
(arm64)”, then Product → Archive. In Organizer:

1. Validate App.
2. Distribute App → App Store Connect → Upload.
3. Keep automatic signing unless the organization requires manual export.

If an organization supplies an export options plist, keep it outside Git and
pass it with `flutter build ipa --export-options-plist=/secure/path/file.plist`.

## 9. TestFlight checklist

1. Create the matching App Store Connect app record.
2. Upload the archive and wait for processing.
3. Complete export-compliance and privacy declarations.
4. Add internal testers first.
5. Run the physical-device matrix above on the processed TestFlight build.
6. Add external testers only after Beta App Review metadata and test notes are
   complete.
7. Record the tested build number, device models, iOS versions, backend
   environment, and known limitations.

Current readiness limit: repository configuration and Windows Flutter
analyze/tests can be checked locally, and macOS CI is configured. A signed IPA,
physical-iPhone run, archive validation, and TestFlight upload remain blocked
until the Apple account information and a Mac/Xcode execution environment are
available.
