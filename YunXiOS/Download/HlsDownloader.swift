/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：HLS（m3u8）下载器（对应 data/download/HlsDownloader.kt）。
 * 用于 UC 等平台「转码播放流」直链：拉取 m3u8 → 逐片下载 → 顺序拼接，
 * 支持 EXT-X-KEY（AES-128）解密与从已完成分片续传。
 */

import Foundation
import CommonCrypto

enum HlsError: LocalizedError {
    case invalidPlaylist(String)
    case segmentFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPlaylist(let msg): return "m3u8 解析失败：\(msg)"
        case .segmentFailed(let index): return "分片下载失败（第 \(index + 1) 片）"
        }
    }
}

final class HlsDownloader {

    struct Segment {
        let url: String
        let key: HlsKey?
        let sequence: Int
    }

    struct HlsKey {
        let method: String
        let uri: String
        let iv: String?
    }

    private let client = HTTPClient.download

    /// 下载 HLS 流到指定文件；已下载的分片数从 sidecar 文件读取以支持续传
    func download(
        url: String,
        headers: [String: String],
        outputURL: URL,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws {
        var allHeaders = headers
        allHeaders["User-Agent"] = allHeaders["User-Agent"] ?? "Mozilla/5.0"

        let playlistText = try await fetchText(url, headers: allHeaders)
        let mediaURL = try await resolveMediaPlaylist(playlistText, baseURL: url, headers: allHeaders)
        let mediaText = try await fetchText(mediaURL, headers: allHeaders)
        let segments = try parseSegments(mediaText, baseURL: mediaURL)
        guard !segments.isEmpty else { throw HlsError.invalidPlaylist("未找到分片") }

        // sidecar 记录已完成分片数与总字节，支持断点续传
        let sidecarURL = outputURL.appendingPathExtension("hlsprog")
        var completed = 0
        if let text = try? String(contentsOf: sidecarURL, encoding: .utf8),
           let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            completed = min(value, segments.count)
        }

        if !FileManager.default.fileExists(atPath: outputURL.path) {
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }

        if completed == 0 {
            try handle.truncate(atOffset: 0)
        } else {
            let currentSize = ((try? handle.seekToEnd()) ?? 0)
            progress(Int64(currentSize), -1)
        }

        // 密钥缓存（同一 uri 只取一次）
        var keyCache: [String: Data] = [:]

        for index in completed..<segments.count {
            if Task.isCancelled { throw CancellationError() }
            let segment = segments[index]
            let data = try await fetchData(segment.url, headers: allHeaders)
            var payload = data
            if let key = segment.key, key.method.uppercased() == "AES-128" {
                let keyData: Data
                if let cached = keyCache[key.uri] {
                    keyData = cached
                } else {
                    let fetched = try await fetchData(key.uri, headers: allHeaders)
                    keyCache[key.uri] = fetched
                    keyData = fetched
                }
                payload = try Self.decryptAES128CBC(data: data, key: keyData, iv: key.iv, sequence: segment.sequence)
            }
            try handle.write(contentsOf: payload)
            let written = (try? handle.offset()) ?? 0
            progress(Int64(written), -1)
            completed = index + 1
            try? String(completed).write(to: sidecarURL, atomically: true, encoding: .utf8)
        }

        try? FileManager.default.removeItem(at: sidecarURL)
    }

    // MARK: - 播放列表

    private func fetchText(_ url: String, headers: [String: String]) async throws -> String {
        let data = try await fetchData(url, headers: headers)
        guard let text = String(data: data, encoding: .utf8) else {
            throw HlsError.invalidPlaylist("响应非 UTF-8")
        }
        return text
    }

    private func fetchData(_ url: String, headers: [String: String]) async throws -> Data {
        let request = try client.makeRequest(url, headers: headers)
        let (data, response) = try await client.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ApiError("请求失败 HTTP \(http.statusCode)")
        }
        return data
    }

    /// 若为 master playlist（含 EXT-X-STREAM-INF），解析出第一个 variant 地址
    private func resolveMediaPlaylist(_ text: String, baseURL: String, headers: [String: String]) async throws -> String {
        guard text.contains("#EXT-X-STREAM-INF") else { return baseURL }
        let lines = text.components(separatedBy: .newlines)
        var variant: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            variant = trimmed
            break
        }
        guard let variant = variant else { throw HlsError.invalidPlaylist("master 播放列表缺少 variant") }
        return resolveURL(variant, base: baseURL) ?? variant
    }

    private func parseSegments(_ text: String, baseURL: String) throws -> [Segment] {
        var segments: [Segment] = []
        var currentKey: HlsKey?
        var sequence = 0
        var pendingKeyLine: HlsKey?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXT-X-KEY") {
                if let key = parseKey(line, base: baseURL) {
                    pendingKeyLine = key
                }
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE") {
                if let value = line.components(separatedBy: ":").last, let v = Int(value) {
                    sequence = v
                }
            } else if line.hasPrefix("#") {
                continue
            } else {
                guard let resolved = resolveURL(line, base: baseURL) else { continue }
                currentKey = pendingKeyLine
                segments.append(Segment(url: resolved, key: currentKey, sequence: sequence))
                sequence += 1
            }
        }
        return segments
    }

    private func parseKey(_ line: String, base: String) -> HlsKey? {
        var method = ""
        var uri = ""
        var iv: String?
        for part in splitAttributes(line) {
            if part.hasPrefix("METHOD=") { method = String(part.dropFirst(7)) }
            if part.hasPrefix("URI=") {
                let raw = String(part.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                uri = resolveURL(raw, base: base) ?? raw
            }
            if part.hasPrefix("IV=") { iv = String(part.dropFirst(3)) }
        }
        if method.isEmpty || method.uppercased() == "NONE" { return nil }
        return HlsKey(method: method, uri: uri, iv: iv)
    }

    /// 按逗号切分属性行，跳过引号内的逗号
    private func splitAttributes(_ line: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle() }
            if ch == "," && !inQuotes {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { parts.append(current.trimmingCharacters(in: .whitespaces)) }
        return Array(parts.dropFirst())
    }

    private func resolveURL(_ value: String, base: String) -> String? {
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        guard let baseURL = URL(string: base) else { return nil }
        if value.hasPrefix("/") {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = value
            components?.query = nil
            return components?.url?.absoluteString
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteString
    }

    // MARK: - AES-128-CBC 解密（EXT-X-KEY）

    static func decryptAES128CBC(data: Data, key: Data, iv: String?, sequence: Int) throws -> Data {
        var ivBytes = Data(count: kCCBlockSizeAES128)
        if let iv = iv, iv.hasPrefix("0x") || iv.hasPrefix("0X") {
            let hex = String(iv.dropFirst(2))
            ivBytes = Data(hexPairs: hex) ?? Data(count: kCCBlockSizeAES128)
        } else {
            // 未显式给 IV 时按规范使用媒体序号作为 IV
            var be = UInt32(sequence).bigEndian
            withUnsafeBytes(of: &be) { ivBytes.replaceSubrange(12..<16, with: $0) }
        }

        let outCapacity = data.count + kCCBlockSizeAES128
        var out = Data(count: outCapacity)
        var moved = 0
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    ivBytes.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, data.count,
                            outPtr.baseAddress, outCapacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else {
            throw ApiError("HLS 分片解密失败（status=\(status)）")
        }
        return out.prefix(moved)
    }
}

extension Data {
    /// 十六进制字符串 → Data
    init?(hexPairs hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = chars[index].hexDigitValue, let low = chars[index + 1].hexDigitValue else { return nil }
            bytes.append(UInt8(high << 4 | low))
            index += 2
        }
        self = Data(bytes)
    }
}
