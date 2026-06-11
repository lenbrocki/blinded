import CoreGraphics
import Foundation

/// Wraps the private `DisplayServices.framework` brightness symbols, resolved at
/// runtime via `dlopen`/`dlsym` so there is no link-time dependency on a private
/// framework. Operates on the built-in display. If the symbols cannot be resolved
/// (future macOS change), `isAvailable` is false and calls become no-ops.
final class BrightnessController {
    private typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private let setFunc: SetBrightnessFunc?
    private let getFunc: GetBrightnessFunc?
    private let displayID: CGDirectDisplayID

    init(displayID: CGDirectDisplayID = BrightnessController.builtInDisplayID()) {
        self.displayID = displayID

        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW) else {
            NSLog("Blinded: failed to dlopen DisplayServices: \(String(cString: dlerror()))")
            setFunc = nil
            getFunc = nil
            return
        }
        setFunc = dlsym(handle, "DisplayServicesSetBrightness").map {
            unsafeBitCast($0, to: SetBrightnessFunc.self)
        }
        getFunc = dlsym(handle, "DisplayServicesGetBrightness").map {
            unsafeBitCast($0, to: GetBrightnessFunc.self)
        }
        if setFunc == nil {
            NSLog("Blinded: DisplayServicesSetBrightness symbol not found")
        }
    }

    var isAvailable: Bool { setFunc != nil }

    /// Current backlight level in 0...1, or nil if unavailable.
    func getBrightness() -> Float? {
        guard let getFunc else { return nil }
        var value: Float = 0
        return getFunc(displayID, &value) == 0 ? value : nil
    }

    /// Sets the backlight level, clamped to 0...1. Returns true on success.
    @discardableResult
    func setBrightness(_ value: Float) -> Bool {
        guard let setFunc else { return false }
        let clamped = max(0, min(1, value))
        return setFunc(displayID, clamped) == 0
    }

    /// Finds the built-in panel; falls back to the main display.
    static func builtInDisplayID() -> CGDirectDisplayID {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return CGMainDisplayID()
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return CGMainDisplayID()
        }
        return displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
    }
}
