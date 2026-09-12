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

## Documentation & Architecture

For a deep dive into how Runalyst operates under the hood, please refer to our detailed documentation:
- **[System Architecture](docs/ARCHITECTURE.md)**: Unidirectional data flow, SwiftUI integration, and Live Coaching/Apple Watch structures.
- **[AI & CoreML Pipeline](docs/AI_PIPELINE.md)**: Feature vectors, Create ML training, Apple TN3193 token limits, and strict `@Generable` schema constraints.
- **[Data Schema & Persistence](docs/DATA_SCHEMA.md)**: SwiftData caching strategy, working vs raw metrics, and our V1 -> V2 schema wipe migration logic.
- **[Contributing](CONTRIBUTING.md)**: Code style, environment setup (iOS 26, Xcode 18), and PR guidelines.

## Project Structure

- `Runalyst/Engine/`: The core analytical layer. Contains `FramboiseEngine` (for mathematical normalization) and `ModelManager` (for CoreML predictions).
- `Runalyst/Models/`: Contains the `SwiftData` schemas and migration plans.
- `Runalyst/LiveCoach/`: Structures and logic for integrating drill targets directly into Apple Watch workflows.
- `Runalyst/CoachingEngine/`: The Intelligence layer interfacing with FoundationModels.
- `Runalyst/Managers/`: Contains singletons and actors like `HealthKitManager`.
- `Runalyst/Views/`: Minimalist SwiftUI components.

## Development & CI/CD

Runalyst uses GitHub Actions for continuous integration.
- **CI & Release**: Automated linting (`SwiftLint`) and testing runs on all pull requests and pushes to `main`.
- **Seed Data Generation**: A python script (`generate_seed_runs.py`) can be triggered via workflow dispatch to generate synthetic balanced running data (CSV) used for offline CoreML training in Create ML.

### Training the CoreML Classifier
To train a new version of the `RunalystClassifier.mlmodel`:
1. **Download Data**: Trigger the "Generate Seed Data" workflow on GitHub Actions and download the `coreml-training-data` artifact (CSV) when it completes.
2. **Open Create ML**: On your Mac, open Xcode and select **Xcode > Open Developer Tool > Create ML**.
3. **Create Project**: Select **File > New Project**, choose **Tabular Classification**, and name the project.
4. **Configure**: Under *Training Data*, import your CSV. Set the *Target* to `targetClass` and select the relevant metrics (e.g., `averagePace`, `averageHeartRate`, `percentZone4`, etc.) under *Features*.
5. **Train & Export**: Click **Train**. Once evaluation finishes, go to the *Output* tab, click **Get**, and drag the resulting `.mlmodel` file into the Xcode project to overwrite the old one.

## Note on Privacy & Scope

Runalyst explicitly **does not** integrate third-party cloud APIs (OpenAI, Anthropic, etc.), **does not** build a custom backend or require user authentication, and **does not** track live workouts or request GPS permissions. All analysis is done securely and privately on-device.
