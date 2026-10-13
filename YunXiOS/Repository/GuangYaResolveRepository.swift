/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：光鸭云盘接口层与分享解析仓库（对应 Android 侧
 *   data/network/GuangYaConstants.kt、data/network/GuangYaApi.kt、
 *   data/repository/GuangYaResolveRepository.kt）。
 * 仅依赖 Foundation，无第三方库。
 */

import Foundation

// MARK: - 常量（对应 GuangYaConstants.kt）

/// 光鸭云盘常量（文档 §1）
enum GuangYaConstants {

    static let CLIENT_ID = "aMe-8VSlkrbQXpUR"

    static let API_BASE = "https://api.guangyapan.com"
    static let ACCOUNT_BASE = "https://account.guangyapan.com"
    static let WEB_SITE = "https://www.guangyapan.com"

    /// 下载直链必须携带的 Referer（文档 §5.6/§7.1）
    static let DOWNLOAD_REFERER = WEB_SITE + "/"

    static let WEB_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    // ---------- 账号 API 公共头（文档 §1.3） ----------
    static let CLIENT_VERSION = "0.0.1"
    static let SDK_VERSION = "9.1.3"
    static let PROTOCOL_VERSION = "301"
    static let DEVICE_MODEL = "chrome%2F131.0.0.0"
    static let DEVICE_NAME = "PC-Chrome"
    static let OS_VERSION = "Win32"
    static let PLATFORM_VERSION = "1"

    // ---------- 端点（文档 §3 业务接口总表） ----------
    static let AUTH_TOKEN = ACCOUNT_BASE + "/v1/auth/token"
    static let USER_ME = ACCOUNT_BASE + "/v1/user/me"
    static let CAPTCHA_INIT = ACCOUNT_BASE + "/v1/shield/captcha/init"
    static let SIGNIN = ACCOUNT_BASE + "/v1/auth/signin"
    static let SIGNUP = ACCOUNT_BASE + "/v1/auth/signup"
    static let VERIFICATION = ACCOUNT_BASE + "/v1/auth/verification"
    static let VERIFICATION_VERIFY = ACCOUNT_BASE + "/v1/auth/verification/verify"

    static let GET_ASSETS = API_BASE + "/assets/v1/get_assets"
    static let SHARE_SUMMARY = API_BASE + "/userres/v1/get_share_summary"
    static let SHARE_ACCESS_TOKEN = API_BASE + "/userres/v1/get_share_access_token"
    static let SHARE_FILES = API_BASE + "/userres/v1/get_share_page_files_list"
    static let SHARE_DOWNLOAD = API_BASE + "/userres/v1/get_share_download_url"
    static let RESTORE_SHARE = API_BASE + "/userres/v1/restore_share"
    static let SHARE_FILE = API_BASE + "/userres/v1/share_file"

    static let FILE_LIST = API_BASE + "/userres/v1/file/get_file_list"
    static let CREATE_DIR = API_BASE + "/userres/v1/file/create_dir"
    static let RENAME = API_BASE + "/userres/v1/file/rename"
    static let MOVE_FILE = API_BASE + "/userres/v1/file/move_file"
    static let DELETE_FILE = API_BASE + "/userres/v1/file/delete_file"
    static let RES_DOWNLOAD = API_BASE + "/userres/v1/get_res_download_url"
    static let TASK_STATUS = API_BASE + "/userres/v1/get_task_status"

    /// 分享根目录 id（空串）
    static let ROOT_PARENT_ID = ""

    /// 分享页大小（文档 §4.3/§5.1）
    static let PAGE_SIZE = 100

    /// 任务轮询：首次前等待 taskDelay（默认 750ms），最多 80 次（文档 §5.7/§8.2）
    static let TASK_DELAY_MS: Int64 = 750
    static let TASK_MAX_POLLS = 80

    private static let hexChars: [Character] = Array("0123456789abcdef")

    /// 生成 count 位十六进制随机串
    private static func randomHex(_ count: Int) -> String {
        String((0..<count).map { _ in hexChars.randomElement()! })
    }

    /// 生成 32 位十六进制设备 id
    static func newDeviceId() -> String {
        randomHex(32)
    }

    /// 形如 wdi10.<32位十六进制>xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx 的设备签名
    static func newDeviceSign(deviceId: String) -> String {
        "wdi10." + deviceId + randomHex(32)
    }

    /// X-Device-Id：取 deviceSign 中第一个 "." 之后的 32 个字符；不足则回退 deviceId（文档 §1.4）
    static func deviceIdFromSign(_ deviceSign: String, fallback: String) -> String {
        guard let idx = deviceSign.firstIndex(of: ".") else { return fallback }
        let rest = String(deviceSign[deviceSign.index(after: idx)...])
        if rest.count >= 32 {
            return String(rest.prefix(32))
        }
        return fallback
    }

    /// 生成 traceparent（文档 §1.3：每次请求重新生成）
    static func newTraceparent() -> String {
        "00-\(randomHex(32))-\(randomHex(16))-01"
    }
}

// MARK: - 数据模型（对应 GuangYaApi.kt 内的 data class）

/// 设备标识（deviceId 32 位十六进制 + deviceSign）
struct GuangYaDevice {
    let deviceId: String
    let deviceSign: String
}

/// 刷新 / 登录成功返回的令牌对
struct GuangYaTokens {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int64

    init(accessToken: String, refreshToken: String, expiresIn: Int64 = 0) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
}

/// 账号信息
struct GuangYaAccountInfo {
    let userId: String
    let nickname: String
}

/// 短信验证码挑战（文档 §2.6）
struct GuangYaSmsChallenge {
    let verificationId: String
    let isUser: Bool
    let expiresIn: Int
}

/// 分享下载受限（业务码 207，文档 §4.4）：分享者未开启免登录下载，
/// 已登录用户需「转存到临时目录 → 从个人盘取链」，未登录则要求先登录。
struct GuangYaShareRestrictedError: Error, LocalizedError {
    var errorDescription: String? { "该光鸭分享需登录并转存后下载，请先登录光鸭云盘" }
}

// MARK: - 文件级辅助（对应 Kotlin 顶层工具函数）

/// 取第一个非空白（空白即 trim 后为空）字符串并 trim（对应 firstNonBlank）
private func gyFirstNonBlank(_ values: String...) -> String {
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    return ""
}

/// isBlank 判定
private func gyIsBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// 延时（对应 Kotlin 协程 delay）
private func gyDelay(_ ms: Int64) async {
    try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
}

/// 从 JSONValue 中按 optJSONObject 语义取对象（非对象/缺失均返回 nil）
private func gyObjectOrNil(_ value: JSONValue, _ key: String) -> JSONValue? {
    guard let dict = value.raw as? [String: Any], let v = dict[key], v is [String: Any] else { return nil }
    return JSONValue(v)
}

/// 从 JSONValue 中按 optJSONArray 语义取数组（非数组/缺失均返回 nil）
private func gyArrayOrNil(_ value: JSONValue, _ key: String) -> [JSONValue]? {
    guard let dict = value.raw as? [String: Any], let v = dict[key], v is [Any] else { return nil }
    return (v as? [Any])?.map { JSONValue($0) }
}

// MARK: - 光鸭云盘 API（对应 GuangYaApi.kt）

/// 光鸭云盘 API 封装（文档 §1-§7）。
/// 业务 API 带 did/dt/traceparent 头；账号 API 带一整套 X-Device-* 头；Authorization 仅在有令牌时携带。
final class GuangYaApi {

    private let client: HTTPClient

    /// 业务 API 的 `did` 设备头提供者（文档 §1.3）。由上层从账号仓库的 deviceId 缓存注入；未登录返回 nil。
    var deviceIdProvider: () -> String? = { nil }

    /// 未登录（匿名分享）时业务请求兜底使用的设备 id（文档 §1.3：业务 API 始终需要 did）
    private let publicDeviceId: String

    init(client: HTTPClient = .api) {
        self.client = client
        self.publicDeviceId = GuangYaConstants.newDeviceId()
    }

    // ---------- 认证（文档 §2） ----------

    /// 人机验证初始化结果：token 可能为空；url 非空表示需要网页验证（文档 §2.4）
    private struct CaptchaInit {
        let token: String?
        let url: String?
    }

    /// 内部信号：需要重试人机验证
    private struct CaptchaError: Error {}

    /// 初始化人机验证（action 见文档 §2.4）
    private func initCaptcha(device: GuangYaDevice, meta: [String: Any], action: String) async throws -> CaptchaInit {
        let body: [String: Any] = [
            "client_id": GuangYaConstants.CLIENT_ID,
            "action": action,
            "device_id": device.deviceId,
            "captcha_token": "",
            "meta": meta,
        ]
        let json = try await executeJSON(
            url: GuangYaConstants.CAPTCHA_INIT,
            method: "POST",
            headers: accountHeaders(device: device, token: nil),
            body: body
        )
        let token = json.string("captcha_token")
        let url = json.string("url")
        return CaptchaInit(
            token: gyIsBlank(token) ? nil : token,
            url: gyIsBlank(url) ? nil : url
        )
    }

    /// 密码登录（文档 §2.5）：先初始化人机验证再 signin；仅在 captcha_required / captcha_invalid 时重试（最多 2 次）。
    func signIn(username: String, password: String, device: GuangYaDevice) async throws -> GuangYaTokens {
        let normalized = normalizeAccount(username)
        let meta = metaFor(normalized)
        var captcha = try await initCaptcha(device: device, meta: meta, action: "POST:/v1/auth/signin")
        for attempt in 0...2 {
            do {
                return try await doSignIn(
                    username: normalized,
                    password: password,
                    captchaToken: captcha.token,
                    device: device
                )
            } catch is CaptchaError {
                if attempt >= 2 {
                    throw ApiError("光鸭安全验证未通过，请重试或切换网页登录")
                }
                captcha = try await initCaptcha(device: device, meta: meta, action: "POST:/v1/auth/signin")
            }
        }
        throw ApiError("光鸭安全验证未通过，请重试或切换网页登录")
    }

    private func doSignIn(
        username: String,
        password: String,
        captchaToken: String?,
        device: GuangYaDevice
    ) async throws -> GuangYaTokens {
        let body: [String: Any] = [
            "client_id": GuangYaConstants.CLIENT_ID,
            "username": username,
            "password": password,
        ]
        var headers = accountHeaders(device: device, token: nil)
        if let captchaToken, !captchaToken.isEmpty {
            headers["X-Captcha-Token"] = captchaToken
        }
        let json = try await executeJSON(url: GuangYaConstants.SIGNIN, method: "POST", headers: headers, body: body)
        let code = json.string("code")
        let error = json.string("error")
        if code == "captcha_required" || error == "captcha_required" ||
            code == "captcha_invalid" || error == "captcha_invalid" {
            throw CaptchaError()
        }
        if !isSuccess(json) { throw ApiError(mapSigninError(json, error)) }
        return try parseTokens(json)
    }

    /// 刷新 Token（文档 §2.1）。凭据失效返回 nil。
    func refreshToken(_ refreshToken: String, device: GuangYaDevice) async throws -> GuangYaTokens? {
        let body: [String: Any] = [
            "client_id": GuangYaConstants.CLIENT_ID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        var headers = accountHeaders(device: device, token: nil)
        headers["X-Action"] = "401"
        let json = try await executeJSON(url: GuangYaConstants.AUTH_TOKEN, method: "POST", headers: headers, body: body)
        if !isSuccess(json) { return nil }
        return try parseTokens(json)
    }

    // ---------- 短信验证码登录 / 注册（文档 §2.6-§2.8） ----------

    /// 发送短信验证码（文档 §2.6）：返回 verification_id / is_user / expires_in。
    func sendSmsCode(phoneNumber: String, device: GuangYaDevice) async throws -> GuangYaSmsChallenge {
        let meta: [String: Any] = ["phone_number": phoneNumber]
        var captcha = try await initCaptcha(device: device, meta: meta, action: "POST:/v1/auth/verification")
        // 初始化返回 url 表示必须走网页人机验证：应用内无法完成，直接给出可执行提示
        if let url = captcha.url, !url.isEmpty {
            throw ApiError("光鸭需要网页人机验证，请稍后重试或改用账号密码登录")
        }
        for attempt in 0...2 {
            do {
                return try await doSendSmsCode(phoneNumber: phoneNumber, captchaToken: captcha.token, device: device)
            } catch is CaptchaError {
                if attempt >= 2 {
                    throw ApiError("光鸭安全验证未通过，请重试或改用账号密码登录")
                }
                captcha = try await initCaptcha(device: device, meta: meta, action: "POST:/v1/auth/verification")
                if let url = captcha.url, !url.isEmpty {
                    throw ApiError("光鸭需要网页人机验证，请稍后重试或改用账号密码登录")
                }
            }
        }
        throw ApiError("光鸭安全验证未通过，请重试或改用账号密码登录")
    }

    private func doSendSmsCode(phoneNumber: String, captchaToken: String?, device: GuangYaDevice) async throws -> GuangYaSmsChallenge {
        let body: [String: Any] = [
            "client_id": GuangYaConstants.CLIENT_ID,
            "phone_number": phoneNumber,
            "target": "ANY",
        ]
        var headers = accountHeaders(device: device, token: nil)
        // 始终带上 X-Captcha-Token（即使为空串）：服务端以该头存在与否判定 "no captcha"
        headers["X-Captcha-Token"] = captchaToken ?? ""
        let json = try await executeJSON(url: GuangYaConstants.VERIFICATION, method: "POST", headers: headers, body: body)
        let code = json.string("code")
        let error = json.string("error")
        if code == "captcha_required" || error == "captcha_required" ||
            code == "captcha_invalid" || error == "captcha_invalid" {
            throw CaptchaError()
        }
        try ensureAccountSuccess(json, fallback: "发送验证码失败")
        let verificationId = accountString(json, "verification_id")
        if verificationId.isEmpty {
            throw ApiError("验证码请求过于频繁，请稍后重试")
        }
        return GuangYaSmsChallenge(
            verificationId: verificationId,
            isUser: accountBoolean(json, "is_user"),
            expiresIn: min(max(accountInt(json, "expires_in", 600), 1), 1800)
        )
    }

    /// 校验短信验证码（文档 §2.7）：验证码格式 ^[0-9]{4,8}$，返回 verification_token。
    func verifySmsCode(verificationId: String, code: String, device: GuangYaDevice) async throws -> String {
        if !isValidSmsCode(code) {
            throw ApiError("短信验证码错误或已过期，请重新获取")
        }
        let body: [String: Any] = [
            "client_id": GuangYaConstants.CLIENT_ID,
            "verification_id": verificationId,
            "verification_code": code,
        ]
        let json = try await executeJSON(
            url: GuangYaConstants.VERIFICATION_VERIFY,
            method: "POST",
            headers: accountHeaders(device: device, token: nil),
            body: body
        )
        try ensureAccountSuccess(json, fallback: "短信验证码错误或已过期，请重新获取")
        let token = accountString(json, "verification_token")
        if token.isEmpty {
            throw ApiError("短信验证码错误或已过期，请重新获取")
        }
        return token
    }

    /// 老用户短信登录（文档 §2.8）。
    func smsSignIn(
        phoneNumber: String,
        code: String,
        verificationToken: String,
        device: GuangYaDevice
    ) async throws -> GuangYaTokens {
        let body: [String: Any] = [
            "client_id": GuangYaConstants.CLIENT_ID,
            "username": phoneNumber,
            "verification_code": code,
            "verification_token": verificationToken,
        ]
        let json = try await executeJSON(url: GuangYaConstants.SIGNIN, method: "POST", headers: accountHeaders(device: device, token: nil), body: body)
        try ensureAccountSuccess(json, fallback: "短信验证码错误或已过期，请重新获取")
        return try parseTokens(json)
    }

    /// 新用户短信注册（文档 §2.8）：name 规则 = 前 3 位 + **** + 后 4 位。
    func smsSignUp(
        phoneNumber: String,
        name: String,
        code: String,
        verificationToken: String,
        device: GuangYaDevice
    ) async throws -> GuangYaTokens {
        let body: [String: Any] = [
            "client_id": GuangYaConstants.CLIENT_ID,
            "phone_number": phoneNumber,
            "name": name,
            "verification_code": code,
            "verification_token": verificationToken,
        ]
        let json = try await executeJSON(url: GuangYaConstants.SIGNUP, method: "POST", headers: accountHeaders(device: device, token: nil), body: body)
        try ensureAccountSuccess(json, fallback: "短信验证码错误或已过期，请重新获取")
        return try parseTokens(json)
    }

    /// 账号信息：GET /v1/user/me（文档 §2.2）。失败返回 nil。
    func fetchAccountInfo(_ accessToken: String, device: GuangYaDevice) async throws -> GuangYaAccountInfo? {
        do {
            let json = try await executeJSON(
                url: GuangYaConstants.USER_ME,
                method: "GET",
                headers: accountHeaders(device: device, token: accessToken),
                body: nil
            )
            if !isSuccess(json) { return nil }
            let userId = gyFirstNonBlank(json.string("sub"), json.string("user_id"), json.string("userId"))
            let nickname = gyFirstNonBlank(
                json.string("nickname"), json.string("nick_name"),
                json.string("name"), json.string("username")
            )
            if userId.isEmpty { return nil }
            return GuangYaAccountInfo(userId: userId, nickname: nickname)
        } catch {
            return nil
        }
    }

    /// 容量信息（文档 §2.3）：POST /assets/v1/get_assets。失败返回 nil。
    func getQuota(_ accessToken: String, device: GuangYaDevice) async throws -> QuotaInfo? {
        do {
            let json = try await executeJSON(
                url: GuangYaConstants.GET_ASSETS,
                method: "POST",
                headers: businessHeaders(device: device, token: accessToken),
                body: [:]
            )
            try checkBusiness(json, fallback: "获取容量信息失败")
            guard let data = dataOf(json) else { return nil }
            let total = data.long("totalSpaceSize")
            if total < 0 { return nil }
            let used = data.long("usedSpaceSize")
            return QuotaInfo(used: used, total: total)
        } catch {
            return nil
        }
    }

    // ---------- 分享（文档 §4） ----------

    /// 分享摘要标题（文档 §4.1）。失败返回 nil。
    func getShareSummary(_ shareId: String) async throws -> String? {
        do {
            let body: [String: Any] = ["shareId": shareId]
            let json = try await executeJSON(
                url: GuangYaConstants.SHARE_SUMMARY,
                method: "POST",
                headers: businessHeaders(device: nil, token: nil),
                body: body
            )
            try checkBusiness(json, fallback: "获取分享信息失败")
            let data = dataOf(json) ?? json
            let title = gyFirstNonBlank(data.string("title"), data.string("shareName"))
            return title.isEmpty ? nil : title
        } catch {
            return nil
        }
    }

    /// 用提取码换取分享访问令牌（文档 §4.2）。code 209 = 提取码错误。
    func getShareAccessToken(_ shareId: String, code: String) async throws -> String {
        let body: [String: Any] = [
            "shareId": shareId,
            "code": gyIsBlank(code) ? "" : code,
        ]
        let json = try await executeJSON(
            url: GuangYaConstants.SHARE_ACCESS_TOKEN,
            method: "POST",
            headers: businessHeaders(device: nil, token: nil),
            body: body
        )
        try checkBusiness(json, fallback: "获取分享访问令牌失败")
        guard let data = dataOf(json) else { throw ApiError("光鸭分享链接无效") }
        let token = gyFirstNonBlank(data.string("accessToken"), data.string("access_token"))
        if token.isEmpty { throw ApiError("光鸭分享链接无效") }
        return token
    }

    /// 分享列目录（文档 §4.3）：返回 (文件列表, 下一页游标 or nil=无更多)。
    func listShareFiles(accessToken: String, parentId: String, cursor: String?) async throws -> (files: [ShareFile], next: String?) {
        var body: [String: Any] = [
            "parentId": parentId,
            "pageSize": GuangYaConstants.PAGE_SIZE,
            "orderBy": 0,
            "sortType": 0,
            "accessToken": accessToken,
        ]
        if let cursor, !gyIsBlank(cursor) {
            body["cursor"] = cursor
        }
        let json = try await executeJSON(
            url: GuangYaConstants.SHARE_FILES,
            method: "POST",
            headers: businessHeaders(device: nil, token: nil),
            body: body
        )
        try checkBusiness(json, fallback: "获取分享文件列表失败")
        guard let data = dataOf(json) else { return ([], nil) }
        let list = parseFileList(listArray(data))
        let hasMore = data.bool("hasMore")
        let nextRaw = data.string("cursor")
        let next: String? = gyIsBlank(nextRaw) ? nil : nextRaw
        let effectiveNext: String?
        if hasMore && next != nil {
            effectiveNext = next
        } else if !hasMore {
            effectiveNext = nil
        } else {
            effectiveNext = next
        }
        return (list, effectiveNext)
    }

    /// 分享取下载地址（文档 §4.4）；业务码 207 表示需登录并转存。
    func getShareDownloadUrl(file: ShareFile, accessToken: String) async throws -> DownloadLink? {
        let body: [String: Any] = [
            "fileId": file.fid,
            "accessToken": accessToken,
        ]
        let json = try await executeJSON(
            url: GuangYaConstants.SHARE_DOWNLOAD,
            method: "POST",
            headers: businessHeaders(device: nil, token: nil),
            body: body
        )
        if json.string("code") == "207" {
            throw GuangYaShareRestrictedError()
        }
        try checkBusiness(json, fallback: "获取下载地址失败")
        guard let data = dataOf(json) else { return nil }
        let url = gyFirstNonBlank(
            data.string("signedURL"), data.string("signedUrl"), data.string("downloadUrl"),
            data.string("download_url"), data.string("url"), data.string("cdnUrl")
        )
        if url.isEmpty {
            throw ApiError("光鸭未返回有效下载地址，请确认下载权限")
        }
        let size = Int64(data.string("size")) ?? file.fsize
        return DownloadLink(fid: file.fid, filename: file.fname, downloadUrl: url, size: size)
    }

    /// 转存分享（文档 §4.5）：body 的 `accessToken` 是分享访问令牌，
    /// `Authorization` 用账号 access token；返回含 taskId 时用账号 token 轮询任务状态。
    func restoreShare(accountToken: String, shareToken: String, fileIds: [String], parentId: String) async throws {
        let body: [String: Any] = [
            "accessToken": shareToken,
            "fileIds": fileIds,
            "parentId": parentId,
        ]
        let json = try await executeJSON(
            url: GuangYaConstants.RESTORE_SHARE,
            method: "POST",
            headers: businessHeaders(device: nil, token: accountToken),
            body: body
        )
        try checkBusiness(json, fallback: "转存失败")
        let taskId = dataOf(json)?.string("taskId") ?? ""
        if !taskId.isEmpty {
            try await waitTask(accountToken, taskId)
        }
    }

    /// 创建分享（文档 §4.6）。
    func createShare(
        accessToken: String,
        fileIds: [String],
        title: String,
        expireDays: Int?,
        passcode: String?
    ) async throws -> ShareInfo {
        let code = passcode ?? ""
        let body: [String: Any] = [
            "fileIds": fileIds,
            "title": title,
            "validateDuration": expireDays ?? 0,
            "shareType": gyIsBlank(code) ? 0 : 1,
            "code": code,
            "autoFillCode": false,
            "trafficLimit": "0",
            "maxRestoreCount": 0,
            "downloadType": 1,
        ]
        let json = try await executeJSON(
            url: GuangYaConstants.SHARE_FILE,
            method: "POST",
            headers: businessHeaders(device: nil, token: accessToken),
            body: body
        )
        try checkBusiness(json, fallback: "创建分享失败")
        guard let data = dataOf(json) else { throw ApiError("创建分享失败") }
        let shareUrl = data.string("shareUrl")
        let shareId = gyFirstNonBlank(data.string("shareId"), data.string("id"))
        var url = shareUrl
        if gyIsBlank(url) {
            if gyIsBlank(shareId) { throw ApiError("创建分享失败") }
            url = "\(GuangYaConstants.WEB_SITE)/s/\(shareId)"
        }
        let realCode = gyIsBlank(data.string("code")) ? code : data.string("code")
        // ShareExpire.UNKNOWN = 0
        return ShareInfo(shareUrl: url, passcode: realCode, pwdId: shareId, title: title, expiredType: 0)
    }

    // ---------- 个人盘（文档 §5） ----------

    /// 个人盘列目录（文档 §5.1）：page 从 0 开始自动翻页。
    func listCloudFiles(_ accessToken: String, parentId: String) async throws -> [ShareFile] {
        var all: [ShareFile] = []
        var seen = Set<String>()
        var page = 0
        while page < 1000 {
            let body: [String: Any] = [
                "parentId": parentId,
                "pageSize": GuangYaConstants.PAGE_SIZE,
                "orderBy": 0,
                "sortType": 0,
                "page": page,
            ]
            let json = try await executeJSON(
                url: GuangYaConstants.FILE_LIST,
                method: "POST",
                headers: businessHeaders(device: nil, token: accessToken),
                body: body
            )
            try checkBusiness(json, fallback: "获取文件列表失败")
            guard let data = dataOf(json) else { break }
            let list = parseFileList(listArray(data))
            if list.isEmpty { break }
            var added = 0
            for file in list where seen.insert(file.fid).inserted {
                all.append(file)
                added += 1
            }
            if added == 0 {
                throw ApiError("光鸭文件列表分页重复，请重试")
            }
            let total = Int64(data.string("total")) ?? data.long("total")
            if total > 0 && Int64(all.count) >= total { break }
            if total <= 0 && list.count < GuangYaConstants.PAGE_SIZE { break }
            page += 1
        }
        return all
    }

    /// 新建目录（文档 §5.2）。
    func createDir(_ accessToken: String, parentId: String, name: String) async throws -> String {
        let body: [String: Any] = [
            "parentId": parentId,
            "dirName": name,
            "failIfNameExist": true,
        ]
        let json = try await executeJSON(
            url: GuangYaConstants.CREATE_DIR,
            method: "POST",
            headers: businessHeaders(device: nil, token: accessToken),
            body: body
        )
        try checkBusiness(json, fallback: "新建文件夹失败")
        guard let data = dataOf(json) else {
            throw ApiError("光鸭未创建文件夹，请检查是否存在同名文件")
        }
        let id = gyFirstNonBlank(data.string("fileId"), data.string("id"))
        if id.isEmpty || data.string("resType") == "1" {
            throw ApiError("光鸭未创建文件夹，请检查是否存在同名文件")
        }
        return id
    }

    /// 重命名（文档 §5.3）。
    func renameFile(_ accessToken: String, fileId: String, newName: String) async throws {
        let body: [String: Any] = ["fileId": fileId, "newName": newName]
        let json = try await executeJSON(
            url: GuangYaConstants.RENAME,
            method: "POST",
            headers: businessHeaders(device: nil, token: accessToken),
            body: body
        )
        try checkBusiness(json, fallback: "重命名失败")
        if let taskId = dataOf(json)?.string("taskId"), !gyIsBlank(taskId) {
            try await waitTask(accessToken, taskId)
        }
    }

    /// 移动文件（文档 §5.4）。
    func moveFiles(_ accessToken: String, fileIds: [String], parentId: String) async throws {
        let body: [String: Any] = ["fileIds": fileIds, "parentId": parentId]
        let json = try await executeJSON(
            url: GuangYaConstants.MOVE_FILE,
            method: "POST",
            headers: businessHeaders(device: nil, token: accessToken),
            body: body
        )
        try checkBusiness(json, fallback: "移动失败")
        if let taskId = dataOf(json)?.string("taskId"), !gyIsBlank(taskId) {
            try await waitTask(accessToken, taskId)
        }
    }

    /// 删除文件（文档 §5.5）。
    func deleteFiles(_ accessToken: String, fileIds: [String]) async throws {
        let body: [String: Any] = ["fileIds": fileIds]
        let json = try await executeJSON(
            url: GuangYaConstants.DELETE_FILE,
            method: "POST",
            headers: businessHeaders(device: nil, token: accessToken),
            body: body
        )
        try checkBusiness(json, fallback: "删除失败")
        if let taskId = dataOf(json)?.string("taskId"), !gyIsBlank(taskId) {
            try await waitTask(accessToken, taskId)
        }
    }

    /// 个人盘取下载地址（文档 §5.6）。
    func getDownloadLink(_ accessToken: String, file: ShareFile) async throws -> DownloadLink? {
        let body: [String: Any] = ["fileId": file.fid]
        let json = try await executeJSON(
            url: GuangYaConstants.RES_DOWNLOAD,
            method: "POST",
            headers: businessHeaders(device: nil, token: accessToken),
            body: body
        )
        try checkBusiness(json, fallback: "获取下载地址失败")
        guard let data = dataOf(json) else { return nil }
        let url = gyFirstNonBlank(
            data.string("signedURL"), data.string("signedUrl"), data.string("downloadUrl"),
            data.string("download_url"), data.string("url"), data.string("cdnUrl")
        )
        if url.isEmpty {
            throw ApiError("光鸭未返回有效下载地址，请确认下载权限")
        }
        let size = Int64(data.string("size")) ?? file.fsize
        return DownloadLink(fid: file.fid, filename: file.fname, downloadUrl: url, size: size)
    }

    /// 任务状态轮询（文档 §5.7）：status 2 且 detail.code 0 = 成功。
    func waitTask(_ accessToken: String, _ taskId: String) async throws {
        await gyDelay(GuangYaConstants.TASK_DELAY_MS)
        for _ in 0..<GuangYaConstants.TASK_MAX_POLLS {
            let body: [String: Any] = ["taskId": taskId]
            let json = try await executeJSON(
                url: GuangYaConstants.TASK_STATUS,
                method: "POST",
                headers: businessHeaders(device: nil, token: accessToken),
                body: body
            )
            try checkBusiness(json, fallback: "任务状态查询失败")
            guard let data = dataOf(json) else {
                // 对应 Kotlin return@repeat：直接进入下一次轮询（不额外延时）
                continue
            }
            let status = data.int("status")
            let detail = data.object("detail")
            let detailCode = detail.int("code")
            if status == 2 && detailCode == 0 { return }
            if status == 3 || (status == 2 && detailCode != 0) {
                let msg = detail.string("msg")
                throw ApiError(gyIsBlank(msg) ? "光鸭操作失败" : msg)
            }
            await gyDelay(GuangYaConstants.TASK_DELAY_MS)
        }
        throw ApiError("光鸭操作仍在处理中，请稍后刷新列表确认结果")
    }

    // ---------- 内部 ----------

    /// 账号规范化为接口要求的形态：11 位手机号 → "+86 xxx"；带 +86 前缀去空格（文档 §2.5）。
    func normalizeAccount(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }
        let digits = s.filter { $0.isNumber }
        if s.hasPrefix("+86") {
            var rest = digits
            if rest.hasPrefix("86") { rest = String(rest.dropFirst(2)) }
            return "+86 " + rest
        }
        if s.count == 11 && s.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return "+86 " + s
        }
        return s
    }

    /// 校验短信验证码格式 ^[0-9]{4,8}$（不使用正则字面量）
    private func isValidSmsCode(_ code: String) -> Bool {
        guard code.count >= 4, code.count <= 8 else { return false }
        return code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private func metaFor(_ account: String) -> [String: Any] {
        if account.hasPrefix("+") { return ["phone_number": account] }
        if account.contains("@") { return ["email": account] }
        return ["username": account]
    }

    private func parseTokens(_ json: JSONValue) throws -> GuangYaTokens {
        let data = gyObjectOrNil(json, "data") ?? json
        let access = gyFirstNonBlank(data.string("access_token"), data.string("accessToken"))
        if access.isEmpty {
            throw ApiError("光鸭登录失败，请检查账号密码，或切换网页登录")
        }
        let refresh = gyFirstNonBlank(data.string("refresh_token"), data.string("refreshToken"))
        return GuangYaTokens(accessToken: access, refreshToken: refresh, expiresIn: expiresInSeconds(data))
    }

    /// 令牌有效期（秒）：优先 expires_in；否则用绝对时间 expire_time/expires_at 反推（毫秒或秒都兼容）。
    private func expiresInSeconds(_ data: JSONValue) -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let direct = data.long("expires_in")
        if direct > 0 { return min(direct, 31_536_000) }
        let absolute: Int64
        if data.has("expire_time") {
            absolute = data.long("expire_time")
        } else if data.has("expires_at") {
            absolute = data.long("expires_at")
        } else {
            return 0
        }
        if absolute <= 0 { return 0 }
        // > 1e12 视为毫秒绝对时间，否则视为秒绝对时间
        let millis = absolute > 1_000_000_000_000 ? absolute : absolute * 1000
        return min(max((millis - now) / 1000, 0), 31_536_000)
    }

    private func accountString(_ json: JSONValue, _ key: String) -> String {
        if let node = gyObjectOrNil(json, "data") {
            let nested = node.string(key)
            if !nested.isEmpty { return nested }
            return json.string(key)
        }
        return json.string(key)
    }

    private func accountBoolean(_ json: JSONValue, _ key: String) -> Bool {
        if let node = gyObjectOrNil(json, "data") {
            return node.has(key) ? node.bool(key) : json.bool(key)
        }
        return json.bool(key)
    }

    private func accountInt(_ json: JSONValue, _ key: String, _ defaultValue: Int) -> Int {
        if let node = gyObjectOrNil(json, "data") {
            if let v = Int(node.string(key)) { return v }
            if let v = Int(json.string(key)) { return v }
            return defaultValue
        }
        if let v = Int(json.string(key)) { return v }
        return defaultValue
    }

    /// 账号 API 成功判定；失败时把验证码类错误映射为文档 §10 的文案。
    private func ensureAccountSuccess(_ json: JSONValue, fallback: String) throws {
        if isSuccess(json) { return }
        let codeRaw = json.string("code")
        let code = codeRaw.isEmpty ? json.string("error") : codeRaw
        let serverMsg = gyFirstNonBlank(json.string("msg"), json.string("message"), json.string("error_description"))
        let lowerCode = code.lowercased()
        let lowerMsg = serverMsg.lowercased()
        let mapped: String
        if lowerMsg.contains("captcha") || lowerCode.contains("captcha") {
            mapped = "光鸭安全验证未通过，请重试或改用账号密码登录"
        } else if lowerCode.contains("frequent") || code == "429" || serverMsg.contains("频繁") {
            mapped = "验证码请求过于频繁，请稍后重试"
        } else if lowerCode.contains("verification") || lowerCode.contains("code") || serverMsg.contains("验证码") {
            mapped = "短信验证码错误或已过期，请重新获取"
        } else {
            mapped = serverMsg.isEmpty ? fallback : serverMsg
        }
        throw ApiError(mapped)
    }

    private func mapSigninError(_ json: JSONValue, _ error: String) -> String {
        let codeRaw = json.string("code")
        let code = codeRaw.isEmpty ? error : codeRaw
        let serverMsg = gyFirstNonBlank(json.string("msg"), json.string("message"), json.string("error_description"))
        switch code {
        case "too_many_requests":
            return "光鸭登录尝试过于频繁，请稍后重试"
        case "invalid_password", "invalid_account_or_password", "invalid_credentials", "unauthenticated", "user_not_found":
            return "光鸭账号或密码不正确，请检查后重试"
        case "password_required", "password_not_set":
            return "该光鸭账号尚未设置密码，请切换网页登录"
        case "verification_required", "verification_code_required":
            return "光鸭需要短信验证，请切换网页登录继续"
        default:
            return serverMsg.isEmpty ? "光鸭登录失败，请检查账号密码，或切换网页登录" : serverMsg
        }
    }

    /// 列出阵列字段：不同接口/版本用 list / items / files / records / content 等多种命名。
    private func listArray(_ data: JSONValue) -> [JSONValue]? {
        for key in ["list", "items", "files", "records", "content"] {
            if let arr = gyArrayOrNil(data, key) { return arr }
        }
        return nil
    }

    private func parseFileList(_ arr: [JSONValue]?) -> [ShareFile] {
        guard let arr else { return [] }
        return arr.compactMap { item in
            guard item.raw is [String: Any] else { return nil }
            return parseFile(item)
        }
    }

    private func parseFile(_ item: JSONValue) -> ShareFile {
        let fid = gyFirstNonBlank(
            item.string("fileId"), item.string("file_id"), item.string("id"),
            item.string("resId"), item.string("resourceId")
        )
        let name = gyFirstNonBlank(
            item.string("fileName"), item.string("name"), item.string("filename"),
            item.string("dirName"), item.string("title")
        )
        let size = Int64(gyFirstNonBlank(item.string("fileSize"), item.string("size"), item.string("file_size"))) ?? 0
        let resType = item.string("resType")
        let dirType = item.string("dirType")
        let isDir: Bool
        switch resType {
        case "2":
            isDir = true
        case "1":
            isDir = false
        default:
            let type = item.string("type").lowercased()
            let fileType = item.string("fileType").lowercased()
            let typeSet: Set<String> = ["folder", "dir", "directory", "0"]
            isDir = item.bool("isDir") || item.bool("isdir") || item.bool("dir") ||
                item.bool("isFolder") || item.bool("folder") ||
                !item.string("dirName").isEmpty ||
                typeSet.contains(type) ||
                typeSet.contains(fileType) ||
                (!name.contains(".") && dirType == "1")
        }
        let parent = gyFirstNonBlank(item.string("parentId"), item.string("parentFileId"), item.string("parent_id"))
        let time = gyFirstNonBlank(
            item.string("updatedAt"), item.string("updateAt"), item.string("updated_at"),
            item.string("updateTime"), item.string("mtime"), item.string("utime"),
            item.string("createdAt"), item.string("createTime"), item.string("ctime")
        )
        return ShareFile(fid: fid, fname: name, fsize: size, isdir: isDir, pdirFid: parent, fidToken: "", modifyTime: time)
    }

    private func checkBusiness(_ json: JSONValue, fallback: String) throws {
        if isSuccess(json) { return }
        let code = json.string("code")
        let serverMsg = gyFirstNonBlank(json.string("msg"), json.string("message"), json.string("error_description"))
        let mapped: String?
        switch code {
        case "209":
            mapped = "光鸭分享提取码错误或缺失"
        case "200", "201", "202":
            mapped = "光鸭分享已取消、过期或不可访问"
        case "205", "206", "207", "504":
            mapped = "光鸭分享下载受限，请在官网确认该分享的下载权限"
        case "157":
            mapped = "光鸭网盘空间不足"
        default:
            mapped = nil
        }
        if let mapped {
            throw ApiError(mapped)
        }
        throw ApiError(serverMsg.isEmpty ? "\(fallback)（code=\(code)）" : serverMsg)
    }

    private func isSuccess(_ json: JSONValue) -> Bool {
        if json.has("success") && !json.bool("success") { return false }
        if !json.string("error").isEmpty { return false }
        let code = json.string("code")
        return code.isEmpty || code == "0"
    }

    private func dataOf(_ json: JSONValue) -> JSONValue? {
        gyObjectOrNil(json, "data")
    }

    /// 业务 API 请求头（文档 §1.3）：did/dt/traceparent 必备。
    private func businessHeaders(device: GuangYaDevice?, token: String?) -> [String: String] {
        var headers: [String: String] = [
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json;charset=UTF-8",
            "User-Agent": GuangYaConstants.WEB_UA,
            "Origin": GuangYaConstants.WEB_SITE,
            "Referer": GuangYaConstants.DOWNLOAD_REFERER,
            "dt": "4",
            "traceparent": GuangYaConstants.newTraceparent(),
        ]
        // did 为业务 API 必需设备头：登录设备优先，其次上层注入，最后匿名兜底设备
        let did = device?.deviceId ?? deviceIdProvider() ?? publicDeviceId
        if !did.isEmpty { headers["did"] = did }
        if let token, !token.isEmpty { headers["Authorization"] = "Bearer \(token)" }
        return headers
    }

    /// 账号 API 请求头（文档 §1.3）：一整套 X-Device-*。
    private func accountHeaders(device: GuangYaDevice, token: String?) -> [String: String] {
        let deviceId = GuangYaConstants.deviceIdFromSign(device.deviceSign, fallback: device.deviceId)
        var headers: [String: String] = [
            "X-Client-Id": GuangYaConstants.CLIENT_ID,
            "X-Client-Version": GuangYaConstants.CLIENT_VERSION,
            // 参考实现（wenxi guangya_login.dart）：X-Device-Id / X-Device-Sign 需 URL 编码
            "X-Device-Id": urlEncode(deviceId),
            "X-Device-Model": GuangYaConstants.DEVICE_MODEL,
            "X-Device-Name": GuangYaConstants.DEVICE_NAME,
            "X-Device-Sign": urlEncode(device.deviceSign),
            "X-Os-Version": GuangYaConstants.OS_VERSION,
            "X-Platform-Version": GuangYaConstants.PLATFORM_VERSION,
            "X-Protocol-Version": GuangYaConstants.PROTOCOL_VERSION,
            "X-Sdk-Version": GuangYaConstants.SDK_VERSION,
            "Accept": "application/json, text/plain, */*",
            "User-Agent": GuangYaConstants.WEB_UA,
        ]
        if let token, !token.isEmpty { headers["Authorization"] = "Bearer \(token)" }
        return headers
    }

    /// 执行请求并解析 JSON（body 为 nil 时走 GET；否则 POST JSON）。
    private func executeJSON(
        url: String,
        method: String,
        headers: [String: String],
        body: [String: Any]?
    ) async throws -> JSONValue {
        let response: HTTPResponse
        if method == "GET" {
            response = try await client.get(url, headers: headers)
        } else {
            response = try await client.postJSON(url, headers: headers, body: body ?? [:])
        }
        let text = response.text
        if gyIsBlank(text) {
            if !response.isSuccessful {
                throw ApiError("请求失败（HTTP \(response.statusCode)）")
            }
            throw ApiError("请求失败：响应为空")
        }
        guard let json = JSONValue.parse(response.body) else {
            throw ApiError("响应解析失败")
        }
        return json
    }
}

// MARK: - 光鸭云盘分享解析仓库（对应 GuangYaResolveRepository.kt）

/// 光鸭云盘分享解析仓库（文档 §4）：
/// 摘要取标题 → 提取码换分享访问令牌（存 session.stoken）→ 游标翻页列目录 → 分享取下载地址；
/// 转存走 restore_share（需登录态 access token，由调用方以 cookie 参数传入）。
/// 分享列目录与取链本身匿名可用（业务 API 公共头，无 Authorization）。
final class GuangYaResolveRepository: ShareResolveRepository {

    private let api: GuangYaApi

    /// 账号 access token 提供者（对应 Kotlin 构造参数 tokenProvider）。
    /// 由账号仓库在启动时注入；未登录返回 nil。`api.deviceIdProvider` 亦可在外部注入设备 id。
    var tokenProvider: (() async -> String?)?

    init() {
        self.api = GuangYaApi()
    }

    /// 允许外部注入 did 设备头（对应 Kotlin api.deviceIdProvider 的注入）
    func setDeviceIdProvider(_ provider: @escaping () -> String?) {
        api.deviceIdProvider = provider
    }

    // MARK: ShareResolveRepository

    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        guard let parsed = ShareLinkParser.parse(link) else {
            throw ApiError("无法识别分享链接")
        }
        // pwd?.takeIf { it.isNotBlank() } ?: parsed.pwd.orEmpty()
        let pwdTakeIf: String? = pwd.flatMap { gyIsBlank($0) ? nil : $0 }
        let sharePwd = pwdTakeIf ?? parsed.pwd ?? ""
        let accessToken = try await api.getShareAccessToken(parsed.shareId, code: sharePwd)
        let title = (try? await api.getShareSummary(parsed.shareId)) ?? "光鸭分享"
        return ShareSession(shareId: parsed.shareId, stoken: accessToken, title: title)
    }

    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        var all: [ShareFile] = []
        var seen = Set<String>()
        var cursor: String? = nil
        var page = 0
        repeat {
            let (files, next) = try await api.listShareFiles(accessToken: session.stoken, parentId: dirFid, cursor: cursor)
            for file in files where seen.insert(file.fid).inserted {
                all.append(file)
            }
            cursor = next
            page += 1
        } while cursor != nil && page < 1000
        return all
    }

    func ensureTempDir(cookie: String) async throws -> String {
        throw ApiError("光鸭分享无需预建临时目录")
    }

    func transferFile(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        // cookie.ifBlank { tokenProvider() ?: "" }
        var token = cookie
        if gyIsBlank(token) {
            if let provider = tokenProvider, let provided = await provider() {
                token = provided
            } else {
                token = ""
            }
        }
        if gyIsBlank(token) { throw ApiError("请先登录光鸭云盘") }
        // body 用分享访问令牌，Authorization 用账号 token
        try await api.restoreShare(
            accountToken: token,
            shareToken: session.stoken,
            fileIds: [file.fid],
            parentId: gyIsBlank(toDirFid) ? "" : toDirFid
        )
        return toDirFid
    }

    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        throw ApiError("光鸭分享请使用 getShareDownloadLink")
    }

    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        do {
            if let link = try await api.getShareDownloadUrl(file: file, accessToken: session.stoken) {
                return link
            }
            throw ApiError("光鸭未返回有效下载地址，请确认下载权限")
        } catch is GuangYaShareRestrictedError {
            // 分享者未开启免登录下载：已登录则转存到临时目录再从个人盘取链
            return try await transferAndDownload(session: session, file: file, cookie: cookie)
        }
    }

    func getGuestShareDownloadLink(session: ShareSession, file: ShareFile) async throws -> DownloadLink {
        do {
            if let link = try await api.getShareDownloadUrl(file: file, accessToken: session.stoken) {
                return link
            }
            throw ApiError("光鸭未返回有效下载地址，请确认下载权限")
        } catch is GuangYaShareRestrictedError {
            throw ApiError("该光鸭分享需登录并转存后下载，请先登录光鸭云盘")
        }
    }

    func cleanupTempDir(dirFid: String, cookie: String) async {
        if gyIsBlank(dirFid) { return }
        // cookie.takeIf { it.isNotBlank() } ?: tokenProvider() ?: return
        let token: String?
        if !gyIsBlank(cookie) {
            token = cookie
        } else if let provider = tokenProvider {
            token = await provider()
        } else {
            token = nil
        }
        guard let token else { return }
        _ = try? await api.deleteFiles(token, fileIds: [dirFid])
    }

    // MARK: - 受限分享下载

    /// 受限分享下载：在个人盘根目录建临时目录 → restore_share 转存 → 轮询目标文件 →
    /// 用转存后的文件 ID 取个人盘直链，并把临时目录 id 作为 cleanupDirFid 交给下载完成时清理。
    private func transferAndDownload(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        // cookie.takeIf { it.isNotBlank() } ?: tokenProvider() ?: throw
        let token: String
        if !gyIsBlank(cookie) {
            token = cookie
        } else if let provider = tokenProvider, let provided = await provider() {
            token = provided
        } else {
            throw ApiError("请先登录光鸭云盘")
        }
        // 名称规则与参考实现一致，便于识别与清理
        let folderName = "AsterLink临时转存_\(UUID().uuidString)"
        let folderId = try await api.createDir(token, parentId: "", name: folderName)
        do {
            try await api.restoreShare(accountToken: token, shareToken: session.stoken, fileIds: [file.fid], parentId: folderId)
            let target = try await pollCopiedFile(token: token, folderId: folderId, source: file)
            guard let link = try await api.getDownloadLink(token, file: target) else {
                throw ApiError("光鸭未返回有效下载地址，请确认下载权限")
            }
            return DownloadLink(
                fid: target.fid,
                filename: file.fname,
                downloadUrl: link.downloadUrl,
                size: link.size,
                cleanupDirFid: folderId,
                isHls: link.isHls,
                guestCookie: link.guestCookie
            )
        } catch {
            // 取链/校验失败：清掉刚建的临时目录，避免残留
            _ = try? await api.deleteFiles(token, fileIds: [folderId])
            throw error
        }
    }

    /// 轮询临时目录直到转存完成（同名文件出现），最多 30 次、间隔 taskDelay。
    private func pollCopiedFile(token: String, folderId: String, source: ShareFile) async throws -> ShareFile {
        for _ in 0..<30 {
            await gyDelay(GuangYaConstants.TASK_DELAY_MS)
            let files = (try? await api.listCloudFiles(token, parentId: folderId)) ?? []
            let matches = files.filter { !$0.isdir && $0.fname == source.fname }
            if matches.count > 1 {
                throw ApiError("光鸭临时目录出现同名文件，无法确定下载目标")
            }
            if let target = matches.first {
                if source.fsize > 0 && target.fsize > 0 && source.fsize != target.fsize {
                    throw ApiError("光鸭转存文件大小不一致")
                }
                return target
            }
        }
        throw ApiError("光鸭转存已提交，目标文件暂不可见，请稍后重试")
    }
}
