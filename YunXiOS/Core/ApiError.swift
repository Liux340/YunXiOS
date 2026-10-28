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

    /// 凭证暂时不可读（密钥尚未就绪 / 密文损坏）。
    /// ★ 这是「读不出来」而不是「没有账号」：调用方必须保留密文，绝不能据此清空或覆盖凭证。
    static var credentialUnreadable: ApiError { ApiError("本机凭证暂时无法解密，请稍后重试") }
}
