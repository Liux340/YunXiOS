/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：下载路径安全策略（对应 data/download/DownloadPathPolicy.kt）。
 */

import Foundation

enum DownloadPathPolicy {

    struct SafePath {
        let fileName: String
        let relativeDirectory: String
    }

    /// 归一化相对路径，拒绝绝对路径与 `..` 逃逸；返回安全的文件名与相对目录
    static func sanitize(relativePath: String, fallbackName: String) -> SafePath? {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") { return nil }

        let rawParts = normalized.components(separatedBy: "/")
        if rawParts.contains(where: { $0 == "." || $0 == ".." }) { return nil }

        let parts = rawParts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let rawName = parts.last ?? ""
        var safeName = sanitizeName(rawName)
        if safeName.isEmpty { safeName = fallbackName }
        let safeDirectory = parts.dropLast().map { sanitizeName($0) }.joined(separator: "/")
        return SafePath(fileName: safeName, relativeDirectory: safeDirectory)
    }

    /// 非法字符替换 + 超长截断（保留扩展名）
    static func sanitizeName(_ name: String) -> String {
        var cleaned = name
        for ch in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"] {
            cleaned = cleaned.replacingOccurrences(of: ch, with: "_")
        }
        // 控制字符
        cleaned = String(cleaned.unicodeScalars.filter { $0.value >= 0x20 })
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 120 {
            let ext = extensionOf(cleaned)
            let base = String(cleaned.prefix(100))
            if !ext.isEmpty && ext != cleaned {
                cleaned = "\(base).\(ext)"
            } else {
                cleaned = String(cleaned.prefix(120))
            }
        }
        return cleaned
    }

    private static func extensionOf(_ name: String) -> String {
        guard let dotIndex = name.lastIndex(of: ".") else { return "" }
        let ext = String(name[name.index(after: dotIndex)...])
        return String(ext.prefix(10))
    }

    /// 校验 candidate 是否位于 base 目录之内
    static func isContained(base: URL, candidate: URL) -> Bool {
        let basePath = base.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        if candidatePath == basePath { return false }
        return candidatePath.hasPrefix(basePath.hasSuffix("/") ? basePath : basePath + "/")
    }
}
