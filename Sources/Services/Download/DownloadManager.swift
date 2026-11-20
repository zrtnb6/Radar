import Foundation
import AppKit

struct DownloadItem: Identifiable, Equatable {
    enum State: String, Equatable {
        case downloading
        case completed
        case failed
        case cancelled
    }

    let id: Int64
    let assetName: String
    let startedAt: Date
    var receivedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var state: State = .downloading
    var localURL: URL?
    var errorMessage: String?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }

    var progressSummary: String {
        let received = ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
        guard totalBytes > 0 else { return received }
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(received) / \(total)"
    }
}

/// App 内下载器：用户主动点击附件后由 URLSessionDownloadTask 下载到「下载」文件夹。
/// 不会自动开始、不会自动打开、不会自动安装，也不执行下载内容。
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [Int64: DownloadItem] = [:]

    private let session: URLSession
    private let delegate: DownloadSessionDelegate
    private let downloadsDirectory: URL
    private var tasks: [Int64: URLSessionDownloadTask] = [:]

    var orderedItems: [DownloadItem] {
        items.values.sorted { $0.startedAt > $1.startedAt }
    }

    var activeCount: Int {
        items.values.filter { $0.state == .downloading }.count
    }

    var downloadsDirectoryURL: URL { downloadsDirectory }

    init(
        configuration: URLSessionConfiguration = .default,
        downloadsDirectory: URL? = nil
    ) {
        let directory = downloadsDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.downloadsDirectory = directory

        let downloadDelegate = DownloadSessionDelegate()
        self.delegate = downloadDelegate
        self.session = URLSession(configuration: configuration, delegate: downloadDelegate, delegateQueue: nil)

        downloadDelegate.onProgress = { [weak self] id, written, expected in
            Task { @MainActor in self?.recordProgress(id: id, received: written, expected: expected) }
        }
        downloadDelegate.onFinish = { [weak self] id, url in
            Task { @MainActor in self?.finish(id: id, localURL: url) }
        }
        downloadDelegate.onFailure = { [weak self] id, message in
            Task { @MainActor in self?.fail(id: id, message: message) }
        }
        downloadDelegate.onCancelled = { [weak self] id in
            Task { @MainActor in self?.markCancelled(id: id) }
        }
    }

    func start(asset: Asset) {
        let id = asset.id
        guard tasks[id] == nil else { return }

        let url: URL
        let fileName: String
        let destination: URL
        do {
            url = try DownloadPolicy.validatedURL(asset.downloadURL)
            fileName = DownloadPolicy.sanitizedFileName(asset.name)
            do {
                try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            } catch {
                throw DownloadError.fileSystem(error.localizedDescription)
            }
            destination = DownloadPolicy.destinationURL(for: fileName, in: downloadsDirectory)
        } catch {
            var item = DownloadItem(id: id, assetName: asset.name, startedAt: Date())
            item.state = .failed
            item.errorMessage = (error as? DownloadError)?.errorDescription ?? error.localizedDescription
            items[id] = item
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        // 不注入 Token：GitHub 附件直链会重定向到签名 CDN，避免认证头被带到第三方主机。
        request.setValue("Radar/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let task = session.downloadTask(with: request)
        task.taskDescription = String(id)
        delegate.setDestination(destination, for: id)
        tasks[id] = task

        var item = DownloadItem(id: id, assetName: fileName, startedAt: Date())
        if asset.size > 0 { item.totalBytes = asset.size }
        items[id] = item
        task.resume()
    }

    func retry(asset: Asset) {
        remove(id: asset.id)
        start(asset: asset)
    }

    func cancel(id: Int64) {
        tasks[id]?.cancel()
    }

    func remove(id: Int64) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
        items.removeValue(forKey: id)
    }

    func clearFinished() {
        for (id, item) in items where item.state != .downloading {
            items.removeValue(forKey: id)
            tasks.removeValue(forKey: id)
        }
    }

    func reveal(id: Int64) {
        guard let url = items[id]?.localURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func recordProgress(id: Int64, received: Int64, expected: Int64) {
        guard var item = items[id], item.state == .downloading else { return }
        item.receivedBytes = received
        if expected > 0 { item.totalBytes = expected }
        items[id] = item
    }

    private func finish(id: Int64, localURL: URL) {
        guard var item = items[id] else { return }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path),
           let size = attributes[.size] as? NSNumber {
            item.totalBytes = size.int64Value
            item.receivedBytes = size.int64Value
        }
        item.state = .completed
        item.localURL = localURL
        item.errorMessage = nil
        items[id] = item
        tasks.removeValue(forKey: id)
    }

    private func fail(id: Int64, message: String) {
        guard var item = items[id], item.state == .downloading else { return }
        item.state = .failed
        item.errorMessage = message
        items[id] = item
        tasks.removeValue(forKey: id)
    }

    private func markCancelled(id: Int64) {
        guard var item = items[id], item.state == .downloading else { return }
        item.state = .cancelled
        items[id] = item
        tasks.removeValue(forKey: id)
    }
}

private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    private let lock = NSLock()
    private var destinations: [Int64: URL] = [:]

    var onProgress: ((Int64, Int64, Int64) -> Void)?
    var onFinish: ((Int64, URL) -> Void)?
    var onFailure: ((Int64, String) -> Void)?
    var onCancelled: ((Int64) -> Void)?

    private func assetID(for task: URLSessionTask) -> Int64? {
        guard let raw = task.taskDescription else { return nil }
        return Int64(raw)
    }

    func setDestination(_ url: URL, for id: Int64) {
        lock.lock()
        destinations[id] = url
        lock.unlock()
    }

    private func destination(for id: Int64) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return destinations[id]
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = assetID(for: downloadTask) else { return }
        onProgress?(id, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = assetID(for: downloadTask) else { return }
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            onFailure?(id, "服务器返回 \(http.statusCode)")
            return
        }
        guard let destination = destination(for: id) else {
            onFailure?(id, "无法确定保存位置")
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            onFinish?(id, destination)
        } catch {
            onFailure?(id, "保存文件失败：\(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = assetID(for: task) else { return }
        if let http = task.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            onFailure?(id, "服务器返回 \(http.statusCode)")
            return
        }
        guard let error else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            onCancelled?(id)
        } else {
            onFailure?(id, error.localizedDescription)
        }
    }
}
