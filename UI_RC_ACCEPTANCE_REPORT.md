# UI Release Candidate Acceptance

Baseline: `55fea20bf068fa527603526d66b52eed0f5eb013`. Branch: `feature/ui-redesign-impeccable`. C — Data-forward Health Intelligence remains frozen; Warm Personal Wellness remains supporting. No new business feature or visual direction. This document separates local evidence, real cloud CI and physical iPhone acceptance.

## 1. Impeccable final audit

Independent Assessment A: full-app Nielsen **31/40**, all ten heuristics apply (3,3,3,3,3,3,3,4,3,3). Independent B: native code/screenshot **16/20** (accessibility 3, performance 3, appearance 4, platform 3, adaptivity 3). Their different scopes are not combined, nor compared with Phase 2's narrower 34/40 and 14/20 scores.

Baseline RC findings: 2 P1 and 4 P2; testing and focused review confirmed three further P2 boundaries. All nine are closed in reviewed source/test scope: eager canteen construction; filled-send contrast; reply arrival for Coach/Health; meal-delete confirmation; editor precision; SearchBar drift; training keyboard overflow; training reply arrival; dish favorite busy state across collapse/reopen. A/B individually checked closure of their final issue without editing code.

Applied critique/distill/polish/harden/audit and targeted optimize; no decorative redesign. Detector exit 0 / `[]` has no proven Dart coverage and is not a clean bill. Final critique archive is local and fingerprinted to the gateway dashboard file, not a whole-app fingerprint.

Codex native hook approval entry unavailable in current environment.

## 2. Root-page consistency

Home, Nutrition, Training, Health, AI and Profile share page headers, 20pt content rhythm, type roles, tabular metrics, subordinate units, outlined icon family, CTA roles and semantic surfaces. Health Reference was not redesigned. Technical AI evidence remains folded; Profile retains open sections and deeper diagnostics. No return to card soup, commercial styling or game mechanics.

## 3. Navigation

Five named destinations remain unchanged. Navigation belongs to `Scaffold.bottomNavigationBar`, not the content list. Tests cover Light/Dark at 320×568, 393×852, 430×932, 200% text, 44pt targets, selected semantics, simulated top 44/bottom 34 safe areas and unchanged bar rectangle during content scroll. Real Home Indicator and back gestures are not yet verified.

## 4. Dark Mode

Retained semantic background/surface/elevated-surface hierarchy, readable secondary text, selected navigation and clinical status labels. SearchBar now consumes the same input roles instead of SDK seed-derived surface/elevation. Both filled send icons explicitly use onPrimary. Existing text/status contrast tests remain strict; color is accompanied by text/icon/labels.

## 5. Small-screen results

Portrait root and support checks cover 320×568, 393×852 and 430×932. Training coach at 320×568 + 200% + 300pt inset originally overflowed by 42px; actual available-height input lines and compact decoration fixed it without clipping stored text or shrinking accessibility text. Six training keyboard scenarios pass. Sheets, dialogs, failed composers and food-search filters retain scroll/recovery paths.

## 6. Dynamic Type

Default 100%, larger 130% and accessibility 200% form an 18-scenario root matrix across three phone sizes and two themes. Dashboard metrics, meal rows, workout editor, clinical rows, messages and settings participate. Additional flow tests exercise full rows/sections. This is TextScaler simulation, not an iOS settings acceptance claim.

## 7. Accessibility static audit

Named icon buttons, selected navigation, explicit chart descriptions and textual abnormal/pending state preserved. Root iOS target guideline and chat reachability checks run without exemptions. New-reply notice is a live region and a named action. Original values remain editable; confirmation names the food and quantity. Reduce Motion retains static loading, respects disableAnimations, and reply following uses immediate visible positioning rather than an entrance animation. Haptic selection stays narrowly scoped; no new universal tap vibration.

Actual VoiceOver focus order/pronunciation, system display modes, real keyboard/focus and touch ergonomics remain device gates. Sam's low-vision, Casey's daily-recording and Alex's large-data obstacles were used for concrete checks, not invented user-research claims.

## 8. Performance audit

No new IntrinsicHeight/Width, BackdropFilter, blur, complex shadow or network image introduced. Explicit colors stay in tokens; retained local dimensions are justified layout roles rather than a new token taxonomy. Shared additions have actual reuse: reply controller/notice across three chat entries; precise editor number across four flows; protected asynchronous button across existing consumers.

Action library and training chat still have eager small-data collections; their large-scale behavior is unprofiled, not an established major defect. Existing photo preview uses compressed local files and bounded decode dimensions; canteen has no images, so no invented image/cache optimization. No provider selectors or domain code were changed merely to claim optimization.

## 9. Canteen performance result

Fixture: 10 canteens, 50 stalls, 1000 synthetic dishes; separately 1000 saved meals and a pathological single expanded 1000-dish stall. Single CustomScrollView with lazy SliverList delegates, stable keys and preserved local expansion state.

| Deterministic widget count | Before | After |
|---|---:|---:|
| Initial mounted saved-meal rows, 1000 total | 1000 | 7 |
| Initial mounted dish rows, one expanded 1000-dish stall | Not separately measured | 2 |

Deep last-item scrolling, Light/Dark 200% expansion/collapse, pending saved-meal scrolling and pending dish favorite collapse/reopen are exercised. Favorite pending is tree-level dish-ID presentation state; original API and payload remain unchanged. Existing food search tests a 1000-entry catalog and explicit submitted query; typing sends no request, so adding debounce or new canteen search would be a false feature.

Debug timings are not release-frame or physical-memory evidence. No 60/120fps claim.

## 10. Golden result

74 comparisons: original 54 retained plus 20 pressure/support captures. Six existing Coach images were manually inspected (only intended send-icon pixels), then explicitly refreshed. No blanket acceptance, comparator tolerance increase, deletion or skip. All 20 new images were individually viewed by main and both reviewers. The twelve frozen Phase 2 final images are separately preserved.

## 11. Flutter analyze

Flutter 3.47.5. Strict `dart format --output=none --set-exit-if-changed lib test tool` and `flutter analyze --no-pub` are required. Latest completed analyzer: no issues, exit 0. Two multiline callback brace lint findings were corrected, not downgraded.

## 12. Flutter tests

Final full suite: **262 tests, exit 0**, including all 74 Goldens. `dart format` checked 94 files with no pending changes; analyzer returned no issues. Production draft flow passed: original 125.5g editing, removing mistaken item and one confirmation with original idempotency key; camera/AI responses are synthetic. Original tests and strict comparisons remain enabled.

Real in-memory SQLite and unchanged OfflineWorkoutRepository exercise start → weight/reps/RIR → two sets → rest → completion, verify exact decimals, set numbers, pending outbox operations and final status. Actual meal delete UI tests cancel, one awaited deletion and safe failure retention. All three chat entries exercise follow versus reading-position preservation.

## 13. Remote CI

Not yet run for this UI RC commit. Do not interpret old RC runs or configured workflows as current success. After local verification, push only `feature/ui-redesign-impeccable` to the explicitly authorized existing repository, then read each actual job. Main must not be merged.

Required: release audit; backend Ruff/mypy/tests; PostgreSQL16+real pgvector/Redis/migration/RAG; Flutter format/analyze/tests; macOS iOS no-codesign; Android secondary. Existing personal-sideload cloud job is also reviewed. Paid App Store signing is conditionally disabled for this branch by the existing project route, not by an RC test workaround.

## 14. Final Screenshot Pack

[UI_RC_PREVIEW](docs/ui-redesign/UI_RC_PREVIEW/README.md): 32 PNGs, source/copy SHA256 equality, per-image viewport/scale/inset manifest. Twelve six-page L/D roots, eight small-phone, eight large-text, two action-library and two small-keyboard captures. Test font and synthetic fixture limitations are explicit.

Original Before / Phase 1 Reference remain [here](docs/ui-redesign/phase2-before/README.md); Phase 2 Final archived [here](docs/ui-redesign/phase2-final/README.md). Standalone Coach is a fixture host, not an added sixth navigation item. Static images cannot execute app actions or permissions.

## 15. Remaining UI debt

No confirmed remaining P0/P1/required P2 in reviewed scope. Unverified boundaries: actual iPhone VoiceOver/fonts/keyboard/gestures/Safe Area/haptic, hardware performance, landscape/iPad/Split View, very large action library/chat history, and the existing API HTTP-status precision limitation. Do not remove declared device support or change business APIs to conceal these limitations. No further P3 polish planned.

## 16. Git commit

Implementation commit message: `design(rc): finalize app-wide visual acceptance` (SHA recorded after commit below). Branch stays `feature/ui-redesign-impeccable`. Backend, providers/controllers, models, repositories, authentication, DB, offline semantics, RAG/safety, iOS/Android and CI workflow were verified unchanged against 55fea20. Two existing indentation issues were only formatter corrections.

User-owned untracked `ui-preview/` and local golden failure evidence are preserved and excluded from staging. Do not claim the entire worktree is clean. No force push, history rewrite, unrelated branch push or merge.

## 17. 是否建议 merge

Not yet: real CI for this commit remains open. Even after it is green, user explicitly requested no merge; report a recommendation separately from executing a merge.

## 18. 是否适合进入 iPhone 真机验收

Local UI evidence supports proceeding once cloud CI succeeds. It does not prove daily-use/native acceptance. Use the project's permitted cloud-build + personal iPhone installation route; no requirement to buy or own a Mac, no Apple ID password/2FA request. Verify native permissions, offline/lifecycle/HTTPS sync and system accessibility on the iPhone. Pause new business features and additional visual exploration.
