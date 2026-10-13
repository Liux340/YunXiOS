/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：单任务下载执行器（对应 DownloadManager 的分片规划 / 并发 / 续传 / 回退链路）。
 *
 * 设计：
 * - 分片写入「按偏移覆盖」到目标文件（预分配 total 大小），因此任意时刻中断后，
 *   只需知道哪些分片已完成即可续传，无需合并、无空洞；
 * - 服务器忽略 Range（返回 200）时抛出 rangeIgnored 信号，上层回退单流整文件；
 * - 每个分片失败重试 MAX_ATTEMPTS 次，指数退避；
 * - 限速在「分片开始前」按分片字节数消费令牌（不阻塞 URLSession 回调队列）。
 */

import Foundation

/// 内部信号
enum DownloadSignal: Error {
    case rangeIgnored
}

/// 线程安全的计数器
private final class Counter {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }
}

final class DownloadRunner {

    struct Input {
        let url: String
        let headers: [String: String]
        let fileURL: URL
        let platform: String
        let threadCount: Int
        let totalSize: Int64
        let supportsRange: Bool
        let blockSize: Int64
        let completedChunks: [ChunkRange]
        let isHls: Bool
    }

    struct Output {
        let downloaded: Int64
        let totalSize: Int64
        let completedChunks: [ChunkRange]
        let supportsRange: Bool
        let blockSize: Int64
    }

    /// 分片失败重试上限
    static let maxAttempts = 3
    /// 分片大小范围
    static let minBlockSize: Int64 = 256 * 1024
    static let maxBlockSize: Int64 = 4 * 1024 * 1024

    private let input: Input
    private let limiter: SpeedLimiter
    private let onProgress: (Int64, Int64) -> Void
    private let onMerging: () -> Void

    private let lock = NSLock()
    private var downloaded: Int64 = 0
    private var totalSize: Int64 = 0
    private var completed: [ChunkRange] = []
    private var rangeIgnored = false
    private var lastReport: Double = 0

    init(
        input: Input,
        limiter: SpeedLimiter,
        onProgress: @escaping (Int64, Int64) -> Void,
        onMerging: @escaping () -> Void
    ) {
        self.input = input
        self.limiter = limiter
        self.onProgress = onProgress
        self.onMerging = onMerging
        self.completed = input.completedChunks
        self.downloaded = input.completedChunks.reduce(0) { $0 + $1.length }
        self.totalSize = input.totalSize
    }

    // MARK: - 入口

    func run() async throws -> Output {
        if input.isHls {
            return try await runHls()
        }

        var total = input.totalSize
        var supportsRange = input.supportsRange && total > 0

        // 总大小未知 / 未探测过 Range：先探测
        if total <= 0 || input.blockSize == 0 {
            if let probed = await ChunkDownloader.shared.probe(url: input.url, headers: input.headers) {
                total = probed.size
                supportsRange = probed.supportsRange
            }
        }
        setTotalSize(total)

        reportProgress(force: true)

        if supportsRange && total > 0 {
            do {
                return try await runChunked(total: total)
            } catch DownloadSignal.rangeIgnored {
                // 服务器忽略 Range：回退单流整文件（不按分片写）
                completed = []
                downloaded = 0
                supportsRange = false
            }
        }

        return try await runSingleStream(total: total, supportsRange: false)
    }

    // MARK: - 分片下载

    private func runChunked(total: Int64) async throws -> Output {
        let threads = max(1, min(input.threadCount, 32))
        let blockSize = input.blockSize > 0 ? input.blockSize : Self.computeBlockSize(total: total, threads: threads)
        let blocks = Self.planBlocks(total: total, blockSize: blockSize)
        let doneStarts = Set(completed.map { $0.start })
        let pending = blocks.filter { !doneStarts.contains($0.start) }

        // 预分配目标文件大小（稀疏写，不实际占盘）
        try Self.preallocate(input.fileURL, size: total)

        if pending.isEmpty {
            return Output(downloaded: total, totalSize: total, completedChunks: blocks, supportsRange: true, blockSize: blockSize)
        }

        let counter = Counter()
        let workerCount = min(threads, pending.count)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask { [self] in
                    while true {
                        if Task.isCancelled { throw CancellationError() }
                        if isRangeIgnored() { throw DownloadSignal.rangeIgnored }
                        let index = counter.next()
                        if index >= pending.count { return }
                        try await downloadBlock(pending[index])
                    }
                }
            }
            try await group.waitForAll()
        }

        // 校验：所有分片都已完成
        let finished = Set(completed.map { $0.start })
        let missing = blocks.contains { !finished.contains($0.start) }
        if missing {
            throw ApiError("下载未完成：存在缺失分片")
        }

        onMerging()
        return Output(
            downloaded: total,
            totalSize: total,
            completedChunks: completed.sorted { $0.start < $1.start },
            supportsRange: true,
            blockSize: blockSize
        )
    }

    private func downloadBlock(_ block: ChunkRange) async throws {
        var attempt = 0
        while true {
            if Task.isCancelled { throw CancellationError() }
            if isRangeIgnored() { throw DownloadSignal.rangeIgnored }

            // 限速：按分片字节数消费令牌（桶容量 1 秒额度）
            await limiter.consume(Int(min(block.length, Int64(Int.max))))

            do {
                let result = try await ChunkDownloader.shared.downloadChunk(
                    url: input.url,
                    headers: input.headers,
                    fileURL: input.fileURL,
                    offset: block.start,
                    expected: block.length
                ) { [weak self] delta in
                    self?.addBytes(delta)
                }
                switch result {
                case .ok:
                    markCompleted(block)
                    return
                case .rangeIgnored:
                    setRangeIgnored()
                    throw DownloadSignal.rangeIgnored
                case .failed:
                    attempt += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let signal as DownloadSignal {
                throw signal
            } catch {
                attempt += 1
                if attempt >= Self.maxAttempts { throw error }
            }

            if attempt >= Self.maxAttempts {
                throw ApiError("分片下载失败（offset=\(block.start)）")
            }
            try await Task.sleep(nanoseconds: UInt64(500_000_000) * UInt64(attempt))
        }
    }

    // MARK: - 单流整文件（回退）

    private func runSingleStream(total: Int64, supportsRange: Bool) async throws -> Output {
        let ok = try await ChunkDownloader.shared.downloadFull(
            url: input.url,
            headers: input.headers,
            fileURL: input.fileURL,
            total: total
        ) { [weak self] delta in
            self?.addBytes(delta)
        }
        if !ok {
            throw ApiError("下载失败：无法获取完整内容")
        }
        let size = Self.fileSize(input.fileURL)
        reportProgress(force: true)
        return Output(
            downloaded: size > 0 ? size : total,
            totalSize: size > 0 ? size : total,
            completedChunks: [],
            supportsRange: supportsRange,
            blockSize: 0
        )
    }

    // MARK: - HLS

    private func runHls() async throws -> Output {
        let downloader = HlsDownloader()
        try await downloader.download(
            url: input.url,
            headers: input.headers,
            outputURL: input.fileURL
        ) { [weak self] done, _ in
            guard let self = self else { return }
            self.setDownloaded(done)
            self.reportProgress()
        }
        let size = Self.fileSize(input.fileURL)
        reportProgress(force: true)
        return Output(
            downloaded: size,
            totalSize: size,
            completedChunks: [],
            supportsRange: false,
            blockSize: 0
        )
    }

    // MARK: - 状态

    private func addBytes(_ delta: Int64) {
        lock.lock()
        downloaded += delta
        let current = downloaded
        lock.unlock()
        reportProgress(value: current)
    }

    private func setDownloaded(_ value: Int64) {
        lock.lock()
        downloaded = value
        lock.unlock()
    }

    private func markCompleted(_ block: ChunkRange) {
        lock.lock()
        if !completed.contains(where: { $0.start == block.start }) {
            completed.append(block)
            // 注意：字节增量已由 onBytes 累加，这里不再重复计入 downloaded，
            // 仅把 downloaded 拉到「已完成前缀 + 本片」的保证值，避免异常情况下少算。
            let done = completed.reduce(Int64(0)) { $0 + $1.length }
            if done > downloaded { downloaded = done }
        }
        let current = downloaded
        lock.unlock()
        reportProgress(value: current)
    }

    private func setTotalSize(_ value: Int64) {
        lock.lock()
        if value > 0 { totalSize = value }
        lock.unlock()
    }

    private func currentTotalSize() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return totalSize
    }

    private func setRangeIgnored() {
        lock.lock()
        rangeIgnored = true
        lock.unlock()
    }

    private func isRangeIgnored() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return rangeIgnored
    }

    private func currentDownloaded() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return downloaded
    }

    /// 进度回调（节流至 10 次/秒）
    private func reportProgress(value: Int64? = nil, force: Bool = false) {
        let now = Date().timeIntervalSince1970
        if !force && now - lastReport < 0.1 { return }
        lastReport = now
        let current = value ?? currentDownloaded()
        onProgress(current, currentTotalSize())
    }

    // MARK: - 分片规划

    /// 弹性分片大小：按「每个 worker 若干块」估算，夹在 [256KB, 4MB]
    static func computeBlockSize(total: Int64, threads: Int) -> Int64 {
        let target = total / Int64(max(1, threads * 8))
        return min(max(target, minBlockSize), maxBlockSize)
    }

    /// 按固定块大小切分 [0, total)
    static func planBlocks(total: Int64, blockSize: Int64) -> [ChunkRange] {
        guard total > 0, blockSize > 0 else { return [] }
        var blocks: [ChunkRange] = []
        var start: Int64 = 0
        while start < total {
            let end = min(start + blockSize, total)
            blocks.append(ChunkRange(start: start, end: end))
            start = end
        }
        return blocks
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    /// 预分配文件到指定大小（稀疏文件，实际磁盘按写入增长）
    static func preallocate(_ url: URL, size: Int64) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let current = (try? handle.seekToEnd()) ?? 0
        if current < UInt64(size) {
            try handle.truncate(atOffset: UInt64(size))
        }
    }
}
