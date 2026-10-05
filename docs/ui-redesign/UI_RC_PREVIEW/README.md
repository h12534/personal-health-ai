# UI_RC_PREVIEW

32 actual Flutter screenshot PNGs, copied without transformation from the reviewed golden outputs. [Manifest](manifest.json) records SHA256, viewport, text scale and simulated keyboard inset for each image. Copied/source hashes were checked for equality.

## Core six pages

| Page | Light | Dark |
|---|---|---|
| Home | [PNG](dashboard-light.png) | [PNG](dashboard-dark.png) |
| Nutrition | [PNG](nutrition-light.png) | [PNG](nutrition-dark.png) |
| Training | [PNG](training-light.png) | [PNG](training-dark.png) |
| Health | [PNG](health-overview-light.png) | [PNG](health-overview-dark.png) |
| AI | [PNG](coach-light.png) | [PNG](coach-dark.png) |
| Profile | [PNG](profile-light.png) | [PNG](profile-dark.png) |

## Pressure cases

Light and Dark for each:

- `dashboard-small`, `nutrition-small`, `training-small`, `health-overview-small`: 320×568, 100% text.
- `coach-large-text`, `profile-large-text`, `health-overview-large-text`, `workout-set-large-text`: 393×852, 200% text.
- `training-library`: shared SearchBar and empty-query result, not a typed-query capture. Submitted filtering is checked by interaction tests.
- `training-keyboard-small`: 320×568, 200% text, simulated 300pt keyboard inset. Blank bottom area represents the inset, not a rendered iOS keyboard.

Large-type content is naturally scrollable; a single first-position capture does not show all controls. Navigation remains outside the body scroll. Actual 44pt targets and above-keyboard send position are asserted separately.

## Provenance and limits

Source harness: `mobile/test/ui_redesign_golden_test.dart`. Flutter 3.47.5, Windows widget test, explicit TargetPlatform.iOS, test-only `GoldenTestChinese` loaded from NotoSansSC. Synthetic records only; no real health data, secrets or live AI requests.

Core Nutrition intentionally retains the earlier aggregate-only fixture; `nutrition-flow` and actual production-screen interaction tests cover populated meal rows and actions separately. Standalone Coach is shown in a fixture host with `我的` selected; it is a detail entry in production, not a new sixth tab.

These are static images, not an interactive installed app or native-permission evidence. iPhone fonts, VoiceOver, keyboard, Safe Area, gestures, HealthKit, camera, Face ID and frame rate need physical acceptance.

Before / Phase 1 Reference: [original archive](../phase2-before/README.md). Phase 2 Final: [frozen archive](../phase2-final/README.md). Full RC report: [UI_RC_ACCEPTANCE_REPORT](../../../UI_RC_ACCEPTANCE_REPORT.md).
