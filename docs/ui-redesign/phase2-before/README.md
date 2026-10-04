# Phase 2 baselines

These synthetic Flutter captures preserve the committed Phase 1 state at `6f3f1e0`, before the app-wide rollout. They use Flutter 3.47.5 on the Windows widget-test engine, 393 × 852 logical pixels, the test-only Chinese font and existing icon assets.

They are not iOS Simulator or physical iPhone evidence. Root-page dark baselines that did not exist in Phase 1 are captured before each corresponding page implementation and identified separately in the rollout report. No real health data is used.

- Home/Nutrition/Training Dark: captured after Navigation commit 317a1f5, before any corresponding page UI edits.
- AI Coach and Profile Light/Dark: added to the real Flutter test harness and captured while their production source was still the original Phase 1 version. Their capture includes final navigation labels; they are not claimed to be old Phase 1 navigation.
- All captures use synthetic fixtures. Nutrition's older aggregate-only fixture intentionally has no meal-detail list; the new nutrition-flow and draft images are additional After scenarios, not relabelled Before comparisons.
