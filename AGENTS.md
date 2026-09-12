# AI Coding Guidelines for Runalyst

This `AGENTS.md` file acts as the primary repository of architectural context, technical rules, and best practices for developing and maintaining the Runalyst iOS application. It is primarily intended for AI assistants, but serves as useful documentation for human developers.

## 1. SwiftData & Concurrency Architecture

- **Thread Safety with ModelContext**: SwiftData `PersistentModel` and `ModelContext` are not `Sendable` and cannot be safely accessed across `await` boundaries within unstructured or detached tasks. To perform async operations (like LLM generation), extract necessary properties into a `Sendable` struct beforehand, await the operation, and then apply updates back on the `MainActor` or within a dedicated `@ModelActor`.
- **Background Operations**: The 30-day relative baseline logic is encapsulated entirely within a `@ModelActor` (e.g., `RunAnalyzerActor`) to safely execute SwiftData fetches, mathematical calculations, and LLM inference in the background, avoiding passing non-Sendable model arrays across threads.
- **Model Migrations**: In SwiftData, assigning inline default values (e.g., `var newField: String = ""`) in a `@Model` class does not satisfy SQLite/CoreData lightweight migration requirements for existing rows. To add new properties to a schema without causing a 'Validation error missing attribute values' crash or requiring a `SchemaMigrationPlan`, mark the newly added properties as Optional (e.g., `String?`) and gracefully unwrap them in code.
- **Sort Orders**: When using SwiftData and UI sorting, maintain separate sort directions for data ingestion versus presentation: process background data oldest-to-newest to build historical context for AI inference pipelines, but use `@Query(sort: \.date, order: .reverse)` in views like `DashboardView` to present newest runs first.
- **Clearing Cache**: The "Resync Health Data & Rebuild AI Insights" button in `SettingsView` deletes all local `RunRecord` entries via `modelContext.delete(run)` and clears cached `@AppStorage` dashboard headlines/bodies. HealthKit data is then re-fetched and AI insights regenerated from scratch.

## 2. FoundationModels & AI Coaching Engine

- **Availability**: FoundationModels SDK components (e.g., `CoachingEngine`, `RunInsight`, and `SuggestedDrill`) must retain their `@available(iOS 26.0, *)` annotations, and call sites invoking them must wrap the usage in `if #available(iOS 26.0, *)` checks to compile properly.
- **Structured Output**: When defining structured output for the LLM using the `@Generable` macro, use explicit, semantically named properties for distinct fields (e.g., `drillWork` for active reps/sets, `drillRecovery` for rest periods, `drillCues`, `drillEffort`, `drillPurpose`) instead of generic arrays. Pair each property with a precise `@Guide` description to prevent the model from misinterpreting distinct roles.
- **Schema Mapping & Fallbacks**:
  - Do not instruct the model to output raw JSON or YAML strings. The SDK compiles the Swift struct directly into its own lower-level proprietary schema. Forcing standard JSON output bypasses native optimizations and increases token overhead.
  - To prevent parse failures, explicitly define the output requirements for *every* field in the `@Generable` payload struct directly within the system prompt and by using strict negative constraints in `@Guide` descriptions.
  - Always wrap the `LanguageModelSession.respond` call in a `do-catch` block and provide a graceful fallback. Wrap fallback text fields generated during AI `do-catch` blocks in `String(localized:)`.
- **System Prompt & Tone**:
  - The system prompt enforces a conversational tone via the consolidated rule `conversational, motivational tone; speak directly to the runner`.
  - For AI prompt language localization, append instructions directly to the system prompt commanding the LLM to output in the user's active device language (e.g., `Respond entirely in \(Locale.current.language.languageCode)`).
  - **Prompt Density**: Keep system prompts to ~10 rules max for on-device models. Consolidate redundant rules (e.g., merge tone + person rules). Fewer rules = higher adherence on small models.
- **Deterministic Math & Directives**:
  - AI AI coaching prioritizes actionable form metrics like cadence. Vertical Oscillation is mathematically linked to cadence. A high vertical oscillation (> 10 cm) indicates bounding/overstriding, prompting cadence relationship analysis and drills like 'Cadence Pyramids'.
  - Mathematical computations for baseline statistics, metric deltas, and drill targets must be completely deterministic and computed locally in Swift to prevent LLM math hallucinations. Inject explicit contextual English strings (e.g., '150 SPM (BELOW the 150 SPM floor)') instead of raw numbers.
  - Evaluate metrics locally via Swift in `RunAnalyzerActor` to compute a `directiveContext`. Pass this diagnostic directive to the LLM prompt alongside a strict rule (`strictly_follow_the_DIRECTIVE_for_tone_and_drill_selection`) rather than relying on the LLM to diagnose issues from raw metrics.
  - **Deterministic Guardrails over Prompt Guardrails**: Never ask the LLM to reason about competing priorities (e.g., "follow the goal but not if fatigued"). Instead, resolve conflicts deterministically in Swift before constructing the directive. For example, when fatigue is detected (`paceDiff < 0 && hrDelta > 0`), Swift strips the user's training goal and injects `"PRIORITY: prescribe Easy Aerobic Recovery. Safety overrides any race goal."` — the model receives one unambiguous signal.
- **Token Limits**: To comply with Apple's TN3193 strict 4,096-token limit, minimize token usage by utilizing concise property names in `@Generable` structs, capping array sizes by specifying limits in the `@Guide(description:)` string, keeping system prompts imperative and under 3 paragraphs, and injecting input data as compact, comma-separated strings. (Do not use the `maximumCount` parameter as it causes macro expansion compilation errors).
- **Strict Guardrails**:
  - No isolated cadence judgments without pace. Emphasis on rhythm and aerobic stability.
  - Drill titles must be exactly one of: Cadence Pyramids, Rhythm Intervals, Tempo Surges, Strides.
  - Separate historical and current data using concise, comma-separated strings (e.g., 'Current:', 'Baseline:', 'Deltas:'). Include strict system rules to evaluate changes based exclusively on comparing the current run against the baseline.
  - Prompt data must preserve explicit `GROUP_A_CARDIO`, `GROUP_B_FORM`, `GROUP_C_PACING` labels so the model knows how to group its observation sentences.
- **Training Goal Context**: The user's aspirational training goal (e.g., "5K Race", "Base Building") is stored in `@AppStorage("trainingGoal")` and injected into the `directiveContext` string by Swift — not as a separate prompt field. When fatigue is detected, Swift omits the goal entirely and substitutes a recovery-priority directive.
- **Drill Schema Detail**: The AI Drill schema and UI drill card must explicitly maintain and display four distinct sequential fields: `drillPurpose`, `drillWork` (active reps/sets), `drillEffort`, and `drillRecovery` (rest instructions). Do not merge recovery instructions into the `drillWork` field. Note: `targetCadence` must be defined as `String?` rather than `Int?` to accommodate steady cadence bands (e.g., '142-146'), while `previousCadence` is `Int?`.

## 3. HealthKit & Data Management

- **Data Ingestion Sync**: The primary HealthKit data synchronization logic is centralized in `ContentView.swift` via `syncData()`. Child views (like `DashboardView`) should trigger syncs by accepting an async closure (e.g., `onSync`) rather than implementing direct manager calls.
- **Run Iteration**: During HealthKit syncs, iterate through unsynced workouts sequentially from oldest to newest. Generate their AI insights by invoking a `@ModelActor` for each run and introducing deliberate delays (e.g., 5s normally, 10s every 5 runs) to minimize device overhead and prevent memory overload or model timeouts.
- **Filters & Units**: When fetching HealthKit data, apply user preference filters (like `minimumRunDistance`) directly to the sync operation in `HealthKitManager`. Ensure unit conversions are handled during comparison.
- **Extracted Metrics**: Runalyst extracts advanced biomechanical and fitness metrics from HealthKit, including `HKQuantityTypeIdentifier.runningVerticalOscillation`, `.runningGroundContactTime`, `.runningStrideLength`, and `.vo2Max`. Vertical Oscillation is tracked in cm as a Double.
- **VO2 Max Logic**: VO2 Max is decoupled from individual run cards and treated as a global profile stat. To fetch the absolute latest global value, use a predicate-free `HKSampleQuery` sorted by `HKSampleSortIdentifierEndDate` descending.
- **Baselines**: When calculating longitudinal baseline metrics (e.g., 30-day averages), use a strict rolling baseline time-locked to the specific run being analyzed. Filter historical workouts using a strict less-than comparison (`$0.date < targetDate`).
- **Background Delivery**: When configuring HealthKit background delivery and `HKObserverQuery`, always store a reference to the active query to prevent duplicate registrations, and ensure the `completionHandler` is called only after fully awaiting asynchronous updates.
- **Permissions Prompt**: To prompt for newly added HealthKit data types without needing app reinstallation, call `HealthKitManager.shared.requestAuthorization()` inside a `.task` modifier on the main `DashboardView`.
- **Global Preferences**: Global user preferences (like unit system `useMetricSystem` and `trainingGoal`) are managed via `@AppStorage` in SwiftUI and read via `UserDefaults.standard.object(forKey:)` in non-UI code. Dynamically inject explicit string definitions of the currently active unit system into Foundation Model prompts. Locale specific formatting (e.g. `DateFormatter.locale`) must be `en_US_POSIX`.
- **Working Stats Engine**: `FramboiseEngine.calculateWorkingAverages` accepts `rawWorkoutDuration`, `rawWorkoutDistance`, and `originalBucketCount`. When no dead-stop buckets are trimmed (`trimmed.count == originalBucketCount`), the engine bypasses bucket summation and strictly inherits raw HealthKit values. This prevents floating-point precision loss from causing Working Stats to diverge from Workout Stats on continuous runs.
- **Run Classification Labels**: The canonical run classification for moderate-effort steady runs is `"Steady Effort"` (not `"Steady Run"`). This label must be consistent across `FramboiseEngine.classifyRun()`, the `classificationOptions` array in `RunDetailView`, mock data seeders (`seedDirectToSwiftData`, `generate_seed_runs.py`), and any UI pickers.

## 4. SwiftUI Presentation & Layout

- **Lazy Evaluation**: When using `LazyVStack` in SwiftUI, do not wrap the inner dynamically loaded elements (like `ForEach`) in a standard `VStack`, as this breaks lazy evaluation. Use `Section` instead.
- **Aggregated Data Display**: When computing global UI metrics in `DashboardView`, use the raw, unfiltered SwiftData `@Query` array to ensure biometric data from shorter runs isn't excluded. Only apply dynamic distance filters (`filteredRunRecords`) when displaying lists of individual runs.
- **Race Conditions**: Pass an `isSyncing` flag down to views and only allow them to trigger on-demand `.task` generation when `!isSyncing` to prevent race conditions.
- **Refreshable modifier**: The `.refreshable` modifier's internal task is cancelled if the view re-renders. Wrap long-running operations like HealthKit syncs in an unstructured `Task` (e.g., `Task { await syncData() }`) and explicitly catch/ignore `CancellationError`.
- **Property Wrappers**: Property wrappers like `@Environment` must be declared at the top level of the view struct, not nested within `var body: some View`.
- **NavigationStack Memory**: Use `.navigationDestination(for: Model.self)` inside a `NavigationStack` with `value`-based `NavigationLink`s rather than the legacy `NavigationLink(destination:)` to avoid memory-hogging.
- **Layout Adjustments**:
  - For responsive grids, use `GridItem(.adaptive(minimum: 140), spacing: 16)`.
  - To prevent SwiftUI `ScrollView` content from bleeding under custom top navigation bars with transparent backgrounds, apply `.background(.regularMaterial.ignoresSafeArea(edges: .top))` to the header stack.
  - Use `.safeAreaInset(edge: .bottom, spacing: 80)` instead of `.overlay()` for floating persistent UI elements over a `ScrollView`.
- **UI Element Specs**:
  - Use tap-to-alert pattern involving `.contentShape(Rectangle())`, `.onTapGesture { showingInfo = true }`, and `.alert` modifier for metric definitions. Do not trigger explainer popups automatically on picker/segmented control changes — only show them when the user explicitly taps the info (ⓘ) icon.
  - Dashboard cards display 30-Day Average SPM and Average Pace rather than static VO2 Max.
  - Historical run rows should dynamically display Focus Pill tags derived from the AI insight's `drillRecommendation.drillTitle` (e.g., 'Cadence').
  - Include a prominent disclaimer stating that the insights are AI-generated, are for informational purposes only, and do not replace professional medical or coaching advice.
  - Use native SwiftUI colors like `.secondary` instead of `.tertiaryLabel`.
  - `UserProfileView` dynamically computes Experience Level and Weekly Volume from the user's SwiftData `RunRecord` history (last 30 days) rather than using static hardcoded values. Training Goal is the only user-editable field.

## 5. Tooling Guidelines

- **Bash Scripting**: When modifying Swift files programmatically via bash (sed/python), replace complete logical blocks or overwrite the file entirely instead of using targeted string insertions to avoid nested duplications and syntax errors.
