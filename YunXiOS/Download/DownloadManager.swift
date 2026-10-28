/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：下载引擎编排（对应 data/download/DownloadManager.kt）。
 * 采用「任务级并发 + 分片级并发」双层调度：
 * - 任务级：同时运行的任务数受「最大并发下载数」约束；
 * - 分片级：单个任务按 Range 分片、多 worker 并发拉取，写盘按偏移覆盖，天然支持断点续传；
 * - 服务器忽略 Range（200）时自动回退单流整文件；
 * - HLS（m3u8）走独立链路；
 * - 全局限速由 SpeedLimiter 令牌桶统一约束。
 */

import Foundation
import SwiftUI

/// 非隔离的设置读取（UserDefaults 线程安全），保证运行中修改限速即时生效
enum DownloadSettings {

    private static var defaults: UserDefaults { UserDefaults.standard }

    static var maxConcurrentDownloads: Int {
        min(max(defaults.object(forKey: "max_concurrent_downloads") as? Int ?? 3, 1), 10)
    }

    static var speedLimitBytesPerSecond: Int64 {
        let kbps = max(0, defaults.object(forKey: "speed_limit_kbps") as? Int ?? 0)
        return Int64(kbps) * 1024
    }

    static func threads(for platform: String) -> Int {
        let key = "download_threads_\(platform)"
        let fallback = defaults.object(forKey: "default_threads") as? Int ?? 8
        return min(max(defaults.object(forKey: key) as? Int ?? fallback, 1), 32)
    }

    static var downloadDirName: String {
        let name = defaults.string(forKey: "download_dir_name") ?? "下载"
        return name.isEmpty ? "下载" : name
    }
}

@MainActor
final class DownloadManager: ObservableObject {

    static let shared = DownloadManager()

    @Published private(set) var tasks: [DownloadTaskModel] = []

    private var runners: [String: Task<Void, Never>] = [:]
    private let limiter = SpeedLimiter()
    private let store = DownloadStore.shared

    private init() {
        tasks = store.tasks
        // 上次退出时处于「下载中/合并中」的任务标记为暂停，等待用户恢复
        for index in tasks.indices where tasks[index].status == .running || tasks[index].status == .merging {
            tasks[index].status = .paused
        }
        persist()
        limiter.setRate(DownloadSettings.speedLimitBytesPerSecond)
    }

    // MARK: - 对外操作

    /// 入队一个下载任务，返回任务 id
    /// - Parameter accountId: 取链所用的账号主键（多账号下载时随直链一起带过来，
    ///   完成后按**同一账号**清理临时转存目录）。nil = 主账号 / 游客。
    @discardableResult
    func enqueue(
        link: DownloadLink,
        platform: SharePlatform,
        relativeDirectory: String,
        headers: [String: String],
        accountId: String? = nil
    ) -> String {
        let platformId = DownloadPlatformId.from(platform)
        let safe = DownloadPathPolicy.sanitize(
            relativePath: relativeDirectory.isEmpty ? link.filename : "\(relativeDirectory)/\(link.filename)",
            fallbackName: "未命名文件"
        )
        let fileName = safe?.fileName ?? "未命名文件"
        let directory = safe?.relativeDirectory ?? ""
        let relativePath = directory.isEmpty ? fileName : "\(directory)/\(fileName)"

        var model = DownloadTaskModel(
            id: UUID().uuidString,
            url: link.downloadUrl,
            filename: fileName,
            relativePath: relativePath,
            platform: platformId,
            totalSize: link.size,
            downloaded: 0,
            status: .queued,
            errorMessage: nil,
            isHls: link.isHls,
            threadCount: DownloadSettings.threads(for: platformId),
            createdAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            headersCipher: DownloadStore.encryptHeaders(headers),
            guestCookieCipher: DownloadStore.encryptGuestCookie(link.guestCookie),
            cleanupDirFid: link.cleanupDirFid,
            accountId: accountId,
            completedChunks: [],
            supportsRange: true,
            blockSize: 0,
            tempDirName: ""
        )
        model.tempDirName = "dl_\(model.id.replacingOccurrences(of: "-", with: "").prefix(12))"
        tasks.append(model)
        persist()
        schedule()
        return model.id
    }

    func pause(_ id: String) {
        runners[id]?.cancel()
        runners[id] = nil
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if tasks[index].status == .running || tasks[index].status == .queued || tasks[index].status == .merging {
            tasks[index].status = .paused
            tasks[index].updatedAt = Date().timeIntervalSince1970
        }
        persist()
        objectWillChange.send()
        schedule()
    }

    func resume(_ id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard tasks[index].status == .paused || tasks[index].status == .failed else { return }
        tasks[index].status = .queued
        tasks[index].errorMessage = nil
        persist()
        schedule()
    }

    func remove(_ id: String) {
        runners[id]?.cancel()
        runners[id] = nil
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let model = tasks[index]
        // 删除已完成/未完成的产物与临时文件（未完成的文件是半成品，保留无意义）
        let fileURL = Self.fileURL(for: model)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: fileURL.appendingPathExtension("hlsprog"))
        tasks.remove(at: index)
        persist()
        objectWillChange.send()
        schedule()
    }

    func removeAllCompleted() {
        tasks.removeAll { $0.status == .completed }
        persist()
        objectWillChange.send()
    }

    func retry(_ id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .queued
        tasks[index].errorMessage = nil
        persist()
        schedule()
    }

    /// 立即开始（忽略并发上限，用于「手动开始」）
    func startNow(_ id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if tasks[index].status == .completed { return }
        tasks[index].status = .queued
        persist()
        schedule(force: true)
    }

    var activeCount: Int {
        tasks.filter { $0.status == .running || $0.status == .merging }.count
    }

    // MARK: - 调度

    private func schedule(force: Bool = false) {
        limiter.setRate(DownloadSettings.speedLimitBytesPerSecond)
        let limit = max(1, DownloadSettings.maxConcurrentDownloads)
        var running = tasks.filter { runners[$0.id] != nil }.count
        if force { running = 0 }
        for task in tasks where task.status == .queued {
            if !force && running >= limit { break }
            if runners[task.id] != nil { continue }
            launch(task.id)
            running += 1
        }
    }

    private func launch(_ id: String) {
        guard runners[id] == nil else { return }
        update(id) { model in
            model.status = .running
            model.updatedAt = Date().timeIntervalSince1970
        }
        let runtime = makeRuntime(id)
        guard let runtime = runtime else { return }

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            do {
                let output = try await runtime.runner.run()
                await self.handleSuccess(runtime, output)
            } catch is CancellationError {
                await self.handleCancelled(runtime)
            } catch {
                if Task.isCancelled {
                    await self.handleCancelled(runtime)
                } else {
                    await self.handleFailure(runtime, error)
                }
            }
        }
        runners[id] = task
    }

    private struct Runtime {
        let id: String
        let platform: String
        let fileURL: URL
        let headers: [String: String]
        let cleanupDirFid: String?
        let runner: DownloadRunner
    }

    private func makeRuntime(_ id: String) -> Runtime? {
        guard let model = tasks.first(where: { $0.id == id }) else { return nil }
        let headers = DownloadStore.decryptHeaders(model.headersCipher)
        let cookie = DownloadStore.decryptGuestCookie(model.guestCookieCipher)
        var effectiveHeaders = headers
        if !cookie.isEmpty {
            let existing = effectiveHeaders["Cookie"] ?? ""
            effectiveHeaders["Cookie"] = existing.isEmpty ? cookie : "\(existing); \(cookie)"
        }
        let fileURL = Self.fileURL(for: model)

        let input = DownloadRunner.Input(
            url: model.url,
            headers: effectiveHeaders,
            fileURL: fileURL,
            platform: model.platform,
            threadCount: DownloadSettings.threads(for: model.platform),
            totalSize: model.totalSize,
            supportsRange: model.supportsRange,
            blockSize: model.blockSize,
            completedChunks: model.completedChunks,
            isHls: model.isHls
        )
        let runner = DownloadRunner(input: input, limiter: limiter) { [weak self] downloaded, total in
            Task { @MainActor in
                self?.applyProgress(id, downloaded: downloaded, total: total)
            }
        } onMerging: { [weak self] in
            Task { @MainActor in
                self?.update(id) { $0.status = .merging }
            }
        }
        return Runtime(
            id: id,
            platform: model.platform,
            fileURL: fileURL,
            headers: effectiveHeaders,
            cleanupDirFid: model.cleanupDirFid,
            runner: runner
        )
    }

    // MARK: - 回调（主线程）

    private func applyProgress(_ id: String, downloaded: Int64, total: Int64) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].downloaded = max(tasks[index].downloaded, downloaded)
        if total > 0 { tasks[index].totalSize = total }
        tasks[index].updatedAt = Date().timeIntervalSince1970
        // 高频回调下控制写盘频率
        if Date().timeIntervalSince1970 - lastPersist > 1.0 {
            persist()
        }
    }

    private var lastPersist: Double = 0

    private func handleSuccess(_ runtime: Runtime, _ output: DownloadRunner.Output) {
        runners[runtime.id] = nil
        guard let index = tasks.firstIndex(where: { $0.id == runtime.id }) else { return }
        tasks[index].status = .completed
        tasks[index].downloaded = max(output.downloaded, tasks[index].downloaded)
        if output.totalSize > 0 { tasks[index].totalSize = output.totalSize }
        tasks[index].completedChunks = output.completedChunks
        tasks[index].supportsRange = output.supportsRange
        tasks[index].blockSize = output.blockSize
        tasks[index].errorMessage = nil
        tasks[index].updatedAt = Date().timeIntervalSince1970
        persist()
        objectWillChange.send()
        AppStateToast.show("已下载：\(tasks[index].filename)")

        // 下载完成后清理临时转存目录（夸克等平台）
        // ★ 按「取链时用的那个账号」清理：多账号下载轮换取链时，临时目录建在对应账号的网盘里，
        //   用主账号的凭证去删只会删不掉（甚至误删主账号的同名目录）。账号已退出则回退主账号。
        if let dirFid = runtime.cleanupDirFid, !dirFid.isEmpty,
           let platform = SharePlatform(rawValue: runtime.platform),
           let repository = PlatformRegistry.shared.repository(for: platform) {
            let cookie = AccountStore.shared.cleanupCredential(for: platform, accountId: tasks[index].accountId)
            Task {
                await repository.cleanupTempDir(dirFid: dirFid, cookie: cookie)
            }
        }
        schedule()
    }

    private func handleCancelled(_ runtime: Runtime) {
        runners[runtime.id] = nil
        guard let index = tasks.firstIndex(where: { $0.id == runtime.id }) else { return }
        if tasks[index].status != .completed && tasks[index].status != .failed {
            tasks[index].status = .paused
        }
        persist()
        objectWillChange.send()
        schedule()
    }

    private func handleFailure(_ runtime: Runtime, _ error: Error) {
        runners[runtime.id] = nil
        guard let index = tasks.firstIndex(where: { $0.id == runtime.id }) else { return }
        tasks[index].status = .failed
        tasks[index].errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        persist()
        objectWillChange.send()
        AppStateToast.show("下载失败：\(tasks[index].filename)")
        schedule()
    }

    // MARK: - 工具

    private func update(_ id: String, _ mutate: (inout DownloadTaskModel) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[index])
        objectWillChange.send()
        persist()
    }

    private func persist() {
        lastPersist = Date().timeIntervalSince1970
        store.persist(tasks)
    }

    /// 下载根目录（Documents/下载名，Files 应用可见）
    static var rootDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent(DownloadSettings.downloadDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    static func fileURL(for task: DownloadTaskModel) -> URL {
        let root = rootDirectory
        let candidate = root.appendingPathComponent(task.relativePath)
        // 防目录穿越：不在根目录内的一律落到根目录下
        if DownloadPathPolicy.isContained(base: root, candidate: candidate) {
            return candidate
        }
        return root.appendingPathComponent(task.filename)
    }
}

/// 轻量 Toast 通道，避免下载模块直接依赖 SwiftUI 视图层
@MainActor
enum AppStateToast {
    static weak var delegate: AppState?

    static func show(_ message: String) {
        delegate?.show(message)
    }
}
