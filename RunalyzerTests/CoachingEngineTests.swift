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
            recoveryCadence: "140"
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
            recoveryCadence: "140"
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
            recoveryCadence: "140"
        )

        let insight = try await engine.generateInsight(for: runData)

        XCTAssertEqual(insight.headline, "Run Analyzed Successfully")
        XCTAssertEqual(insight.drills.count, 1)
        XCTAssertEqual(insight.drills.first?.drillTitle, "Strides")
    }
}
