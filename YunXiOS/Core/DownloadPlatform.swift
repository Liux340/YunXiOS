/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：下载来源平台标识（对应 data/download/DownloadPlatform.kt）。
 */

import Foundation

enum DownloadPlatformId {
    static let quark = "quark"
    static let uc = "uc"
    static let xunlei = "xunlei"
    static let baidu = "baidu"
    static let c139 = "c139"
    static let pan123 = "pan123"
    static let pan115 = "pan115"
    static let guangya = "guangya"
    static let ilanzou = "ilanzou"
    static let lanzou = "lanzou"
    static let magnet = "magnet"
    static let github = "github"
    static let generic = "generic"

    static func from(_ platform: SharePlatform) -> String {
        switch platform {
        case .quark: return quark
        case .uc: return uc
        case .xunlei: return xunlei
        case .baidu: return baidu
        case .c139: return c139
        case .pan123: return pan123
        case .pan115: return pan115
        case .guangya: return guangya
        case .ilanzou: return ilanzou
        case .lanzou: return lanzou
        case .github: return github
        }
    }
}
