import Foundation
import AVFoundation

/// Loads an audio file and converts it to 16 kHz mono Float32.
/// Used by the self-test/headless mode, not the live dictation path.
enum AudioFileLoader {

    enum LoadError: Error { case unreadable, conversionFailed }

    static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frameCount) else {
            throw LoadError.unreadable
        }
        try file.read(into: inBuffer)

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: Recorder.targetSampleRate,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw LoadError.conversionFailed
        }

        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 128
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            throw LoadError.conversionFailed
        }

        var fed = false
        var convError: NSError?
        converter.convert(to: outBuffer, error: &convError) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return inBuffer
        }
        if convError != nil { throw LoadError.conversionFailed }

        guard outBuffer.frameLength > 0, let channel = outBuffer.floatChannelData else {
            throw LoadError.conversionFailed
        }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(outBuffer.frameLength)))
    }
}
