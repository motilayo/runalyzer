# Runalyzer

Runalyzer is a native iOS application acting as an analytical mirror for runners. It reads running data from **Apple HealthKit**, processes each workout through a local Framboise metrics pipeline, and uses **Apple's on-device Foundation Models** to generate plain-text coaching insights and technique drills. The app is private and local: it does not track live GPS, require an account, or send workout data to a cloud service.

## Features

- **Passive Sync**: Reads your previous running data seamlessly from Apple HealthKit.
- **Framboise Metrics**: Builds one-minute heart-rate, cadence, pace, vertical-oscillation, VO2 Max, ground-contact, and stride-length buckets, trims outliers, adds heuristic tags, and classifies the run.
- **Correct Pace Display**: Formats pace as `minutes:seconds` for the active kilometer or mile unit across dashboard summaries, filtered runs, and run details.
- **Private AI**: Uses native iOS on-device FoundationModels (`LanguageModelSession`) to analyze performance and suggest drills with qualitative fatigue observations.
- **Actionable Drills**: Provides coaching headlines, aerobic and biomechanical observations, distinct work and recovery instructions, and deterministic cadence targets.
- **WorkoutKit Handoff**: A `Start Drill` action creates a native running `CustomWorkout` with cadence alert boundaries and presents it through Apple's workout preview.
- **Progression Hub**: The dashboard flows from time and distance filters to seven/thirty-day macro statistics, fatigue insight, and the filtered run list.
- **Minimalist Design**: A clean, native SwiftUI interface with high-contrast elements and compact metric surfaces.

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Local Database**: SwiftData
- **Health Data**: HealthKit
- **AI Engine**: FoundationModels (Apple Native On-Device AI)
- **Workout Handoff**: WorkoutKit

## Requirements

- **iOS 18.0+** for the app and **iOS 26.0+** for FoundationModels coaching features
- **Xcode 16.0+**
- An iOS Device or Simulator with **Apple HealthKit** configured and containing running workout data. Note that testing on-device FoundationModels usually requires a physical device with Neural Engine support.

## How to Run

1. Clone this repository to your local machine.
2. Open the project in **Xcode**.
3. In the project settings, ensure your **Team** is selected under Signing & Capabilities.
4. Ensure the **HealthKit** capability is added to your target.
5. In your `Info.plist`, verify that the following keys are present with descriptive messages for the user:
   - `NSHealthShareUsageDescription` (e.g., "Runalyzer needs to read your workout data to provide AI coaching insights.")
6. Select a compatible iOS Simulator or Physical Device (iOS 18+).
7. Build and Run (`Cmd + R`).

### Command-line validation

To compile the app against an installed simulator:

```sh
xcodebuild -project Runalyzer.xcodeproj -scheme Runalyzer -sdk iphonesimulator \
   -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The app target builds successfully with this command. The current `RunalyzerTests` target is missing a test-bundle `Info.plist` or generated plist setting, so `build-for-testing` may stop during test-bundle code signing until that project configuration is repaired.

## Project Structure

- `Runalyzer/Models/`: Contains the `SwiftData` schemas (`RunRecord`, `CoachingInsight`, `DrillRecommendation`).
- `Runalyzer/Managers/`: Contains singletons and actors like `HealthKitManager` for data ingestion.
- `Runalyzer/CoachingEngine/`: Framboise bucket processing, FoundationModels coaching, and progression macro queries.
- `Runalyzer/LiveCoach/`: WorkoutKit translation, cadence alert construction, and live coaching support.
- `Runalyzer/Views/`: SwiftUI components for the dashboard, filtered runs, run details, onboarding, and settings.

## Data and UI behavior

HealthKit sync processes workouts oldest-to-newest. `FramboiseEngine` is the single owner of bucketed metric reads and derives both raw and working values from those buckets. Working averages remove low-value outliers before classification and tagging; the run detail toggle makes that distinction visible.

Pace is stored as decimal minutes per kilometer and formatted only at the presentation boundary. The shared `formattedPaceString` conversion first calculates total seconds, preventing values such as `415:16/km` when the intended pace is `6:55/km`.

AI output is generated on-device and is informational only. It does not replace professional medical or coaching advice. Macro fatigue output is required to avoid numbers and exact measurements, while deterministic metric comparisons and drill targets remain in Swift.

## Note on Privacy & Scope

Runalyzer explicitly **does not** integrate third-party cloud APIs (OpenAI, Anthropic, etc.), **does not** build a custom backend or require user authentication, and **does not** track live workouts or request GPS permissions. All analysis is done securely and privately on-device.
