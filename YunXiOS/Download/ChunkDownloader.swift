/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：分片流式下载器（对应 data/download/ChunkDownloader.kt）。
 * 基于 URLSessionDataDelegate 边收边写盘，避免整段响应驻留内存；
 * 支持 206 分片校验、200（Range 被忽略）识别、写入字节数严格校验、任务级取消。
 */

import Foundation

/// 分片下载结果
enum ChunkResult {
    /// 该分片已正确写入预期字节数
    case ok
    /// 服务器忽略 Range（返回 200 整文件）——上层应回退单流，绝不为单分片下载整文件
    case rangeIgnored
    /// 结构性失败（非 206/200、HTML 广告页、写入字节不足）
    case failed
}

/// 单次分片请求的上下文
private final class ChunkContext {
    let fileHandle: FileHandle
    let offset: Int64
    /// 预期写入字节数；-1 表示未知（流式）
    let expected: Int64
    /// 是否使用 Range（否则为完整 GET）
    let expectRange: Bool
    let onBytes: (Int64) -> Void

    var written: Int64 = 0
    var result: ChunkResult = .failed
    var failure: Error?
    var finished = false
    var continuation: CheckedContinuation<ChunkResult, Error>?

    init(fileHandle: FileHandle, offset: Int64, expected: Int64, expectRange: Bool, onBytes: @escaping (Int64) -> Void) {
        self.fileHandle = fileHandle
        self.offset = offset
        self.expected = expected
        self.expectRange = expectRange
        self.onBytes = onBytes
    }
}

/// 分片下载器（单例，共享一条 URLSession，按 taskIdentifier 分流）
final class ChunkDownloader: NSObject {

    static let shared = ChunkDownloader()

    private static let bufferHint = 64 * 1024

    private let lock = NSLock()
    private var contexts: [Int: ChunkContext] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 3600
        config.httpMaximumConnectionsPerHost = 64
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    private override init() { super.init() }

    // MARK: - 对外接口

    /// 探测总大小与是否支持 Range
    /// - 先试 `Range: bytes=0-0`：返回 206 且 Content-Range 合法 ⇒ 支持 Range 且已知总大小；
    /// - 再退到完整 GET 的 Content-Length（支持大小但不保证可分段）。
    func probe(url: String, headers: [String: String]) async -> (size: Int64, supportsRange: Bool)? {
        if let size = await probeSize(url: url, headers: headers, withRange: true) {
            return (size, true)
        }
        if let size = await probeSize(url: url, headers: headers, withRange: false) {
            return (size, false)
        }
        return nil
    }

    /// 探测总大小：先试 Range: bytes=0-0，失败再试完整 GET 的 Content-Length
    func probeTotalSize(url: String, headers: [String: String]) async -> Int64? {
        if let size = await probeSize(url: url, headers: headers, withRange: true) { return size }
        return await probeSize(url: url, headers: headers, withRange: false)
    }

    private func probeSize(url: String, headers: [String: String], withRange: Bool) async -> Int64? {
        var allHeaders = headers
        if withRange { allHeaders["Range"] = "bytes=0-0" }
        do {
            var request = try HTTPClient.download.makeRequest(url, headers: allHeaders)
            request.timeoutInterval = 20
            let (_, response) = try await HTTPClient.download.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            if contentType.lowercased().contains("text/html") { return nil }
            guard (200...299).contains(http.statusCode) else { return nil }
            if withRange {
                guard http.statusCode == 206 else { return nil }
                guard let range = HttpRangePolicy.parse(http.value(forHTTPHeaderField: "Content-Range")) else { return nil }
                guard range.start == 0, range.end == 0 else { return nil }
                return range.total
            } else {
                guard let length = http.value(forHTTPHeaderField: "Content-Length"), let value = Int64(length), value > 0 else {
                    return nil
                }
                return value
            }
        } catch {
            return nil
        }
    }

    /// 下载一个分片到文件指定偏移（断点续传：以文件当前内容为准，本方法从 offset 起覆盖写入）
    func downloadChunk(
        url: String,
        headers: [String: String],
        fileURL: URL,
        offset: Int64,
        expected: Int64,
        onBytes: @escaping (Int64) -> Void
    ) async throws -> ChunkResult {
        let handle = try openHandle(fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try await stream(url: url, headers: headers, handle: handle, offset: offset, expected: expected, expectRange: true, onBytes: onBytes)
    }

    /// 单流整文件下载（Range 被忽略时的回退）。会先清空文件，保证不出现「旧前缀 + 完整响应」的拼接损坏。
    func downloadFull(
        url: String,
        headers: [String: String],
        fileURL: URL,
        total: Int64,
        onBytes: @escaping (Int64) -> Void
    ) async throws -> Bool {
        let handle = try openHandle(fileURL)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.seek(toOffset: 0)
        let expected: Int64 = total > 0 ? total : -1
        let result = try await stream(url: url, headers: headers, handle: handle, offset: 0, expected: expected, expectRange: false, onBytes: onBytes)
        if result == .ok {
            if total > 0 {
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                if size < total {
                    throw ApiError("下载失败：写入不足（\(size)/\(total)）")
                }
            }
            return true
        }
        return false
    }

    // MARK: - 内部

    private func openHandle(_ fileURL: URL) throws -> FileHandle {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        return try FileHandle(forWritingTo: fileURL)
    }

    private func stream(
        url: String,
        headers: [String: String],
        handle: FileHandle,
        offset: Int64,
        expected: Int64,
        expectRange: Bool,
        onBytes: @escaping (Int64) -> Void
    ) async throws -> ChunkResult {
        var allHeaders = headers
        if expectRange {
            if expected >= 0 {
                allHeaders["Range"] = "bytes=\(offset)-\(offset + expected - 1)"
            } else {
                allHeaders["Range"] = "bytes=\(offset)-"
            }
        }
        var request = try HTTPClient.download.makeRequest(url, headers: allHeaders)
        request.timeoutInterval = 60

        let context = ChunkContext(fileHandle: handle, offset: offset, expected: expected, expectRange: expectRange, onBytes: onBytes)
        let task = session.dataTask(with: request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ChunkResult, Error>) in
                lock.lock()
                contexts[task.taskIdentifier] = context
                context.continuation = continuation
                lock.unlock()
                if Task.isCancelled {
                    task.cancel()
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// 立即中断某任务（当前实现按会话整体取消，粒度到任务级由上层保证同时只有一个在飞）
    func cancelAll() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }

    private func finish(_ context: ChunkContext, taskIdentifier: Int, result: ChunkResult, error: Error? = nil) {
        lock.lock()
        guard !context.finished else { lock.unlock(); return }
        context.finished = true
        context.result = result
        context.failure = error
        contexts.removeValue(forKey: taskIdentifier)
        let continuation = context.continuation
        lock.unlock()

        guard let continuation = continuation else { return }
        if let error = error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: result)
        }
    }
}

extension ChunkDownloader: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        let context = contexts[dataTask.taskIdentifier]
        lock.unlock()
        guard let context = context else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            finish(context, taskIdentifier: dataTask.taskIdentifier, result: .failed, error: ApiError("响应异常"))
            completionHandler(.cancel)
            return
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.lowercased().contains("text/html") {
            finish(context, taskIdentifier: dataTask.taskIdentifier, result: .failed,
                   error: ApiError("下载失败：链接已失效或需要 Referer（返回 HTML 页）"))
            completionHandler(.cancel)
            return
        }
        if context.expectRange {
            switch http.statusCode {
            case 206:
                let requestedEnd = context.expected >= 0 ? context.offset + context.expected - 1 : nil
                if !HttpRangePolicy.matches(http.value(forHTTPHeaderField: "Content-Range"),
                                            requestedStart: context.offset,
                                            requestedEnd: requestedEnd) {
                    finish(context, taskIdentifier: dataTask.taskIdentifier, result: .failed,
                           error: ApiError("Content-Range 与请求不一致"))
                    completionHandler(.cancel)
                    return
                }
                completionHandler(.allow)
            case 200:
                // 服务器忽略 Range：交由上层回退单流，绝不按分片写入
                finish(context, taskIdentifier: dataTask.taskIdentifier, result: .rangeIgnored)
                completionHandler(.cancel)
            default:
                finish(context, taskIdentifier: dataTask.taskIdentifier, result: .failed,
                       error: ApiError("下载失败 HTTP \(http.statusCode)"))
                completionHandler(.cancel)
            }
        } else {
            guard (200...299).contains(http.statusCode) else {
                finish(context, taskIdentifier: dataTask.taskIdentifier, result: .failed,
                       error: ApiError("下载失败 HTTP \(http.statusCode)"))
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let context = contexts[dataTask.taskIdentifier]
        lock.unlock()
        guard let context = context, !context.finished else { return }

        // 服务器可能忽略 end 返回超量 body：严格截断，避免文件膨胀
        var allow: Int64 = Int64(data.count)
        if context.expected >= 0 {
            let remain = context.expected - context.written
            if remain <= 0 { return }
            allow = min(Int64(data.count), remain)
        }
        guard allow > 0 else { return }

        do {
            if allow == Int64(data.count) {
                try context.fileHandle.write(contentsOf: data)
            } else {
                try context.fileHandle.write(contentsOf: data.prefix(Int(allow)))
            }
        } catch {
            finish(context, taskIdentifier: dataTask.taskIdentifier, result: .failed, error: error)
            dataTask.cancel()
            return
        }
        context.written += allow
        context.onBytes(allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let context = contexts[task.taskIdentifier]
        lock.unlock()
        guard let context = context else { return }

        if let error = error {
            let nsError = error as NSError
            // 由 finish(didReceive:) 主动取消导致的中断不算失败
            if context.finished { return }
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                finish(context, taskIdentifier: task.taskIdentifier, result: .failed,
                       error: ApiError("下载被取消"))
            } else {
                finish(context, taskIdentifier: task.taskIdentifier, result: .failed, error: error)
            }
            return
        }

        // 写入字节数校验：已知预期时必须写满，否则视为失败（防空洞/损坏）
        if context.expected >= 0 && context.written < context.expected {
            finish(context, taskIdentifier: task.taskIdentifier, result: .failed,
                   error: ApiError("分片写入不足（\(context.written)/\(context.expected)）"))
            return
        }
        finish(context, taskIdentifier: task.taskIdentifier, result: .ok)
    }
}
