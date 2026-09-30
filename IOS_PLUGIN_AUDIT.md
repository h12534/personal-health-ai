# iOS Plugin Audit

Audit date: 2026-09-30

Flutter baseline: 3.47.5 / Dart 3.13.4

Application deployment target: iOS 16.0

This audit is based on `mobile/pubspec.lock`, the packages resolved by Flutter,
and each package's checked-in iOS manifest or package metadata. The static audit
is complete. Native compilation remains a macOS/Xcode CI and device acceptance
gate; a Windows host cannot prove that an iOS binary builds.

## Direct dependency matrix

| Plugin | Locked version | Purpose | iOS support | Declared/native minimum | Native permission or capability | Audit note |
|---|---:|---|---|---|---|---|
| Flutter SDK | 3.47.5 | Application runtime/UI | Yes | Flutter supports iOS 15+; app pins 16.0 | None by itself | iOS is the primary committed Runner. |
| `cupertino_icons` | 1.0.9 | Apple-style glyph font | Yes, asset-only | Inherits app | None | No native code. |
| `dio` | 5.11.1 | HTTPS API client | Yes, Dart | Inherits app | Network access only | Production and staging URLs are forced to HTTPS by `AppConfig`. |
| `connectivity_plus` | 6.1.5 | Detect network transport changes | Yes | iOS 12.0 in Package.swift/podspec | None | Reachability is only a hint; requests still handle failures. |
| `drift` | 2.35.0 | Local relational data and outbox | Yes | Inherits app | None | Database remains inside the app sandbox. |
| `flutter_riverpod` | 2.6.1 | State/dependency management | Yes, Dart | Inherits app | None | No native integration. |
| `flutter_secure_storage` | 9.2.4 | Access/refresh token storage | Yes | iOS 9.0 in the locked podspec | Keychain; no user prompt | Uses Flutter's CocoaPods fallback because this locked release predates its SwiftPM manifest. Configured with `first_unlock_this_device`; no Keychain Sharing entitlement is used. |
| `flutter_image_compress` | 2.5.1 | JPEG resize/compression and EXIF removal | Yes | Inherits app target | None by itself | `compressAndGetFile` is supported on iOS; physical-device HEIC inputs still require testing. |
| `http_parser` | 4.1.2 | Multipart image media type | Yes, Dart | Inherits app | None | No native integration. |
| `image_picker` | 1.2.3 | Camera/photo-library input | Yes; iOS implementation 0.8.13+8 | iOS 13.0 in Package.swift/podspec | Camera, Photo Library | `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` are present. Microphone is unnecessary because the app does not record video. |
| `intl` | 0.20.3 | Date/number formatting | Yes, Dart | Inherits app | None | No native integration. |
| `path` | 1.9.1 | Portable path joining | Yes, Dart | Inherits app | None | No platform-specific path literals found. |
| `path_provider` | 2.1.6 | Resolve app sandbox directories | Yes; Foundation implementation 2.6.0 | Inherits app | None | Durable pending photos now use Application Support; Drift keeps its established Documents path to avoid data migration risk. |
| `uuid` | 4.6.0 | Local IDs/idempotency keys | Yes, Dart | Inherits app | None | No native integration. |

## Permission and capability findings

- Camera and photo-library access are requested only when the user taps
  “拍照或选择图片”; neither is requested at first launch.
- `NSPhotoLibraryAddUsageDescription` is present for a future explicit
  “save to Photos” action. The current application does not write images to the
  photo library and therefore does not request add-only access.
- No microphone, location, contacts, tracking, Bluetooth, HealthKit, or push
  entitlement is included in this readiness change.
- Tokens are stored in iOS Keychain through `flutter_secure_storage`; database
  rows and pending photos stay in the application sandbox.
- Third-party AI image analysis remains an explicit, revocable opt-in in the
  profile screen. Camera/photo permission does not imply AI-processing consent.

## Dependency decisions

No package upgrade was forced during this audit. The locked versions resolve
under Flutter 3.47.5 and their declared iOS minimums are below the application's
iOS 16.0 target. Upgrading `flutter_secure_storage` across its major-version
boundary is deferred to a dedicated migration because token compatibility must
be verified on an upgrading physical device.

Swift Package Manager is explicitly enabled for the application. Flutter's
documented CocoaPods fallback remains necessary for locked plugins without a
SwiftPM manifest, so the macOS CI verifies CocoaPods availability before the
native build.

HealthKit and local-notification packages are intentionally absent. Provider
interfaces and product rules are defined first; native plugins, entitlements,
permission prompts, and device tests will be added in their delivery phases.

## macOS verification gate

The required primary CI job runs, on macOS:

1. `flutter pub get`
2. `dart run tool/configure_ios.dart`
3. `dart format --output=none --set-exit-if-changed lib test`
4. `flutter analyze`
5. `flutter test`
6. `flutter build ios --release --no-codesign`

Only a passing macOS job closes native plugin compatibility. Camera, photo
selection, Keychain persistence, HEIC/JPEG compression, app reinstall/upgrade,
and background/foreground transitions still require a physical iPhone matrix.
