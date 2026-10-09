import Foundation
import SwiftData
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Chat message model for the interactive AI Analyst conversation.
struct AnalystChatMessage: Identifiable, Equatable {
    let id: UUID
    let sender: MessageSender
    let text: String
    let timestamp: Date

    enum MessageSender: Equatable {
        case user
        case analyst
    }

    init(id: UUID = UUID(), sender: MessageSender, text: String, timestamp: Date = Date()) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
    }
}

/// Actor managing the interactive RAG Analyst Chat session with FoundationModels and strict operational guardrails.
@MainActor
class AnalystChatEngine: ObservableObject {
    @Published var messages: [AnalystChatMessage] = []
    @Published var isResponding: Bool = false

    private let runSignature: RunSignature?
    private let macroProfile: MacroProfile?
    private let runRecord: RunRecord

    #if canImport(FoundationModels)
    private var modelSession: Any? // LanguageModelSession on iOS 26+
    #endif

    private var baselineStats: (avgPace: Double, avgCadence: Double, avgHR: Double)? {
        guard let context = runRecord.modelContext,
              let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runRecord.date) else {
            return nil
        }
        let targetDate = runRecord.date
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate<RunRecord> { $0.date >= thirtyDaysAgo && $0.date < targetDate }
        )
        guard let prior = try? context.fetch(descriptor), !prior.isEmpty else { return nil }
        let validPaces = prior.map(\.workingAvgPace).filter { $0 > 0 }
        let validCads = prior.map(\.workingAvgCadence).filter { $0 > 0 }
        let validHRs = prior.map(\.workingAvgHeartRate).filter { $0 > 0 }
        guard !validPaces.isEmpty, !validCads.isEmpty, !validHRs.isEmpty else { return nil }
        return (
            avgPace: validPaces.reduce(0, +) / Double(validPaces.count),
            avgCadence: validCads.reduce(0, +) / Double(validCads.count),
            avgHR: validHRs.reduce(0, +) / Double(validHRs.count)
        )
    }

    init(runRecord: RunRecord, runSignature: RunSignature? = nil, macroProfile: MacroProfile? = nil) {
        self.runRecord = runRecord
        self.runSignature = runSignature ?? runRecord.signature
        self.macroProfile = macroProfile ?? MacroProfile.load()

        setupInitialGreeting()
    }

    private func setupInitialGreeting() {
        let runType = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let isIndoor = runRecord.isIndoor ?? false
        let envNote = isIndoor ? "on the treadmill" : "outdoors"
        let initialGreeting = "I took a look at your \(runType) \(envNote). What would you like to know about your pace, heart rate, cadence, or how your run felt?"
        messages.append(AnalystChatMessage(sender: .analyst, text: initialGreeting))
    }

    /// Sends a runner question and generates an analyst response with RAG telemetry context and guardrails.
    func sendMessage(_ userQuestion: String) async {
        let trimmed = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(AnalystChatMessage(sender: .user, text: trimmed))
        isResponding = true
        defer { isResponding = false }

        // --- Guardrail 1: Medical Boundary ---
        let lowercased = trimmed.lowercased()
        let medicalKeywords = ["pain", "hurt", "injured", "injury", "shin splint", "plantar", "achilles", "knee pain", "diagnosis", "doctor", "strain my"]
        if medicalKeywords.contains(where: { lowercased.contains($0) }) {
            let medicalReferral = "I'm an AI running coach, not a doctor or physical therapist. If you're experiencing pain or persistent soreness, please take time to rest and check in with a doctor or physical therapist."
            messages.append(AnalystChatMessage(sender: .analyst, text: medicalReferral))
            return
        }

        // --- Guardrail 2: Hardware Boundary (Indoor GPS inquiry) ---
        let gpsKeywords = ["gps", "route", "map", "elevation gain", "hills outside"]
        if (runRecord.isIndoor ?? false) && gpsKeywords.contains(where: { lowercased.contains($0) }) {
            let hardwareExplanation = "This run was recorded on a treadmill indoors. Apple Watch turns off GPS and elevation tracking indoors because there are no satellites or hills inside. We track your run using your arm swing, cadence, and heart rate instead."
            messages.append(AnalystChatMessage(sender: .analyst, text: hardwareExplanation))
            return
        }

        // --- Guardrail 3: Subjective Gear / Shoe Boundary ---
        let gearKeywords = ["shoes", "shoe", "vaporfly", "alphafly", "superblast", "hoka", "nike", "saucony", "gear to buy", "what shoes"]
        if gearKeywords.contains(where: { lowercased.contains($0) }) {
            let gearResponse = "I focus on your running form, cadence, and effort rather than specific shoe brands. The best shoe is whatever feels comfortable for you, but keeping a quick, light step under your hips does the most to protect your legs."
            messages.append(AnalystChatMessage(sender: .analyst, text: gearResponse))
            return
        }

        // FoundationModels on-device generation with RAG context
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if SystemLanguageModel.default.isAvailable {
                do {
                    let responseText = try await generateFoundationModelResponse(for: trimmed)
                    messages.append(AnalystChatMessage(sender: .analyst, text: responseText))
                    return
                } catch {
                    print("FoundationModels chat error: \(error)")
                }
            }
        }
        #endif

        // Deterministic Fallback response
        let fallbackResponse = generateDeterministicResponse(for: trimmed)
        messages.append(AnalystChatMessage(sender: .analyst, text: fallbackResponse))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateFoundationModelResponse(for userQuestion: String) async throws -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"

        let systemInstructions = """
        You are the Runalyst AI Coach. You are an encouraging, elite personal running coach conversing directly with your runner about their workout.
        Always speak directly using "you" and "your".

        Coaching Rules:
        1. Laser-Focused: Answer ONLY what the runner asks about. Stay laser-focused on their specific question.
        2. Grounded in Data: Anchor observations in their actual workout numbers (intervals, pace, BPM, SPM, or baseline deltas).
        3. DIVERSITY ACROSS TURNS (NO REPETITION): Never repeat the same cue, phrase, or target metric across turns. Rotate across varied biomechanical and tactical coaching dimensions:
           - Arm swing drive and compact elbow rhythm
           - Foot strike landing directly beneath hips
           - Core posture and tall thoracic alignment
           - Interval pacing discipline and heart rate recovery between reps
           - Breathing cadence matched to foot strike
           - Recommended pre-run drills (e.g. Cadence Pyramids, Strides, Rhythm Intervals)
        4. "Most Improved" vs "Least Improved": When asked what improved most or least, reference their baseline deltas, interval consistency, or cardiac cost. Give balanced, honest coaching.
        5. Natural Voice: Speak like a real running coach in 2 to 3 fluid sentences. Never use robotic templates, bullet points, or repetitive fillers like "Trust your progress".
        6. On treadmill runs: The belt enforces pace, so evaluate cardiovascular strain, interval recovery, and turnover stability.
        7. Safety: For physical pain or injury, advise resting and consulting a doctor or physical therapist.
        8. Cadence Floor: If cadence is ABOVE the 150 floor, treat it as a solid foundation. If BELOW floor, advise quickening turnover. Never falsely claim cadence is below the floor when it is above 150 SPM.
        Respond in \(language).
        """

        let session: LanguageModelSession
        if let existing = modelSession as? LanguageModelSession {
            session = existing
        } else {
            session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: systemInstructions
            )
            self.modelSession = session
        }

        let env = (runRecord.isIndoor == true) ? "Treadmill" : "Outdoor"
        let cad = Int(runRecord.workingAvgCadence)
        let hr = Int(runRecord.workingAvgHeartRate)
        let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        let type = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw

        let isSubFloor = cad < 150
        let cadenceStatus = isSubFloor
            ? "\(cad) SPM (BELOW the 150 SPM floor; turnover is slow)"
            : "\(cad) SPM (ABOVE the 150 SPM floor; solid foundation)"

        var telemetryLines = [
            "Workout: \(type) (\(env))",
            "Overall Pace: \(pace)",
            "Overall Cadence: \(cadenceStatus)",
            "Overall Heart Rate: \(hr) BPM"
        ]
        if let osc = runRecord.workingAvgVerticalOscillation {
            telemetryLines.append("Bounce: \(String(format: "%.1f", osc)) cm")
        }
        if let stride = runRecord.workingAvgStrideLength {
            telemetryLines.append("Stride Length: \(String(format: "%.2f", stride)) m")
        }
        if let acwr = macroProfile?.acwr {
            telemetryLines.append("Training Balance (ACWR): \(String(format: "%.2f", acwr))")
        }

        let signature = runSignature ?? runRecord.signature
        let workSegments = signature?.phaseSegments.filter { $0.kind == "work" } ?? []
        let recoverySegments = signature?.phaseSegments.filter { $0.kind == "recovery" } ?? []

        if !workSegments.isEmpty {
            let avgWorkPace = PaceFormatter.formatPace(secondsPerKilometer: workSegments.map(\.avgPace).reduce(0, +) / Double(workSegments.count))
            let avgWorkCad = Int(workSegments.map(\.avgCadence).reduce(0, +) / Double(workSegments.count))
            let avgWorkHR = Int(workSegments.map(\.avgHR).reduce(0, +) / Double(workSegments.count))
            telemetryLines.append("Work Intervals (\(workSegments.count) reps): Avg Pace \(avgWorkPace), Cadence \(avgWorkCad) SPM, HR \(avgWorkHR) BPM")
            if !recoverySegments.isEmpty {
                let avgRecHR = Int(recoverySegments.map(\.avgHR).reduce(0, +) / Double(recoverySegments.count))
                telemetryLines.append("Recovery Intervals (\(recoverySegments.count) reps): Avg HR \(avgRecHR) BPM")
            }
        }

        if let base = baselineStats {
            let cadDiff = cad - Int(base.avgCadence)
            let hrDiff = hr - Int(base.avgHR)
            let paceDiffSec = Int(base.avgPace - runRecord.workingAvgPace)
            let paceDesc = paceDiffSec > 0 ? "\(paceDiffSec)s faster than baseline" : "\(abs(paceDiffSec))s slower than baseline"
            let hrDesc = hrDiff > 0 ? "+\(hrDiff) BPM higher strain" : "\(hrDiff) BPM lower strain"
            let cadDesc = cadDiff >= 0 ? "+\(cadDiff) SPM faster turnover" : "\(cadDiff) SPM slower turnover"
            telemetryLines.append("30-Day Comparison: Pace was \(paceDesc), HR was \(hrDesc), Cadence was \(cadDesc)")
        }

        if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
            let purpose = drill.drillPurpose ?? "rhythm and turnover"
            telemetryLines.append("Target Drill for Next Run: \(drill.drillTitle) (\(purpose))")
        }

        let fullPrompt = """
        Runner's telemetry for this session:
        \(telemetryLines.joined(separator: ", "))

        Runner's question: "\(userQuestion)"
        """

        let response = try await session.respond(to: fullPrompt)
        return response.content
    }
    #endif

    private func generateDeterministicResponse(for userQuestion: String) -> String {
        let cad = Int(runRecord.workingAvgCadence)
        let hr = Int(runRecord.workingAvgHeartRate)
        let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        let isIndoor = runRecord.isIndoor ?? false
        let lower = userQuestion.lowercased()
        let signature = runSignature ?? runRecord.signature
        let workSegments = signature?.phaseSegments.filter { $0.kind == "work" } ?? []
        let recoverySegments = signature?.phaseSegments.filter { $0.kind == "recovery" } ?? []

        // 1. Least Improved / Weakness / Hardest
        if lower.contains("least") || lower.contains("weakness") || lower.contains("struggled") || lower.contains("hardest") || lower.contains("room to grow") {
            if !recoverySegments.isEmpty {
                let recHR = Int(recoverySegments.map(\.avgHR).reduce(0, +) / Double(recoverySegments.count))
                return "The biggest opportunity for growth was your recovery between intervals. Your heart rate held near \(recHR) BPM during rest intervals—slowing down to an easy walk or gentle jog will help your pulse drop more and give you sharper pop on work reps."
            } else if let osc = runRecord.workingAvgVerticalOscillation, osc > 9.5 {
                return "The clearest area to refine is vertical bounce (\(String(format: "%.1f", osc)) cm). Channeling more energy horizontally rather than bounding upward will soften ground impacts and preserve leg fatigue."
            } else if cad < 160 {
                return "The main area with room to grow is foot turnover. At \(cad) SPM, your feet spend a bit longer on the ground each stride—gently quickening your rhythm will make your effort feel lighter and reduce joint impact."
            } else {
                return "Your metrics were remarkably solid throughout this run. The main refinement to target is monitoring cardiac drift during late miles to sustain your pace with less cardiac cost."
            }
        }

        // 2. Most Improved / Strongest / Biggest Win
        if lower.contains("most improve") || lower.contains("biggest win") || lower.contains("best part") || lower.contains("strongest") || (lower.contains("most") && lower.contains("improve")) {
            if !workSegments.isEmpty {
                let workPace = PaceFormatter.formatPace(secondsPerKilometer: workSegments.map(\.avgPace).reduce(0, +) / Double(workSegments.count))
                let avgWorkCad = Int(workSegments.map(\.avgCadence).reduce(0, +) / Double(workSegments.count))
                return "Your biggest win was your assertive rhythm during work intervals—holding an average of \(workPace) at \(avgWorkCad) SPM showed fantastic aerobic drive and confidence on speed segments."
            } else if hr <= 150 {
                return "Your standout strength was cardiovascular control—holding an average of \(hr) BPM showed great aerobic discipline and smart energy conservation."
            } else if cad >= 165 {
                return "Your strongest metric was your sharp \(cad) SPM turnover. That quick turnover keeps your feet landing softly under your hips, protecting your joints."
            } else {
                return "Your biggest win was pacing consistency. Holding a steady \(pace) rhythm without fading demonstrates solid stamina and endurance pacing."
            }
        }

        // 3. Heart Rate / Effort / Intensity
        if lower.contains("effort") || lower.contains("heart rate") || lower.contains("hr") || lower.contains("intensity") || lower.contains("hard") || lower.contains("tired") {
            let envDetail = isIndoor
                ? " On the treadmill, where the belt enforces your speed, this demonstrates steady cardiovascular control even without outdoor airflow."
                : " Your pacing was well-matched to your aerobic engine."
            return "Your effort was smooth and controlled, with an average heart rate of \(hr) BPM.\(envDetail) You kept your intensity in a productive training zone without over-straining."
        }

        // 4. Next Run / Tip / Focus / Technique (rotated by response count so it never repeats the same cue!)
        if lower.contains("tip") || lower.contains("cue") || lower.contains("focus") || lower.contains("next run") || lower.contains("improve") || lower.contains("technique") || lower.contains("form") {
            if cad < 150 {
                return "The best area to focus on is quickening your foot turnover. Your cadence averaged \(cad) SPM, which is below the 150 SPM floor. Aiming for lighter, quicker steps landing directly under your hips will reduce impact on your joints and improve rhythm."
            }

            let coachTurnIndex = messages.filter { $0.sender == .analyst }.count % 4

            if coachTurnIndex == 0 {
                if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
                    let purpose = drill.drillPurpose?.lowercased() ?? "cadence efficiency"
                    return "Your cadence held steady at \(cad) SPM. Before your next run, warm up with \(drill.drillTitle) to build \(purpose) and keep your foot turnover sharp."
                } else {
                    return "Your cadence averaged \(cad) SPM. Focus on your arm drive: keep your elbows bent at 90 degrees and drive them straight back like a pendulum. A compact arm swing naturally quickens your foot turnover with zero extra leg fatigue."
                }
            } else if coachTurnIndex == 1 {
                return "Holding \(cad) SPM provides a solid foundation above the floor. Focus on landing lightly directly beneath your hips rather than reaching forward, keeping your contact time quick and your turnover crisp."
            } else if coachTurnIndex == 2 {
                return "With your turnover holding steady at \(cad) SPM, try rhythm breathing on your next run: inhale for 3 footstrikes and exhale for 2. This odd-pattern breathing alternates landing impact across both legs and keeps your heart rate stable."
            } else {
                return "Your \(cad) SPM rhythm is solid. Focus on tall posture: imagine a string gently pulling the crown of your head toward the sky, and keep your gaze 10–15 meters forward rather than looking down at your feet."
            }
        }

        // 5. Cadence / Turnover specifically
        if lower.contains("cadence") || lower.contains("turnover") || lower.contains("rhythm") || lower.contains("spm") {
            if cad >= 168 {
                return "Your cadence averaged a sharp \(cad) SPM. That quick turnover keeps your feet landing softly under your hips, protecting your knees and keeping your stride light."
            } else if cad >= 150 {
                return "Your cadence averaged \(cad) SPM—a solid baseline above the 150 floor. Gently building that rhythm toward 165–170 SPM will help shorten your contact time with the ground and make your stride feel lighter."
            } else {
                return "Your cadence averaged \(cad) SPM, which is below the 150 floor. Quickening your foot strike will reduce impact forces and protect your joints."
            }
        }

        // 6. Pace / Speed specifically
        if lower.contains("pace") || lower.contains("speed") || lower.contains("fast") || lower.contains("slow") {
            if isIndoor {
                return "You held a steady pace of \(pace) on the treadmill. Since the treadmill belt sets your speed, your true aerobic effort is best reflected in your \(hr) BPM heart rate and \(cad) SPM turnover."
            } else {
                return "Your pace averaged \(pace), showing consistent, well-managed speed across the session."
            }
        }

        // 7. Bounce / Vertical Oscillation
        if lower.contains("bounce") || lower.contains("vertical") || lower.contains("oscillation") {
            if let osc = runRecord.workingAvgVerticalOscillation {
                return "Your vertical bounce was \(String(format: "%.1f", osc)) cm. Keeping that below 9 cm ensures your energy propels you forward rather than bounding upward into the air."
            }
        }

        // 8. Stride Length / Overstride
        if lower.contains("stride") || lower.contains("overstride") || lower.contains("reach") {
            let strideDetail = runRecord.workingAvgStrideLength.map { " (averaging \(String(format: "%.2f", $0)) m)" } ?? ""
            return "To keep your stride efficient\(strideDetail), focus on landing your feet directly under your center of mass rather than reaching out in front of your body."
        }

        return "During this run, you maintained an average cadence of \(cad) SPM, a heart rate of \(hr) BPM, and a pace of \(pace). Focusing on quick, relaxed steps beneath your hips will keep your running smooth and injury-free."
    }
}
