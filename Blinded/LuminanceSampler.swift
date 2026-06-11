import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Event-driven screen sampler built on ScreenCaptureKit. The stream is push-based:
/// frames are delivered only when content changes (dirty-region tracking), so there is
/// ~0 work on a static screen. Only `.complete` frames are forwarded.
final class LuminanceSampler: NSObject, SCStreamOutput, SCStreamDelegate {
    enum SamplerError: Error { case noDisplay }

    /// Called on `sampleQueue` (a background queue) for each changed frame.
    var onFrame: ((CGImage) -> Void)?
    /// Called when the stream stops with an error.
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private let ciContext = CIContext(options: [.priorityRequestLow: true])
    private let sampleQueue = DispatchQueue(label: "com.blinded.sampler", qos: .userInitiated)

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
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first(where: { $0.displayID == targetDisplayID })
                ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
            throw SamplerError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 64
        config.height = 40
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
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

        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRaw = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        onFrame?(cgImage)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }
}
