import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// Observable state for the menu bar UI. Owns the `DisplayCoordinator` and mirrors its
/// per-display state into view models for SwiftUI.
@MainActor
final class AppState: ObservableObject {
    struct DisplayVM: Identifiable {
        let id: CGDirectDisplayID
        let name: String
        let isBuiltIn: Bool
        var luminance: Double
        var brightness: Double
        var corrections: Int
    }

    @Published var isEnabled = false
    @Published var displays: [DisplayVM] = []
    @Published var hasScreenPermission = false
    @Published var lastErrorMessage: String?
    @Published var settleTime: Double = 0.05 {
        didSet { coordinator.settleTime = settleTime }
    }

    let builtInBrightnessAvailable: Bool

    static let settleTimeOptionsMs: [Int] = Array(stride(from: 0, through: 100, by: 10))

    private let coordinator = DisplayCoordinator()

    // Live values + throttled flush so the popover doesn't rebuild on every frame.
    private var lumByID: [CGDirectDisplayID: Double] = [:]
    private var briByID: [CGDirectDisplayID: Double] = [:]
    private var correctionsByID: [CGDirectDisplayID: Int] = [:]
    private var flushScheduled = false

    init() {
        builtInBrightnessAvailable = BuiltInBrightnessBackend().isAvailable
        hasScreenPermission = LuminanceSampler.hasPermission()

        coordinator.onDisplaysChanged = { [weak self] in self?.rebuildDisplays() }
        coordinator.onUpdate = { [weak self] id, lum, bri in
            self?.lumByID[id] = lum
            self?.briByID[id] = bri
            self?.scheduleFlush()
        }
        coordinator.onLearn = { [weak self] id in
            self?.correctionsByID[id, default: 0] += 1
            self?.rebuildDisplays()
        }
        coordinator.onError = { [weak self] error in
            self?.lastErrorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ on: Bool) {
        if on {
            if !LuminanceSampler.hasPermission() {
                LuminanceSampler.requestPermission()
                hasScreenPermission = LuminanceSampler.hasPermission()
            }
            lastErrorMessage = nil
            coordinator.start()
        } else {
            coordinator.stop()
            lumByID.removeAll(); briByID.removeAll()
            displays = []
        }
        isEnabled = on
    }

    // MARK: - Slider corrections

    func previewBrightness(_ id: CGDirectDisplayID, _ value: Double) {
        coordinator.previewBrightness(displayID: id, value)
        briByID[id] = value
        updateBrightness(id, value)
    }

    func commitBrightness(_ id: CGDirectDisplayID, _ value: Double) {
        coordinator.commitBrightness(displayID: id, value)
        briByID[id] = value
    }

    func resetLearning(_ id: CGDirectDisplayID) {
        coordinator.resetLearning(displayID: id)
        correctionsByID[id] = 0
        rebuildDisplays()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - View-model mirroring

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.flushScheduled = false
            self?.rebuildDisplays()
        }
    }

    private func rebuildDisplays() {
        displays = coordinator.displays.map { info in
            DisplayVM(id: info.displayID,
                      name: info.name,
                      isBuiltIn: info.isBuiltIn,
                      luminance: lumByID[info.displayID] ?? 0,
                      brightness: briByID[info.displayID] ?? 0,
                      corrections: correctionsByID[info.displayID] ?? 0)
        }
    }

    /// Updates just one display's brightness in place (used during live slider drags).
    private func updateBrightness(_ id: CGDirectDisplayID, _ value: Double) {
        guard let idx = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[idx].brightness = value
    }
}
