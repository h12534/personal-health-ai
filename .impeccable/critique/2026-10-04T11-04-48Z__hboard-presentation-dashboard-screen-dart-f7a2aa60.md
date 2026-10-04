---
target: Phase 2 Home Today dashboard
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 0
target_identity: "file:E:\\codex项目\\个人身体健康管理\\mobile\\lib\\features\\dashboard\\presentation\\dashboard_screen.dart"
target_fingerprint: "sha256:beb7b01e6d022d58562f12e092e9e15ebfde1df8aafb3af1cf43bd00e14391d9"
target_path: "E:\\codex项目\\个人身体健康管理\\mobile\\lib\\features\\dashboard\\presentation\\dashboard_screen.dart"
timestamp: 2026-10-04T11-04-48Z
slug: hboard-presentation-dashboard-screen-dart-f7a2aa60
closed: true
---
# Phase 2 Home baseline critique

Closure: original two P1 categories resolved by main-agent-only implementation. A/B finish reviews confirmed no blockers against real Light/Dark captures and source. One protein-goal unit P2 was corrected. Score 24/40 is the historical baseline; no synthetic post-fix score. Final verification: analyzer clean; whole suite 79 tests. Native physical acceptance remains unverified.

Method: dual-agent (A: ui_review_a · B: ui_review_b), independent read-only reviews. Mode: Operate. C is fixed; no shape exploration.

| # | Heuristic | Score | Key finding |
| --- | --- | --- | --- |
| 1 | Status | 2 | Refresh is a no-op, date absent |
| 2 | Real-world match | 3 | Familiar labels, useful weight context |
| 3 | Control | 3 | Stable shell, cancellable entry |
| 4 | Consistency | 3 | Theme aligned, old card structure |
| 5 | Prevention | 2 | Invalid weight input silent |
| 6 | Recognition | 3 | Labeled data, focus must be inferred |
| 7 | Efficiency | 2 | Recording available, focus unclear |
| 8 | Minimalism | 2 | Seven equal metric cards |
| 9 | Recovery | 2 | Raw errors, weight input lost |
| 10 | Help | 2 | Limited inline recovery context |
| Total | | 24/40 | Acceptable |

## Specificity and overall impression

Private health language is established but the old card topology is still interchangeable with a nutrition tracker. Today → focus → key data → tasks → secondary next-step insight is pinned by the user. Cognitive load is moderate: six possible top tasks plus seven equivalent metric containers. The calm arrival becomes an effort to infer what matters, with invalid-save and recovery valleys.

## Working

Weight average and weekly change support long-term reading. Missing goals/steps have actual text. Existing task states, callbacks and stable navigation provide a foundation.

## Priority Issues

P1 — Rebuild truthful Today/action hierarchy. Use data.date and actual pending tasks in server order, distinguish skipped/unknown states; never equate !isCompleted with pending. Preserve all seven metric records via primary/secondary grouping and keep deterministic aiNextAction unchanged, not falsely labeled model insight. No new health conclusions or score.

P1 — Harden the complete entry/read path. Replace fixed-height two-column metrics with content-adaptive layout, wire the existing provider refresh, add accessible weight validation and friendly error with preserved input, maintain null/zero-goal meaning and missing steps. Keep original callbacks, open-all-tasks and all old tests.

Suggested methods: layout/typeset/distill for hierarchy; harden/adapt for text, state and recovery; polish/audit after actual screenshots.

## Personas and minor observations

Sam: fixed metric ratio and untranslated validation failure may block large text and recovery. Casey: long task block pushes primary action down and failure requires retyping. Both need a visible real focus and preserved inputs. Sidebar/five destinations are not cognitive overload in this context. No fake offline freshness, no fabricated task engine.

## Detector / evidence

B attempted real Dart detect: [] / exit 0, unsupported, no native-clean meaning. Baseline is source and Windows Flutter golden with test font, not iPhone/VoiceOver/performance. No native browser overlay/server.

Questions skipped: 2 Priority Issues; sequence, C direction, scope and primary task route are already explicit.
