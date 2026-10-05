# Individually reviewed macOS UI Golden evidence

Owner-authorized synthetic screenshots only. Main viewed **74 standard + 12 free = 86** actual PNGs individually, not an automatic or blanket Golden update. Font and fixture provenance was sealed; source network was forbidden. Full source/exact-set/PNG CRC/decompression/EXIF-text rejection/offline bilingual OCR checks passed before each upload. No real user data, names, accounts, keys, device identifiers, reports or meal photos appear in these fixtures.

The repository is public. These artifacts are treated as potentially accessible to external readers; short retention is not relied upon as privacy protection. Any failed safety check blocks upload, even with owner authorization.

| Set | Actual workflow / source | Approved artifact / expiry UTC |
|---|---|---|
| Standard, 74 | [37288364174](https://github.com/h12534/personal-health-ai/actions/runs/37288364174), `83726595b0d425edd90c41b8a171915c65443c20` | [11335398755](https://github.com/h12534/personal-health-ai/actions/runs/37288364174/artifacts/11335398755), 2026-10-06 09:16:21Z |
| Free, 12 | [37289471831](https://github.com/h12534/personal-health-ai/actions/runs/37289471831), `87eaf8d12f20f74d84aa8a6c7c881788281ba8bd` | [11335169497](https://github.com/h12534/personal-health-ai/actions/runs/37289471831/artifacts/11335169497), 2026-10-06 09:25:10Z |

Each ZIP checksum matches Actions metadata. Each ZIP contains exactly its named PNG set, no extra file or linked entry. Each downloaded PNG is already metadata-free. All 86 independent decoded-RGBA hashes and dimensions match the cloud comparator candidates. Source under `mobile/` is identical between the two capture commits; the free retry changes safety interpretation and upload scope only.

Images are NOT added to Git. `mobile/test/goldens/digests/macos.json` contains reviewed pixel hashes, exact dimensions, provenance and the individual notes below. Comparisons remain exact; missing entries and automatic updates fail. Existing Windows image baselines and Phase 2 archives remain unchanged. Expired artifacts do not disable future hash comparisons. A future pixel change still requires review, not auto-adoption.

This is a host-rendering baseline review, not physical iPhone/VoiceOver/keyboard/permission/performance acceptance. Pressure views intentionally include scrollable below-fold content, horizontally scrolled tabs/drafts and mocked keyboard insets; those must not be misreported as native device proof. No new visual direction, business feature or independent review score was invented.

Strict implementation verification is complete: [real CI 37292995869](https://github.com/h12534/personal-health-ai/actions/runs/37292995869), commit `6dae1319b216cb2646c5de87efeeee2d6ec2a764`, attempt 1, workflow conclusion SUCCESS. Primary job 111707578426 and personal job 111711280048 logs confirm three full suites of 268 passing tests, each with all 74 strict Goldens (222 comparisons of 86 distinct images); format/analyze, primary no-codesign build and both unsigned personal IPA builds/package checks succeed. Original backend/PostgreSQL/release/Android checks also succeed. Paid signing remains suspended; capture is optional and was not requested again. No required test was skipped, no tolerance increased, no new image committed. Later documentation commits are not retrospectively attributed to this verified source SHA.

| Individually viewed key | Main review disposition |
|---|---|
| `goldens/add-food-dark.png` | Quantity/unit and 137 kcal hierarchy, onPrimary CTA and rows clear in dark. |
| `goldens/add-food-light.png` | Same synthetic portion values and aligned units; light CTA/readability verified. |
| `goldens/canteen-dark.png` | Three empty-state groups and retry/add actions legible; synthetic, no food photos. |
| `goldens/canteen-light.png` | Empty/recovery hierarchy matches frozen C reference without crowded cards. |
| `goldens/coach-conversation-dark.png` | Intentional scrolled conversation; reply/disclaimer/composer and fixed bottom navigation clear. |
| `goldens/coach-conversation-light.png` | Scrolled viewport and send contrast verified; no account/contact values. |
| `goldens/coach-dark.png` | Empty trend/chat state and composer readable; evidence folded, no invented metrics. |
| `goldens/coach-keyboard-small-dark.png` | 320px inset capture; large multiline synthetic draft and contrasting send button stay reachable. |
| `goldens/coach-keyboard-small-light.png` | Keyboard-short viewport wraps rather than hiding draft; onPrimary send icon visible. |
| `goldens/coach-large-text-dark.png` | 200% explanatory copy wraps and scrolls; composer/nav remain anchored. |
| `goldens/coach-large-text-light.png` | Same large-type hierarchy without scaled-down type or overlap; scroll cut is intentional. |
| `goldens/coach-light.png` | Frozen C coach hierarchy, evidence disclosure and recovery copy visually verified. |
| `goldens/dashboard-dark.png` | 100.0 kg and nutrient/steps units clear; semantic hierarchy and selected fixed nav preserved. |
| `goldens/dashboard-light.png` | Source fixture metrics unchanged; uncluttered layout and muted unit contrast checked. |
| `goldens/dashboard-small-dark.png` | 320×568 wraps hero/caption naturally; remaining metrics scroll below fixed navigation. |
| `goldens/dashboard-small-light.png` | Small-phone nav labels stay visible; no squeezed metric or horizontal overflow. |
| `goldens/food-search-dark.png` | Semantic SearchBar, selected Recent filter, sample rice row and favorite affordance clear. |
| `goldens/food-search-light.png` | Same input/filter hierarchy and portion text; no extra photos/private identity. |
| `goldens/health-chat-dark.png` | Warning and medical-boundary text remain prominent; evidence folded and composer/nav readable. |
| `goldens/health-chat-light.png` | Urgent/medical labels retain text plus color, no synthesized diagnosis or real identity. |
| `goldens/health-data-detail-dark.png` | Modal sheet focus, 5.8%, exact report range and synthetic date chart verified. |
| `goldens/health-data-detail-light.png` | Sheet/underlay separation, ranges and non-causation caption are clear. |
| `goldens/health-keyboard-small-dark.png` | Matches reviewed 320×268 pressure fixture; scrolled tab/input ends visible, full draft asserted separately; native focus pending. |
| `goldens/health-keyboard-small-light.png` | Same short keyboard viewport and horizontal field scroll; no source change or lost stored text; native focus pending. |
| `goldens/health-knowledge-dark.png` | Expanded synthetic citation explicitly labeled; safe .invalid URL and folded evidence structure verified. |
| `goldens/health-knowledge-light.png` | Clear source title/excerpt/publisher hierarchy; no actual report or account fields. |
| `goldens/health-overview-dark.png` | Report-based flag/range, percent unit and two synthetic dates are unchanged; C focus hierarchy. |
| `goldens/health-overview-large-text-dark.png` | 200% metric/range stays readable; horizontal tab scrolling and below-fold trend are intentional. |
| `goldens/health-overview-large-text-light.png` | Large text not reduced; title/date and attention flag clear, bottom nav fixed. |
| `goldens/health-overview-light.png` | Clinical range and trend caption preserve non-diagnosis semantics, light hierarchy verified. |
| `goldens/health-overview-small-dark.png` | Compact metric fits 320px; horizontally scrollable tabs and below-fold trend preserved. |
| `goldens/health-overview-small-light.png` | Flag/range/unit and selected nav remain legible at small width. |
| `goldens/health-sync-dark.png` | Simulator fixture explicitly labeled; App sync toggles are not misrepresented as OS authorization. |
| `goldens/health-sync-light.png` | Permission explanation and switches clear; synthetic fixture has no raw HealthKit data. |
| `goldens/health-variant-clinical.png` | Retained reference-only composition; dates/axis/range read correctly, not a new production direction. |
| `goldens/health-variant-warm.png` | Retained warm reference fixture; two labeled source dates and medical boundary visible. |
| `goldens/lab-draft-dark.png` | Explicit synthetic indicator, displayed rounded value and full reference range; pending status and confirm clear. |
| `goldens/lab-draft-light.png` | Synthetic draft remains unconfirmed; edit/confirm roles unchanged, no real report filename. |
| `goldens/login-dark.png` | Empty email/password fields, no account values; quiet existing leaf and CTA contrast verified. |
| `goldens/login-light.png` | Clean login hierarchy and empty fields; no private identifiers/secrets. |
| `goldens/meal-draft-dark.png` | Synthetic estimate/range, hidden-oil caution, editable grams and confirm action remain visible. |
| `goldens/meal-draft-light.png` | Precise portion controls and estimate disclaimer match source; no real meal photo. |
| `goldens/notifications-dark.png` | Pre-permission explanation, selected supervision level and local schedule legible; App flags not OS grants. |
| `goldens/notifications-light.png` | Switch hierarchy, consent CTA and 08:00 synthetic time clear; no push device identifiers. |
| `goldens/nutrition-dark.png` | Offline state and unavailable meal details are explicit; camera disabled, fixed nav preserved. |
| `goldens/nutrition-flow-dark.png` | Synthetic next-meal range and editable-draft camera intent clear; no actual image/data. |
| `goldens/nutrition-flow-light.png` | Light nutrient/range hierarchy and camera CTA contrast reviewed; no extra cards. |
| `goldens/nutrition-light.png` | Unavailable-detail recovery text retained; metrics and zero-private camera icon verified. |
| `goldens/nutrition-small-dark.png` | 320px nutrient goals and offline caption fit; remaining camera content scrolls above fixed nav. |
| `goldens/nutrition-small-light.png` | Same compact hierarchy and visible targets; no artificial type shrinking. |
| `goldens/personal-free/health-data-detail-dark.png` | Free capability notice visible behind modal; sheet's synthetic value/range/chart remains legible. |
| `goldens/personal-free/health-data-detail-light.png` | Manual-only notice and unchanged source sheet semantics, no HealthKit grant claim. |
| `goldens/personal-free/health-overview-dark.png` | Full manual-recording notice scrolls with overview; fixed nav, ranges and synthetic trend preserved. |
| `goldens/personal-free/health-overview-large-text-dark.png` | 200% free notice is complete and scrollable; source metric continues below fold without shrinking. |
| `goldens/personal-free/health-overview-large-text-light.png` | Same full notice/date header and natural scroll; no fabricated Apple Health automatic sync. |
| `goldens/personal-free/health-overview-light.png` | Free mode retains C hierarchy and truthful capability text; no actual health/account data. |
| `goldens/personal-free/health-overview-small-dark.png` | 320px complete manual capability notice and report metric visible; remaining content scrolls normally. |
| `goldens/personal-free/health-overview-small-light.png` | Small free-mode notice wraps without fixed-header overflow; nav remains anchored. |
| `goldens/personal-free/health-sync-dark.png` | Manual fallback only, no HealthKit toggles or false grants/zero readings; full explanation visible. |
| `goldens/personal-free/health-sync-light.png` | Free capability boundary explicit with readable manual/local-notification explanation. |
| `goldens/personal-free/health-variant-clinical.png` | Archived clinical reference plus truthful free notice; source chart dates/ranges are synthetic. |
| `goldens/personal-free/health-variant-warm.png` | Archived warm reference respects free capability boundary and same synthetic report facts. |
| `goldens/privacy-data-dark.png` | Default-off lock, subordinate exports and clearly destructive outlined action; no actual exported data. |
| `goldens/privacy-data-light.png` | Deletion/retention explanation readable; safe default and secondary affordances match source. |
| `goldens/profile-dark.png` | Grouped settings and semantic labels visible without user name/email/account. |
| `goldens/profile-large-text-dark.png` | 200% rows expand naturally and scroll; fixed nav and disclosure affordances remain clear. |
| `goldens/profile-large-text-light.png` | Large-type setting rows wrap without compression; navigation remains anchored and labeled. |
| `goldens/profile-light.png` | Six-page style consistency with simple grouped disclosures; no commercial/account identity UI. |
| `goldens/reports-empty-dark.png` | Daily/weekly/monthly selection and generate-empty-report recovery readable; no invented score. |
| `goldens/reports-empty-light.png` | Explicit no-report state and restrained CTA match the reviewed reference. |
| `goldens/timeline-empty-dark.png` | Named filters/selected state and safe retry copy preserved; no fabricated health events. |
| `goldens/timeline-empty-light.png` | Empty timeline/action clear and high-contrast; no real dates or event identifiers. |
| `goldens/training-dark.png` | Synthetic plan with explicit start-before-recording disabled state; fields and RIR explanation clear. |
| `goldens/training-keyboard-small-dark.png` | Sheet handle/back, focused synthetic draft and contrasting send action match pressure fixture; native keyboard deferred. |
| `goldens/training-keyboard-small-light.png` | Same focused single-line scroll without stored-text loss; sheet hierarchy preserved. |
| `goldens/training-library-dark.png` | SearchBar and collapsed sample exercise use shared semantic styling; no network photos. |
| `goldens/training-library-light.png` | Search/collapsed action row and selected tab align with frozen design roles. |
| `goldens/training-light.png` | Plan, start CTA, disabled pre-session controls and fixed Training navigation verified. |
| `goldens/training-progress-dark.png` | Synthetic max-load history, dates and frequency readable; incomplete-history disclaimer retained. |
| `goldens/training-progress-light.png` | Source values/range and date labels match; no false complete-training claim. |
| `goldens/training-small-dark.png` | Small plan view scrolls before clipped lower inputs; fixed nav and start action visible. |
| `goldens/training-small-light.png` | 320px wrapping and scroll boundary preserved; no horizontal overflow introduced. |
| `goldens/weight-editor-dark.png` | Focused synthetic 98.6 kg, cancel/save distinction and modal contrast clear. |
| `goldens/weight-editor-light.png` | Unit suffix and precise decimal remain intact; modal hierarchy unchanged. |
| `goldens/workout-set-large-text-dark.png` | 200% stacked load/reps/RIR fields retain values and explanation; complete-set action scrollable. |
| `goldens/workout-set-large-text-light.png` | Same large-type stacked editor and intentional below-fold action, no value rounding or shrinking. |
