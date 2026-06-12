import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Screen sampler built on ScreenCaptureKit.
///
/// ScreenCaptureKit is NOT a pure "push on change" API: `SCStream` delivers buffers at up to
/// `minimumFrameInterval`, and on a static screen those buffers still arrive carrying
/// `SCFrameStatus.idle` ("new frame was not generated because the display did not change").
/// So the capture rate is the idle-CPU floor — there is no setting for "zero delivery until
/// something changes." We therefore capture at a low fixed rate: idle frames are cheap at this
/// rate, and only `.complete` frames (real content changes) are forwarded for luminance work.
///
/// Trade-off: a low rate means a real change is noticed up to `1/captureFPS` seconds late.
final class LuminanceSampler: NSObject, SCStreamOutput, SCStreamDelegate {
    enum SamplerError: Error { case noDisplay }

    private static let captureFPS: Int32 = 5

    /// Called on `sampleQueue` (a background queue) with the average luminance (0...1) of each
    /// changed frame.
    var onFrame: ((Double) -> Void)?
    /// Called when the stream stops with an error.
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.lumos.sampler", qos: .userInitiated)

    /// The display this sampler captures. Defaults to the main display.
    private let targetDisplayID: CGDirectDisplayID

    init(displayID: CGDirectDisplayID = CGMainDisplayID()) {
        targetDisplayID = displayID
        super.init()
    }

    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    func start() async throws {
        // Tear down any prior (possibly dead) stream so this is safe to call for recovery.
        if stream != nil { await stop() }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first(where: { $0.displayID == targetDisplayID })
                ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
            throw SamplerError.noDisplay
        }

        // Exclude our own windows (the menu-bar popover) from capture. Otherwise the popover —
        // which shows live luminance/brightness — feeds back into the capture: rendering it
        // changes the screen, which produces a frame, which updates the popover, and so on, so
        // the loop never settles while it's open. Excluding our windows also keeps our own UI
        // from skewing the luminance reading.
        let myBundleID = Bundle.main.bundleIdentifier
        let ownWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == myBundleID
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let config = SCStreamConfiguration()
        config.width = 64
        config.height = 40
        config.minimumFrameInterval = CMTime(value: 1, timescale: Self.captureFPS)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Forward only real content changes; ignore `.idle` (and any non-`.complete`) frames.
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRaw = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(LuminanceCalculator.averageLuminance(of: pixelBuffer))
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }
}
