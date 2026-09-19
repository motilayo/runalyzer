# [Short title of solved problem and decision]

* **Status**: [Draft | Proposed | Accepted | Rejected | Deprecated | Superseded by [ADR-0000](0000-example.md)]
* **Date**: YYYY-MM-DD
* **Deciders**: [List of people involved]
* **Consulted**: [List of people consulted]
* **Informed**: [List of people informed]

## Context and Problem Statement

[Describe the context, problem, and forces at play. Include user experience impact, data constraints (e.g. HealthKit, watchOS, SwiftData), and why a decision was required.]

## Decision Drivers

* [Driver 1, e.g., Physiological correctness (recovery is not a graded effort)]
* [Driver 2, e.g., WatchOS WorkoutKit interval structure invariance]
* [Driver 3, e.g., Avoidance of scalar threshold failure on jogged recoveries]

## Considered Options

* [Option 1 - The selected decision]
* [Option 2 - Alternative approach A]
* [Option 3 - Alternative approach B]

## Decision Outcome

Chosen option: "[Option 1]", because [justification. e.g., only option that satisfies core invariants without ad-hoc threshold tuning].

### Positive Consequences

* [e.g., Eliminates false-positive work intervals on recovery jogs]
* [e.g., Guarantees exact 1-to-1 parity between prescribed iterations and UI pips]

### Negative Consequences / Tradeoffs

* [e.g., Requires drill duration/iteration schedule metadata to determine expected sequence length]

## Pros and Cons of the Options

### [Option 1]

* Good, because [argument a]
* Good, because [argument b]
* Bad, because [argument c]

### [Option 2]

* Good, because [argument a]
* Bad, because [argument b]

## Links and References

* [Link to issue / PR / commit]
* [Related ADRs, if any]
