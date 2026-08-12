import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import os

struct VoiceMemoGuardianState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case recording
        case silence
    }

    let phase: Phase
    let startedAt: Date
    let silentSince: Date?

    func displayText(at now: Date) -> String {
        switch phase {
        case .recording:
            "录音 \(Self.compactMinutes(from: startedAt, to: now))"
        case .silence:
            "静音 \(Self.compactMinutes(from: silentSince ?? startedAt, to: now))"
        }
    }

    private static func compactMinutes(from start: Date, to end: Date) -> String {
        "\(max(0, Int(end.timeIntervalSince(start)) / 60))分"
    }
}

enum VoiceMemoSilencePolicy {
    static let reminderThreshold: TimeInterval = 5 * 60
    static let meanVolumeThreshold = -45.0
    static let peakVolumeThreshold = -30.0

    static func isSilent(meanDB: Double, peakDB: Double) -> Bool {
        meanDB <= meanVolumeThreshold && peakDB <= peakVolumeThreshold
    }

    static func shouldRemind(silentSince: Date?, now: Date) -> Bool {
        guard let silentSince else { return false }
        return now.timeIntervalSince(silentSince) >= reminderThreshold
    }
}

@MainActor
final class VoiceMemoGuardian {
    var onStateChanged: ((VoiceMemoGuardianState?) -> Void)?
    var onSilenceReminder: ((VoiceMemoGuardianState) -> Void)?

    private static let voiceMemosBundleIdentifier = "com.apple.VoiceMemos"
    private static let logger = Logger(
        subsystem: "dev.kanyun.CodexHermesTouchBar",
        category: "VoiceMemoGuardian"
    )
    private let audioMeter = VoiceMemoAudioMeter()
    private var timer: Timer?
    private var recordingStartedAt: Date?
    private var lastReminderAt: Date?
    private var lastState: VoiceMemoGuardianState?

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: 5, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        audioMeter.stop()
    }

    func continueRecording() {
        audioMeter.markSoundNow()
        lastReminderAt = Date()
        poll()
    }

    @objc private func timerFired() {
        poll()
    }

    private func poll() {
        let now = Date()
        guard let detectedStart = activeRecordingStartDate(now: now) else {
            reset()
            return
        }
        if lastState == nil {
            Self.logger.info("Voice Memos active recording detected")
        }
        recordingStartedAt = recordingStartedAt ?? detectedStart
        audioMeter.startIfNeeded()

        let silentSince = audioMeter.silentSince
        let state = VoiceMemoGuardianState(
            phase: VoiceMemoSilencePolicy.shouldRemind(silentSince: silentSince, now: now)
                ? .silence
                : .recording,
            startedAt: recordingStartedAt ?? detectedStart,
            silentSince: silentSince
        )
        lastState = state
        onStateChanged?(state)

        guard state.phase == .silence else {
            lastReminderAt = nil
            return
        }
        if let lastReminderAt, now.timeIntervalSince(lastReminderAt) < 15 * 60 { return }
        lastReminderAt = now
        onSilenceReminder?(state)
    }

    private func reset() {
        recordingStartedAt = nil
        lastReminderAt = nil
        audioMeter.stop()
        guard lastState != nil else { return }
        Self.logger.info("Voice Memos recording ended")
        lastState = nil
        onStateChanged?(nil)
    }

    private func activeRecordingStartDate(now: Date) -> Date? {
        guard AXIsProcessTrusted() else {
            return nil
        }
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.voiceMemosBundleIdentifier
        ).first else {
            return nil
        }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        guard containsButton(in: root, descriptions: ["暂停", "Pause"]) else {
            return nil
        }
        guard let clock = firstDescription(in: root, matching: /^\d{1,2}:\d{2}$/) else {
            return recordingStartedAt ?? now
        }
        let pieces = clock.split(separator: ":").compactMap { Int($0) }
        guard pieces.count == 2 else { return recordingStartedAt ?? now }
        return Calendar.current.date(bySettingHour: pieces[0], minute: pieces[1], second: 0, of: now)
            ?? recordingStartedAt
            ?? now
    }

    private func containsButton(
        in element: AXUIElement,
        descriptions: Set<String>,
        depth: Int = 0
    ) -> Bool {
        guard depth < 10 else { return false }
        let role = attribute(kAXRoleAttribute, from: element) as? String
        let description = attribute(kAXDescriptionAttribute, from: element) as? String
        if role == kAXButtonRole, description.map(descriptions.contains) == true { return true }
        guard let children = attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else {
            return false
        }
        return children.contains { containsButton(in: $0, descriptions: descriptions, depth: depth + 1) }
    }

    private func firstDescription(
        in element: AXUIElement,
        matching expression: Regex<Substring>,
        depth: Int = 0
    ) -> String? {
        guard depth < 10 else { return nil }
        if let description = attribute(kAXDescriptionAttribute, from: element) as? String,
           description.wholeMatch(of: expression) != nil {
            return description
        }
        guard let children = attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let match = firstDescription(in: child, matching: expression, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private func attribute(_ name: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}

@MainActor
private final class VoiceMemoAudioMeter: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let accumulator = VoiceMemoLevelAccumulator()
    var silentSince: Date? { accumulator.silentSince }
    private var isRunning = false
    private var permissionRequestInFlight = false

    func startIfNeeded() {
        guard !isRunning, !permissionRequestInFlight else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            permissionRequestInFlight = true
            Self.requestAudioAccess { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.permissionRequestInFlight = false
                    if granted { self.startEngine() }
                }
            }
        default:
            break
        }
    }

    nonisolated private static func requestAudioAccess(
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    func stop() {
        guard isRunning else {
            accumulator.reset()
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        accumulator.reset()
    }

    func markSoundNow() {
        accumulator.reset()
    }

    private func startEngine() {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        Self.installTap(on: input, format: format, accumulator: accumulator)
        do {
            try engine.start()
            isRunning = true
            accumulator.beginSilence(at: Date())
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    nonisolated private static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        accumulator: VoiceMemoLevelAccumulator
    ) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let levels = levels(in: buffer) else { return }
            accumulator.accept(meanDB: levels.mean, peakDB: levels.peak, now: Date())
        }
    }

    nonisolated private static func levels(in buffer: AVAudioPCMBuffer) -> (mean: Double, peak: Double)? {
        guard let channel = buffer.floatChannelData?.pointee else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        var sumSquares = 0.0
        var peak = 0.0
        for index in 0..<count {
            let sample = Double(abs(channel[index]))
            sumSquares += sample * sample
            peak = max(peak, sample)
        }
        let mean = sqrt(sumSquares / Double(count))
        return (20 * log10(max(mean, 0.000_001)), 20 * log10(max(peak, 0.000_001)))
    }
}

private final class VoiceMemoLevelAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSilentSince: Date?

    var silentSince: Date? {
        lock.lock()
        defer { lock.unlock() }
        return storedSilentSince
    }

    func accept(meanDB: Double, peakDB: Double, now: Date) {
        lock.lock()
        defer { lock.unlock() }
        if VoiceMemoSilencePolicy.isSilent(meanDB: meanDB, peakDB: peakDB) {
            storedSilentSince = storedSilentSince ?? now
        } else {
            storedSilentSince = nil
        }
    }

    func beginSilence(at date: Date) {
        lock.lock()
        storedSilentSince = date
        lock.unlock()
    }

    func reset() {
        lock.lock()
        storedSilentSince = nil
        lock.unlock()
    }
}
