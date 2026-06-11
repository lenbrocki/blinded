import AppKit
import CoreGraphics
import Foundation

/// Identity + metadata for a controllable display.
struct DisplayInfo: Identifiable, Equatable {
    let displayID: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    /// Stable key for persisting this display's learned curve across reconnects/reboots.
    let persistKey: String

    var id: CGDirectDisplayID { displayID }
}

/// Owns one `DisplayEngine` per controllable display (built-in via DisplayServices + every
/// DDC-controllable external), starting/stopping them together and rebuilding on hotplug.
final class DisplayCoordinator {
    private(set) var engines: [CGDirectDisplayID: DisplayEngine] = [:]
    private(set) var order: [CGDirectDisplayID] = []

    var settleTime: CFTimeInterval = 0.05 {
        didSet { engines.values.forEach { $0.settleTime = settleTime } }
    }

    /// Called on the main thread when the set of displays changes (hotplug).
    var onDisplaysChanged: (() -> Void)?
    /// (displayID, luminance, brightness) on the main thread.
    var onUpdate: ((CGDirectDisplayID, Double, Double) -> Void)?
    /// (displayID) on the main thread when a display's curve learns.
    var onLearn: ((CGDirectDisplayID) -> Void)?
    var onError: ((Error) -> Void)?

    private let externalManager = ExternalDisplayManager()
    private var isRunning = false
    private var observing = false

    var displays: [DisplayInfo] { order.compactMap { engines[$0]?.info } }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        rebuild()
        observeHotplug()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engines.values.forEach { $0.stop() }
        engines.removeAll()
        order.removeAll()
    }

    func resetLearning(displayID: CGDirectDisplayID) { engines[displayID]?.resetLearning() }
    func resetAllLearning() { engines.values.forEach { $0.resetLearning() } }

    func previewBrightness(displayID: CGDirectDisplayID, _ value: Double) {
        engines[displayID]?.previewUserBrightness(value)
    }
    func commitBrightness(displayID: CGDirectDisplayID, _ value: Double) {
        engines[displayID]?.commitUserBrightness(value)
    }

    // MARK: - Building the engine set

    /// Rebuilds engines to match currently connected, controllable displays. Keeps existing
    /// engines for displays that are still present (preserves their running state/curve cache).
    private func rebuild() {
        guard isRunning else { return }
        let desired = currentControllableDisplays()      // [(DisplayInfo, BrightnessBackend)]
        let desiredIDs = Set(desired.map { $0.info.displayID })

        // Remove engines for displays that went away.
        for (id, engine) in engines where !desiredIDs.contains(id) {
            engine.stop()
            engines[id] = nil
        }

        // Add engines for new displays.
        for (info, backend) in desired where engines[info.displayID] == nil {
            let engine = DisplayEngine(info: info, backend: backend)
            engine.settleTime = settleTime
            engine.onUpdate = { [weak self] lum, bri in self?.onUpdate?(info.displayID, lum, bri) }
            engine.onLearn = { [weak self] in self?.onLearn?(info.displayID) }
            engine.onError = { [weak self] err in self?.onError?(err) }
            engines[info.displayID] = engine
            engine.start()
        }

        order = desired.map { $0.info.displayID }
        onDisplaysChanged?()
    }

    private func currentControllableDisplays() -> [(info: DisplayInfo, backend: BrightnessBackend)] {
        var result: [(DisplayInfo, BrightnessBackend)] = []

        // Built-in panel.
        let builtInID = BrightnessController.builtInDisplayID()
        let builtIn = BuiltInBrightnessBackend(displayID: builtInID)
        if builtIn.isAvailable {
            let info = DisplayInfo(displayID: builtInID,
                                   name: "Built-in Display",
                                   isBuiltIn: true,
                                   persistKey: persistKey(for: builtInID, fallback: "builtin"))
            result.append((info, builtIn))
        }

        // DDC-controllable externals.
        for ext in externalManager.detect() {
            let info = DisplayInfo(displayID: ext.displayID,
                                   name: ext.name,
                                   isBuiltIn: false,
                                   persistKey: persistKey(for: ext.displayID, fallback: ext.name))
            result.append((info, ext.backend))
        }
        return result
    }

    /// Stable per-display key from its CoreGraphics UUID (survives reconnect); falls back to a name.
    private func persistKey(for displayID: CGDirectDisplayID, fallback: String) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return fallback
    }

    // MARK: - Hotplug

    private func observeHotplug() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
    }
}
