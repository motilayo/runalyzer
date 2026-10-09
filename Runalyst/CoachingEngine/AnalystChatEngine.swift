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
        You are the Runalyst AI Coach. You are an encouraging, experienced personal running coach chatting directly with your runner about their workout.
        Always speak directly using "you" and "your".

        Coaching Guidelines:
        1. Plain, Simple & Direct Speech: Strike a natural balance between accurate running metrics and everyday human language. Never use robotic clichés, corporate buzzwords, or stiff clinical jargon like "thoracic alignment", "tactical composure", "blunt that strain", "turnover stability", "strategic attention", or "amplify efficiency".
           - Say "run tall with relaxed shoulders" instead of "thoracic alignment".
           - Say "take impact off your knees and joints" instead of "blunt strain".
           - Say "steady pacing control" instead of "tactical composure".
           - Say "steady step rhythm" instead of "turnover stability".
        2. Answer Directly:
           - When asked a conceptual or form question (e.g. "How does arm drive help?", "What are strides?", "How should I breathe?"), answer that question directly and simply first. Do NOT recite their workout stats unless they specifically asked about their session numbers.
           - When asked about their performance, improvements, or pacing, anchor your answer in their actual session numbers (pace, BPM, SPM, or baseline comparisons) and explain what the numbers mean for their body in plain English.
        3. No Canned Formulas or Repetitive Advice:
           - Avoid repetitive templates. Vary your openings and advice.
           - NEVER default to the same advice (like arm swing) across turns.
           - Rotate naturally across varied practical running tips: landing softly under hips, rhythmic breathing (e.g. 3 steps in, 2 steps out), keeping recovery intervals slow enough for heart rate to settle, running tall with an open chest, or pre-run drills like Strides and Cadence Pyramids.
        4. Natural Voice: Speak like a real human coach in 2 to 3 fluid, friendly sentences. Never use bullet points, numbered lists, or robotic sign-offs like "Trust your progress".
        5. Treadmill Runs: On a treadmill, the belt sets speed, so evaluate cardiovascular effort, recovery between reps, and step cadence.
        6. Cadence Floor: If cadence is at or above 150 SPM, treat it as a solid foundation. If below 150 SPM, encourage lighter, quicker steps. Never claim cadence is below the floor when it is at or above 150 SPM.
        7. Safety: For physical pain or injury, advise resting and consulting a doctor or physical therapist.
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

        let lower = userQuestion.lowercased()
        let isConceptualOrForm = lower.starts(with: "how does")
            || lower.starts(with: "why does")
            || lower.starts(with: "how do")
            || lower.starts(with: "why do")
            || lower.starts(with: "what is")
            || lower.starts(with: "what are")
            || lower.contains("how should i")
            || lower.contains("explain")
            || (lower.contains("arm") && !lower.contains("my run") && !lower.contains("my pace"))
            || (lower.contains("breathe") && !lower.contains("my run"))
            || (lower.contains("posture") && !lower.contains("my run"))

        let fullPrompt: String
        if isConceptualOrForm {
            fullPrompt = """
            Runner's question: "\(userQuestion)"
            (Instruction: Answer the runner's question directly and simply in 2 to 3 plain, conversational sentences without canned jargon. Do NOT recite their pace or heart rate numbers unless directly relevant to explaining the concept.)
            """
        } else {
            fullPrompt = """
            Runner's workout data:
            \(telemetryLines.joined(separator: ", "))

            Runner's question: "\(userQuestion)"
            (Instruction: Answer directly in 2 to 3 plain, conversational sentences using everyday runner language. Avoid canned jargon or repetitive templates.)
            """
        }

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

        // 1. Conceptual: Arm Drive / Arm Swing
        if lower.contains("arm drive") || lower.contains("arm swing") || (lower.contains("arm") && (lower.contains("help") || lower.contains("do") || lower.contains("why") || lower.contains("how"))) {
            return "Your arms act like a metronome for your legs—your feet naturally follow the tempo of your arm swing. Keeping your elbows bent around 90 degrees and driving them straight back helps you turn your feet over quicker without straining your legs, while preventing you from overreaching your stride."
        }

        // 2. Conceptual: Breathing
        if lower.contains("breath") || lower.contains("breathe") {
            return "Rhythmic breathing helps keep your heart rate calm and spreads landing impact across both legs. Try inhaling for 3 footstrikes and exhaling for 2—this odd-count pattern prevents you from always exhaling on the same foot strike, keeping your rhythm steady."
        }

        // 3. Conceptual: Posture
        if lower.contains("posture") || lower.contains("tall") || lower.contains("head") || lower.contains("shoulder") {
            return "Good running posture starts from the crown of your head: run tall with an open chest, keep your shoulders down and relaxed, and look 10 to 15 meters ahead rather than down at your feet. This opens up your airways and takes unnecessary tension out of your neck."
        }

        // 4. Performance: Degradation / Fading / Tiring out / End of run
        if lower.contains("degrad") || lower.contains("fade") || lower.contains("tiring") || lower.contains("tired") || lower.contains("end of") || lower.contains("late") || lower.contains("later") {
            if !workSegments.isEmpty {
                return "Your interval pacing held steady across your work reps without significant drop-off. Your heart rate climbed slightly during the later intervals, which is natural cardiac drift as fatigue builds—focusing on taking lighter, quicker steps late in the workout helps take stress off tired legs."
            } else {
                return "Your pace stayed consistent right through the later miles. Your heart rate rose slightly near the finish, which is normal aerobic fatigue, but you maintained your form and avoided any sudden slowdown."
            }
        }

        // 5. Weak point / Least Improved / Hardest / Room to grow
        if lower.contains("least") || lower.contains("weak") || lower.contains("struggle") || lower.contains("hardest") || lower.contains("room to grow") {
            if !recoverySegments.isEmpty {
                let recHR = Int(recoverySegments.map(\.avgHR).reduce(0, +) / Double(recoverySegments.count))
                return "The biggest area for growth was your recovery between intervals. Your heart rate stayed near \(recHR) BPM during rest breaks—slowing down to an easy walk or very gentle jog will let your pulse drop more so you have more pop on the work reps."
            } else if let osc = runRecord.workingAvgVerticalOscillation, osc > 9.5 {
                return "The main area with room to grow is vertical bounce (\(String(format: "%.1f", osc)) cm). Directing more energy forward rather than bounding upward will soften ground impact and save leg fatigue."
            } else if cad < 160 {
                return "The clearest area with room to grow is foot turnover. At \(cad) SPM, your feet spend a bit longer on the ground each stride—gently quickening your step rhythm will make your effort feel lighter and take stress off your joints."
            } else {
                return "Your metrics were remarkably solid throughout this run. The main area to keep an eye on is late-run heart rate drift, keeping your early pace relaxed so you finish with plenty of energy in reserve."
            }
        }

        // 6. Most Improved / Strongest / Biggest Win
        if lower.contains("most improve") || lower.contains("biggest win") || lower.contains("best part") || lower.contains("strongest") || (lower.contains("most") && lower.contains("improve")) {
            if !workSegments.isEmpty {
                let workPace = PaceFormatter.formatPace(secondsPerKilometer: workSegments.map(\.avgPace).reduce(0, +) / Double(workSegments.count))
                let avgWorkCad = Int(workSegments.map(\.avgCadence).reduce(0, +) / Double(workSegments.count))
                return "Your biggest win was your pacing control during work intervals. Holding an average pace of \(workPace) at \(avgWorkCad) SPM showed great discipline and confidence on the fast segments."
            } else if hr <= 150 {
                return "Your standout strength was cardiovascular control—holding an average of \(hr) BPM showed great aerobic discipline and smart energy management."
            } else if cad >= 165 {
                return "Your strongest metric was your sharp \(cad) SPM turnover. That quick rhythm keeps your feet landing softly under your hips, protecting your knees and shins."
            } else {
                return "Your biggest win was pacing consistency. Holding a steady \(pace) rhythm without fading shows solid stamina and endurance control."
            }
        }

        // 7. Heart Rate / Effort / Intensity
        if lower.contains("effort") || lower.contains("heart rate") || lower.contains("hr") || lower.contains("intensity") || lower.contains("hard") {
            let envDetail = isIndoor
                ? " On the treadmill, where the belt enforces your speed, this shows steady cardiovascular control even without outdoor airflow."
                : " Your pacing was well-matched to your aerobic engine."
            return "Your effort was smooth and controlled, with an average heart rate of \(hr) BPM.\(envDetail) You kept your intensity in a productive training zone without straining your engine."
        }

        // 8. Next Run / Tip / Focus / Technique / Form (rotated across 4 distinct, plain-language cues)
        if lower.contains("tip") || lower.contains("cue") || lower.contains("focus") || lower.contains("next run") || lower.contains("improve") || lower.contains("technique") || lower.contains("form") {
            if cad < 150 {
                return "The best area to focus on is quickening your foot turnover. Your cadence averaged \(cad) SPM, which is below the 150 SPM floor. Aiming for lighter, quicker steps landing directly under your hips will take impact off your joints and improve your rhythm."
            }

            let coachTurnIndex = messages.filter { $0.sender == .analyst }.count % 4

            if coachTurnIndex == 0 {
                if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
                    let purpose = drill.drillPurpose?.lowercased() ?? "cadence efficiency"
                    return "Your cadence held steady at \(cad) SPM. Before your next run, warm up with \(drill.drillTitle) to build \(purpose) and get your legs feeling springy."
                } else {
                    return "Your cadence averaged \(cad) SPM. Before your next run, warm up with a few light 15-second Strides to wake up your fast-twitch muscle fibers and get your legs used to quick, effortless steps."
                }
            } else if coachTurnIndex == 1 {
                return "Holding \(cad) SPM is a solid foundation. Focus on landing softly with your feet directly under your hips rather than reaching forward—it keeps impact light on your knees and keeps your momentum moving ahead."
            } else if coachTurnIndex == 2 {
                return "With your rhythm steady at \(cad) SPM, try rhythmic breathing on your next run: inhale for 3 footstrikes and exhale for 2. This steady breathing pattern keeps your heart rate calm and balances landing impact across both legs."
            } else {
                return "Your \(cad) SPM turnover is steady. Focus on your posture: run tall with an open chest, keep your shoulders down and relaxed, and look 10 to 15 meters ahead instead of down at your feet."
            }
        }

        // 9. Cadence / Turnover specifically
        if lower.contains("cadence") || lower.contains("turnover") || lower.contains("rhythm") || lower.contains("spm") {
            if cad >= 168 {
                return "Your cadence averaged a sharp \(cad) SPM. That quick turnover keeps your feet landing softly under your hips, protecting your knees and keeping your stride light."
            } else if cad >= 150 {
                return "Your cadence averaged \(cad) SPM—a solid baseline above the 150 floor. Building that rhythm toward 165–170 SPM over time will shorten your ground contact and make your stride feel lighter."
            } else {
                return "Your cadence averaged \(cad) SPM, which is below the 150 floor. Taking shorter, quicker steps will reduce ground impact forces and protect your joints."
            }
        }

        // 10. Pace / Speed specifically
        if lower.contains("pace") || lower.contains("speed") || lower.contains("fast") || lower.contains("slow") {
            if isIndoor {
                return "You held a steady pace of \(pace) on the treadmill. Since the treadmill belt sets your speed, your true aerobic effort is best reflected in your \(hr) BPM heart rate and \(cad) SPM turnover."
            } else {
                return "Your pace averaged \(pace), showing consistent, well-managed speed across the session."
            }
        }

        // 11. Bounce / Vertical Oscillation
        if lower.contains("bounce") || lower.contains("vertical") || lower.contains("oscillation") {
            if let osc = runRecord.workingAvgVerticalOscillation {
                return "Your vertical bounce was \(String(format: "%.1f", osc)) cm. Keeping that below 9 cm ensures your energy propels you forward rather than bounding upward into the air."
            }
        }

        // 12. Stride Length / Overstride
        if lower.contains("stride") || lower.contains("overstride") || lower.contains("reach") {
            let strideDetail = runRecord.workingAvgStrideLength.map { " (averaging \(String(format: "%.2f", $0)) m)" } ?? ""
            return "To keep your stride efficient\(strideDetail), focus on landing your feet directly under your center of mass rather than reaching out in front of your body."
        }

        return "During this run, you maintained an average cadence of \(cad) SPM, a heart rate of \(hr) BPM, and a pace of \(pace). Focusing on quick, relaxed steps beneath your hips will keep your running smooth and injury-free."
    }
}
