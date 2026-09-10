import Foundation
import WorkoutKit
import HealthKit
@preconcurrency import AVFoundation
#if os(watchOS)
import WatchKit
#endif

@available(iOS 17.0, watchOS 10.0, *)
@MainActor
public class LiveCoachEngine {

    public var silentModeEnabled: Bool = false
    public let audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var isMetronomeRunning = false
    private var currentMetronomeTargetSPM: Int = 0
    private var metronomeTimer: Timer?

    public init() {}

    private var isRunningInTest: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func setupAudioIfNeeded() {
        guard !isRunningInTest else { return }
        guard !audioEngine.isRunning else { return }
        audioEngine.attach(playerNode)
        let format = audioEngine.outputNode.inputFormat(forBus: 0)
        audioEngine.connect(playerNode, to: audioEngine.outputNode, format: format)
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    /// Translates an AI drill prescription string into a CustomWorkout.
    /// Expects a string like "4x400m intervals".
    public func translate(prescription: String, targetSPM: Int) -> CustomWorkout? {
        let pattern = #"(\d+)x(\d+)m"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: prescription, options: [], range: NSRange(location: 0, length: prescription.utf16.count)),
              let iterRange = Range(match.range(at: 1), in: prescription),
              let distRange = Range(match.range(at: 2), in: prescription),
              let iterations = Int(prescription[iterRange]),
              let distance = Double(prescription[distRange]) else {
            return nil
        }

        var workStep = WorkoutStep(goal: .distance(distance, .meters))
        let lowerBound = Double(max(0, targetSPM - 5))
        let upperBound = Double(targetSPM + 5)
        workStep.alert = .cadence(lowerBound...upperBound)
        let recoveryStep = WorkoutStep(goal: .open)

        let workInterval = IntervalStep(.work, step: workStep)
        let recoveryInterval = IntervalStep(.recovery, step: recoveryStep)

        let block = IntervalBlock(steps: [workInterval, recoveryInterval], iterations: iterations)

        return CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: "AI Prescribed Workout",
            warmup: nil,
            blocks: [block],
            cooldown: nil
        )
    }

    /// Starts the continuous audio metronome mapped directly to the target SPM.
    public func startMetronome(targetSPM: Int) {
        if silentModeEnabled { return }
        if targetSPM <= 0 { return }

        currentMetronomeTargetSPM = targetSPM
        isMetronomeRunning = true

        guard !isRunningInTest else { return }
        setupAudioIfNeeded()

        let interval = 60.0 / Double(targetSPM)

        self.metronomeTimer?.invalidate()

        if let buffer = self.generateBeep(frequency: 880, duration: 0.05) {
            self.metronomeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self, self.isMetronomeRunning, !self.silentModeEnabled else { return }
                    self.playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
                    if !self.playerNode.isPlaying {
                        self.playerNode.play()
                    }
                }
            }
        }
    }

    public func stopMetronome() {
        isMetronomeRunning = false
        metronomeTimer?.invalidate()
        metronomeTimer = nil
        playerNode.stop()
    }

    /// Evaluates if a corrective haptic should be triggered.
    public func shouldTriggerCorrectiveHaptic(currentSPM: Int, targetSPM: Int) -> Bool {
        return currentSPM < targetSPM
    }

    /// Evaluates if haptic feedback should be delivered according to the selected HapticFeedbackMode.
    public nonisolated static func shouldTriggerHaptic(
        mode: HapticFeedbackMode,
        currentSPM: Int,
        targetSPM: Int,
        intervalElapsedSeconds: TimeInterval
    ) -> Bool {
        switch mode {
        case .off:
            return false
        case .on:
            // Pulses rhythm during the first 20 seconds of each work interval or when cadence drops below target threshold
            return intervalElapsedSeconds <= 20.0 || currentSPM < (targetSPM - 2)
        }
    }

    public func shouldTriggerHaptic(
        mode: HapticFeedbackMode,
        currentSPM: Int,
        targetSPM: Int,
        intervalElapsedSeconds: TimeInterval
    ) -> Bool {
        Self.shouldTriggerHaptic(
            mode: mode,
            currentSPM: currentSPM,
            targetSPM: targetSPM,
            intervalElapsedSeconds: intervalElapsedSeconds
        )
    }

    /// Triggers audio and/or haptic cues based on current performance and silent mode.
    /// Returns a tuple indicating if (audioWasPlayed, hapticWasTriggered) for testing purposes.
    @discardableResult
    public func triggerCues(currentSPM: Int, targetSPM: Int) -> (audio: Bool, haptic: Bool) {
        let shouldHaptic = shouldTriggerCorrectiveHaptic(currentSPM: currentSPM, targetSPM: targetSPM)
        var audioTriggered = false
        var hapticTriggered = false

        if shouldHaptic {
            #if os(watchOS)
            WKInterfaceDevice.current().play(.directionDown) // Corrective nudge
            #endif
            hapticTriggered = true
        }

        if !silentModeEnabled {
            if currentMetronomeTargetSPM != targetSPM || !isMetronomeRunning {
                startMetronome(targetSPM: targetSPM)
            }
            audioTriggered = true
        } else {
            // Stop metronome if it's running but silent mode was toggled on
            if isMetronomeRunning {
                stopMetronome()
            }
        }

        return (audioTriggered, hapticTriggered)
    }

    private func generateBeep(frequency: Float, duration: Double) -> AVAudioPCMBuffer? {
        let format = audioEngine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let channels = Int(format.channelCount)
        for ch in 0..<channels {
            let channelData = buffer.floatChannelData?[ch]
            for frame in 0..<Int(frameCount) {
                let time = Double(frame) / sampleRate
                let value = Float(sin(2.0 * Double.pi * Double(frequency) * time))
                channelData?[frame] = value
            }
        }
        return buffer
    }

    /// Triggers a success haptic when an interval is completed.
    public func intervalCompleted() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
}
