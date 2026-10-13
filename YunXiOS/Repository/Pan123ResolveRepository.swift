/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：123 云盘网络接口层与分享解析仓库
 * （对应 data/network/Pan123Api.kt + Pan123Constants.kt + Pan123DeviceId.kt
 *   + Pan123LoginSupport.kt + data/repository/Pan123ResolveRepository.kt）。
 *
 * 硬性约束：仅 import Foundation；不使用 Swift Regex 字面量；JSON body 用 [String: Any]。
 */

import Foundation

// MARK: - 123 常量（对应 Pan123Constants.kt）

enum Pan123Constants {

    // ---------- BaseURL（按用途） ----------

    /// 个人盘业务 API / 分享列表（主域式）
    static let API_BASE = "https://yun.123pan.cn"

    /// 分享下载信息（抓包实证）
    static let DOWNLOAD_BASE = "https://www.123865.com"

    // ---------- API 路径（严格按文档，不自行加/去 /b） ----------

    /// 网页登录页
    static let WEB_LOGIN_URL = "https://yun.123pan.cn/"

    /// 账号密码登录（原生接口，域名与个人盘 API 不同站）
    static let SIGN_IN_URL = "https://user.123pan.cn/api/user/sign_in"

    /// 账号密码登录的 Origin / Referer（缺了会被风控拒绝）
    static let SIGN_IN_ORIGIN = "https://user.123pan.cn"
    static let SIGN_IN_REFERER = "https://user.123pan.cn/"

    /// 账号密码登录专用 app-version（网页端是 3，登录接口要 132）
    static let APP_VERSION_SIGN_IN = "132"

    /// 网页登录态在 localStorage 中的键名
    static let LOCAL_STORAGE_TOKEN_KEY = "authorToken"

    /// 分享文件列表（GET /b/api/share/get，匿名、无签名）
    static let SHARE_GET_URL = API_BASE + "/b/api/share/get"

    /// 分享下载信息（POST /b/api/share/download/info，需登录+签名）
    static let SHARE_DOWNLOAD_INFO_URL = DOWNLOAD_BASE + "/b/api/share/download/info"

    /// 个人盘文件列表（GET /b/api/file/list/new，需登录+签名）
    static let FILE_LIST_URL = API_BASE + "/b/api/file/list/new"

    /// 个人盘下载信息（POST /api/file/download_info，注意无 /b/）
    static let FILE_DOWNLOAD_INFO_URL = API_BASE + "/api/file/download_info"

    /// 流量校验
    static let TRAFFIC_CHECK_URL = API_BASE + "/b/api/file/download/traffic/check"

    /// 删除/移入回收站
    static let FILE_TRASH_URL = API_BASE + "/b/api/file/trash"

    /// 重命名
    static let FILE_RENAME_URL = API_BASE + "/b/api/file/rename"

    /// 移动
    static let FILE_MOD_PID_URL = API_BASE + "/b/api/file/mod_pid"

    /// 新建文件夹 / 上传预创建（type=1 建目录、0 文件）
    static let FILE_UPLOAD_REQUEST_URL = API_BASE + "/b/api/file/upload_request"

    /// 创建分享
    static let SHARE_CREATE_URL = API_BASE + "/b/api/share/create"

    /// 用户信息（校验登录态/取昵称/容量）
    static let USER_INFO_URL = API_BASE + "/b/api/user/info"

    // ---------- 公共请求头 ----------

    /// 浏览器 UA
    static let WEB_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"

    /// Dart UA（分享列表匿名请求）
    static let DART_UA = "Dart/3.12 (dart:io)"

    /// platform：web
    static let PLATFORM_WEB = "web"

    /// platform：android
    static let PLATFORM_ANDROID = "android"

    /// app-version：web 系
    static let APP_VERSION_WEB = "3"

    /// app-version：android 系（仅分享下载）
    static let APP_VERSION_ANDROID = "39"

    /// 下载真实 CDN 直链时必须携带的 Referer
    static let DOWNLOAD_REFERER = "https://yun.123pan.cn/"

    // ---------- 签名算法常量 ----------

    /// 数字 0-9 的替换表，索引 = 数字值
    static let SIGN_TABLE = "adefghlmyijnopkqrstubcvwsz"

    /// 签名内部固定 OS
    static let SIGN_OS = "web"

    /// 签名内部固定 VER
    static let SIGN_VER = "3"

    /// timeSign 时间基准偏移：ts + 57600 秒（+16h）
    static let SIGN_OFFSET_SECONDS: Int64 = 57600

    /// 永久分享的过期时间
    static let EXPIRATION_FOREVER = "2099-12-12T08:00:00+08:00"

    /// 生成 32 位十六进制 loginuuid
    static func newLoginUuid() -> String {
        let chars = Array("0123456789abcdef")
        var result = ""
        result.reserveCapacity(32)
        for _ in 0..<32 {
            result.append(chars[Int.random(in: 0..<chars.count)])
        }
        return result
    }
}

// MARK: - 设备标识（对应 Pan123DeviceId.kt）

/// 123 云盘的设备标识（`loginuuid` 请求头，32 位十六进制）。
///
/// Android 原实现用 SharedPreferences 持久化（同一设备长期不变、参与风控判断）。
/// iOS 无可用且稳定的 Android 专有指纹，这里用一个本地生成的持久 32 位十六进制
/// 随机串替代，首次生成后写入 UserDefaults 长期复用，语义与 Android 侧一致：
/// 生成一次即固定，避免每次启动都换新值被服务端当成新设备。
enum Pan123DeviceId {

    private static let prefsKey = "pan123_device_login_uuid"
    private static let lock = NSLock()
    private static var cached: String?

    /// 当前设备标识；未落盘时生成并持久化一个（幂等）
    static func value() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cached { return cached }
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: prefsKey), isHex32(saved) {
            cached = saved
            return saved
        }
        let uuid = Pan123Constants.newLoginUuid()
        defaults.set(uuid, forKey: prefsKey)
        cached = uuid
        return uuid
    }

    /// 是否为 32 位十六进制（不用 Regex 字面量，逐字符判断）
    private static func isHex32(_ value: String) -> Bool {
        guard value.count == 32 else { return false }
        return value.allSatisfy { ch in
            ("0"..."9").contains(ch) || ("a"..."f").contains(ch) || ("A"..."F").contains(ch)
        }
    }
}

// MARK: - 登录结果与登录纯逻辑（对应 Pan123LoginSupport.kt）

/// 123 账号密码登录结果
enum Pan123LoginResult {
    case success(String)
    case failure(String)
}

/// 123 云盘登录的纯逻辑（错误映射 + 令牌校验）
enum Pan123LoginSupport {

    static let MESSAGE_TOO_FREQUENT = "123 登录请求过于频繁，请稍后重试"
    static let MESSAGE_FALLBACK = "123 登录失败，请检查账号和密码后重试"
    static let MESSAGE_VERIFY_REQUIRED = "123 要求额外安全验证，请改用网页登录完成验证"

    /// 把登录失败的响应翻译成一句能给用户看的中文（绝不回显服务端原文）
    static func describeFailure(httpStatus: Int, code: Int, serverMessage: String) -> String {
        let message = serverMessage.lowercased()
        if (300...399).contains(httpStatus) { return "123 登录接口发生变化，请稍后重试" }
        if httpStatus == 429 { return MESSAGE_TOO_FREQUENT }
        if httpStatus >= 500 { return "123 登录服务暂时不可用，请稍后重试" }
        if code == 429 { return MESSAGE_TOO_FREQUENT }
        if fiftyPlusKeywords.contains(where: { message.contains($0) }) { return MESSAGE_TOO_FREQUENT }
        if verifyKeywords.contains(where: { message.contains($0) }) { return MESSAGE_VERIFY_REQUIRED }
        if frozenKeywords.contains(where: { message.contains($0) }) {
            return "123 账号暂时不可登录，请先在官方客户端检查账号状态"
        }
        return MESSAGE_FALLBACK
    }

    /// 登录返回的令牌是否可用：非空、长度合理、不含控制字符
    static func isValidToken(_ value: String) -> Bool {
        if value.isEmpty { return false }
        if value.count > 16384 { return false }
        let hasControl = value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
        return !hasControl
    }

    private static let fiftyPlusKeywords = ["频繁", "频率", "次数", "稍后"]
    private static let verifyKeywords = ["验证码", "滑块", "安全验证", "验证失败", "captcha", "verify"]
    private static let frozenKeywords = ["冻结", "封禁", "封停", "注销", "禁用"]
}

// MARK: - 文件级小工具

/// Kotlin `isBlank()` 等价：空串或全为空白字符
private func pan123IsBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// 宽松 Base64 解码（Android Base64.DEFAULT 容忍缺失的 padding 与换行）
private func pan123Base64Decode(_ value: String) -> String? {
    var str = value.trimmingCharacters(in: .whitespacesAndNewlines)
    // 去掉可能存在的换行
    str = str.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
    let mod = str.count % 4
    if mod > 0 { str += String(repeating: "=", count: 4 - mod) }
    guard let data = Data(base64Encoded: str) else { return nil }
    return String(data: data, encoding: .utf8)
}

// MARK: - 123 云盘 API（对应 Pan123Api.kt）

final class Pan123Api {

    /// 设备标识（同设备长期不变、不参与签名）
    private let loginuuid: String = Pan123DeviceId.value()

    // ---------- 签名算法 ----------

    /// 标准 CRC-32（IEEE 802.3）→ 小写十六进制（与 Kotlin toHexString 一致，不补零）
    private func crc32Hex(_ s: String) -> String {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in s.utf8 {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        crc ^= 0xFFFFFFFF
        return String(crc, radix: 16)
    }

    /// 生成 123 云盘签名头：auth-key (timeSign) 与 auth-value。
    /// @param path URL 路径：含 /b 前缀、不含 host、不含 query。
    func makeSign(path: String, ts: Int64? = nil) -> (authKey: String, authValue: String) {
        let now = ts ?? Int64(Date().timeIntervalSince1970)
        // ts + 16h 以 UTC 格式化为 YYYYMMDDHHmm
        let date = Date(timeIntervalSince1970: TimeInterval(now + Pan123Constants.SIGN_OFFSET_SECONDS))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmm"
        let minute = formatter.string(from: date)

        let table = Array(Pan123Constants.SIGN_TABLE)
        var substituted = ""
        for ch in minute {
            guard let digit = ch.wholeNumberValue, digit >= 0, digit < table.count else { continue }
            substituted.append(table[digit])
        }
        let authKey = crc32Hex(substituted)

        // auth-value = "<ts>-<random>-<crc32_hex(ts|random|path|web|3|auth_key)>"
        let random = Int.random(in: 0..<10_000_000)
        let data = "\(now)|\(random)|\(path)|\(Pan123Constants.SIGN_OS)|\(Pan123Constants.SIGN_VER)|\(authKey)"
        let authValue = "\(now)-\(random)-\(crc32Hex(data))"
        return (authKey, authValue)
    }

    // ---------- 账号密码登录 ----------

    /// 账号密码登录：POST sign_in → data.token（authorToken）。成功判定是 code == 200。
    func passwordLogin(account: String, password: String) async -> Pan123LoginResult {
        let passport = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if passport.isEmpty || password.isEmpty {
            return .failure("请输入账号和密码")
        }
        if passport.count > 254 || password.count > 256 {
            return .failure("账号或密码过长")
        }
        let body: [String: Any] = [
            "passport": passport,
            "password": password,
            "remember": false,
        ]
        let headers: [String: String] = [
            "platform": Pan123Constants.PLATFORM_WEB,
            "app-version": Pan123Constants.APP_VERSION_SIGN_IN,
            "loginuuid": loginuuid,
            "Origin": Pan123Constants.SIGN_IN_ORIGIN,
            "Referer": Pan123Constants.SIGN_IN_REFERER,
            "User-Agent": Pan123Constants.WEB_UA,
            "Content-Type": "application/json; charset=utf-8",
        ]
        do {
            let response = try await HTTPClient.api.postJSON(Pan123Constants.SIGN_IN_URL, headers: headers, body: body)
            let json = JSONValue.parse(response.text)
            let code = (json?.has("code") ?? false) ? json!.int("code") : -1
            let token = json?.object("data").string("token") ?? ""
            if response.isSuccessful && code == 200 && Pan123LoginSupport.isValidToken(token) {
                return .success(token)
            }
            return .failure(
                Pan123LoginSupport.describeFailure(
                    httpStatus: response.statusCode,
                    code: code,
                    serverMessage: json?.string("message") ?? ""
                )
            )
        } catch {
            return .failure("网络异常，无法连接 123 登录服务，请稍后重试")
        }
    }

    // ---------- 用户信息 ----------

    /// 校验登录态 + 取昵称：GET /b/api/user/info → data.Nickname；失败返回 nil
    func fetchNickname(token: String) async -> String? {
        do {
            let json = try await getAuth(Pan123Constants.USER_INFO_URL, path: "/b/api/user/info", token: token)
            try checkOk(json, "获取用户信息失败")
            let nickname = json.object("data").string("Nickname")
            return pan123IsBlank(nickname) ? nil : nickname
        } catch {
            return nil
        }
    }

    /// 网盘空间详情：SpaceUsed / SpacePermanent / SpaceTemp
    func getQuota(token: String) async -> QuotaInfo? {
        do {
            let json = try await getAuth(Pan123Constants.USER_INFO_URL, path: "/b/api/user/info", token: token)
            try checkOk(json, "获取空间详情失败")
            let data = json.object("data")
            if data.isNull { return nil }
            return QuotaInfo(
                used: data.long("SpaceUsed"),
                total: data.long("SpacePermanent") + data.long("SpaceTemp")
            )
        } catch {
            return nil
        }
    }

    // ---------- 分享文件列表（匿名、无签名） ----------

    /// 读取分享文件/目录列表（匿名），支持提取码、翻页、进入子目录。
    /// 返回 (文件列表, 下一页游标 or nil=末页)；Next == "-1" 无下一页，空串表示还有下一页。
    func getShareFiles(
        shareKey: String,
        sharePwd: String,
        parentFileId: String,
        next: String,
        page: Int
    ) async throws -> (files: [ShareFile], next: String?) {
        // 参数顺序与抓包一致；无提取码时不传 SharePwd
        var url = Pan123Constants.SHARE_GET_URL
        url += "?limit=100"
        url += "&next=\(next)"
        url += "&orderBy=file_name"
        url += "&orderDirection=asc"
        url += "&shareKey=\(urlEncode(shareKey))"
        url += "&ParentFileId=\(parentFileId)"
        url += "&Page=\(page)"
        if !pan123IsBlank(sharePwd) {
            url += "&SharePwd=\(urlEncode(sharePwd))"
        }
        let json = try await execute(
            url: url,
            method: "GET",
            headers: ["User-Agent": Pan123Constants.DART_UA],
            body: nil
        )
        try checkOk(json, "获取文件列表失败")
        let data = json.object("data")
        if data.isNull { return ([], nil) }
        if data.bool("Expired") {
            throw ApiError("分享已失效")
        }
        let files = parseInfoList(data)
        let nextRaw = data.string("Next")
        return (files, nextRaw == "-1" ? nil : nextRaw)
    }

    // ---------- 分享下载信息（需登录+签名） ----------

    /// 分享文件取下载直链（POST /b/api/share/download/info）。
    func getShareDownloadLink(
        shareKey: String,
        file: ShareFile,
        token: String
    ) async throws -> DownloadLink? {
        let token3 = decodeToken(file.fidToken)
        let body: [String: Any] = [
            "ShareKey": shareKey,
            "FileID": file.fid,
            "S3KeyFlag": token3.s3KeyFlag,
            "Size": file.fsize,
            "Etag": token3.etag,
        ]
        let json = try await postAuth(
            Pan123Constants.SHARE_DOWNLOAD_INFO_URL,
            path: "/b/api/share/download/info",
            body: body,
            token: token,
            platform: Pan123Constants.PLATFORM_ANDROID,
            appVersion: Pan123Constants.APP_VERSION_ANDROID
        )
        try checkOk(json, "获取下载链接失败")
        let data = json.object("data")
        if data.isNull { return nil }
        let downloadUrl = data.string("DownloadURL")
        if pan123IsBlank(downloadUrl) { return nil }
        let decoded = decodeDownloadUrl(downloadUrl) ?? downloadUrl
        let realUrl = await followRedirectUrl(decoded)
        return DownloadLink(
            fid: file.fid,
            filename: file.fname,
            downloadUrl: realUrl,
            size: file.fsize
        )
    }

    // ---------- 个人盘（需登录+签名） ----------

    /// 单页个人盘文件：GET /b/api/file/list/new
    private func fetchCloudPage(
        parentFileId: String,
        token: String,
        next: String
    ) async throws -> (files: [ShareFile], next: String?)? {
        var url = Pan123Constants.FILE_LIST_URL
        url += "?driveId=0&limit=100&next=\(next)"
        url += "&orderBy=update_time&orderDirection=desc"
        url += "&parentFileId=\(parentFileId)"
        url += "&trashed=false&SearchData=&Page=1&OnlyLookAbnormalFile=0"
        url += "&event=homeListFile&operateType=1&inDirectSpace=false"
        let json = try await getAuth(url, path: "/b/api/file/list/new", token: token)
        try checkOk(json, "获取文件列表失败")
        let data = json.object("data")
        if data.isNull { return nil }
        let files = parseInfoList(data)
        let nextRaw = data.string("Next")
        return (files, nextRaw == "-1" ? nil : nextRaw)
    }

    /// 个人盘文件列表：自动翻页，返回该目录下全部文件
    func listCloudFiles(parentFileId: String, token: String) async throws -> [ShareFile] {
        var all: [ShareFile] = []
        var next = "0"
        for _ in 0..<200 { // 封顶 200 页，防异常死循环
            guard let page = try await fetchCloudPage(parentFileId: parentFileId, token: token, next: next) else {
                return all
            }
            all += page.files
            guard let cursor = page.next else { return all }
            next = cursor
        }
        return all
    }

    /// 个人盘下载信息：POST /api/file/download_info（注意无 /b/）
    func getDownloadLink(file: ShareFile, token: String) async throws -> DownloadLink? {
        let token3 = decodeToken(file.fidToken)
        let body: [String: Any] = [
            "driveId": 0,
            "etag": token3.etag,
            "fileId": Int64(file.fid) ?? 0,
            "s3keyFlag": token3.s3KeyFlag,
            "type": 0,
            "fileName": file.fname,
            "size": file.fsize,
        ]
        let json = try await postAuth(
            Pan123Constants.FILE_DOWNLOAD_INFO_URL,
            path: "/api/file/download_info",
            body: body,
            token: token
        )
        try checkOk(json, "获取下载链接失败")
        let data = json.object("data")
        if data.isNull { return nil }
        let raw = data.string("DownloadUrl")
        if pan123IsBlank(raw) { return nil }
        // 绝不能用 startsWith("http") 短路：中转页 URL 同样以 http 开头
        let decoded = decodeDownloadUrl(raw) ?? raw
        let url = await followRedirectUrl(decoded)
        return DownloadLink(
            fid: file.fid,
            filename: file.fname,
            downloadUrl: url,
            size: file.fsize
        )
    }

    // ---------- 网盘管理操作 ----------

    /// 保存他人分享到个人网盘（copy/save）。mshare 子域无需签名，仅带 Bearer + LoginUuid。
    /// 返回 (taskID, ShareId) 用于轮询 copy/save/get。
    func copySave(
        shareKey: String,
        sharePwd: String,
        file: ShareFile,
        toDirFid: String,
        token: String
    ) async throws -> (taskId: Int64, shareId: String)? {
        let shareId = shareIdOf(file)
        if pan123IsBlank(shareId) {
            throw ApiError("无法识别分享 ID（缺少 S3KeyFlag）")
        }
        let token3 = decodeToken(file.fidToken)
        let fileId = Int64(file.fid) ?? 0
        let parentId = Int64(toDirFid) ?? 0
        let fileItem: [String: Any] = [
            "fileID": fileId,
            "fileId": fileId,
            "size": file.fsize,
            "etag": token3.etag,
            "type": file.isdir ? 1 : 0,
            "parentFileID": parentId,
            "parentFileId": parentId,
            "fileName": file.fname,
            "driveID": 0,
            "driveId": 0,
            "s3keyFlag": token3.s3KeyFlag,
            "S3KeyFlag": token3.s3KeyFlag,
            "StorageNode": token3.storageNode,
        ]
        let body: [String: Any] = [
            "fileList": [fileItem],
            "shareKey": shareKey,
            // 无提取码发空串 ""，不要发 null
            "sharePwd": pan123IsBlank(sharePwd) ? "" : sharePwd,
            "currentLevel": 1,
            "superAdmin": NSNull(),
        ]
        let url = "https://\(shareId).mshare.123pan.cn/b/api/restful/goapi/v1/file/copy/save"
        let headers: [String: String] = [
            "Authorization": "Bearer \(token)",
            "LoginUuid": loginuuid,
            "platform": Pan123Constants.PLATFORM_WEB,
            "Content-Type": "application/json;charset=UTF-8",
            "User-Agent": Pan123Constants.DART_UA,
        ]
        let json = try await execute(url: url, method: "POST", headers: headers, body: body)
        try checkOk(json, "转存失败")
        let data = json.object("data")
        if data.isNull { return nil }
        return (data.long("taskID"), shareId)
    }

    /// 轮询转存任务结果（GET copy/save/get?taskID=，同样无需签名）。
    /// 返回转存成功后的新 fileId；超时返回 nil。
    func pollCopySave(taskId: Int64, shareId: String, token: String) async throws -> String? {
        let url = "https://\(shareId).mshare.123pan.cn/b/api/restful/goapi/v1/file/copy/save/get?taskID=\(taskId)"
        let headers: [String: String] = [
            "Authorization": "Bearer \(token)",
            "LoginUuid": loginuuid,
            "platform": Pan123Constants.PLATFORM_WEB,
            "User-Agent": Pan123Constants.DART_UA,
        ]
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let json = try await execute(url: url, method: "GET", headers: headers, body: nil)
            let code = json.has("code") ? json.int("code") : -1
            if code != 0 {
                // 任务失败/异常：读取 message 抛错（若只是进行中则继续轮询）
                let msg = json.string("message")
                if !pan123IsBlank(msg) {
                    throw ApiError("转存失败：\(msg)")
                }
                continue
            }
            let data = json.object("data")
            if data.isNull { continue }
            // 完成标志（响应格式未完整呈现，容错多种形态）
            let status = data.has("status") ? data.int("status") : -1
            let state = data.string("state").lowercased()
            let done = data.bool("finished")
                || status == 2 || status == 3
                || state == "success" || state == "done" || state == "2"
                || data.has("fileId") || data.has("FileId") || data.has("newFileId")
            if done {
                let candidates = [data.string("newFileId"), data.string("FileId"), data.string("fileId")]
                if let first = candidates.first(where: { !pan123IsBlank($0) }) {
                    return first
                }
                return String(taskId)
            }
        }
        return nil
    }

    /// 从分享列表项提取数值 ShareId（S3KeyFlag 形如 "1816216065-0"，前缀即 mshare 子域数字）
    private func shareIdOf(_ file: ShareFile) -> String {
        let s3 = file.fidToken.components(separatedBy: "|").first ?? ""
        return s3.components(separatedBy: "-").first ?? ""
    }

    /// 删除（移入回收站）：POST /b/api/file/trash
    func deleteFiles(files: [ShareFile], token: String) async throws {
        var list: [[String: Any]] = []
        for f in files {
            let token3 = decodeToken(f.fidToken)
            list.append([
                "FileId": Int64(f.fid) ?? 0,
                "FileName": f.fname,
                "Type": f.isdir ? 1 : 0,
                "Size": f.fsize,
                "S3KeyFlag": token3.s3KeyFlag,
                "Etag": token3.etag,
            ])
        }
        let body: [String: Any] = [
            "driveId": 0,
            "fileTrashInfoList": list,
            "operation": true,
            "event": "intoRecycle",
            "operatePlace": 1,
            "safeBox": false,
        ]
        let json = try await postAuth(
            Pan123Constants.FILE_TRASH_URL,
            path: "/b/api/file/trash",
            body: body,
            token: token
        )
        try checkOk(json, "删除失败")
    }

    /// 重命名：POST /b/api/file/rename
    func renameFile(fileId: String, newName: String, token: String) async throws {
        let body: [String: Any] = [
            "driveId": 0,
            "fileId": Int64(fileId) ?? 0,
            "fileName": newName,
            "duplicate": 1,
            "event": "fileRename",
            "operatePlace": "right",
            "RequestSource": NSNull(),
        ]
        let json = try await postAuth(
            Pan123Constants.FILE_RENAME_URL,
            path: "/b/api/file/rename",
            body: body,
            token: token
        )
        try checkOk(json, "重命名失败")
    }

    /// 新建文件夹：复用上传预创建接口（type=1），返回新文件夹 id
    func createDir(parentFileId: String, name: String, token: String) async throws -> String {
        let body: [String: Any] = [
            "driveId": 0,
            "parentFileId": Int64(parentFileId) ?? 0,
            "fileName": name,
            "size": 0,
            "type": 1,
            "etag": "",
            "duplicate": 1,
            "NotReuse": true,
            "RequestSource": NSNull(),
        ]
        let json = try await postAuth(
            Pan123Constants.FILE_UPLOAD_REQUEST_URL,
            path: "/b/api/file/upload_request",
            body: body,
            token: token
        )
        try checkOk(json, "新建文件夹失败")
        let data = json.object("data")
        if data.isNull { throw ApiError("123 未返回文件夹编号") }
        // 取法：data.Info.FileId → data.FileId → data.fileId
        var id = data.object("Info").string("FileId")
        if pan123IsBlank(id) { id = data.string("FileId") }
        if pan123IsBlank(id) { id = data.string("fileId") }
        if !pan123IsBlank(id) && id != "0" { return id }
        throw ApiError("123 未返回文件夹编号")
    }

    /// 移动：POST /b/api/file/mod_pid
    func moveFiles(fileIds: [String], toParentFileId: String, token: String) async throws {
        let list: [[String: Any]] = fileIds.map { ["FileId": Int64($0) ?? 0] }
        let body: [String: Any] = [
            "fileIdList": list,
            "parentFileId": Int64(toParentFileId) ?? 0,
            "event": "fileMove",
            "operatePlace": 1,
            "RequestSource": NSNull(),
        ]
        let json = try await postAuth(
            Pan123Constants.FILE_MOD_PID_URL,
            path: "/b/api/file/mod_pid",
            body: body,
            token: token
        )
        try checkOk(json, "移动失败")
    }

    /// 创建分享：POST /b/api/share/create
    func createShare(
        fileIds: [String],
        shareName: String,
        expiration: String,
        sharePwd: String?,
        token: String
    ) async throws -> ShareInfo {
        var body: [String: Any] = [
            "driveId": 0,
            "expiration": expiration,
            "shareName": shareName,
            "event": "shareCreate",
            "fileNum": fileIds.count,
            "shareModality": 4,
            "trafficLimitSwitch": 1,
            "trafficLimit": 0,
            "trafficSwitch": 1,
            "fillPwdSwitch": 0,
        ]
        if fileIds.count == 1 {
            body["fileIdList"] = Int64(fileIds[0]) ?? 0
        } else {
            body["fileIdList"] = fileIds.map { Int64($0) ?? 0 }
        }
        if let sharePwd = sharePwd, !pan123IsBlank(sharePwd) {
            body["sharePwd"] = sharePwd
        }
        let json = try await postAuth(
            Pan123Constants.SHARE_CREATE_URL,
            path: "/b/api/share/create",
            body: body,
            token: token
        )
        try checkOk(json, "创建分享失败")
        let data = json.object("data")
        if data.isNull { throw ApiError("创建分享失败：未返回数据") }
        let shareKey = data.string("ShareKey")
        if pan123IsBlank(shareKey) { throw ApiError("创建分享失败：未返回 ShareKey") }
        let linkList = data.object("shareLinkList")
        var shareUrl = linkList.array("list").first?.stringValue ?? ""
        if pan123IsBlank(shareUrl) { shareUrl = linkList.string("standBy") }
        if pan123IsBlank(shareUrl) { shareUrl = "https://www.123pan.com/s/\(shareKey)" }
        return ShareInfo(
            shareUrl: shareUrl,
            passcode: sharePwd ?? "",
            pwdId: shareKey,
            title: shareName,
            // 123 响应不返回有效期；调用方会用用户所选中性码覆盖此处。
            // 未覆盖时显示「未知」（ShareExpire.UNKNOWN == 0）比硬猜「30 天」更安全。
            expiredType: 0
        )
    }

    // ---------- 内部工具 ----------

    /// 解析响应 InfoList（分享与个人盘结构一致）
    private func parseInfoList(_ data: JSONValue) -> [ShareFile] {
        let arr = data.array("InfoList")
        var result: [ShareFile] = []
        result.reserveCapacity(arr.count)
        for item in arr {
            if item.isNull { continue }
            let type = item.int("Type")
            // 123 下载/转存需要 S3KeyFlag + Etag + StorageNode，编码进 fidToken
            let fidToken = "\(item.string("S3KeyFlag"))|\(item.string("Etag"))|\(item.string("StorageNode"))"
            result.append(
                ShareFile(
                    fid: item.string("FileId"),
                    fname: item.string("FileName"),
                    fsize: item.long("Size"),
                    isdir: type == 1,
                    pdirFid: item.string("ParentFileId"),
                    fidToken: fidToken,
                    modifyTime: item.string("UpdateAt")
                )
            )
        }
        return result
    }

    /// 解码 fidToken（"S3KeyFlag|Etag|StorageNode"；旧格式两段时 StorageNode 为空）
    private func decodeToken(_ fidToken: String) -> (s3KeyFlag: String, etag: String, storageNode: String) {
        let parts = fidToken.components(separatedBy: "|")
        func part(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
        return (part(0), part(1), part(2))
    }

    /// 解码 123 下载 URL（兼容两种形态）：
    /// - 形态 1：整段 base64（alist 风格）
    /// - 形态 2：download-v2?params=<base64 URL-safe>
    private func decodeDownloadUrl(_ downloadUrl: String) -> String? {
        let trimmed = downloadUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        // 形态 1：整段 base64（不含协议头的串）
        if !trimmed.contains("://") {
            guard let decoded = pan123Base64Decode(trimmed), decoded.lowercased().hasPrefix("http") else {
                return nil
            }
            return decoded
        }
        // 形态 2：download-v2?params=<base64>
        guard let range = trimmed.range(of: "params=") else { return nil }
        var params = String(trimmed[range.upperBound...])
        if let amp = params.firstIndex(of: "&") {
            params = String(params[..<amp])
        }
        let normalized = params.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return pan123Base64Decode(normalized)
    }

    /// 跟随 123 CDN 的 redirect_url（最多 5 跳）
    private func followRedirectUrl(_ initialUrl: String) async -> String {
        var url = initialUrl
        for _ in 0..<5 {
            guard let next = await probeJsonRedirect(url) else { return url }
            url = next
        }
        return url
    }

    /// 探测单跳：响应为小 JSON 且含 data.redirect_url 时返回新地址，否则 nil。
    ///
    /// 说明：Kotlin 侧仅当 Content-Length ≤ 8KB 才读取响应体，真实文件流不会整段拉取。
    /// iOS 的 URLSession 无「只取响应头」能力，这里用 Range 头把读取上限压到 8KB，
    /// 对真实文件只会下载 8KB 后判为非 JSON 而回退，行为与 Kotlin 等价。
    private func probeJsonRedirect(_ url: String) async -> String? {
        do {
            let request = try HTTPClient.api.makeRequest(url, method: "GET", headers: [
                "Referer": Pan123Constants.DOWNLOAD_REFERER,
                "User-Agent": Pan123Constants.DART_UA,
                "Range": "bytes=0-8191",
            ])
            let (data, response) = try await HTTPClient.api.data(for: request)
            let http = response as? HTTPURLResponse
            let headerLen = http?.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) } ?? -1
            let len = headerLen >= 0 ? headerLen : Int64(data.count)
            guard len <= 8192 else { return nil }
            guard let body = String(data: data, encoding: .utf8) else { return nil }
            guard body.drop(while: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" }).hasPrefix("{") else {
                return nil
            }
            let redirect = JSONValue.parse(body)?.object("data").string("redirect_url") ?? ""
            return pan123IsBlank(redirect) ? nil : redirect
        } catch {
            return nil
        }
    }

    /// 成功判定：code == 0（登录接口除外，为 200）
    private func checkOk(_ json: JSONValue, _ fallback: String) throws {
        let code = json.has("code") ? json.int("code") : -1
        if code == 0 { return }
        let msg = json.string("message")
        let text = pan123IsBlank(msg) ? fallback : msg
        throw ApiError("\(text)（code=\(code)）", code: code)
    }

    /// 鉴权 GET（带 auth-key/auth-value 签名头）
    private func getAuth(_ url: String, path: String, token: String) async throws -> JSONValue {
        let sign = makeSign(path: path)
        let headers: [String: String] = [
            "platform": Pan123Constants.PLATFORM_WEB,
            "app-version": Pan123Constants.APP_VERSION_WEB,
            "authorization": "Bearer \(token)",
            "loginuuid": loginuuid,
            "auth-key": sign.authKey,
            "auth-value": sign.authValue,
            "User-Agent": Pan123Constants.WEB_UA,
            "Accept": "application/json, text/plain, */*",
        ]
        return try await execute(url: url, method: "GET", headers: headers, body: nil)
    }

    /// 鉴权 POST（签名内部固定 web/3）
    private func postAuth(
        _ url: String,
        path: String,
        body: [String: Any],
        token: String,
        platform: String = Pan123Constants.PLATFORM_WEB,
        appVersion: String = Pan123Constants.APP_VERSION_WEB
    ) async throws -> JSONValue {
        let sign = makeSign(path: path)
        let headers: [String: String] = [
            "platform": platform,
            "app-version": appVersion,
            "authorization": "Bearer \(token)",
            "loginuuid": loginuuid,
            "auth-key": sign.authKey,
            "auth-value": sign.authValue,
            "Content-Type": "application/json;charset=UTF-8",
            "User-Agent": Pan123Constants.WEB_UA,
        ]
        return try await execute(url: url, method: "POST", headers: headers, body: body)
    }

    /// 执行请求并解析为 JSONValue
    private func execute(
        url: String,
        method: String,
        headers: [String: String],
        body: [String: Any]?
    ) async throws -> JSONValue {
        let response: HTTPResponse
        if method == "POST" {
            response = try await HTTPClient.api.postJSON(url, headers: headers, body: body ?? [:])
        } else {
            response = try await HTTPClient.api.get(url, headers: headers)
        }
        let text = response.text
        if text.isEmpty {
            throw ApiError("请求失败：响应为空（\(response.statusCode)）")
        }
        if !response.isSuccessful && pan123IsBlank(text) {
            throw ApiError("请求失败（HTTP \(response.statusCode)）")
        }
        guard let json = JSONValue.parse(text) else {
            throw ApiError("请求失败：响应不是合法 JSON（HTTP \(response.statusCode)）")
        }
        return json
    }
}

// MARK: - 分享解析仓库（对应 Pan123ResolveRepository.kt）

final class Pan123ResolveRepository: ShareResolveRepository {

    private let api = Pan123Api()

    init() {}

    // MARK: - ShareResolveRepository

    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        guard let parsed = ShareLinkParser.parse(link) else {
            throw ApiError("无法识别分享链接")
        }
        // 提取码优先级：用户手输 > 链接/文案自带
        let typedPwd = pwd.flatMap { pan123IsBlank($0) ? nil : $0 }
        let sharePwd = typedPwd ?? (parsed.pwd ?? "")
        // 用分享根目录列表校验提取码 + 取标题
        let result = try await api.getShareFiles(
            shareKey: parsed.shareId,
            sharePwd: sharePwd,
            parentFileId: "0",
            next: "0",
            page: 1
        )
        let firstName = result.files.first?.fname ?? ""
        let title = pan123IsBlank(firstName) ? parsed.shareId : firstName
        return ShareSession(shareId: parsed.shareId, stoken: sharePwd, title: title)
    }

    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        // next 参数始终固定 "0"，翻页靠 Page 递增；结束条件：Next == "-1" 或列表为空
        var all: [ShareFile] = []
        var page = 1
        while true {
            let result = try await api.getShareFiles(
                shareKey: session.shareId,
                sharePwd: session.stoken,
                parentFileId: dirFid,
                next: "0",
                page: page
            )
            all += result.files
            let hasMore = !result.files.isEmpty && result.next != nil
            page += 1
            if !(hasMore && page < 50) { break }
        }
        return all
    }

    /// 123 分享下载无需转存
    func ensureTempDir(cookie: String) async throws -> String {
        throw ApiError("123 分享无需转存")
    }

    /// 保存他人分享到个人网盘（copy/save）：无需签名，仅 Bearer + LoginUuid；异步任务 → 轮询取新 fileId。
    func transferFile(
        session: ShareSession,
        file: ShareFile,
        toDirFid: String,
        cookie: String
    ) async throws -> String {
        let token = await resolveToken(cookie)
        if pan123IsBlank(token) { throw ApiError("请先登录123云盘") }
        guard let task = try await api.copySave(
            shareKey: session.shareId,
            sharePwd: session.stoken,
            file: file,
            toDirFid: pan123IsBlank(toDirFid) ? "0" : toDirFid,
            token: token
        ) else {
            throw ApiError("创建转存任务失败")
        }
        guard let newId = try await api.pollCopySave(taskId: task.taskId, shareId: task.shareId, token: token) else {
            throw ApiError("转存超时或失败")
        }
        return newId
    }

    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        throw ApiError("123 分享请使用 getShareDownloadLink")
    }

    func getShareDownloadLink(
        session: ShareSession,
        file: ShareFile,
        cookie: String
    ) async throws -> DownloadLink {
        // cookie 参数即登录 token（UI 传入当前凭证）
        let token = await resolveToken(cookie)
        if pan123IsBlank(token) { throw ApiError("请先登录123云盘") }
        guard let link = try await api.getShareDownloadLink(
            shareKey: session.shareId,
            file: file,
            token: token
        ) else {
            throw ApiError("获取下载链接失败")
        }
        let filename = pan123IsBlank(file.fname) ? link.filename : file.fname
        return DownloadLink(
            fid: link.fid,
            filename: filename,
            downloadUrl: link.downloadUrl,
            size: link.size,
            cleanupDirFid: link.cleanupDirFid,
            isHls: link.isHls,
            guestCookie: link.guestCookie
        )
    }

    // MARK: - 内部

    /// 解析登录凭证：请求传入的 cookie 优先，否则回退到账号仓库里的 123 JWT
    private func resolveToken(_ cookie: String) async -> String {
        if !pan123IsBlank(cookie) { return cookie }
        return await MainActor.run { AccountStore.shared.token(for: .pan123) }
    }
}
