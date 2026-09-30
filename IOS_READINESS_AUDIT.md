# iOS Platform Readiness Audit

Audit date: 2026-09-30

Target: iPhone, iOS 16.0+

Branch: `feature/ios-readiness`

## Outcome

The repository is now structured as iOS-first while preserving the Flutter
business code, backend, Phase 0–4 architecture, and Android compatibility. The
`mobile/ios` Runner is committed and configurable. Static Flutter validation
can run on Windows; native compilation is delegated to the primary macOS CI
gate.

This audit does not claim an iOS build, signed IPA, device run, or TestFlight
upload. Those require macOS, Xcode, Apple signing information, and physical
iPhone execution.

## Windows validation evidence

- `dart analyze lib test tool`: no issues.
- `flutter analyze --no-pub`: no issues when run from an ASCII-path temporary
  copy of the same source.
- `flutter test --no-pub`: 14 tests passed.
- Info.plist parsed as valid XML; deployment targets, bundle settings, permission
  keys, local config ignore rule, and absence of a broad ATS exception were
  checked.

Flutter 3.47.5 on Windows currently corrupts LSP/shader paths when the project or
SDK resides under this workspace's Chinese path. The ASCII-path reruns isolate
that host-tool defect; macOS CI remains the authoritative iOS build gate.

## Native project

- Generated from the existing Flutter project with official Flutter 3.47.5;
  existing `mobile/lib` was retained.
- Deployment target is iOS 16.0 in the Xcode project and Flutter framework
  metadata.
- Default bundle identifier: `com.personal.healthcoach`.
- Bundle ID and display name can be overridden through `IOS_BUNDLE_ID` and
  `APP_DISPLAY_NAME` using `dart run tool/configure_ios.dart`.
- Camera, photo-library, and future add-to-library purpose strings are present.
- There is no broad `NSAppTransportSecurity` exception.

## Layout and interaction audit

| Area | Finding | Status/action |
|---|---|---|
| Safe areas | Auth and main dashboard bodies use `SafeArea`; the coach composer has an explicit bottom safe area. | Ready for simulator/device verification. |
| Notch/Dynamic Island | No absolute top positioning or custom status-bar overlay found. | Verify compact/large iPhones. |
| Home indicator | Scaffold NavigationBar and coach composer respect bottom insets. | Verify on hardware. |
| Navigation | Flutter Material routes use the platform page transition; no code blocks interactive back navigation. | Verify edge swipe on pushed food/canteen/analysis routes. |
| Bottom sheets | Image-source sheets use `SafeArea`; content uses drag handles or bottom padding. | Verify large text and landscape. |
| Pickers/dialogs | Forms use Flutter dialogs and platform keyboards; long hunger content is scrollable. | Verify keyboard, decimal input, and Dynamic Type. |
| Keyboard | Scaffolds retain default resize behavior; coach input is anchored in a safe area. | Verify on small iPhone and Chinese keyboard. |
| Status bar | No forced overlay/color logic. | System-managed; verify light/dark contrast. |
| Dark mode | Added system-driven light/dark themes. | Automated widget coverage plus visual device QA required. |
| Accessibility | Material semantics/tooltips exist for primary icon buttons. | VoiceOver, contrast, reduced motion, and XXL text remain device QA gates. |

## Storage and security audit

- Tokens now explicitly use iOS Keychain with a non-migrating,
  after-first-unlock accessibility class.
- Drift uses the app sandbox and no Android-only path.
- Existing Drift path is preserved to avoid a silent database relocation.
- Pending vision photos moved to Application Support and continue to be
  deleted with task/private-data cleanup.
- No hard-coded Windows or Android filesystem path exists in runtime code.

## Image and permission flow

- Camera/photo access starts from an explicit user action, not first launch.
- `requestFullMetadata: false`, EXIF removal, JPEG compression, size limit,
  editable draft, explicit confirmation, offline retry, manual fallback, and
  third-party AI opt-in remain intact.
- Physical-device acceptance must cover denial/revocation, limited library,
  HEIC rotation, low storage, interruption, and background/foreground recovery.

## Health data architecture

`HealthDataProvider`, `AppleHealthProvider`, `ManualHealthProvider`, and a
prioritized provider are present. The intended iPhone order is Apple Health,
then manual data. `AppleHealthProvider` deliberately reports unavailable;
there is no HealthKit entitlement or prompt until the feature is implemented.

## Notifications

Notifications are not implemented. The approved delivery architecture is local
iOS notifications first and APNs second. Permission is contextual after an
in-app rationale, never on first launch. Server scheduling performs supervision
and idempotency; the app is not assumed to remain alive in the background.

## Network environments

`APP_ENV` supports dev/staging/prod and `API_BASE_URL` supports an explicit
endpoint. Loopback endpoints are rejected because they cannot address the Mac
from an iPhone. Staging and production reject HTTP. Development HTTP is allowed
only as an explicit override; no shipping ATS relaxation is committed.

## Deferred roadmap items

iOS widgets and an Apple Watch companion are future integrations, not Phase 5
deliverables. HealthKit and notification plugins, capabilities, and prompts
remain separate audited changes.

## Exit gate before Phase 5

Repository work is ready for Phase 5 development and macOS verification. iOS
release readiness still requires:

1. the macOS iOS CI job passes;
2. an Apple team and final bundle ID are configured;
3. a physical iPhone smoke test passes;
4. camera/photo/Keychain behavior is verified;
5. placeholder icon and production HTTPS endpoint work is scheduled before
   TestFlight.
