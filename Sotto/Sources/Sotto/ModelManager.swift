import Foundation

/// Downloads and stores Whisper models under
/// ~/Library/Application Support/Sotto/models/
/// All state is main-thread confined (URLSession delegate queue is .main).
final class ModelManager: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelManager()

    let modelsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sotto/models", isDirectory: true)
    }()

    /// Called on the main queue as a download progresses (fraction 0...1)
    var onProgress: ((ModelOption, Double) -> Void)?
    /// Called on the main queue when a download finishes (success flag)
    var onFinished: ((ModelOption, Bool) -> Void)?

    private(set) var downloading: [ModelOption: Double] = [:]
    private var tasks: [URLSessionDownloadTask: ModelOption] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    func path(for model: ModelOption) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName)
    }

    func isDownloaded(_ model: ModelOption) -> Bool {
        let p = path(for: model)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: p.path),
              let size = attrs[.size] as? Int64 else { return false }
        return size >= model.minValidSize
    }

    func isDownloading(_ model: ModelOption) -> Bool {
        downloading[model] != nil
    }

    func download(_ model: ModelOption) {
        guard !isDownloaded(model), !isDownloading(model) else { return }
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        downloading[model] = 0
        let task = session.downloadTask(with: model.downloadURL)
        tasks[task] = model
        task.resume()
    }

    // MARK: URLSessionDownloadDelegate (delivered on main queue)

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let model = tasks[downloadTask], totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        downloading[model] = fraction
        onProgress?(model, fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let model = tasks[downloadTask] else { return }
        var ok = false
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200,
           let size = (try? FileManager.default.attributesOfItem(atPath: location.path))?[.size] as? Int64,
           size >= model.minValidSize {
            let dest = path(for: model)
            try? FileManager.default.removeItem(at: dest)
            ok = (try? FileManager.default.moveItem(at: location, to: dest)) != nil
        }
        finish(task: downloadTask, model: model, ok: ok)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let downloadTask = task as? URLSessionDownloadTask,
              let model = tasks[downloadTask] else { return }
        NSLog("Sotto: model download failed: \(error.localizedDescription)")
        finish(task: downloadTask, model: model, ok: false)
    }

    private func finish(task: URLSessionDownloadTask, model: ModelOption, ok: Bool) {
        tasks[task] = nil
        downloading[model] = nil
        onFinished?(model, ok)
    }
}
