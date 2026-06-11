import CoreGraphics
import Foundation

/// Abstracts "set the brightness of one display" so the engine can drive either the built-in
/// panel (DisplayServices) or an external monitor (DDC/CI over I2C) the same way.
protocol BrightnessBackend: AnyObject {
    var isAvailable: Bool { get }
    /// Whether `read()` reliably reflects the hardware (built-in: yes; DDC: no on many monitors).
    /// Used to decide whether the engine can detect user overrides by polling.
    var supportsReadback: Bool { get }
    func read() -> Double?
    func write(_ value: Double)
}

/// Built-in panel via the private DisplayServices framework (wraps `BrightnessController`).
final class BuiltInBrightnessBackend: BrightnessBackend {
    private let controller: BrightnessController

    init(displayID: CGDirectDisplayID = BrightnessController.builtInDisplayID()) {
        controller = BrightnessController(displayID: displayID)
    }

    var isAvailable: Bool { controller.isAvailable }
    var supportsReadback: Bool { true }
    func read() -> Double? { controller.getBrightness().map(Double.init) }
    func write(_ value: Double) { controller.setBrightness(Float(value)) }
}

/// External monitor via DDC/CI (VCP `0x10` = luminance), using the vendored `Arm64DDC`.
/// Readback is attempted but treated as unreliable; the engine relies on the in-app slider
/// for corrections rather than polling these monitors.
final class DDCBrightnessBackend: BrightnessBackend {
    private let service: IOAVService?
    private let maxValue: UInt16
    private(set) var lastWritten: Double

    init?(match: Arm64DDC.Arm64Service) {
        guard match.service != nil, !match.dummy else { return nil }
        service = match.service
        // Probe the display's max VCP value (most report 100); fall back to 100.
        let probe = Arm64DDC.read(service: match.service, command: 0x10)
        maxValue = (probe?.max ?? 0) > 0 ? probe!.max : 100
        if let p = probe, p.max > 0 {
            lastWritten = Double(p.current) / Double(p.max)
        } else {
            lastWritten = 1.0
        }
    }

    var isAvailable: Bool { service != nil }
    var supportsReadback: Bool { false }

    func read() -> Double? {
        guard let r = Arm64DDC.read(service: service, command: 0x10), r.max > 0 else { return nil }
        return Double(r.current) / Double(r.max)
    }

    func write(_ value: Double) {
        let clamped = max(0, min(1, value))
        lastWritten = clamped
        let raw = UInt16((Double(maxValue) * clamped).rounded())
        _ = Arm64DDC.write(service: service, command: 0x10, value: raw)
    }
}
