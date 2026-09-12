# System Architecture

Runalyst V2 is built around a unidirectional data flow: fetching from Apple Health, mathematically normalizing the data, running it through CoreML classifiers, and feeding the structured output into Apple FoundationModels for natural language coaching.

## High-Level Data Flow

The following Mermaid diagram illustrates the lifecycle of a `RunRecord` from extraction to UI presentation.

```mermaid
graph TD
    A[Apple HealthKit] -->|HKWorkout Queries| B(HealthKitManager)
    B -->|Raw Metrics| C{Framboise Engine}
    C -->|Normalizes dead-stops| D[Working Averages]
    D --> E(ModelManager / CoreML)
    E -->|Predicts Class| F[RunRecord DTO]
    F -->|Persisted| G[(SwiftData SQLite)]
    G -->|On-Demand Task| H(RunAnalyzerActor)
    H -->|Constructs Directive| I[CoachingEngine]
    I -->|System Prompt| J((Apple FoundationModels))
    J -->|Structured JSON| K[DrillRecommendation & Insight]
    K --> G
    G -->|@Query| L[SwiftUI Views]
```

## Core Components

### 1. Data Ingestion (`HealthKitManager.swift`)
**Role**: Extracts raw `HKWorkout` and `HKQuantitySample` data.
**Future Code Context**: When adding new biometrics (e.g., Running Power), add the `HKQuantityTypeIdentifier` to the read request. Do not attempt to calculate working averages here; pass raw arrays of buckets to the `FramboiseEngine`.

### 2. Normalization (`FramboiseEngine.swift`)
**Role**: The deterministic mathematical core. It strips out sensor "dead time" (e.g., heart rate < 40 BPM, pace = 0) to compute *Effective Working Averages*.
**Future Code Context**: Any changes to how fitness metrics are calculated must be made here deterministically. Do NOT rely on the AI/LLM to do math.

### 3. Machine Learning (`ModelManager.swift`)
**Role**: Interfaces with the offline-trained `RunalystClassifier.mlmodel`.
**Future Code Context**: Because CoreML output is non-sendable across Swift 6 strict concurrency boundaries, the `RunalystClassifierOutput` uses `@unchecked Sendable`. If you update the model to output new targets, ensure the Swift interface handles the new labels gracefully.

### 4. Background Processing (`RunAnalyzerActor.swift`)
**Role**: A `@ModelActor` that safely executes the heavy lifting in the background without blocking the UI.
**Future Code Context**: Never pass a `PersistentModel` instance across thread boundaries. Always extract primitive values into a `Sendable` DTO struct, perform the AI generation, and then apply the results back onto the model inside the actor.

### 5. Generative AI (`CoachingEngine.swift`)
**Role**: Sends the computed metrics and historical baselines to the native iOS 26 FoundationModels.
**Future Code Context**: When adding new drill types, add them to the system prompt's allowed ENUM constraint and update the deterministic logic in `RunAnalyzerActor` to flag them. Maintain strict token efficiency by using concise property names.

### 6. Presentation (SwiftUI)
**Role**: Declarative UI binding directly to the local SwiftData cache via `@Query`.
**Future Code Context**: Do not trigger data processing tasks implicitly within `var body`. Use explicit user intents (Pull to Refresh, Button Taps) combined with `.task` or unstructured `Task {}` blocks.
