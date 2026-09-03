// Modified 2026-09-03 for the cmux carousel build (cmux-carousel-ui CONTRACT, harness H2; rows 121, 122).
//
// H2's recorder, IN PROCESS.
//
// Why this exists rather than an ffmpeg screen capture. An out-of-process recording of
// the screen needs the Screen Recording TCC grant, and an ssh session cannot answer a
// TCC prompt -- `screencapture -x` returns "could not create image from display" and
// ffmpeg's avfoundation input simply hangs. Team-lead ruling 2026-09-03: no Screen
// Recording grant will be requested. So H2 records itself.
//
// The permission-free path is the repo's own, already used for window screenshots:
// `SCShareableContent.currentProcess` returns THIS process's windows without ever
// prompting (macOS 14.4+, verified in Sources/TerminalController+WindowScreenshotCapture.swift).
// The same filter drives an SCStream rather than a one-shot SCScreenshotManager capture,
// which is the only difference between a screenshot and a 60 fps recording.
//
// This is also a BETTER measurement than the ffmpeg route it replaces: it records the
// app's own window rather than the whole screen, so nothing else on the desktop can
// enter the frame and no cropping step can misalign the geometry H2 tracks.
//
// It records; it does not measure. Duration, monotonicity and overshoot come from
// tools/fidelity/motion_measure.py over the extracted frames, and FRAME RATE comes from
// H4 Instruments alone (CONTRACT row 112) -- a recording reads 60 fps while the app
// drops frames the compositor hides, which is the whole reason row 112 exists. Nothing
// here reports a frame rate, so nothing here can be quoted for one.
//
// DEBUG-ONLY. It is inert unless CMUX_CAROUSEL_RECORD names an output path, so a normal
// run never constructs a stream, and it never ships enabled.

import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Records this process's own window at a fixed frame interval, permission-free.
///
/// `SCStream` delivers sample buffers on a queue of our choosing, so every piece of
/// mutable state lives behind an actor and the delegate hop is explicit. There is no
/// `@unchecked Sendable` here: the concurrency skill is right that it silences the
/// diagnostic without fixing the race, and an actor costs nothing at 60 buffers a second.
@available(macOS 14.4, *)
final class CarouselFrameRecorder: NSObject, SCStreamOutput, SCStreamDelegate {

    enum RecorderError: LocalizedError {
        case noMatchingWindow(String)
        case writerSetupFailed(String)
        case notRecording

        var errorDescription: String? {
            switch self {
            case .noMatchingWindow(let title):
                return "No window of this process matched \"\(title)\". A recording with no window "
                     + "is not a recording; launch the carousel before starting H2."
            case .writerSetupFailed(let detail):
                return "Could not start the asset writer: \(detail)"
            case .notRecording:
                return "stop() called before start()."
            }
        }
    }

    /// Serialises writer state. The stream hands buffers to `sampleQueue`, so without an
    /// actor two buffers could reach `append` concurrently during a burst.
    private actor WriterBox {
        private var writer: AVAssetWriter?
        private var input: AVAssetWriterInput?
        private var started = false
        private(set) var framesAppended = 0
        private(set) var framesDropped = 0

        func configure(url: URL, width: Int, height: Int, fps: Int32) throws {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                // Lossless is not the goal; H2 tracks luminance EDGES, and a low CRF
                // keeps those crisp while a 60 fps 2688-wide stream stays writable in
                // real time on this machine.
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: width * height * 8,
                    AVVideoExpectedSourceFrameRateKey: fps,
                    AVVideoMaxKeyFrameIntervalKey: fps,
                ],
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw RecorderError.writerSetupFailed("the writer rejected the video input")
            }
            writer.add(input)
            self.writer = writer
            self.input = input
        }

        func append(_ buffer: CMSampleBuffer) {
            guard let writer, let input else { return }
            if !started {
                guard writer.startWriting() else {
                    // startWriting() failing is terminal; count everything after it as
                    // dropped rather than silently recording nothing.
                    framesDropped += 1
                    return
                }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
                started = true
            }
            guard input.isReadyForMoreMediaData, input.append(buffer) else {
                framesDropped += 1
                return
            }
            framesAppended += 1
        }

        func finish() async -> (appended: Int, dropped: Int) {
            guard let writer, let input, started else {
                return (framesAppended, framesDropped)
            }
            input.markAsFinished()
            await writer.finishWriting()
            return (framesAppended, framesDropped)
        }
    }

    private let box = WriterBox()
    private let sampleQueue = DispatchQueue(label: "com.cmux.carousel.fidelity.recorder")
    private var stream: SCStream?

    /// The output path H2 records to, or nil when recording is not enabled.
    ///
    /// Reading the environment here rather than at a call site is deliberate: it is the
    /// single place that decides whether any of this runs, so a normal launch cannot
    /// construct a stream by accident.
    static func requestedOutputURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let path = environment["CMUX_CAROUSEL_RECORD"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Starts recording the current process's window whose title contains `titleMatch`.
    ///
    /// - Parameter fps: the capture rate. 60 on this build's target panel, which has no
    ///   ProMotion. Passed in rather than hardcoded so the value comes from the display.
    func start(outputURL: URL, titleMatch: String, fps: Int32 = 60) async throws {
        // currentProcess is the permission-free query. Any other SCShareableContent
        // entry point prompts for Screen Recording, which is exactly what this avoids.
        let content = try await SCShareableContent.currentProcess
        let candidates = content.windows.filter { window in
            guard window.isOnScreen, window.frame.width > 200, window.frame.height > 200 else {
                return false
            }
            guard !titleMatch.isEmpty else { return true }
            return (window.title ?? "").localizedCaseInsensitiveContains(titleMatch)
        }
        guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        else {
            throw RecorderError.noMatchingWindow(titleMatch)
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let info = SCShareableContent.info(for: filter)
        let scale = CGFloat(info.pointPixelScale)
        let width = max(2, Int((info.contentRect.width * scale).rounded()))
        let height = max(2, Int((info.contentRect.height * scale).rounded()))

        try await box.configure(url: outputURL, width: width, height: height, fps: fps)

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.capturesAudio = false
        // The frame interval is a CEILING, not a guarantee: ScreenCaptureKit delivers a
        // frame when the window changes. A still window yields fewer buffers, which is
        // why the recorded frame count must never be read as a frame rate.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: fps)
        configuration.queueDepth = 8

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    /// Stops the stream and finalises the file. Returns what was actually written.
    @discardableResult
    func stop() async throws -> (appended: Int, dropped: Int) {
        guard let stream else { throw RecorderError.notRecording }
        try await stream.stopCapture()
        self.stream = nil
        return await box.finish()
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        // A complete frame carries an attachment saying so; ScreenCaptureKit also emits
        // idle and blank status buffers, and appending those would pad the recording
        // with frames that never appeared on screen.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                       createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw),
              status == .complete else { return }
        let box = self.box
        Task { await box.append(sampleBuffer) }
    }

    // MARK: - SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Surfaced rather than swallowed: a stream that dies mid-run otherwise produces
        // a short file that looks like a completed recording.
        FileHandle.standardError.write(
            Data("CarouselFrameRecorder: stream stopped with error: \(error)\n".utf8))
    }
}
