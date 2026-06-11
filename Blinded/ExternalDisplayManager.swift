import CoreGraphics
import Foundation

struct DetectedExternalDisplay {
    let displayID: CGDirectDisplayID
    let name: String
    let backend: DDCBrightnessBackend
}

/// Detects external displays and which ones are DDC-controllable on Apple Silicon, using the
/// vendored `Arm64DDC` matcher. Also provides a manual write for hardware verification.
final class ExternalDisplayManager {
    private(set) var displays: [DetectedExternalDisplay] = []

    @discardableResult
    func detect() -> [DetectedExternalDisplay] {
        let externals = activeDisplayIDs().filter { CGDisplayIsBuiltin($0) == 0 }
        guard !externals.isEmpty else {
            displays = []
            return []
        }
        var result: [DetectedExternalDisplay] = []
        for match in Arm64DDC.getServiceMatches(displayIDs: externals) where match.service != nil && !match.dummy {
            guard let backend = DDCBrightnessBackend(match: match) else { continue }
            let raw = match.serviceDetails.productName
            let name = raw.isEmpty ? "Display \(match.displayID)" : raw
            result.append(DetectedExternalDisplay(displayID: match.displayID, name: name, backend: backend))
        }
        displays = result
        return result
    }

    /// Human-readable summary for the menu, useful to confirm DDC works on real hardware.
    func report() -> String {
        let externals = activeDisplayIDs().filter { CGDisplayIsBuiltin($0) == 0 }
        if externals.isEmpty { return "No external displays connected." }
        if displays.isEmpty {
            return "\(externals.count) external display(s) found, none DDC-controllable."
        }
        let lines = displays.map { d -> String in
            let pct = d.backend.read().map { " — \(Int(($0 * 100).rounded()))%" } ?? ""
            return "• \(d.name)\(pct)"
        }
        return "DDC-controllable:\n" + lines.joined(separator: "\n")
    }

    /// Writes a brightness to every detected external display (manual test).
    func setAll(_ value: Double) {
        for d in displays { d.backend.write(value) }
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
