import Foundation
import CWhisper

/// Wraps the whisper.cpp C API. The model stays loaded in memory between
/// dictations so transcription starts instantly on key release.
final class Transcriber {
    private var ctx: OpaquePointer?
    private var loadedModelPath: String?
    private let queue = DispatchQueue(label: "sotto.whisper", qos: .userInitiated)

    private static let languageEn: UnsafePointer<CChar> = UnsafePointer(strdup("en")!)

    init() {
        // Silence whisper.cpp's stderr logging
        whisper_log_set({ _, _, _ in }, nil)
    }

    /// Load the model in the background so the first dictation is fast.
    func preload(modelPath: String, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            let ok = self.ensureLoaded(modelPath)
            if let completion {
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    /// Must be called before the process exits — the Metal backend asserts
    /// if a context is still alive during atexit teardown.
    func unloadSync() {
        queue.sync {
            if let c = self.ctx { whisper_free(c) }
            self.ctx = nil
            self.loadedModelPath = nil
        }
    }

    /// Transcribes 16 kHz mono samples. Completion is called on the whisper
    /// queue with nil on failure, or the trimmed transcript ("" if silence).
    func transcribe(samples: [Float], modelPath: String, completion: @escaping (String?) -> Void) {
        queue.async {
            guard self.ensureLoaded(modelPath), let ctx = self.ctx else {
                completion(nil)
                return
            }

            var pcm = samples

            // Skip obviously silent recordings (avoids Whisper hallucinating
            // words like "Thank you." from background hiss).
            let rms = sqrt(pcm.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(pcm.count, 1)))
            if rms < 0.0008 {
                completion("")
                return
            }

            // whisper.cpp requires at least ~1s of audio
            let minSamples = Int(1.2 * Recorder.targetSampleRate)
            if pcm.count < minSamples {
                pcm.append(contentsOf: [Float](repeating: 0, count: minSamples - pcm.count))
            }

            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_progress = false
            params.print_realtime = false
            params.print_special = false
            params.print_timestamps = false
            params.no_timestamps = true
            params.translate = false
            params.suppress_blank = true
            params.language = Transcriber.languageEn
            params.n_threads = Int32(min(8, max(4, ProcessInfo.processInfo.activeProcessorCount)))

            let status = pcm.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
            guard status == 0 else {
                completion(nil)
                return
            }

            var text = ""
            for i in 0..<whisper_full_n_segments(ctx) {
                if let seg = whisper_full_get_segment_text(ctx, i) {
                    text += String(cString: seg)
                }
            }
            completion(Transcriber.cleaned(text))
        }
    }

    private func ensureLoaded(_ path: String) -> Bool {
        if loadedModelPath == path, ctx != nil { return true }
        if let c = ctx { whisper_free(c); ctx = nil; loadedModelPath = nil }
        guard FileManager.default.fileExists(atPath: path) else { return false }

        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true
        ctx = whisper_init_from_file_with_params(path, cparams)
        if ctx != nil { loadedModelPath = path }
        return ctx != nil
    }

    /// Trims whitespace and drops non-speech annotations like
    /// "[BLANK_AUDIO]" or "(wind blowing)".
    private static func cleaned(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAnnotation = (text.hasPrefix("[") && text.hasSuffix("]"))
            || (text.hasPrefix("(") && text.hasSuffix(")"))
            || (text.hasPrefix("*") && text.hasSuffix("*"))
        return isAnnotation ? "" : text
    }
}
