/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：下载任务模型与持久化（对应 data/db/DownloadTaskEntity + DownloadTaskDao）。
 * 请求头（含 Cookie）与游客令牌加密落盘，与 Android 侧一致的「凭证不裸存」约定。
 */

import Foundation

enum DownloadStatus: String, Codable {
    case queued
    case running
    case paused
    case merging
    case completed
    case failed

    var displayName: String {
        switch self {
        case .queued: return "排队中"
        case .running: return "下载中"
        case .paused: return "已暂停"
        case .merging: return "合并中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

/// 已完成/待完成的分片区间（半开区间 [start, end)）
struct ChunkRange: Codable, Hashable {
    var start: Int64
    var end: Int64

    var length: Int64 { end - start }
}

struct DownloadTaskModel: Codable, Identifiable, Hashable {

    var id: String
    var url: String
    var filename: String
    /// 相对下载根目录的路径（含子目录）
    var relativePath: String
    var platform: String
    var totalSize: Int64
    var downloaded: Int64
    var status: DownloadStatus
    var errorMessage: String?
    var isHls: Bool
    var threadCount: Int
    var createdAt: Double
    var updatedAt: Double
    /// 加密后的请求头 JSON
    var headersCipher: String
    /// 加密后的游客 Cookie（夸克/UC 的 __pugs）
    var guestCookieCipher: String
    /// 下载完成后需要清理的临时转存目录 fid
    var cleanupDirFid: String?
    /// 已完成分片
    var completedChunks: [ChunkRange]
    /// 服务器是否支持 Range（不支持则退化为单流）
    var supportsRange: Bool
    /// 分片大小（弹性调整后回写，便于续传）
    var blockSize: Int64
    /// 合并用的临时分片目录名（分片模式下使用）
    var tempDirName: String

    var progress: Double {
        guard totalSize > 0 else { return status == .completed ? 1 : 0 }
        return min(1.0, Double(downloaded) / Double(totalSize))
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var downloadedText: String {
        ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
    }
}

/// 下载任务持久化（JSON 文件，原子写入）
@MainActor
final class DownloadStore {

    static let shared = DownloadStore()

    private let fileURL: URL
    private var cache: [DownloadTaskModel] = []

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("yunx_downloads.json")
        load()
    }

    var tasks: [DownloadTaskModel] { cache }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([DownloadTaskModel].self, from: data) {
            cache = decoded
        }
    }

    /// 整体写回（调用方保证已在主线程）
    func persist(_ tasks: [DownloadTaskModel]) {
        cache = tasks
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        // 原子写入，避免中途崩溃损坏任务表
        try? data.write(to: fileURL, options: .atomic)
    }

    func upsert(_ task: DownloadTaskModel, into tasks: inout [DownloadTaskModel]) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }

    /// 加密请求头
    static func encryptHeaders(_ headers: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(headers),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return CredentialStore.encrypt(text, purpose: "download.requestHeaders")
    }

    /// 解密请求头
    static func decryptHeaders(_ cipher: String) -> [String: String] {
        guard !cipher.isEmpty,
              let text = CredentialStore.decrypt(cipher, purpose: "download.requestHeaders"),
              let data = text.data(using: .utf8),
              let headers = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return headers
    }

    static func encryptGuestCookie(_ cookie: String) -> String {
        guard !cookie.isEmpty else { return "" }
        return CredentialStore.encrypt(cookie, purpose: "download.guestCookie")
    }

    static func decryptGuestCookie(_ cipher: String) -> String {
        guard !cipher.isEmpty else { return "" }
        return CredentialStore.decrypt(cipher, purpose: "download.guestCookie") ?? ""
    }
}
