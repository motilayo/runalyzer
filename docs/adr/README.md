# Architecture Decision Records (ADRs)

This directory documents key architectural decisions made in the Runalyst project. Each record captures the context, decision drivers, considered alternatives, and consequences of significant technical choices.

## Index of Records

| ADR | Title | Status | Date |
| :--- | :--- | :--- | :--- |
| [0001](0001-record-architecture-decisions.md) | [Record Architecture Decisions](0001-record-architecture-decisions.md) | Accepted | 2026-09-18 |
| [0002](0002-structural-sequence-parsing-for-interval-workouts.md) | [Structural Sequence Parsing and Work-Only Adherence for Interval Workouts](0002-structural-sequence-parsing-for-interval-workouts.md) | Accepted | 2026-09-18 |
| [0003](0003-topological-signature-classification-for-run-types.md) | [Topological Signature Classification for Run Types](0003-topological-signature-classification-for-run-types.md) | Accepted | 2026-09-24 |
| [0004](0004-stride-length-biomechanical-analysis.md) | [Incorporating Stride Length into Biomechanical Analysis and Coaching](0004-stride-length-biomechanical-analysis.md) | Accepted | 2026-09-24 |
| [0005](0005-dual-scope-refresh-and-healthkit-sync-lifecycle.md) | [Dual-Scope Refresh and HealthKit Synchronization Lifecycle](0005-dual-scope-refresh-and-healthkit-sync-lifecycle.md) | Accepted | 2026-09-24 |

---

## Authoring Guidelines

When introducing new architectural patterns, major refactors, or resolving structural bugs:
1. Copy [template.md](template.md) to `docs/adr/NNNN-[short-title].md`.
2. Assign the next sequential 4-digit number.
3. Document the context, root cause (if bug), decision drivers, and invariants that must be preserved.
4. Add the new record to the index above.
