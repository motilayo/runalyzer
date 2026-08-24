# Runalyzer

Runalyzer is a minimal, native iOS application acting as an "analytical mirror" for runners. It leverages **Apple HealthKit** to read your past running data and uses **Apple’s on-device Foundation Models** to generate plain-text coaching insights and technique drills—completely privately, locally on-device, and without tracking live GPS or workouts.

## Features

- **Passive Sync**: Reads your previous running data seamlessly from Apple HealthKit.
- **Private AI**: Uses native iOS on-device FoundationModels (`LanguageModelSession`) to analyze your performance and suggest drills.
- **Actionable Drills**: Provides coaching headlines, observations on aerobic effort or biomechanics, and actionable technique drills.
- **Minimalist Design**: A clean, native SwiftUI interface with high-contrast elements and smooth typography.

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Local Database**: SwiftData
- **Health Data**: HealthKit
- **AI Engine**: FoundationModels (Apple Native On-Device AI)

## Requirements

- **iOS 18.0+** (Required for the latest `LanguageModelSession` FoundationModels features)
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

## Project Structure

- `Runalyzer/Models/`: Contains the `SwiftData` schemas (`RunRecord`, `CoachingInsight`, `DrillRecommendation`).
- `Runalyzer/Managers/`: Contains singletons and actors like `HealthKitManager` for data ingestion.
- `Runalyzer/CoachingEngine/`: The Intelligence layer interfacing with FoundationModels (`CoachingEngine.swift`).
- `Runalyzer/Views/`: Minimalist SwiftUI components (Dashboard, Onboarding, RunDetail, Settings).

## Note on Privacy & Scope

Runalyzer explicitly **does not** integrate third-party cloud APIs (OpenAI, Anthropic, etc.), **does not** build a custom backend or require user authentication, and **does not** track live workouts or request GPS permissions. All analysis is done securely and privately on-device.
