/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：统一错误类型（对应各平台 XxxApiException）。
 */

import Foundation

/// 平台 API 错误：携带服务端 message 与可选业务码，透传给 UI 展示。
struct ApiError: LocalizedError {
    let message: String
    let code: Int?

    init(_ message: String, code: Int? = nil) {
        self.message = message
        self.code = code
    }

    var errorDescription: String? { message }
}

enum YunXError {
    static func api(_ message: String, code: Int? = nil) -> ApiError {
        ApiError(message, code: code)
    }

    /// 未登录
    static var notLoggedIn: ApiError { ApiError("该平台未登录时无法下载，请先登录后再试") }

    /// 无法识别分享链接
    static var unrecognizedLink: ApiError { ApiError("无法识别分享链接") }
}
