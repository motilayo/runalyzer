# 1. Record Architecture Decisions

* **Status**: Accepted
* **Date**: 2026-09-18
* **Deciders**: Runalyst Engineering Team

## Context and Problem Statement

As Runalyst grows in biometrics processing, HealthKit data ingestion, SwiftData versioning, on-device FoundationModels inference, and Apple Watch WorkoutKit integration, architectural decisions need durable, accessible records. 

Without formalized architectural records:
1. Past rationale for non-obvious engineering choices (e.g., deterministic Swift directives vs LLM prompts, single-responsibility actor boundaries, invariant sequence grammars) becomes tribal knowledge.
2. Future contributors or AI agents risk inadvertently breaking core architectural guardrails or re-litigating settled trade-offs.
3. Bug fixes risk becoming ad-hoc, symptom-treating patches instead of architecturally coherent solutions.

## Decision Drivers

* Maintain clarity on non-obvious technical decisions across SwiftData, HealthKit, WorkoutKit, and FoundationModels.
* Ensure AI coding assistants and human developers share identical context on design choices.
* Prevent regressions where intentional architectural invariants are undone.

## Considered Options

* **Option 1**: Architecture Decision Records (ADRs) stored in `docs/adr/` alongside code in the repository.
* **Option 2**: Ad-hoc documentation in pull requests and commit descriptions.
* **Option 3**: Monolithic guideline file (`AGENTS.md` / `ARCHITECTURE.md` only).

## Decision Outcome

Chosen option: **Option 1 (ADRs in `docs/adr/`)**, supplemented by high-level rules in `AGENTS.md`.

ADRs provide version-controlled, immutable snapshots of architectural choices at the moment they are made. `AGENTS.md` and `ARCHITECTURE.md` remain the living references, while individual ADRs capture the historical decision logs, considered alternatives, and trade-offs.

### Positive Consequences

* Decisions are versioned alongside the code they affect in Git.
* Reviews can reference specific ADR numbers (e.g., "See ADR-0002 for interval sequence parsing").
* Easy onboarding for new developers and AI assistants.

### Negative Consequences / Tradeoffs

* Slight documentation maintenance overhead when proposing major design overhauls.

## Links and References

* [Michael Nygard's ADR format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
* [Runalyst Architecture Documentation](../ARCHITECTURE.md)
* [Runalyst AI Coding Guidelines](../../AGENTS.md)
