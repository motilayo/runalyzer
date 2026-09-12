# Runalyst

Runalyst is a minimal, native iOS application acting as an "analytical mirror" for runners. It leverages **Apple HealthKit** to read your past running data, utilizes an on-device **CoreML classification model**, mathematically evaluates your performance via the custom **Framboise Engine**, and uses **Apple’s on-device Foundation Models** to generate plain-text coaching insights and technique drills. All of this happens completely privately, locally on-device, and without tracking live GPS or workouts.

## Features

- **Passive Sync**: Reads your previous running data seamlessly from Apple HealthKit.
- **Biomechanical Evaluation**: The custom Framboise Engine normalizes HealthKit data, excluding dead-stops, to calculate true working averages for metrics like cadence, heart rate, and vertical oscillation.
- **On-Device Machine Learning**: Uses a trained CoreML model (`RunalystClassifier`) to automatically classify run types (e.g., Threshold, Easy, Long Run) based on pace, heart rate zones, and biomechanics.
- **Private Generative AI**: Uses native iOS 26 on-device FoundationModels (`LanguageModelSession`) to parse deterministic performance directives into conversational, actionable coaching insights.
- **Actionable Drills**: Provides targeted technique drills (e.g., Cadence Pyramids, Tempo Surges) based on identified biomechanical gaps.
- **Minimalist Design**: A clean, native SwiftUI interface with high-contrast elements, responsive carousels, and smooth typography.

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Local Database**: SwiftData
- **Health Data**: HealthKit
- **Machine Learning**: CoreML
- **AI Engine**: FoundationModels (Apple Native On-Device AI)

## Requirements

- **iOS 26.0+** (Required for the latest `LanguageModelSession` FoundationModels features and SDK updates)
- **Xcode 18.0+**
- An iOS physical device with **Apple HealthKit** configured and containing running workout data. Testing on-device FoundationModels and the Neural Engine for CoreML requires a physical device.

## How to Run

1. Clone this repository to your local machine.
2. Open the project in **Xcode**.
3. In the project settings, ensure your **Team** is selected under Signing & Capabilities.
4. Ensure the **HealthKit** capability is added to your target.
5. Select a compatible iOS Physical Device (iOS 26+).
6. Build and Run (`Cmd + R`).

## Project Structure

- `Runalyst/Engine/`: The core analytical layer. Contains `FramboiseEngine` (for mathematical normalization) and `ModelManager` (for CoreML predictions).
- `Runalyst/Models/`: Contains the `SwiftData` schemas and migration plans (`RunRecord`, `CoachingInsight`, `DrillRecommendation`, `TrainingCorrection`).
- `Runalyst/LiveCoach/`: Structures and logic for integrating drill targets directly into Apple Watch workflows.
- `Runalyst/CoachingEngine/`: The Intelligence layer interfacing with FoundationModels (`CoachingEngine.swift`).
- `Runalyst/Managers/`: Contains singletons and actors like `HealthKitManager` for data ingestion.
- `Runalyst/Views/`: Minimalist SwiftUI components (Dashboard, DrillsLibrary, Onboarding, RunDetail, Settings).

## Development & CI/CD

Runalyst uses GitHub Actions for continuous integration.
- **CI & Release**: Automated linting (`SwiftLint`) and testing runs on all pull requests and pushes to `main`.
- **Seed Data Generation**: A python script (`generate_seed_runs.py`) can be triggered via workflow dispatch to generate synthetic balanced running data (CSV) used for offline CoreML training in Create ML.

## Note on Privacy & Scope

Runalyst explicitly **does not** integrate third-party cloud APIs (OpenAI, Anthropic, etc.), **does not** build a custom backend or require user authentication, and **does not** track live workouts or request GPS permissions. All analysis is done securely and privately on-device.
