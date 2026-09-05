import Foundation
import WorkoutKit
import HealthKit
import AVFoundation
#if os(watchOS)
import WatchKit
#endif

@available(iOS 17.0, watchOS 10.0, *)
public class LiveCoachEngine {

    public var silentModeEnabled: Bool = false
    public let audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var isMetronomeRunning = false
    private var currentMetronomeTargetSPM: Int = 0
    private var metronomeTimer: Timer?

    public init() {
        setupAudio()
    }

    private func setupAudio() {
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
    /// Expects a string like "4x400m at 165 SPM".
    public func translate(prescription: String) -> CustomWorkout? {
        let pattern = #"(\d+)x(\d+)m(?:\s+at\s+(\d+)\s*SPM)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: prescription, options: [], range: NSRange(location: 0, length: prescription.utf16.count)),
              let iterRange = Range(match.range(at: 1), in: prescription),
              let distRange = Range(match.range(at: 2), in: prescription),
              let iterations = Int(prescription[iterRange]),
              let distance = Double(prescription[distRange]) else {
            return nil
        }

        var workStep = WorkoutStep(goal: .distance(distance, .meter()))
        let recoveryStep = WorkoutStep(goal: .open)

        // Parse target SPM and add alert
        if match.range(at: 3).location != NSNotFound,
           let spmRange = Range(match.range(at: 3), in: prescription),
           let spm = Int(prescription[spmRange]) {
            let cadenceAlert = WorkoutAlert.cadence(target: .range(Double(spm - 5)...Double(spm + 5)))
            workStep.alerts.append(cadenceAlert)
        }

        let workInterval = IntervalStep(.work, step: workStep)
        let recoveryInterval = IntervalStep(.recovery, step: recoveryStep)

        let block = IntervalBlock(steps: [workInterval, recoveryInterval], iterations: iterations)

        return CustomWorkout(
            activity: .running,
            location: .unknown,
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

        let interval = 60.0 / Double(targetSPM)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.metronomeTimer?.invalidate()

            if let buffer = self.generateBeep(frequency: 880, duration: 0.05) {
                self.metronomeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
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
        DispatchQueue.main.async { [weak self] in
            self?.metronomeTimer?.invalidate()
            self?.metronomeTimer = nil
        }
        playerNode.stop()
    }

    /// Evaluates if a corrective haptic should be triggered.
    public func shouldTriggerCorrectiveHaptic(currentSPM: Int, targetSPM: Int) -> Bool {
        return currentSPM < targetSPM
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
            if audioEngine.isRunning {
                // Ensure metronome is running at the correct target SPM
                if currentMetronomeTargetSPM != targetSPM || !isMetronomeRunning {
                    startMetronome(targetSPM: targetSPM)
                }
                audioTriggered = true
            }
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
