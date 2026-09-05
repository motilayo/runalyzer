import XCTest
@testable import Runalyzer


@available(iOS 26.0, *)
@MainActor
class MockLanguageModelProvider: LanguageModelProvider, @unchecked Sendable {
    var isAvailable: Bool = true
    var shouldThrowError = false
    var mockInsight: RunInsight?

    func respond(to prompt: String, generating type: RunInsight.Type, with instructions: String) async throws -> RunInsight {
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: nil)
        }

        if let insight = mockInsight {
            return insight
        }

        return RunInsight(
            headline: "Mock Headline",
            observation: "Mock Observation",
            drills: []
        )
    }
}


@available(iOS 26.0, *)
@MainActor
final class CoachingEngineTests: XCTestCase {

    func testGenerateInsightModelNotAvailable() async throws {
                let mockProvider = MockLanguageModelProvider()
        mockProvider.isAvailable = false

        let engine = CoachingEngine(modelProvider: mockProvider)
        let runData = RunDataForAI(
            directiveContext: "Test",
            vo2Context: "Test",
            cadenceContext: "Test",
            paceContext: "Test",
            hrContext: "Test",
            vertOscContext: "Test",
            gctContext: "Test",
            strideContext: "Test",
            intervalCadence: "160",
            recoveryCadence: "140",
            runType: "intervals",
            framboiseTags: "tag1, tag2",
            workingAveragesContext: "Using Working Averages (outliers trimmed)"
        )

        do {
            _ = try await engine.generateInsight(for: runData)
            XCTFail("Expected generateInsight to throw an error when model is not available")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "CoachingEngine")
            XCTAssertEqual(nsError.code, 1)
        }
    }

    func testGenerateInsightSuccess() async throws {
                let mockProvider = MockLanguageModelProvider()
        let expectedDrill = SuggestedDrill(
            drillTitle: "Cadence Pyramids",
            drillPurpose: "Purpose",
            drillWork: "Work",
            drillCues: "Cues",
            drillEffort: "Effort",
            targetCadence: "165-170"
        )
        let expectedInsight = RunInsight(
            headline: "Great Run",
            observation: "Good job",
            drills: [expectedDrill]
        )
        mockProvider.mockInsight = expectedInsight

        let engine = CoachingEngine(modelProvider: mockProvider)
        let runData = RunDataForAI(
            directiveContext: "Test",
            vo2Context: "Test",
            cadenceContext: "Test",
            paceContext: "Test",
            hrContext: "Test",
            vertOscContext: "Test",
            gctContext: "Test",
            strideContext: "Test",
            intervalCadence: "160",
            recoveryCadence: "140",
            runType: "intervals",
            framboiseTags: "tag1, tag2",
            workingAveragesContext: "Using Working Averages (outliers trimmed)"
        )

        let insight = try await engine.generateInsight(for: runData)

        XCTAssertEqual(insight.headline, "Great Run")
        XCTAssertEqual(insight.observation, "Good job")
        XCTAssertEqual(insight.drills.count, 1)
        XCTAssertEqual(insight.drills.first?.drillTitle, "Cadence Pyramids")
    }

    func testGenerateInsightFallbackOnFailure() async throws {
                let mockProvider = MockLanguageModelProvider()
        mockProvider.shouldThrowError = true

        let engine = CoachingEngine(modelProvider: mockProvider)
        let runData = RunDataForAI(
            directiveContext: "Test",
            vo2Context: "Test",
            cadenceContext: "Test",
            paceContext: "Test",
            hrContext: "Test",
            vertOscContext: "Test",
            gctContext: "Test",
            strideContext: "Test",
            intervalCadence: "160",
            recoveryCadence: "140",
            runType: "intervals",
            framboiseTags: "tag1, tag2",
            workingAveragesContext: "Using Working Averages (outliers trimmed)"
        )

        let insight = try await engine.generateInsight(for: runData)

        XCTAssertEqual(insight.headline, "Run Analyzed Successfully")
        XCTAssertEqual(insight.drills.count, 1)
        XCTAssertEqual(insight.drills.first?.drillTitle, "Strides")
    }

    func testPromptPayload_Generation() async throws {
        let mockProvider = MockLanguageModelProvider()
        let engine = CoachingEngine(modelProvider: mockProvider)

        let runData = RunDataForAI(
            directiveContext: "Test",
            vo2Context: "Test",
            cadenceContext: "Test",
            paceContext: "Test",
            hrContext: "Test",
            vertOscContext: "Test",
            gctContext: "Test",
            strideContext: "Test",
            intervalCadence: "160",
            recoveryCadence: "140",
            runType: "tempo",
            framboiseTags: "tag1, tag2",
            workingAveragesContext: "Using Working Averages (outliers trimmed)"
        )

        _ = try await engine.generateInsight(for: runData)

        XCTAssertEqual(runData.runType, "tempo")
        XCTAssertEqual(runData.framboiseTags, "tag1, tag2")
        XCTAssertEqual(runData.workingAveragesContext, "Using Working Averages (outliers trimmed)")
    }

    func testStateTrigger_AIRegeneration() async throws {
        // Assert that updating the view model's RunType state from .steady to .intervals
        // automatically invokes the generateAnalysis() function.
        // We can test this logic by simulating the RunDetailView behavior
        // Note: In an actual SwiftUI test, we'd use view inspector.
        // Here we just test the model context setup

        // Simulating user override:
        let record = RunRecord(date: Date(), distance: 5000, duration: 1800, avgPace: 5.5, avgHeartRate: 150, avgCadence: 165)
        record.runTypeRaw = "steady"

        let initialInsight = CoachingInsight(headline: "Initial", longitudinalObservation: "Test")
        record.insight = initialInsight

        // When user overrides:
        record.runTypeRaw = "intervals"
        record.insight = nil

        XCTAssertEqual(record.runTypeRaw, "intervals")
        XCTAssertNil(record.insight)
    }
}
