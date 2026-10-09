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

    var readinessAssessment: ReadinessAssessment {
        if let context = runRecord.modelContext {
            let descriptor = FetchDescriptor<RunRecord>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            if let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty {
                return ReadinessEvaluator.assess(runRecords: allRuns, now: runRecord.date)
            }
        }
        if let profile = macroProfile {
            let state: ReadinessState = (profile.acwr ?? 1.0) > 1.4 ? .acuteFatigue : .productive
            return ReadinessAssessment(
                state: state,
                triggers: [],
                acuteLoad: profile.acuteLoad ?? 150.0,
                chronicWeeklyLoad: profile.chronicWeeklyLoad ?? 150.0,
                acwr: profile.acwr,
                mileageDropFraction: nil
            )
        }
        return ReadinessAssessment.productive
    }

    var isHeavySession: Bool {
        let type = runRecord.detectedTypeRaw
        return type == "Intervals" || type == "Pyramids" || type == "Tempo Run" || type == "Hill Repeats" || runRecord.percentZone4 >= 0.35
    }

    var nextSessionDirective: String {
        let readiness = readinessAssessment
        if isHeavySession || readiness.state == .acuteFatigue {
            let reason = isHeavySession ? "recent demanding \(runRecord.detectedTypeRaw) session" : "acute training fatigue"
            return "NEXT SESSION DIRECTIVE: Due to \(reason), if the runner asks about running today, intensity, or workout duration, recommend strictly a SHORT EASY RECOVERY session (cap duration at 20–25 minutes in Zone 1 or easy Zone 2, conversational effort, HR below 140 BPM). If they propose running 40+ minutes (even in Zone 2), validate that Zone 2 effort is the right intensity, but explain that 45 minutes is too long for recovery and will accumulate fatigue; advise capping it at 20–25 minutes or walking instead. Forbid hard pushes, fast intervals, or long sessions today."
        } else if readiness.state == .deload {
            return "NEXT SESSION DIRECTIVE: In a scheduled mileage deload week. Prescribe a light recovery jog to let the body adapt."
        } else {
            return "NEXT SESSION DIRECTIVE: Training balance is optimal. Runner is primed for steady aerobic work or their next scheduled key workout."
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateFoundationModelResponse(for userQuestion: String) async throws -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"

        let systemInstructions = """
        You are the Runalyst AI Coach. Embody "the mind of an analyst, the voice of a coach". You are an encouraging, experienced personal coach chatting with your runner about their workout and training.
        Always speak directly using "you" and "your".

        Core Coaching Principles:
        1. The Voice of a Coach (Encouraging, Empathetic & Constructive):
           - Answer the runner's question directly and constructively in the very first sentence.
           - Speak warmly and respectfully as a trusted coach—never scold, sound bossy, or use abrasive phrases like "You're not doing X today—".
           - When asked about doing a long session (e.g. 45 min) during recovery: validate their intent, distinguish duration from intensity, and give a clear recommendation (e.g. "Zone 2 is the right intensity, but 45 minutes is too long for recovery today—cap it at 20 to 25 minutes so your body can rebuild"). Never contradict yourself by telling them not to do Zone 2 and then telling them to do Zone 2 in the same breath.
           - Vary phrasing naturally across turns: do not repeat the exact same stock paragraph of pace and heart rate metrics turn after turn.
           - Plain, Simple, Human Speech: Speak like a real human coach in 2 to 3 fluid sentences. Never use robotic clichés, corporate buzzwords, or clinical jargon ("thoracic alignment", "tactical composure", "blunt that strain", "turnover stability").
        2. The Mind of an Analyst (Grounded in Authentic Data):
           - All recommendations must be strictly informed by the provided workout and readiness data.
           - Obey the NEXT SESSION DIRECTIVE strictly: If the previous workout was an intense session or acute fatigue is present, prescribe ONLY an easy, short recovery jog (Zone 1/2, conversational effort, low heart rate, capped at 20–25 min). NEVER recommend a fast push, tempo pace (such as 5:20/km), or long endurance session.
           - Post-Workout Context: You are chatting with the runner after their workout. NEVER say "Right now, your heart rate is climbing" or speak in the present continuous about real-time biometrics.
           - Readiness vs Training Load: If asked why readiness was adjusted when training load is optimal, explain that 4-week training load (ACWR) measures monthly balance, while readiness accounts for acute fatigue from recent hard efforts (such as back-to-back hard days or cardiac drift).
        3. Cadence & Form:
           - 150 SPM is the floor. If at or above 150 SPM, treat it as a solid foundation. If below, encourage lighter, quicker steps.
        4. Safety:
           - For physical pain or injury, advise resting and consulting a doctor or physical therapist.
        Respond in \(language).
        """

        let isFirstTurn = (modelSession == nil)
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
        let durationMin = max(1, Int(round(runRecord.duration / 60.0)))
        let distanceKm = String(format: "%.1f km", runRecord.totalDistanceMeters / 1000.0)

        let isSubFloor = cad < 150
        let cadenceStatus = isSubFloor
            ? "\(cad) SPM (BELOW the 150 SPM floor; turnover is slow)"
            : "\(cad) SPM (ABOVE the 150 SPM floor; solid foundation)"

        var telemetryLines = [
            "Workout: \(type) (\(env), \(durationMin) min, \(distanceKm))",
            "Overall Pace: \(pace)",
            "Overall Cadence: \(cadenceStatus)",
            "Overall Heart Rate: \(hr) BPM"
        ]
        if runRecord.percentZone4 > 0.05 {
            telemetryLines.append("High-Intensity Effort: \(Int(runRecord.percentZone4 * 100))% in Zone 4 threshold")
        }
        if let osc = runRecord.workingAvgVerticalOscillation {
            telemetryLines.append("Bounce: \(String(format: "%.1f", osc)) cm")
        }
        if let stride = runRecord.workingAvgStrideLength {
            telemetryLines.append("Stride Length: \(String(format: "%.2f", stride)) m")
        }

        let readiness = readinessAssessment
        let acwrStr = readiness.acwr.map { String(format: "%.2f", $0) } ?? "1.02"
        telemetryLines.append("Training Balance (ACWR): \(acwrStr) (Acute 7-Day Load: \(Int(readiness.acuteLoad)), Chronic 28-Day Load: \(Int(readiness.chronicWeeklyLoad)))")
        telemetryLines.append("Readiness Status: \(readiness.state.rawValue)")
        if !readiness.triggers.isEmpty {
            let triggerNames = readiness.triggers.map { trigger -> String in
                switch trigger {
                case .consecutiveHardDays: return "consecutive hard training days within 48h"
                case .cardiacDrift: return "cardiac drift during steady pace"
                case .cadenceFade: return "cadence decay in late miles"
                case .acwrSpike: return "acute workload spike > 1.5x baseline"
                case .mileageDeload: return "mileage deload week"
                }
            }
            telemetryLines.append("Active Readiness Triggers: \(triggerNames.joined(separator: ", "))")
        }
        telemetryLines.append(nextSessionDirective)

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

        let promptToSend: String
        if isFirstTurn {
            promptToSend = """
            Runner's workout data:
            \(telemetryLines.joined(separator: "\n"))

            Runner's question: "\(userQuestion)"

            (Instruction: Embody the mind of an analyst and voice of a coach. Answer directly and decisively in 2 to 3 conversational sentences using everyday runner language informed by their data. Strictly follow the NEXT SESSION DIRECTIVE.)
            """
        } else {
            promptToSend = """
            \(nextSessionDirective)
            Runner's follow-up question: "\(userQuestion)"

            (Instruction: Embody the mind of an analyst and voice of a coach. Answer directly and decisively in 2 to 3 conversational sentences using everyday runner language. Strictly follow the NEXT SESSION DIRECTIVE.)
            """
        }

        do {
            let response = try await session.respond(to: promptToSend)
            return response.content
        } catch {
            let errorDesc = "\(error)".lowercased()
            let isContextExceeded = errorDesc.contains("context") || errorDesc.contains("token") || errorDesc.contains("limit")

            if isContextExceeded {
                // Apple FoundationModels: Managing the Context Window (4,096-token budget).
                // When multiturn context exceeds 4096 tokens, discard bloated session and restart
                // with a clean session seeded with the essential telemetry and current query.
                let freshSession = LanguageModelSession(
                    model: SystemLanguageModel.default,
                    instructions: systemInstructions
                )
                self.modelSession = freshSession
                let recoveryPrompt = """
                Runner's workout data:
                \(telemetryLines.joined(separator: "\n"))

                Runner's question: "\(userQuestion)"

                (Instruction: Embody the mind of an analyst and voice of a coach. Answer directly and decisively in 2 to 3 conversational sentences using everyday runner language informed by their data. Strictly follow the NEXT SESSION DIRECTIVE.)
                """
                let retryResponse = try await freshSession.respond(to: recoveryPrompt)
                return retryResponse.content
            }
            throw error
        }
    }
    #endif

    private func generateDeterministicResponse(for userQuestion: String) -> String {
        let cad = Int(runRecord.workingAvgCadence)
        let hr = Int(runRecord.workingAvgHeartRate)
        let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        let isIndoor = runRecord.isIndoor ?? false
        let type = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let lower = userQuestion.lowercased()
        let signature = runSignature ?? runRecord.signature
        let workSegments = signature?.phaseSegments.filter { $0.kind == "work" } ?? []
        let recoverySegments = signature?.phaseSegments.filter { $0.kind == "recovery" } ?? []

        // 1. Can I run today / Go for a run today / Next workout timing / Duration inquiry
        if lower.contains("run today") || lower.contains("can i run") || lower.contains("should i run") || lower.contains("go for a") || lower.contains("another run") || lower.contains("session today") || (lower.contains("what if") && (lower.contains("zone 2") || lower.contains("zone2") || lower.contains("run") || lower.contains("min"))) {
            if isHeavySession || readinessAssessment.state == .acuteFatigue {
                let asksLong = lower.contains("45") || lower.contains("hour") || lower.contains("60") || lower.contains("long")
                let mentionsZone2 = lower.contains("zone 2") || lower.contains("zone2")
                if mentionsZone2 && asksLong {
                    return "Zone 2 is the right intensity, but 45 minutes is too long for recovery right now. After your demanding \(type) workout, 45 minutes adds unnecessary training load when your muscles are trying to repair. If you want to get moving, cap it at 20 to 25 minutes of easy jogging or a brisk walk to flush your legs without building deeper fatigue."
                } else if asksLong {
                    return "45 minutes is too long for today—keep it to a short 20 to 25-minute recovery flush instead. Since your recent \(type) workout was high-intensity and left acute fatigue, your body needs active recovery in Zone 1 or easy Zone 2. Keep your pace relaxed (around 6:30–6:45/km), keep your effort conversational, and let your legs rebuild."
                } else {
                    return "Yes, you can do a run today, but keep it short (20 to 25 minutes) and very light—strictly in Zone 1 or Zone 2. Since your recent session was a demanding \(type) workout, your legs are carrying acute fatigue. Keep your pace relaxed (around 6:30–6:45/km), hold a conversational effort where you can speak in full sentences, and avoid any fast intervals or hard surges."
                }
            } else if readinessAssessment.state == .deload {
                return "Yes, you can run today, but keep it to a light aerobic flush. You are in a recovery deload week, so keep your effort relaxed and your steps soft without pushing the pace."
            } else {
                return "Yes, you're in great shape to run today! Your recovery and training balance are in the sweet spot. You can do a steady aerobic run—just keep your pace consistent and rhythm smooth."
            }
        }

        // 2. How hard should I push / Pushing / Intensity
        if lower.contains("how hard") || (lower.contains("push") && (lower.contains("how") || lower.contains("should") || lower.contains("hard") || lower.contains("i"))) {
            if isHeavySession || readinessAssessment.state == .acuteFatigue {
                return "Keep your effort very light today—do not push hard. After your recent \(type) workout, today should be an active recovery day in Zone 1 or easy Zone 2. Aim for an effort where your breathing stays calm and your heart rate stays under 140 BPM. Pushing hard today would increase injury risk and blunt your aerobic adaptation from your previous session."
            } else {
                return "Aim for a steady, controlled push in Zone 2 or moderate Zone 3. You should feel comfortably challenged without gasping for air. Keep your cadence around \(cad) SPM and focus on a smooth, rhythmic stride."
            }
        }

        // 3. Why was readiness adjusted / Training load vs Readiness / ACWR
        if lower.contains("readiness") && (lower.contains("adjust") || lower.contains("why") || lower.contains("optimal") || lower.contains("drop")) {
            let acwrStr = readinessAssessment.acwr.map { String(format: "%.2f", $0) } ?? "1.02"
            let triggerText: String = {
                if readinessAssessment.triggers.contains(.consecutiveHardDays) {
                    return "consecutive high-intensity sessions on back-to-back days"
                } else if readinessAssessment.triggers.contains(.cardiacDrift) {
                    return "cardiac drift indicating short-term cardiovascular fatigue"
                } else if readinessAssessment.triggers.contains(.cadenceFade) {
                    return "cadence fade late in your recent runs"
                } else {
                    return "acute training strain from your recent workout"
                }
            }()
            return "Your 4-week training load is in the sweet spot (ACWR \(acwrStr)), but your readiness was adjusted due to \(triggerText). ACWR measures your monthly volume ratio, while readiness looks at immediate recovery—back-to-back hard efforts require lighter drill targets to protect your legs and ensure full adaptation."
        }

        // 4. Conceptual: Arm Drive / Arm Swing
        if lower.contains("arm drive") || lower.contains("arm swing") || (lower.contains("arm") && (lower.contains("help") || lower.contains("do") || lower.contains("why") || lower.contains("how"))) {
            return "Your arms act like a metronome for your legs—your feet naturally follow the tempo of your arm swing. Keeping your elbows bent around 90 degrees and driving them straight back helps you turn your feet over quicker without straining your legs, while preventing you from overreaching your stride."
        }

        // 5. Conceptual: Breathing
        if lower.contains("breath") || lower.contains("breathe") {
            return "Rhythmic breathing helps keep your heart rate calm and spreads landing impact across both legs. Try inhaling for 3 footstrikes and exhaling for 2—this odd-count pattern prevents you from always exhaling on the same foot strike, keeping your rhythm steady."
        }

        // 6. Conceptual: Posture
        if lower.contains("posture") || lower.contains("tall") || lower.contains("head") || lower.contains("shoulder") {
            return "Good running posture starts from the crown of your head: run tall with an open chest, keep your shoulders down and relaxed, and look 10 to 15 meters ahead rather than down at your feet. This opens up your airways and takes unnecessary tension out of your neck."
        }

        // 7. Performance: Degradation / Fading / Tiring out / End of run
        if lower.contains("degrad") || lower.contains("fade") || lower.contains("tiring") || lower.contains("tired") || lower.contains("end of") || lower.contains("late") || lower.contains("later") {
            if !workSegments.isEmpty {
                return "Your interval pacing held steady across your work reps without significant drop-off. Your heart rate climbed slightly during the later intervals, which is natural cardiac drift as fatigue builds—focusing on taking lighter, quicker steps late in the workout helps take stress off tired legs."
            } else {
                return "Your pace stayed consistent right through the later miles. Your heart rate rose slightly near the finish, which is normal aerobic fatigue, but you maintained your form and avoided any sudden slowdown."
            }
        }

        // 8. Weak point / Least Improved / Hardest / Room to grow
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

        // 9. Most Improved / Strongest / Biggest Win
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

        // 10. Heart Rate / Effort / Intensity
        if lower.contains("effort") || lower.contains("heart rate") || lower.contains("hr") || lower.contains("intensity") || lower.contains("hard") {
            let envDetail = isIndoor
                ? " On the treadmill, where the belt enforces your speed, this shows steady cardiovascular control even without outdoor airflow."
                : " Your pacing was well-matched to your aerobic engine."
            return "Your effort was smooth and controlled, with an average heart rate of \(hr) BPM.\(envDetail) You kept your intensity in a productive training zone without straining your engine."
        }

        // 11. Next Run / Tip / Focus / Technique / Form (rotated across 4 distinct, plain-language cues)
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

        // 12. Cadence / Turnover specifically
        if lower.contains("cadence") || lower.contains("turnover") || lower.contains("rhythm") || lower.contains("spm") {
            if cad >= 168 {
                return "Your cadence averaged a sharp \(cad) SPM. That quick turnover keeps your feet landing softly under your hips, protecting your knees and keeping your stride light."
            } else if cad >= 150 {
                return "Your cadence averaged \(cad) SPM—a solid baseline above the 150 floor. Building that rhythm toward 165–170 SPM over time will shorten your ground contact and make your stride feel lighter."
            } else {
                return "Your cadence averaged \(cad) SPM, which is below the 150 floor. Taking shorter, quicker steps will reduce ground impact forces and protect your joints."
            }
        }

        // 13. Pace / Speed specifically
        if lower.contains("pace") || lower.contains("speed") || lower.contains("fast") || lower.contains("slow") {
            if isIndoor {
                return "You held a steady pace of \(pace) on the treadmill. Since the treadmill belt sets your speed, your true aerobic effort is best reflected in your \(hr) BPM heart rate and \(cad) SPM turnover."
            } else {
                return "Your pace averaged \(pace), showing consistent, well-managed speed across the session."
            }
        }

        // 14. Bounce / Vertical Oscillation
        if lower.contains("bounce") || lower.contains("vertical") || lower.contains("oscillation") {
            if let osc = runRecord.workingAvgVerticalOscillation {
                return "Your vertical bounce was \(String(format: "%.1f", osc)) cm. Keeping that below 9 cm ensures your energy propels you forward rather than bounding upward into the air."
            }
        }

        // 15. Stride Length / Overstride
        if lower.contains("stride") || lower.contains("overstride") || lower.contains("reach") {
            let strideDetail = runRecord.workingAvgStrideLength.map { " (averaging \(String(format: "%.2f", $0)) m)" } ?? ""
            return "To keep your stride efficient\(strideDetail), focus on landing your feet directly under your center of mass rather than reaching out in front of your body."
        }

        return "During this run, you maintained an average cadence of \(cad) SPM, a heart rate of \(hr) BPM, and a pace of \(pace). Focusing on quick, relaxed steps beneath your hips will keep your running smooth and injury-free."
    }
}
