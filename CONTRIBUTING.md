# Contributing to Runalyst

Thank you for your interest in contributing to Runalyst! 

## Environment Setup
- **macOS**: You must be running a macOS version compatible with Xcode 18.
- **Xcode 18+**: Required for the iOS 26 SDK and the newest `LanguageModelSession` FoundationModels APIs.
- **Physical Device**: While you can run the app on the simulator to view the UI and test HealthKit syncs (if mock data is injected), **testing the generative AI coaching requires a physical iOS device** with a Neural Engine. FoundationModels will often fail or fallback on the simulator.

## Code Style & Linting
We use **SwiftLint** to enforce a consistent code style.
- Our custom rules are defined in `.swiftlint.yml`.
- A GitHub Actions workflow automatically runs SwiftLint on all Pull Requests.
- **Tip**: To ensure your PR passes CI, install SwiftLint locally (`brew install swiftlint`) and run `swiftlint` in the project root before committing.

## Architectural Guidelines
Before opening a PR that alters the core logic, please read our documentation to understand the V2 architecture:
- [System Architecture](docs/ARCHITECTURE.md)
- [AI & CoreML Pipeline](docs/AI_PIPELINE.md)
- [Data Schema & Persistence](docs/DATA_SCHEMA.md)

Also, check `AGENTS.md` for specific rules regarding Swift concurrency, UI layout, and token optimization.

## Opening a Pull Request
1. Fork the repository and create your branch from `main`.
2. If you've added code that should be tested, add tests.
3. Ensure the test suite passes (`Cmd + U` in Xcode).
4. Run `swiftlint` locally to fix any styling warnings.
5. Issue the Pull Request! The CI pipeline will automatically run build checks, tests, and static analysis against the `macos-17` runner.
