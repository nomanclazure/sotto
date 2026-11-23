import Foundation

/// Command-line test modes (no GUI, no permissions needed):
///   Sotto --transcribe <audio-file> [model-path]   transcribe a file and print it
///   Sotto --selftest [model-path]                  synthesize speech, transcribe, verify
func runHeadless(args: [String]) -> Never {
    let mode = args[1]

    func defaultModelPath() -> String {
        ModelManager.shared.path(for: Settings.shared.model).path
    }

    switch mode {
    case "--transcribe":
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: Sotto --transcribe <audio-file> [model-path]\n".utf8))
            exit(2)
        }
        let audioPath = args[2]
        let modelPath = args.count >= 4 ? args[3] : defaultModelPath()
        exit(transcribeFile(audioPath: audioPath, modelPath: modelPath, expectKeywords: nil) ? 0 : 1)

    case "--selftest":
        let modelPath = args.count >= 3 ? args[2] : defaultModelPath()
        let phrase = "The quick brown fox jumps over the lazy dog near the riverbank in the early morning light."
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sotto-selftest-\(ProcessInfo.processInfo.processIdentifier).wav")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", tmp.path, "--data-format=LEI16@16000", phrase]
        do {
            try say.run()
            say.waitUntilExit()
        } catch {
            print("SELFTEST FAIL: could not run /usr/bin/say: \(error)")
            exit(1)
        }
        guard say.terminationStatus == 0 else {
            print("SELFTEST FAIL: say exited with \(say.terminationStatus)")
            exit(1)
        }
        let ok = transcribeFile(audioPath: tmp.path, modelPath: modelPath,
                                expectKeywords: ["quick", "brown", "fox", "lazy", "dog", "riverbank", "morning"])
        print(ok ? "SELFTEST PASS" : "SELFTEST FAIL")
        exit(ok ? 0 : 1)

    default:
        FileHandle.standardError.write(Data("unknown flag: \(mode)\n".utf8))
        exit(2)
    }
}

private func transcribeFile(audioPath: String, modelPath: String, expectKeywords: [String]?) -> Bool {
    guard FileManager.default.fileExists(atPath: modelPath) else {
        print("ERROR: model not found at \(modelPath)")
        return false
    }
    let samples: [Float]
    do {
        samples = try AudioFileLoader.load(URL(fileURLWithPath: audioPath))
    } catch {
        print("ERROR: could not read audio file \(audioPath): \(error)")
        return false
    }
    print("AUDIO: \(String(format: "%.1f", Double(samples.count) / Recorder.targetSampleRate))s at 16kHz")

    let transcriber = Transcriber()
    defer { transcriber.unloadSync() }

    // Time the model load separately from inference — during normal use the
    // model is already resident, so inference time is the real-world latency.
    let loadStart = Date()
    var loadOK = false
    let loadSem = DispatchSemaphore(value: 0)
    transcriber.preload(modelPath: modelPath) { ok in
        loadOK = ok
        loadSem.signal()
    }
    // preload completion is delivered via the main queue; pump it manually
    while loadSem.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    guard loadOK else {
        print("ERROR: failed to load model")
        return false
    }
    print("MODEL LOAD: \(String(format: "%.2f", -loadStart.timeIntervalSinceNow))s")

    let inferStart = Date()
    var result: String?
    let sem = DispatchSemaphore(value: 0)
    transcriber.transcribe(samples: samples, modelPath: modelPath) { text in
        result = text
        sem.signal()
    }
    sem.wait()
    let inferTime = -inferStart.timeIntervalSinceNow

    guard let text = result else {
        print("ERROR: transcription failed")
        return false
    }
    print("TIME: \(String(format: "%.2f", inferTime))s")
    print("TEXT: \(text)")

    if let keywords = expectKeywords {
        let lower = text.lowercased()
        let missing = keywords.filter { !lower.contains($0) }
        if !missing.isEmpty {
            print("MISSING KEYWORDS: \(missing.joined(separator: ", "))")
            return false
        }
    }
    return true
}
