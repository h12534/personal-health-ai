# UI Release Candidate Acceptance

Baseline: `55fea20bf068fa527603526d66b52eed0f5eb013`. Branch: `feature/ui-redesign-impeccable`. C — Data-forward Health Intelligence remains frozen; Warm Personal Wellness remains supporting. No new business feature or visual direction. This document separates local evidence, real cloud CI and physical iPhone acceptance.

## 1. Impeccable final audit

Independent Assessment A: full-app Nielsen **31/40**, all ten heuristics apply (3,3,3,3,3,3,3,4,3,3). Independent B: native code/screenshot **16/20** (accessibility 3, performance 3, appearance 4, platform 3, adaptivity 3). Their different scopes are not combined, nor compared with Phase 2's narrower 34/40 and 14/20 scores.

Baseline RC findings: 2 P1 and 4 P2; testing and focused review confirmed three further P2 boundaries. All nine are closed in reviewed source/test scope: eager canteen construction; filled-send contrast; reply arrival for Coach/Health; meal-delete confirmation; editor precision; SearchBar drift; training keyboard overflow; training reply arrival; dish favorite busy state across collapse/reopen. A/B individually checked closure of their final issue without editing code.

Applied critique/distill/polish/harden/audit and targeted optimize; no decorative redesign. Detector exit 0 / `[]` has no proven Dart coverage and is not a clean bill. Final critique archive is local and fingerprinted to the gateway dashboard file, not a whole-app fingerprint.

Post-push flavor verification found a tenth defect: the free-personal manual HealthKit notice occupied fixed header height and overflowed at accessibility text sizes. Main moved the unchanged notice into the scrollable overview, preserved the existing disabled-capability gate, manually reviewed all 12 free-flavor screenshots, and re-ran all three full configurations. The independent A/B scores above belong to their original full-app review; they are not newly invented scores for this follow-up.

Codex native hook approval entry unavailable in current environment.

## 2. Root-page consistency

Home, Nutrition, Training, Health, AI and Profile share page headers, 20pt content rhythm, type roles, tabular metrics, subordinate units, outlined icon family, CTA roles and semantic surfaces. Health Reference was not redesigned. Technical AI evidence remains folded; Profile retains open sections and deeper diagnostics. No return to card soup, commercial styling or game mechanics.

## 3. Navigation

Five named destinations remain unchanged. Navigation belongs to `Scaffold.bottomNavigationBar`, not the content list. Tests cover Light/Dark at 320×568, 393×852, 430×932, 200% text, 44pt targets, selected semantics, simulated top 44/bottom 34 safe areas and unchanged bar rectangle during content scroll. Real Home Indicator and back gestures are not yet verified.

## 4. Dark Mode

Retained semantic background/surface/elevated-surface hierarchy, readable secondary text, selected navigation and clinical status labels. SearchBar now consumes the same input roles instead of SDK seed-derived surface/elevation. Both filled send icons explicitly use onPrimary. Existing text/status contrast tests remain strict; color is accompanied by text/icon/labels.

## 5. Small-screen results

Portrait root and support checks cover 320×568, 393×852 and 430×932. Training coach at 320×568 + 200% + 300pt inset originally overflowed by 42px; actual available-height input lines and compact decoration fixed it without clipping stored text or shrinking accessibility text. Six training keyboard scenarios pass. Sheets, dialogs, failed composers and food-search filters retain scroll/recovery paths.

Free personal mode additionally reproduced 178px overflow at 320×568/200% and 20px with the ordinary-phone keyboard. Moving the full notice into the overview list fixes both; 43 focused layout/permission/accessibility checks pass. Its large-text first viewport remains naturally scrollable, not artificially clipped to reveal more metrics.

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

Each of the three configurations still executes all 74 comparisons. Twelve free-mode images were individually inspected locally. Under the owner's subsequent artifact-only constraint, their decoded RGBA hashes and dimensions replace new committed PNGs; the other 62 captures share standard references. The earlier image-bearing local commits are preserved in an unpushed local snapshot, not ancestors of the new public repair chain. Existing 74 Windows PNGs predate this authorization and remain unchanged. Enabled-permission assertions remain for standard/HealthKit-attempt builds; free-mode assertions verify no toggles, no false authorization and zero permission reads/writes/uploads.

macOS cross-host baseline review is complete: all 74 standard + 12 free cloud actuals were individually viewed by main, both artifact ZIP checksums/exact file sets/metadata were independently verified, and every downloaded PNG's decoded-RGBA hash and dimensions match the cloud candidates. [Individual review ledger](docs/ui-redesign/MACOS_GOLDEN_REVIEW.md). Existing Windows and Phase 2 PNGs remain unchanged. The text-only macOS manifest compares dimensions + SHA-256 with zero pixel tolerance; missing entries fail and automatic update throws. Flutter documents host differences: [LocalFileComparator](https://api.flutter.dev/flutter/flutter_test/LocalFileComparator-class.html). Actual strict CI [37292995869](https://github.com/h12534/personal-health-ai/actions/runs/37292995869), SHA `6dae1319b216cb2646c5de87efeeee2d6ec2a764`, is SUCCESS: all three full suites passed 268 tests and all 74 Goldens each (222 comparisons over 86 distinct reviewed macOS images). Safe image upload alone was never treated as passing tests/builds.

## 11. Flutter analyze

Flutter 3.47.5. Strict `dart format --output=none --set-exit-if-changed lib test tool` and `flutter analyze --no-pub` are required. Latest completed analyzer: no issues, exit 0. Two multiline callback brace lint findings were corrected, not downgraded.

## 12. Flutter tests

Latest artifact-only repair full suites: **268 tests each, exit 0** in standard, `APP_DISTRIBUTION=personal_sideload`, and personal mode with `PERSONAL_SIDELOAD_FREE=true`. Each includes all 74 Goldens. Six new comparator tests prove exact-pixel matching, single-channel one-pixel rejection, dimension/missing-entry rejection, disabled automatic update, preserved legacy comparison and forbidden fixture network. `dart format` checked 97 files with no pending changes; analyzer returned no issues. Python 3.12 script tests: **45 pass**, including twenty-one fail-closed privacy/export checks; new Python Ruff check/format pass. Production draft flow passed: original 125.5g editing, removing mistaken item and one confirmation with original idempotency key; camera/AI responses are synthetic. Original tests and strict comparisons remain enabled.

Real in-memory SQLite and unchanged OfflineWorkoutRepository exercise start → weight/reps/RIR → two sets → rest → completion, verify exact decimals, set numbers, pending outbox operations and final status. Actual meal delete UI tests cancel, one awaited deletion and safe failure retention. All three chat entries exercise follow versus reading-position preservation.

## 13. Remote CI

**PASS / cloud UI RC gate CLOSED for the reviewed implementation.** Real push run [37292995869](https://github.com/h12534/personal-health-ai/actions/runs/37292995869), commit `6dae1319b216cb2646c5de87efeeee2d6ec2a764`, attempt 1, workflow conclusion `success`, completed 2026-10-05 10:17:54Z. Every actual job result, completed log and artifact list was read. Standard, HealthKit-attempt and free manual full suites each pass 268 tests including all 74 strict Goldens. No new screenshot upload occurs on the normal push; optional capture is not requested. No main merge. The following old runs remain historical failures, not relabeled green.

| Current real job | Actual result / evidence |
|---|---|
| [release-audit, 111707578096](https://github.com/h12534/personal-health-ai/actions/runs/37292995869/job/111707578096) | SUCCESS; errors=0, existing external warnings=3, 45 script tests |
| [backend, 111707578582](https://github.com/h12534/personal-health-ai/actions/runs/37292995869/job/111707578582) | SUCCESS; Ruff check/format (203 files), strict mypy 165 files, 89 tests |
| [backend-postgres, 111707578202](https://github.com/h12534/personal-health-ai/actions/runs/37292995869/job/111707578202) | SUCCESS; PostgreSQL 16.15 / real pgvector, Redis 7.4.11, JSONB/cosine/full text/Hybrid RAG/UUID/timezone/unique/idempotency/cascade checks; 0001→0007→0008 upgrade, downgrade/re-upgrade/check; 7 integration tests; ten-table count/UUID restore drill |
| [mobile-ios-primary, 111707578426](https://github.com/h12534/personal-health-ai/actions/runs/37292995869/job/111707578426) | SUCCESS; format 97 unchanged, analyze clean, 268 tests / all 74 strict Goldens, release no-codesign Runner.app 24.5MB |
| [mobile-android-compat, 111707578285](https://github.com/h12534/personal-health-ai/actions/runs/37292995869/job/111707578285) | SUCCESS; secondary debug APK build |
| [mobile-ios-personal-sideload, 111711280048](https://github.com/h12534/personal-health-ai/actions/runs/37292995869/job/111711280048) | SUCCESS; both modes 268 tests / 74 strict Goldens, both unsigned builds/package validation/artifact uploads |
| mobile-ios-signed, 111711282252 | SKIPPED / SUSPENDED by existing paid-route conditions; NOT a passed signing/TestFlight gate |
| ui-golden-review, 111707579701 | Optional manual capture not requested; no duplicate screenshots; all regular tests above executed |

Actual toolchain: Flutter 3.47.5, macOS 26.6.2 arm64, Xcode 26.6 (17F113), CocoaPods 1.17.0. SwiftPM was attempted; existing plugins use the supported CocoaPods compatibility route. Their future SwiftPM adoption warning remains a dependency limitation, not hidden by disabling checks. Compiled iOS target is 16.0; native permissions/hardware remain separate.

Both unsigned IPAs are 0.1.0 / build 30.1 and source SHA `6dae1319b216cb2646c5de87efeeee2d6ec2a764`. CI package validation reports device arm64/Payload/native flavor/version/hash/unsigned checks passed: [HealthKit-attempt artifact 11337971795](https://github.com/h12534/personal-health-ai/actions/runs/37292995869/artifacts/11337971795), IPA SHA-256 `f2192e364e3924a93d80aa1a88323ff4b791d857fef0ac8ce398e7014e65d176`; [free artifact 11337838434](https://github.com/h12534/personal-health-ai/actions/runs/37292995869/artifacts/11337838434), IPA SHA-256 `3799f5b64ca8f2f2a28d7cda92997de6ad041ba43a3d2b4c12122da2265250ee`. These are existing build artifacts, separate from one-day screenshot artifacts. Current IPAs have CI validation; no new local download/physical-device validation is claimed. API host remains `.invalid`, `api_configured=false`; real HTTPS login/AI/sync, Windows re-sign and iPhone install/launch/permissions are NOT RUN.

| Run | Pushed commit | Result |
|---|---|---|
| [37271096988](https://github.com/h12534/personal-health-ai/actions/runs/37271096988) | `6b5a94bc61d4566631814b184802f88c0269f567` | Four jobs pass; primary macOS tests fail 74 Goldens; dependent personal build and paid signing skipped |
| [37272234650](https://github.com/h12534/personal-health-ai/actions/runs/37272234650) | `b4615e684e9afc404ed2398ab72a9081198bb697` | Same strict failure; four explicitly synthetic rendering evidence files retained |

Historical completed run 37272234650:

| Actual job | Result / evidence |
|---|---|
| release-audit, 111641493440 | SUCCESS, errors=0, existing warnings=3 |
| backend, 111641492646 | SUCCESS, Ruff check/format, mypy 165 files, 89 tests |
| backend-postgres, 111641492731 | SUCCESS, PostgreSQL16 + pgvector / Redis; upgrade 0001→0007→0008, 7 integration tests, restore drill passes |
| mobile-ios-primary, 111641493123 | FAILURE at full tests: 188 pass, 74 Golden mismatches; format/analyze pass; current UI iOS no-codesign step did not run |
| mobile-android-compat, 111641492583 | SUCCESS, debug APK build |
| mobile-ios-personal-sideload, 111642751180 | SKIPPED because its primary dependency failed; neither unsigned IPA flavor built in this run |
| mobile-ios-signed, 111642751223 | SKIPPED by existing paid-route conditions, not a passed signing gate |

Earlier safety review rejected an arbitrary failure directory, then the full set before explicit authorization. The approved four-file subset was uploaded (artifact 11329585473). The owner has now explicitly authorized exactly 74 standard + 12 free synthetic screenshots as Actions artifacts only, with automatic checks and 1–3 day retention. No screenshot may enter the new Git repair chain. That authorization is fulfilled through the opt-in manual `ui_golden_review` matrix, not unguarded failure uploads.

Before publishing: verify 67 sealed source/font/fixture files and exact owner repository/branch/manual event; forbid fixture network; validate an exact 74/12 file set, PNG dimensions, CRC, bounded decompression and allowed chunk types; reject EXIF/text metadata and strip harmless ancillary chunks; run offline Chinese and English OCR and block email/token/key/device/path/phone/private URL markers. Empty/unavailable OCR blocks. Stage atomically only after every image passes. Artifacts contain only canonical PNGs, no OCR text, logs or manifests, and expire after **1 day**. The earlier unscreened four-file upload step is replaced, not retained as a bypass. Full test/build steps remain enabled.

Safety checks are defense-in-depth over frozen synthetic provenance, not a claim that OCR alone can prove privacy. Any source drift requires another review and blocks the sealed capture until reviewed. Capture jobs do not turn a missing-baseline test failure green; each normal full suite is still required. Actual new run IDs and completed image review will be appended only after execution.

First authorized capture run [37281939646](https://github.com/h12534/personal-health-ai/actions/runs/37281939646), SHA `8a587e61056ab68d583628dd8eb923a496382c71`: both source attestations and both Swift OCR builds succeeded, but both privacy/export steps blocked `UNAPPROVED_PNG_CHUNK`; screenshot uploads were skipped. Existing cloud PNG evidence confirms Flutter's `sBIT` chunk. The repair validates exactly full 8-bit precision for each channel, forbids duplicate/out-of-order/malformed structures, and strips the chunk without changing compressed pixels, per the [PNG specification](https://www.w3.org/TR/png/#11sBIT). Unknown chunks and all EXIF/text rejection remain. Two regression tests added; latest script suite **36 pass**, Python Ruff check/format pass. This is an encoder compatibility correction, not a privacy bypass or Golden threshold change.

Retry [37282718158](https://github.com/h12534/personal-health-ai/actions/runs/37282718158), SHA `eda8eb402b1644830e0df1c2bbfcca8189db11ba`: PNG validation succeeds; both exports then block `PRIVATE_CONTENT_DETECTED`, with both uploads skipped. No private OCR content or unchecked screenshot is emitted. The next diagnostic only names the unchanged detection rule category and the already sealed fixture basename; no recognized text or path. All eight detection patterns are retained unchanged. Latest script suite **37 pass**, including a check that reasons never echo recognized content. Individual cloud review remains NOT RUN until safe export succeeds.

Diagnostic [37283507812](https://github.com/h12534/personal-health-ai/actions/runs/37283507812), SHA `977e776096a788d17ef9d085ed6c4c69d0d88d1e`: both exports blocked; no screenshot uploaded. Fixed reasons isolate `PRIVATE_CONTENT_PATH` on the knowledge page and `PRIVATE_CONTENT_PHONE` on the clinical reference. The drive regex incorrectly matched `s:/` inside the already sealed synthetic HTTPS URL; its drive-prefix boundary is repaired with local-path/private-URL regression checks retained. For the clinical reference only, any merged numeric OCR observation must be the ENTIRE observation and exactly the two frozen test-axis dates 2026-06-01 and 2026-09-01 (zero-padding variants); other numbers, other images, labeled identifiers, extra digits, changed dates and all email/key/device rules still block. The synthetic axis was viewed and source dates verified; no app/fixture pixel was altered to evade OCR. Latest script suite **39 pass**. Cloud results and actual-image review remain pending, not green.

Run [37284504075](https://github.com/h12534/personal-health-ai/actions/runs/37284504075), SHA `638b4a4d2e8c00560f2c62b181a46d34a850373f`: standard scan passed the prior URL/axis point but blocked `OCR_UNAVAILABLE` on the entirely Chinese login screen; free mode still blocked clinical long digits. No screenshot uploaded. The guessed numeric-date lexicon is removed, not broadened. The revised local Vision checker completes separate Chinese/English recognition and returns text plus normalized boxes only to the private scanner. Empty total OCR / failed or unsupported language / malformed geometry still blocks; an empty completed English result on a Chinese-only view is not a failed OCR service. English merged numeric text on the clinical reference requires independent recognition of BOTH exact Chinese fixture dates at the SAME location, with no extra text there; other images/dates/numbers/emails/keys remain blocked. No OCR content/geometry sidecar is published. Latest guardrail suite **41 pass**, including missing context, wrong location/date, additional identifiers, malformed/empty observations and one-language-only result. Strict Golden and source attestation remain unchanged; new cloud execution is pending.

Required: release audit; backend Ruff/mypy/tests; PostgreSQL16+real pgvector/Redis/migration/RAG; Flutter format/analyze/tests; macOS iOS no-codesign; Android secondary. Existing personal-sideload cloud job is also reviewed. Paid App Store signing is conditionally disabled for this branch by the existing project route, not by an RC test workaround.

Before releasing the revised bilingual export, cross-observation secret-label/value detection was explicitly preserved (e.g. `Token:` and a separate OCR value still block). Original per-observation text is checked before any independently confirmed fixture-date interpretation, followed by the full joined scan. New regression: **42 script tests pass**; no detector is skipped. In-progress review run [37285720755](https://github.com/h12534/personal-health-ai/actions/runs/37285720755), SHA `19aef14a10ba51bec308a5ece521408f23310f60`, is superseded by this safety correction; its configured workflow is not an upload/CI acceptance claim.

Run [37286056406](https://github.com/h12534/personal-health-ai/actions/runs/37286056406), SHA `48778d042fac2b0c7768cc1fd1719602d1e64611`: both export/upload gates remain blocked, standard at `nutrition-light` (EMAIL) and free at clinical (PHONE). All 86 screenshots remain unuploaded. A nutrition camera glyph was visually checked; a bare `@` is not itself an email/account. The email detector is corrected to actual address/handle syntax, including Unicode, whitespace and split observations; all those privacy negatives remain blocked. No suspicious numeric string is broadly accepted. OCR analysis now uses an in-memory 3× image to improve small Chinese-label recognition; the original exported PNG pixels are unchanged and no resampled sidecar is written. Fixed failure categories may also report language and known-label counts, never raw text/coordinates. Latest script suite **43 pass**, Ruff check/format pass; new real run pending.

Run [37287114359](https://github.com/h12534/personal-health-ai/actions/runs/37287114359), SHA `9a4575d5b993db42459a3ae6158d11b0882929e4`: clinical reference passes; free still blocks at its large-text health header, standard at small-keyboard OCR structure. No screenshots uploaded. The already synthetic large-text report header was viewed and its source verified; the same-location Chinese proof is extended only to its exact `上次体检2026年9月1日` in the two named L/D captures, not general numbers/dates. OCR boxes that genuinely overlap a clipped image edge are intersected with the image for context geometry, while ALL original recognized text is still scanned; nonfinite/degenerate/outside-image geometry blocks. Empty observations still block with a distinct fixed reason. Latest script suite **45 pass** including wrong header/date/location and clipped geometry with secret text; no tolerance change or image modification. Actual next run result pending.

Run [37288364174](https://github.com/h12534/personal-health-ai/actions/runs/37288364174), SHA `83726595b0d425edd90c41b8a171915c65443c20`: standard source attestation, Swift OCR, exact-set privacy/metadata scan and upload all **SUCCESS** (job 111692627699). `synthetic_ui_safety=passed images=74 metadata=none ocr=local`. Artifact [11335398755](https://github.com/h12534/personal-health-ai/actions/runs/37288364174/artifacts/11335398755), 4,308,096-byte ZIP, SHA-256 `1221e6164809fc7f6f0ad2d8ac55b35759ed359350704fb4241c85dff42840c8`; created 2026-10-05 09:16:22Z, expires 2026-10-06 09:16:21Z (**1 day**). Free 12 remain blocked/unuploaded: exact Chinese header context is confirmed, but English's mixed glyph/numeric observation fails the overly literal whole-numeric constraint. The correction interprets that independently confirmed source text at the same location, while still rejecting explicit phone/account labels and checking EVERY original email/key/token/device/path pattern. Tests include secret labels, additional Chinese phone text and other locations; suite remains 45 pass. The retry requests only free screenshots; all normal full test/build gates still run. No duplicate standard screenshot upload and no automatic pixel-baseline approval.

## 14. Final Screenshot Pack

Completed owner-authorized artifact-only review: 74 standard / 12 free. Free artifact [11335169497](https://github.com/h12534/personal-health-ai/actions/runs/37289471831/artifacts/11335169497), run 37289471831 / SHA `87eaf8d12f20f74d84aa8a6c7c881788281ba8bd`, privacy/upload job 111696356883 SUCCESS, `images=12 metadata=none ocr=local`; ZIP 796,680 bytes, SHA-256 `a2747b2e7d39d37d038421614c4c5f4b716f70d87ae1047f982e8318251adfd7`, expires 2026-10-06 09:25:10Z. Together with standard artifact 11335398755, exactly 86 necessary actual PNGs were uploaded; no repeat standard set in the free retry. Both ZIPs match their declared checksums and exact filename allowlists; all 86 downloaded files are canonical PNGs without metadata, logs or sidecars. All 86 were individually viewed and all pixel digests cross-verified. [Per-image ledger](docs/ui-redesign/MACOS_GOLDEN_REVIEW.md). The prior baseline-less capture jobs correctly remain failed; approval is a separate text-manifest change, not relabeling failed jobs green.

[UI_RC_PREVIEW](docs/ui-redesign/UI_RC_PREVIEW/README.md): the previously committed 32 PNGs and hash manifest remain unchanged. Twelve six-page L/D roots, eight small-phone, eight large-text, two action-library and two small-keyboard captures. The extra 8 free-mode preview images from the earlier 40-image local pack remain only in the unpushed pre-authorization local snapshot. The 74 standard / 12 free cloud images are now safely uploaded as artifact-only evidence with 1-day retention and completed individual review. No new screenshot is added to the public source/history. Widget-test images are not physical iPhone evidence.

Original Before / Phase 1 Reference remain [here](docs/ui-redesign/phase2-before/README.md); Phase 2 Final archived [here](docs/ui-redesign/phase2-final/README.md). Standalone Coach is a fixture host, not an added sixth navigation item. Static images cannot execute app actions or permissions.

## 15. Remaining UI debt

No confirmed remaining P0/P1/required P2 in the locally and cloud-verified presentation scope. The strict macOS Golden/full-test/no-codesign/unsigned build gate is CLOSED for implementation `6dae131`; physical daily-use acceptance remains OPEN. Unverified boundaries: actual iPhone VoiceOver/fonts/keyboard/gestures/Safe Area/haptic, hardware performance, landscape/iPad/Split View, very large action library/chat history, and the existing API HTTP-status precision limitation. Existing plugin SwiftPM-adoption warnings remain documented. Do not remove declared device support or change business APIs to conceal these limitations. No further P3 polish planned.

## 16. Git commit

Published implementation: `6b5a94bc61d4566631814b184802f88c0269f567`; diagnostic CI: `b4615e684e9afc404ed2398ab72a9081198bb697`. The earlier unpushed local `b415a41` / `ba0e557` commits contain new free-mode PNGs; they are preserved at local-only `codex/ui-rc-artifact-local-snapshot-20261005`. Current `feature/ui-redesign-impeccable` continues from the already-pushed b4615e6 with those text fixes reapplied, plus strict digest/security tooling, but no new PNGs. No force push or published-history rewrite is involved.

Individually approved text-only macOS baseline commit: `6dae1319b216cb2646c5de87efeeee2d6ec2a764`, verified by real successful run 37292995869. This final acceptance update changes documentation only; it does not silently claim its later commit SHA was the implementation tested by that run.

Backend, providers/controllers, models, repositories, authentication, DB, offline semantics, RAG/safety and iOS/Android remain unchanged against 55fea20. Workflow adds gated artifact-only review with fail-closed safety; no existing full test/build/check is removed or weakened. Crypto 3.0.7 moves from an already locked transitive package to a pinned test-only dependency; no runtime upgrade. Two earlier indentation issues were formatter-only; archive whitespace fixed without rescoring.

User-owned untracked `ui-preview/` and local golden failure evidence are preserved and excluded from staging. Do not claim the entire worktree is clean. No force push, history rewrite, unrelated branch push or merge.

## 17. 是否建议 merge

From the verified presentation/code/cloud-CI scope, the feature branch is ready for owner review and a merge recommendation. **No merge is executed**: the user explicitly requested no merge. Physical iPhone acceptance is separately pending and not certified by this recommendation.

## 18. 是否适合进入 iPhone 真机验收

Yes: real cloud CI has succeeded, so the existing personal installation route can proceed. This does not prove daily-use/native acceptance. Use cloud build + Windows personal signing + the owner's iPhone; no requirement to buy or own a Mac, no Apple ID password/2FA request. Real HTTPS API deployment/access is still missing; `.invalid` builds cannot establish login/AI/sync acceptance. Verify native permissions, offline/lifecycle/HTTPS sync and system accessibility on the iPhone. Pause new business features and additional visual exploration.

## Run Notes

Impeccable context reused once for this logical session; applicable references and craft floor read directly by main. Critique snapshot saved and closed; trend returned snapshots with different surface scopes, so no score-improvement claim was made. Detector returned `[]` / exit 0 with unsupported Dart coverage; no ignore rule, value suppression or security-hook workaround was added. Two reviewers were read-only, with focused closure checks; free-flavor follow-up was main's actual screenshot/test verification, not an invented independent score. No RC browser server/overlay was started. Temporary critique body was removed after validating its exact workspace path. User-owned local gallery and failure images remain untouched.

Owner authorization was executed: all 86 new synthetic PNGs passed automatic source/PNG/privacy checks before artifact upload, with one-day expiry, no image committed and no OCR/log/sidecar file attached. Main individually reviewed each image and independently verified all exact pixel hashes. Real strict implementation CI 37292995869 is SUCCESS; all six required regular jobs passed and all three full suites executed. The paid route remains suspended and optional screenshot capture is not requested, neither a skipped required test. No public repository was created, no arbitrary failure directory uploaded, no automatic Golden approval, test skip, main merge or force push. Native iPhone acceptance is still NOT RUN.
