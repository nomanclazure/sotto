import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

enum RecorderError: LocalizedError {
    case noInputDevice
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone was found. Connect a microphone or choose a different one in the Sotto menu."
        case .engineStartFailed(let why):
            return "Could not start recording: \(why)"
        }
    }
}

/// Captures the microphone while the hotkey is held, resampling live to
/// 16 kHz mono Float32 (what Whisper expects). A fresh AVAudioEngine is
/// created per recording so microphone changes always take effect.
final class Recorder {
    static let targetSampleRate = 16000.0

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    func start(deviceUID: String?) throws {
        stopEngineIfNeeded()
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode

        if let uid = deviceUID, let devID = AudioDevices.deviceID(forUID: uid), let au = input.audioUnit {
            var id = devID
            AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &id,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: Recorder.targetSampleRate,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw RecorderError.engineStartFailed("unsupported audio format")
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.append(buffer, outFormat: outFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.engine = nil
            throw RecorderError.engineStartFailed(error.localizedDescription)
        }
        isRecording = true
    }

    /// Stops capture and returns everything recorded, as 16 kHz mono Float32.
    func stop() -> [Float] {
        stopEngineIfNeeded()
        isRecording = false
        lock.lock(); let result = samples; samples = []; lock.unlock()
        return result
    }

    private func stopEngineIfNeeded() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.converter = nil
    }

    private func append(_ buffer: AVAudioPCMBuffer, outFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }

        guard out.frameLength > 0, let channel = out.floatChannelData else { return }
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
        lock.unlock()
    }
}
