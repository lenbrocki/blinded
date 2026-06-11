import CoreGraphics
import Foundation
import QuartzCore

/// Content-adaptive brightness controller for a single display. Same pipeline as before
/// (ScreenCaptureKit frame -> luminance -> stabilizer -> learnable curve -> ramped brightness),
/// but the actuation is injected as a `BrightnessBackend` so it works for the built-in panel
/// (DisplayServices) or an external monitor (DDC).
///
/// Corrections:
/// - Built-in (backend supports readback): a poll detects brightness-key / Control-Center changes.
/// - External (no reliable readback): the in-app slider calls `commitUserBrightness`.
/// Both feed the same learning (`reinforce`) on this display's own curve.
final class DisplayEngine {
    let info: DisplayInfo

    // Reaction tuning.
    var jumpThreshold: Double = 0.15
    var fastRampPerSecond: Double = 6.0     // big brightening (dark content) — kept gentle to avoid a flash
    var dimRampPerSecond: Double = 50.0     // big dimming (content got brighter) — ~instant (one frame)
    var gentleRampPerSecond: Double = 2.0
    var settleTime: CFTimeInterval = 0.0 {
        didSet { stabilizer.settleTime = settleTime }
    }

    // Learning tuning.
    var overrideThreshold: Double = 0.04
    var overrideSettleTime: CFTimeInterval = 0.4

    var onUpdate: ((Double, Double) -> Void)?
    var onError: ((Error) -> Void)?
    var onLearn: (() -> Void)?

    private let sampler: LuminanceSampler
    private let backend: BrightnessBackend

    private var model: AdaptiveBrightnessModel

    private var stabilizer = LuminanceStabilizer()
    private var latestLuminance: Double = 0
    private var targetBrightness: Double = 1.0
    private var currentBrightness: Double = 1.0
    private var rampPerSecond: Double = 2.0
    private var controlTimer: Timer?
    private var lastTick: CFTimeInterval = 0

    // Override / manual-edit state.
    private var monitorTimer: Timer?
    private var pendingOverride: Double?
    private var pendingOverrideSince: CFTimeInterval = 0
    private var isUserEditing = false

    // Capture recovery.
    private var isLaunching = false
    private var captureRetry = 0
    private let maxCaptureRetries = 12

    private(set) var isRunning = false

    init(info: DisplayInfo, backend: BrightnessBackend) {
        self.info = info
        self.backend = backend
        self.sampler = LuminanceSampler(displayID: info.displayID)
        self.model = AdaptiveBrightnessModel.loadOrDefault(key: info.persistKey)
    }

    var brightnessAvailable: Bool { backend.isAvailable }
    var displayedBrightness: Double { currentBrightness }
    var displayedLuminance: Double { latestLuminance }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        if let hw = backend.read() {
            currentBrightness = hw
            targetBrightness = hw
        }

        stabilizer = LuminanceStabilizer()
        stabilizer.settleTime = settleTime

        sampler.onFrame = { [weak self] image in
            let lum = LuminanceCalculator.averageLuminance(of: image)
            DispatchQueue.main.async { self?.ingest(luminance: lum) }
        }
        sampler.onError = { [weak self] error in
            // Stream stopped (display sleep, resolution change, etc.) — recover, don't give up.
            DispatchQueue.main.async { self?.handleCaptureStopped(error) }
        }

        if backend.supportsReadback {
            startMonitor()
        }

        launchCapture()
    }

    // MARK: - Capture lifecycle / recovery

    /// Re-establishes capture after a sleep/wake or display reconfiguration. Resets the retry
    /// budget so a long-asleep display reconnects cleanly.
    func restartCapture() {
        guard isRunning else { start(); return }
        captureRetry = 0
        launchCapture()
    }

    private func launchCapture() {
        guard isRunning, !isLaunching else { return }
        isLaunching = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sampler.start()
                await MainActor.run { self.isLaunching = false }
            } catch {
                await MainActor.run {
                    self.isLaunching = false
                    self.scheduleCaptureRetry(error)
                }
            }
        }
    }

    private func handleCaptureStopped(_ error: Error) {
        guard isRunning else { return }
        scheduleCaptureRetry(error)
    }

    /// During wake, displays are briefly unavailable (`SCShareableContent` returns none). Retry
    /// with backoff; only surface an error after many failures (e.g. permission truly revoked).
    private func scheduleCaptureRetry(_ error: Error) {
        guard isRunning else { return }
        guard captureRetry < maxCaptureRetries else {
            onError?(error)
            return
        }
        captureRetry += 1
        let delay = min(0.5 * Double(captureRetry), 3.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRunning else { return }
            self.launchCapture()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        sampler.onFrame = nil
        Task { [sampler] in await sampler.stop() }
        DispatchQueue.main.async { [weak self] in
            self?.controlTimer?.invalidate(); self?.controlTimer = nil
            self?.monitorTimer?.invalidate(); self?.monitorTimer = nil
            self?.pendingOverride = nil
        }
    }

    func resetLearning() {
        model = AdaptiveBrightnessModel()
        model.save(key: info.persistKey)
        onLearn?()
    }

    // MARK: - Manual correction (slider)

    /// Live preview while dragging: apply immediately and pause auto-adjust, without learning yet.
    func previewUserBrightness(_ value: Double) {
        isUserEditing = true
        let v = max(0, min(1, value))
        currentBrightness = v
        targetBrightness = v
        backend.write(v)
        onUpdate?(latestLuminance, v)
    }

    /// Final value when the user releases the slider: apply, learn, and resume auto-adjust.
    func commitUserBrightness(_ value: Double) {
        let v = max(0, min(1, value))
        currentBrightness = v
        targetBrightness = v
        backend.write(v)
        model.reinforce(luminance: stabilizer.committed, brightness: v)
        model.save(key: info.persistKey)
        isUserEditing = false
        onUpdate?(latestLuminance, v)
        onLearn?()
    }

    // MARK: - Control loop (main thread)

    private func ingest(luminance lum: Double) {
        captureRetry = 0 // frames are flowing again
        latestLuminance = lum
        ensureControlTimer()
    }

    private func ensureControlTimer() {
        guard controlTimer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.controlTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        controlTimer = timer
    }

    private func controlTick() {
        let now = CACurrentMediaTime()
        let dt = max(0, now - lastTick)
        lastTick = now

        if stabilizer.update(luminance: latestLuminance, now: now) {
            let newTarget = model.brightness(forLuminance: stabilizer.committed)
            let delta = newTarget - currentBrightness
            if abs(delta) >= jumpThreshold {
                // Dimming (content got brighter) is sped up to minimize the brightness flare;
                // brightening stays gentler so it doesn't flash.
                rampPerSecond = delta < 0 ? dimRampPerSecond : fastRampPerSecond
            } else {
                rampPerSecond = gentleRampPerSecond
            }
            targetBrightness = newTarget
        }

        // Don't fight the user (key override in progress, or actively dragging the slider).
        if pendingOverride == nil, !isUserEditing {
            let diff = targetBrightness - currentBrightness
            if abs(diff) > 0.0005 {
                let step = rampPerSecond * dt
                currentBrightness = abs(diff) <= step
                    ? targetBrightness
                    : currentBrightness + (diff > 0 ? step : -step)
                backend.write(currentBrightness)
            }
        }
        onUpdate?(latestLuminance, currentBrightness)

        let luminanceSettled = abs(latestLuminance - stabilizer.committed) <= stabilizer.noiseBand
        let brightnessSettled = abs(targetBrightness - currentBrightness) <= 0.0005
        if pendingOverride == nil, !isUserEditing, luminanceSettled, brightnessSettled {
            controlTimer?.invalidate()
            controlTimer = nil
        }
    }

    private var isActivelyRamping: Bool {
        controlTimer != nil && abs(targetBrightness - currentBrightness) > 0.005
    }

    // MARK: - Override detection (built-in only)

    private func startMonitor() {
        guard monitorTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.monitorTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    private func monitorTick() {
        guard !isActivelyRamping, !isUserEditing else { return }
        guard let hw = backend.read() else { return }
        let now = CACurrentMediaTime()

        if let pending = pendingOverride {
            if abs(hw - pending) > 0.005 {
                pendingOverride = hw
                pendingOverrideSince = now
            } else if now - pendingOverrideSince >= overrideSettleTime {
                commitOverride(brightness: hw)
            }
        } else if abs(hw - currentBrightness) > overrideThreshold {
            pendingOverride = hw
            pendingOverrideSince = now
        }
    }

    private func commitOverride(brightness hw: Double) {
        pendingOverride = nil
        currentBrightness = hw
        targetBrightness = hw
        model.reinforce(luminance: stabilizer.committed, brightness: hw)
        model.save(key: info.persistKey)
        onUpdate?(latestLuminance, currentBrightness)
        onLearn?()
    }
}
