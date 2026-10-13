/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：迅雷网盘网络接口层 + 分享解析仓库。
 * 对应 Kotlin：
 *   - data/network/XunleiConstants.kt
 *   - data/network/XunleiDeviceFingerprint.kt
 *   - data/network/XunleiKouling.kt
 *   - data/network/XunleiWebCredential.kt
 *   - data/network/XunleiApi.kt
 *   - data/repository/XunleiResolveRepository.kt
 *
 * 说明：iOS 无 Android ID / SharedPreferences / WebView 依赖，设备指纹改用持久 UUID；
 * 只依赖 Foundation（哈希用 CryptoKit），无第三方库。
 */

import Foundation
import CryptoKit

// MARK: - 分享有效期（中性码）

/// 分享有效期（中性码，对应 Kotlin model/ShareExpire）。
/// 迅雷创建分享接口不返回有效期，创建结果统一填 UNKNOWN，由调用方用用户所选值覆盖。
enum ShareExpire {
    /// 未知
    static let UNKNOWN = -1
}

// MARK: - 哈希辅助（对应 Kotlin MessageDigest）

/// MD5 十六进制（小写）
private func xunleiMD5Hex(_ input: String) -> String {
    Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// SHA-1 十六进制（小写）
private func xunleiSHA1Hex(_ input: String) -> String {
    Insecure.SHA1.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
}

// MARK: - 常量（对应 XunleiConstants.kt）

/// 迅雷网盘常量（依据抓包 + 迅雷网盘 API 文档，两者互相印证）。
enum XunleiConstants {

    /// 登录 / 验证码 / Token 主机
    static let AUTH_BASE = "https://xluser-ssl.xunlei.com"

    /// 文件 / 分享 / 下载主机
    static let PAN_BASE = "https://api-pan.xunlei.com"

    /// Web 端公开凭据（文档推荐，可正常换 Token）
    static let CLIENT_ID = "Xp6pAdwyJv9sQuoN"
    static let CLIENT_SECRET = "standard_a@api#"

    /// App 端凭据（官方 app 抓包，/v1/auth/signin/token 换 token 用）
    static let APP_CLIENT_ID = "Xp6vsxz_7IYVw2BB"
    static let APP_CLIENT_SECRET = "Xp6vsy4tN9toTVdMSpomVdXpRmES"

    /// Android 端身份（captcha_sign 计算用，alist 验证与 MoePal 抓包一致）
    static let APP_CLIENT_VERSION = "8.31.0.9726"
    static let APP_PACKAGE_NAME = "com.xunlei.downloadprovider"

    /// Android 端 captcha 盐（10 个，alist 源码确认，活体验证通过）
    static let CAPTCHA_SALTS: [String] = [
        "9uJNVj/wLmdwKrJaVj/omlQ",
        "Oz64Lp0GigmChHMf/6TNfxx7O9PyopcczMsnf",
        "Eb+L7Ce+Ej48u",
        "jKY0",
        "ASr0zCl6v8W4aidjPK5KHd1Lq3t+vBFf41dqv5+fnOd",
        "wQlozdg6r1qxh0eRmt3QgNXOvSZO6q/GXK",
        "gmirk+ciAvIgA/cxUUCema47jr/YToixTT+Q6O",
        "5IiCoM9B1/788ntB",
        "P07JH0h6qoM6TSUAK2aL9T5s2QBVeY9JWvalf",
        "+oK0AN",
    ]

    /// App UA（官方 app 抓包）
    static let APP_UA =
        "ANDROID-com.xunlei.downloadprovider/8.31.0.9726 netWorkType/5G appid/40 " +
        "deviceName/Xiaomi_M2004j7ac deviceModel/M2004J7AC OSVersion/12 protocolVersion/301 " +
        "platformVersion/10 sdkVersion/512000 Oauth2Client/0.9 (Linux 4_14_186-perf-gddfs8vbb238b) (JAVA 0)"

    /// 浏览器 UA（Web 端 pan 请求）
    static let WEB_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

    // ---------- 设备标识（fallback 官方指纹；正常由 XunleiDeviceFingerprint 动态生成） ----------

    /// 设备 ID（x-device-id / captcha device_id / devicesign 前半；fallback）
    static let DEVICE_ID = "78a70629a2b17d0b4302317ffa94807a"

    /// 登录请求 peerID（fallback）
    static let PEER_ID = "92df4c42e0926ff55f1c605ebe4c3754"

    /// 设备指纹 div101.设备ID+SDK指纹（fallback）
    static let DEVICE_SIGN = "div101.78a70629a2b17d0b4302317ffa94807a31491e163e795b39e798ed33ae58858b"

    // ---------- 登录端点 ----------

    /// 验证码盾初始化
    static let CAPTCHA_INIT_URL = "\(AUTH_BASE)/v1/shield/captcha/init"

    /// 账号密码登录（xluser 会话）
    static let LOGIN_URL = "\(AUTH_BASE)/xluser.core.login/v3/login"

    /// 发送短信验证码
    static let SEND_SMS_URL = "\(AUTH_BASE)/xluser.core.login/v3/sendsms"

    /// 短信验证码登录
    static let SMS_LOGIN_URL = "\(AUTH_BASE)/xluser.core.login/v3/smslogin"

    /// 换取 access_token（官方 app 抓包：POST /v1/auth/signin/token，body 带 signin_token=sessionID）
    static let TOKEN_URL = "\(AUTH_BASE)/v1/auth/signin/token"

    /// 刷新 access_token（OAuth2 refresh_token；导入恢复后 token 过期自动续期）
    static let REFRESH_URL = "\(AUTH_BASE)/v1/auth/token"

    // ---------- Pan 端点 ----------

    /// 文件列表 / 详情 / 建目录
    static let FILES_URL = "\(PAN_BASE)/drive/v1/files"

    /// 分享解析（GET ?share_id=&pass_code=&limit=&page_token=&thumbnail_size=）
    static let SHARE_URL = "\(PAN_BASE)/drive/v1/share"

    /// 分享子目录文件列表（GET ?share_id=&parent_id=&pass_code_token=&limit=&page_token=&thumbnail_size=）
    static let SHARE_DETAIL_URL = "\(PAN_BASE)/drive/v1/share/detail"

    /// 转存（POST）
    static let RESTORE_URL = "\(PAN_BASE)/drive/v1/share/restore"

    /// 异步任务轮询（GET /tasks/{taskId}?type=share）
    static let TASKS_URL = "\(PAN_BASE)/drive/v1/tasks"

    /// 转存目标目录名
    static let TEMP_DIR_NAME = "YunX临时转存"

    /// 移动文件（batchMove：ids + to.parent_id）
    static let MOVE_URL = "\(PAN_BASE)/drive/v1/files:batchMove"

    /// 删除文件（batchTrash：ids + space）
    static let TRASH_URL = "\(PAN_BASE)/drive/v1/files:batchTrash"

    /// 创建分享（POST /drive/v1/share，file_ids + title + expiration_days）
    static let SHARE_CREATE_URL = "\(PAN_BASE)/drive/v1/share"
}

// MARK: - 设备指纹（对应 XunleiDeviceFingerprint.kt）

/// 迅雷设备指纹管理器（动态生成 + 持久化）。
///
/// - 每台设备首次使用生成唯一 deviceId/peerId/devicesign，此后永久复用；
/// - devicesign 公式：`div101.{deviceId}{md5(sha1(deviceId + package + appid + appkey))}`；
/// - 未初始化（异常路径）时回退到 XunleiConstants 官方抓包指纹，保证行为不崩；
/// - 目的：开源分发后每台设备独立指纹，避免所有用户共享一个官方指纹被迅雷风控识别 / 连带封禁。
///
/// iOS 说明：Android 侧用 `Random` 生成 32 位十六进制随机串并写入 SharedPreferences；
/// iOS 无 Android ID 且需跨进程持久复用，这里改用**持久化 UUID**（去掉横线后即为 32 位十六进制）
/// 作为 deviceId / peerId 的替代，并存入 UserDefaults，语义与 Android 侧一致。
enum XunleiDeviceFingerprint {

    private static let prefsKeyId = "xunlei_device_fp.device_id"
    private static let prefsKeyPeer = "xunlei_device_fp.peer_id"
    private static let prefsKeySign = "xunlei_device_fp.device_sign"

    // devicesign 计算常量（与文档 §8 / alist 一致）
    private static let PACKAGE_NAME = "com.xunlei.downloadprovider"
    private static let APPID = "40"
    private static let APP_KEY = "34a062aaa22f906fca4fefe9fb3a3021"

    private static let lock = NSLock()
    private static var initialized = false

    // 未初始化时的 fallback：官方抓包真实设备（保持旧行为，绝不崩）
    private static var _deviceId = XunleiConstants.DEVICE_ID
    private static var _peerId = XunleiConstants.PEER_ID
    private static var _deviceSign = XunleiConstants.DEVICE_SIGN

    /// 幂等初始化（对应 Android 侧 Application.onCreate 中调用；iOS 侧首次读取时自动触发，可显式调用）
    static func initialize() { ensureInitialized() }

    static func deviceId() -> String { ensureInitialized(); return _deviceId }

    static func peerId() -> String { ensureInitialized(); return _peerId }

    static func deviceSign() -> String { ensureInitialized(); return _deviceSign }

    private static func ensureInitialized() {
        if initialized { return }
        lock.lock()
        defer { lock.unlock() }
        if initialized { return }
        let defaults = UserDefaults.standard
        if let savedId = defaults.string(forKey: prefsKeyId), !savedId.isEmpty {
            _deviceId = savedId
            _peerId = defaults.string(forKey: prefsKeyPeer) ?? XunleiConstants.PEER_ID
            _deviceSign = defaults.string(forKey: prefsKeySign) ?? XunleiConstants.DEVICE_SIGN
        } else {
            // 首次使用：生成唯一设备指纹并持久化
            let newId = randomHex32()
            let newPeer = randomHex32()
            let newSign = buildDeviceSign(newId)
            defaults.set(newId, forKey: prefsKeyId)
            defaults.set(newPeer, forKey: prefsKeyPeer)
            defaults.set(newSign, forKey: prefsKeySign)
            _deviceId = newId
            _peerId = newPeer
            _deviceSign = newSign
        }
        initialized = true
    }

    /// devicesign：div101.{deviceId}{md5(sha1(deviceId + package_name + appid + app_key))}
    private static func buildDeviceSign(_ id: String) -> String {
        let base = id + PACKAGE_NAME + APPID + APP_KEY
        let sha1 = xunleiSHA1Hex(base)
        let md5 = xunleiMD5Hex(sha1)
        return "div101.\(id)\(md5)"
    }

    /// iOS 无 Android ID：用持久化 UUID（去横线后 32 位十六进制）替代设备随机指纹
    private static func randomHex32() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

// MARK: - 迅雷中文口令（对应 XunleiKouling.kt）

/// 迅雷中文口令（如「张三丰资源」）→ 分享链接 + 提取码（纯逻辑）。
///
/// 口令本质上是「分享链接 + 提取码」的打包形式：把口令当关键词打 shoulei 的搜索跳转接口，
/// 响应 `ext.kouling_type == "share_page"` 时 `location` 就是带 `pwd` 的分享页地址。
/// 网络请求见 `XunleiApi.parseKouling`。
enum XunleiKouling {

    /// 口令 → 分享链接的跳转接口
    static let JUMP_API = "https://api-shoulei-ssl.xunlei.com/xlppc.searcher.api/jump"

    /// 接口来源标识：服务端按渠道校验，缺了拿不到 `share_page`。
    static let ORIGIN = "https://sl-m-ssl.xunlei.com"
    static let REFERER = "https://sl-m-ssl.xunlei.com/"
    static let USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/108.0.5359.215 Safari/537.36 TBC/1.3.3.999 Thunder/12.4.4.3740"

    /// 渠道参数（前端固定值，抓包所得）
    private static let TN = "15007414_5_dg"
    private static let SRC = "lm"
    private static let LS = "sm3016480"
    private static let LM_EXTEND = "ctype:31"

    /// 口令长度上限：正常口令是短文本，过长说明用户粘的是整段文案
    private static let MAX_LENGTH = 64

    /// 口令两侧常见的装饰符号（引号 / 书名号 / 括号 / 标点）
    private static let DECORATIONS = "「」『』【】《》〈〉“”‘’\"'`()（）[]{}<>.,，。;；:：!！?？、|"

    private static let shareIdPattern = "pan\\.xunlei\\.com/s/([A-Za-z0-9_-]+)"
    private static let pwdPattern = "[?&]pwd=([A-Za-z0-9]+)"

    /// 去掉两侧空白与装饰符号，得到干净的口令文本
    static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let decorations = CharacterSet(charactersIn: DECORATIONS)
        return trimmed.trimmingCharacters(in: decorations).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 是否值得按口令去解析：非空、不太长、正文只含汉字 / 字母 / 数字，且至少有汉字。
    static func looksLikeKouling(_ text: String) -> Bool {
        let t = normalize(text)
        if t.isEmpty || t.count > MAX_LENGTH { return false }
        if !t.allSatisfy({ $0.isLetter || $0.isNumber }) { return false }
        return t.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
    }

    /// 拼 jump 请求 URL：`wd`（中文口令）必须 URL 编码
    static func buildJumpUrl(_ keyword: String) -> String {
        "\(JUMP_API)?noredirect=1&t=20&wd=\(urlEncode(keyword))&tn=\(TN)&src=\(SRC)&ls=\(LS)&lm_extend=\(LM_EXTEND)"
    }

    /// 从响应 `location` 里取干净的分享链接：`https://pan.xunlei.com/s/<share_id>?pwd=<pwd>`，
    /// 丢掉 `channel`/`content`/`from`/`share_userid`/`wd` 等业务参数。不是迅雷分享页返回 nil。
    static func shareUrlFromLocation(_ location: String?) -> String? {
        let loc = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if loc.isEmpty { return nil }
        guard let shareId = RegexUtil.firstGroup(shareIdPattern, in: loc) else { return nil }
        if let pwd = RegexUtil.firstGroup(pwdPattern, in: loc), !pwd.isEmpty {
            return "https://pan.xunlei.com/s/\(shareId)?pwd=\(pwd)"
        }
        return "https://pan.xunlei.com/s/\(shareId)"
    }
}

// MARK: - 网页登录凭据（对应 XunleiWebCredential.kt）

/// 迅雷网页登录凭据（pan.xunlei.com 的 localStorage 对象）。
struct XunleiWebTokens: Equatable {
    let accessToken: String
    let refreshToken: String
    let deviceId: String
    let captchaToken: String
    let userId: String
    let nickname: String
}

/// 迅雷网页登录：站点私有格式的解析（纯逻辑）。
///
/// 网页版把登录态写进 localStorage 的 `credentials_<clientId>`（子账号 `credentials_<clientId>@<sub>`），
/// 形如 `{"access_token":"…","refresh_token":"…","sub":"…"}`。
/// iOS 说明：Android 侧依赖 WebView / WebSettings 的部分（UA 元数据、渲染修补脚本、域名白名单）
/// 属平台专有实现，不随网络层移植，这里保留可移植的解析与常量。
enum XunleiWebCredential {

    /// 网页版 OAuth client_id（抓包自 pan.xunlei.com，与 App 端不同）。网页 token 只能用这个刷新。
    static let CLIENT_ID = "Xqp0kJBXWhwaTpB6"

    /// 登录态在 localStorage 中的键名
    static let STORAGE_KEY = "credentials_\(CLIENT_ID)"

    /// 验证码 token 在 localStorage 中的键名
    static let CAPTCHA_KEY = "captcha_\(CLIENT_ID)"

    /// 网页登录页
    static let LOGIN_URL = "https://pan.xunlei.com/"

    /// 落库时写入的认证方式：网页 token 的刷新路径与 App token 不同
    static let AUTH_TYPE = "webToken"

    /// 网页版桌面 UA（网页 token 的刷新请求必须带，否则被风控拒绝）
    static let DESKTOP_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    /// 与 DESKTOP_UA 配套的客户端提示头（版本号必须与 UA 里的 Chrome 大版本一致，品牌名带引号）
    static let DESKTOP_SEC_CH_UA = "\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\""
    static let DESKTOP_SEC_CH_UA_MOBILE = "?0"
    static let DESKTOP_SEC_CH_UA_PLATFORM = "\"Windows\""

    /// 允许停留 / 跳转的域名（登录过程会经 i.xunlei.com 等官方域，统一放行 *.xunlei.com）
    private static let TRUSTED_HOSTS = ["xunlei.com"]

    /// 是否允许停留在该 URL：仅 https 的 xunlei.com 及其子域、443 端口（about:blank 放行）
    static func isTrustedUrl(_ url: String?) -> Bool {
        let value = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "about:blank" { return true }
        guard let comps = URLComponents(string: value) else { return false }
        guard comps.scheme?.lowercased() == "https" else { return false }
        if let user = comps.user, !user.isEmpty { return false }
        if let port = comps.port, port != 443 { return false }
        let host = (comps.host ?? "").lowercased()
        return TRUSTED_HOSTS.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// 解析网页登录凭据，支持三种输入：
    /// 1. 完整 JSON（localStorage 原文 / 抓包复制）；
    /// 2. 被引号包起来的 JSON 字符串；
    /// 3. 裸 access_token（手动粘贴兜底，此时没有 refresh_token）。
    /// 解析失败一律返回 nil。
    static func parse(_ raw: String) -> XunleiWebTokens? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        // 形态 2：外层是 JSON 字符串 → 还原成里面的内容
        if let unwrapped = unwrapQuoted(text) {
            text = unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.isEmpty { return nil }
        // 形态 3：不是 JSON 对象 → 按裸 token 处理
        if !text.hasPrefix("{") { return parseRawToken(text) }
        guard let root = parseObject(text) else { return nil }
        return fieldsFrom(toFieldMap(unwrapNested(root)))
    }

    /// 裸 token（手动粘贴 access_token 的场景）。
    static func parseRawToken(_ text: String) -> XunleiWebTokens? {
        let token = stripBearer(text)
        if isValidToken(token) {
            return XunleiWebTokens(accessToken: token, refreshToken: "", deviceId: "", captchaToken: "", userId: "", nickname: "")
        }
        return nil
    }

    /// 从「键 → 值」映射里挑出凭据字段（纯逻辑）。任一 token 非法即整体判失败。
    static func fieldsFrom(_ fields: [String: String]) -> XunleiWebTokens? {
        let access = pick(fields, "access_token", "accessToken")
        let refresh = pick(fields, "refresh_token", "refreshToken")
        if !access.isEmpty && !isValidToken(access) { return nil }
        if !refresh.isEmpty && !isValidToken(refresh) { return nil }
        if access.isEmpty && refresh.isEmpty { return nil }
        let captcha = pick(fields, "captcha_token", "captchaToken")
        return XunleiWebTokens(
            accessToken: access,
            refreshToken: refresh,
            deviceId: pick(fields, "device_id", "deviceId"),
            captchaToken: isValidToken(captcha) ? captcha : "",
            userId: pick(fields, "user_id", "userId", "sub"),
            nickname: pick(fields, "nick_name", "nickname", "name", "user_name")
        )
    }

    /// 去掉 `Bearer ` 前缀与首尾空白
    private static func stripBearer(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "^Bearer\\s+", options: [.regularExpression, .caseInsensitive]) {
            return String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// 把 JSON 对象拍平成「键 → 字符串值」；非字符串 / 数字的值直接丢掉
    private static func toFieldMap(_ data: JSONValue) -> [String: String] {
        guard let dict = data.raw as? [String: Any] else { return [:] }
        var map: [String: String] = [:]
        for (key, value) in dict {
            if let s = value as? String {
                map[key] = s
            } else if let n = value as? NSNumber {
                map[key] = n.stringValue
            }
        }
        return map
    }

    /// 外层是 JSON 字符串字面量时还原内容；不是则返回 nil
    private static func unwrapQuoted(_ text: String) -> String? {
        if !text.hasPrefix("\"") { return nil }
        guard let data = text.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return obj as? String
    }

    /// 解析成 JSON 对象；不是对象（裸 token / 数组 / 非法 JSON）返回 nil
    private static func parseObject(_ text: String) -> JSONValue? {
        if !text.hasPrefix("{") { return nil }
        guard let data = text.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        guard obj is [String: Any] else { return nil }
        return JSONValue(obj)
    }

    /// 兼容嵌套包装：有些版本把 token 包在 `credentials` / `token` / `data` 里，最多向下找两层。
    private static func unwrapNested(_ root: JSONValue) -> JSONValue {
        var current = root
        for _ in 0..<2 {
            if current.has("access_token") || current.has("accessToken") ||
                current.has("refresh_token") || current.has("refreshToken") {
                return current
            }
            let credentials = current.object("credentials")
            let token = current.object("token")
            let data = current.object("data")
            if !credentials.isNull {
                current = credentials
            } else if !token.isNull {
                current = token
            } else if !data.isNull {
                current = data
            } else {
                return current
            }
        }
        return current
    }

    /// 取第一个非空字符串字段（数字也接受，与网页侧 pick 行为一致）
    private static func pick(_ fields: [String: String], _ keys: String...) -> String {
        for key in keys {
            let text = (fields[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if containsControlChars(text) { continue }
            return text
        }
        return ""
    }

    private static func containsControlChars(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value <= 0x1F || $0.value == 0x7F }
    }

    /// token 合法性：长度 16~16384、仅 JWT/Base64 允许的字符集、且不是占位串
    static func isValidToken(_ value: String) -> Bool {
        guard value.count >= 16 && value.count <= 16384 else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~+/=-")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return value != "null" && value != "undefined"
    }
}

// MARK: - 迅雷 API 中间结果

/// 迅雷分享解析结果
struct XunleiShareResult {
    let title: String
    let files: [ShareFile]
    let passCodeToken: String
    let shareId: String
    var nextPageToken: String = ""
}

struct XunleiFilePage {
    let files: [ShareFile]
    let nextPageToken: String
}

/// 迅雷登录中间结果
struct XunleiLoginStep {
    /// 是否需要短信验证
    var needSms: Bool = false
    /// sendsms 返回的 creditkey
    var smsCreditKey: String = ""
    /// sendsms 返回的 token
    var smsToken: String = ""
    /// 登录成功的会话（loginKey）
    var sessionKey: String = ""
    /// 登录成功的 sessionID（换 token 用 signin_token）
    var sessionId: String = ""
    var nickname: String = ""
    var userID: String = ""
    /// review_panel 返回的验证页 URL（可浏览器兜底）
    var reviewUrl: String = ""
    var message: String = ""
}

// MARK: - 迅雷 API（对应 XunleiApi.kt）

/// 迅雷 API 封装：
/// - 登录：captcha/init → v3/login（密码，可能触发短信）→ sendsms → smslogin → v1/auth/token
/// - Pan：文件列表 / 分享解析 / 转存 / 直链（Bearer 认证，无需 x-signature，抓包确认）
final class XunleiApi {

    private let client = HTTPClient.api

    /// captcha_invalid 时刷新出的新 captcha_token（后续请求优先使用）
    private var refreshedCaptcha: String?

    /// 当前有效 access_token（401 自动刷新后更新；pan 请求优先使用）
    private var currentAccessToken: String = ""

    /// 401/unauthenticated 时自动刷新：提供 refresh_token 换新 token（由调用方注入并持久化）
    var refreshTokenProvider: ((String) async -> (String, String)?)?

    /// 当前用户 ID（从 access_token JWT 解析，captcha init 的 meta 需要）
    private var currentUserId: String = ""

    private let jsonContentType = "application/json"

    // ---------- 底层请求 ----------

    /// 构造 URLRequest（JSON body 用 [String: Any]；表单用 formBody 字符串）
    private func makeRequest(
        url: String,
        method: String,
        headers: [String: String],
        jsonBody: [String: Any]? = nil,
        formBody: String? = nil
    ) throws -> URLRequest {
        var request = try client.makeRequest(url, method: method, headers: headers)
        if let jsonBody = jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
        } else if let formBody = formBody {
            request.httpBody = formBody.data(using: .utf8)
        }
        return request
    }

    /// 执行请求并封装响应
    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        let result: (data: Data, response: URLResponse)
        do {
            result = try await client.data(for: request)
        } catch {
            throw ApiError(error.localizedDescription)
        }
        guard let http = result.response as? HTTPURLResponse else {
            throw ApiError("响应异常")
        }
        var headers: [String: [String]] = [:]
        for (key, value) in http.allHeaderFields {
            headers["\(key)".lowercased(), default: []].append("\(value)")
        }
        return HTTPResponse(statusCode: http.statusCode, body: result.data, headers: headers)
    }

    /// 解析响应 JSON（失败抛「响应解析失败」）
    private func decode(_ response: HTTPResponse) throws -> JSONValue {
        guard let json = JSONValue.parse(response.text) else {
            throw ApiError("响应解析失败（HTTP \(response.statusCode)）")
        }
        return json
    }

    // ---------- 登录 ----------

    /// 1. 验证码盾初始化，返回 captcha_token（换 token 与 pan 请求需带 X-Captcha-Token）。
    /// 官方抓包：client_id 用 app 凭据 Xp6vsxz_7IYVw2BB。
    /// 按文档 §9.5：meta 必须带 captcha_sign（10-salt 算法），否则拿到降级 token。
    func initCaptcha(
        deviceId: String,
        username: String,
        action: String = "POST:/auth/signin/token"
    ) async throws -> String? {
        let ts = String(Int64(Date().timeIntervalSince1970 * 1000))
        let sign = buildCaptchaSign(deviceId: deviceId, tsMs: ts)
        let meta: [String: Any] = [
            "username": username,
            "client_version": XunleiConstants.APP_CLIENT_VERSION,
            "package_name": XunleiConstants.APP_PACKAGE_NAME,
            "timestamp": ts,
            "captcha_sign": sign,
            "user_id": currentUserId, // 真实 user_id，空会得到降级 token
        ]
        let body: [String: Any] = [
            "action": action,
            "captcha_token": "",
            "client_id": XunleiConstants.APP_CLIENT_ID,
            "device_id": deviceId,
            "meta": meta,
            "redirect_uri": "xlaccsdk01://xunlei.com/callback?state=harbor",
        ]
        let headers = [
            "User-Agent": XunleiConstants.APP_UA,
            "Accept": "application/json;charset=UTF-8",
            "Content-Type": jsonContentType,
            "X-Client-Id": XunleiConstants.APP_CLIENT_ID,
            "X-Device-Id": deviceId,
            "X-Client-Version": "8.31.0.9726",
        ]
        do {
            let request = try makeRequest(url: XunleiConstants.CAPTCHA_INIT_URL, method: "POST", headers: headers, jsonBody: body)
            let response = try await send(request)
            let json = try decode(response)
            let token = json.string("captcha_token")
            return token.isEmpty ? nil : token
        } catch {
            return nil
        }
    }

    /// 2. 账号密码登录（官方首次登录：creditkey=""，sdk UA）。
    /// 新客户端第一次登录必然返回 review_panel(1007) → 走短信验证；不要填任何 creditkey/captcha。
    func loginWithPassword(
        username: String,
        password: String,
        deviceId: String,
        checkCode: String = ""
    ) async throws -> XunleiLoginStep {
        var body = baseLoginBody(deviceId: deviceId, clientVersion: "25.0.5.25", sdkVersion: "513006")
        body["userName"] = username
        body["passWord"] = password
        body["verifyKey"] = ""
        body["verifyCode"] = checkCode
        body["isMd5Pwd"] = "0"
        // 官方抓包 v3/login 头：sdk UA + content-type，无 Cookie，无 x-device-id/x-client-id
        let headers = [
            "User-Agent": "android-ok-http-client/xl-acc-sdk/version-5.1.3.513006",
            "Content-Type": jsonContentType,
        ]
        let request = try makeRequest(url: XunleiConstants.LOGIN_URL, method: "POST", headers: headers, jsonBody: body)
        let response = try await send(request)
        let json = try decode(response)
        return parseLoginResponse(json)
    }

    /// 3a. 发送短信验证码（官方：UA=xl-acc-sdk/version-5.0.12.512000，creditkey=""，无 Cookie）
    func sendSms(mobile: String, deviceId: String) async throws -> XunleiLoginStep {
        var body = baseLoginBody(deviceId: deviceId, clientVersion: "8.31.0.9726", sdkVersion: "231500")
        body["mobile"] = mobile
        body["register"] = "0"
        let headers = [
            "User-Agent": "android-ok-http-client/xl-acc-sdk/version-5.0.12.512000",
            "Content-Type": jsonContentType,
        ]
        let request = try makeRequest(url: XunleiConstants.SEND_SMS_URL, method: "POST", headers: headers, jsonBody: body)
        let response = try await send(request)
        let json = try decode(response)
        var message = json.string("errorDesc")
        if message.isEmpty { message = "短信已发送" }
        return XunleiLoginStep(
            needSms: true,
            smsCreditKey: json.string("creditkey"),
            smsToken: json.string("token"),
            message: message
        )
    }

    /// 3b. 短信验证码登录（官方：UA=xl-acc-sdk/version-5.0.12.512000，body 带 creditkey/token，无 Cookie）
    func smsLogin(
        mobile: String,
        smsCode: String,
        creditKey: String,
        smsToken: String,
        deviceId: String
    ) async throws -> XunleiLoginStep {
        var body = baseLoginBody(deviceId: deviceId, clientVersion: "8.31.0.9726", sdkVersion: "231500", creditKey: creditKey)
        body["mobile"] = mobile
        body["smsCode"] = smsCode
        body["token"] = smsToken
        body["register"] = "0"
        let headers = [
            "User-Agent": "android-ok-http-client/xl-acc-sdk/version-5.0.12.512000",
            "Content-Type": jsonContentType,
        ]
        let request = try makeRequest(url: XunleiConstants.SMS_LOGIN_URL, method: "POST", headers: headers, jsonBody: body)
        let response = try await send(request)
        let json = try decode(response)
        return parseLoginResponse(json)
    }

    /// 兜底：OAuth2 密码直换 token（官方抓包证实此路径不存在，v3/login + signin_token 才是正路）
    func loginWithTokenPassword(
        username: String,
        password: String,
        deviceId: String,
        captchaToken: String,
        checkCode: String = ""
    ) async throws -> (String, String)? {
        return nil
    }

    /// 4. 用 v3/smslogin 返回的 sessionID 换取 access_token（官方抓包 POST /v1/auth/signin/token）。
    /// 请求头必须带 X-Captcha-Token（captcha/init 返回）。
    func exchangeToken(sessionId: String, deviceId: String, captchaToken: String) async throws -> (String, String)? {
        let body: [String: Any] = [
            "client_id": XunleiConstants.APP_CLIENT_ID,
            "client_secret": XunleiConstants.APP_CLIENT_SECRET,
            "provider": "access_end_point_token",
            "signin_token": sessionId,
        ]
        var headers = [
            "User-Agent": XunleiConstants.APP_UA,
            "Accept": "application/json;charset=UTF-8",
            "Content-Type": jsonContentType,
            "X-Client-Id": XunleiConstants.APP_CLIENT_ID,
            "X-Device-Id": deviceId,
            "X-Client-Version": "8.31.0.9726",
        ]
        if !captchaToken.isEmpty { headers["X-Captcha-Token"] = captchaToken }
        do {
            let request = try makeRequest(url: XunleiConstants.TOKEN_URL, method: "POST", headers: headers, jsonBody: body)
            let response = try await send(request)
            let json = try decode(response)
            return applyTokenResponse(json)
        } catch {
            return nil
        }
    }

    /// 缓存当前用户 ID（从 access_token JWT 解析），供 captcha/init 的 meta 使用
    func cacheUserId(accessToken: String) {
        if currentUserId.isEmpty { currentUserId = jwtSub(accessToken) }
    }

    /// 用 refresh_token 刷新 access_token（OAuth2 refresh_token）。
    ///
    /// - Parameter authType: 登录方式；网页登录（`XunleiWebCredential.AUTH_TYPE`）的 token 与 App token
    ///   不是同一套 OAuth 客户端——网页 token 只能用网页 client_id 刷新，请求形态也不同
    ///   （JSON + 桌面 UA + Origin/Referer，且必须不带 client_secret）。
    /// - Returns: 新 (access_token, refresh_token)；失败返回 nil
    func refreshToken(_ refreshToken: String, deviceId: String, authType: String = "") async throws -> (String, String)? {
        let web = authType == XunleiWebCredential.AUTH_TYPE
        do {
            let response: HTTPResponse
            if web {
                let body: [String: Any] = [
                    "grant_type": "refresh_token",
                    "client_id": XunleiWebCredential.CLIENT_ID,
                    "refresh_token": refreshToken,
                ]
                // 桌面 UA 必须同步这套 client hints：只改 UA 不同步 Sec-CH-UA 会被判成移动端而冲突
                let headers = [
                    "Content-Type": jsonContentType,
                    "X-Device-Id": deviceId,
                    "X-Client-Id": XunleiWebCredential.CLIENT_ID,
                    "Origin": "https://pan.xunlei.com",
                    "Referer": "https://pan.xunlei.com/",
                    "User-Agent": XunleiWebCredential.DESKTOP_UA,
                    "Sec-Ch-Ua": XunleiWebCredential.DESKTOP_SEC_CH_UA,
                    "Sec-Ch-Ua-Mobile": XunleiWebCredential.DESKTOP_SEC_CH_UA_MOBILE,
                    "Sec-Ch-Ua-Platform": XunleiWebCredential.DESKTOP_SEC_CH_UA_PLATFORM,
                ]
                let request = try makeRequest(url: XunleiConstants.REFRESH_URL, method: "POST", headers: headers, jsonBody: body)
                response = try await send(request)
            } else {
                let body = "grant_type=refresh_token" +
                    "&client_id=\(XunleiConstants.APP_CLIENT_ID)" +
                    "&client_secret=\(XunleiConstants.APP_CLIENT_SECRET)" +
                    "&refresh_token=\(urlEncode(refreshToken))"
                let headers = [
                    "Content-Type": "application/x-www-form-urlencoded",
                    "X-Device-Id": deviceId,
                ]
                let request = try makeRequest(url: XunleiConstants.REFRESH_URL, method: "POST", headers: headers, formBody: body)
                response = try await send(request)
            }
            let json = try decode(response)
            return applyTokenResponse(json)
        } catch {
            return nil
        }
    }

    /// 校验一个 access_token 是否真的能用（网页登录落库前调用）。
    /// 必须校验传入的这个 token（preferCachedToken = false），网络异常也返回 false。
    func verifyAccessToken(accessToken: String, deviceId: String, captchaToken: String) async throws -> Bool {
        if accessToken.isEmpty { return false }
        do {
            let request = try panRequest(
                "\(XunleiConstants.PAN_BASE)/drive/v1/about",
                accessToken: accessToken, deviceId: deviceId, captchaToken: captchaToken,
                jsonBody: nil, preferCachedToken: false
            )
            let response = try await send(request)
            if !response.isSuccessful { return false }
            let json = try decode(response)
            // 该接口的返回结构随通道不同：App 通道包在 data 里，网页（webToken）通道是顶层 kind/quota
            return !json.object("data").isNull || json.string("kind") == "drive#about"
        } catch {
            return false
        }
    }

    /// 解析 JWT 的 exp（秒）；解析失败返回 0
    func jwtExp(_ token: String) -> Int64 {
        jwtPayload(token)?.long("exp") ?? 0
    }

    /// 从 JWT 中解析 sub（用户 ID）
    private func jwtSub(_ token: String) -> String {
        jwtPayload(token)?.string("sub") ?? ""
    }

    /// 解析 JWT 载荷（第二段，Base64URL 无填充）
    private func jwtPayload(_ token: String) -> JSONValue? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return nil }
        guard let data = base64URLDecode(parts[1]) else { return nil }
        return JSONValue.parse(data)
    }

    /// Base64URL（无填充）解码
    private func base64URLDecode(_ value: String) -> Data? {
        var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let rem = s.count % 4
        if rem > 0 { s += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: s)
    }

    /// 解析 access_token / refresh_token 字段，并缓存 user_id / currentAccessToken；无 access_token 返回 nil
    private func applyTokenResponse(_ json: JSONValue) -> (String, String)? {
        var at = json.string("access_token")
        if at.isEmpty { at = json.string("accessToken") }
        var rt = json.string("refresh_token")
        if rt.isEmpty { rt = json.string("refreshToken") }
        if at.isEmpty { return nil }
        let sub = jwtSub(at)
        if !sub.isEmpty { currentUserId = sub }
        currentAccessToken = at
        return (at, rt)
    }

    /// 解析 v3/login / v3/smslogin 响应
    private func parseLoginResponse(_ json: JSONValue) -> XunleiLoginStep {
        let errorCode = json.string("errorCode")
        if errorCode == "0" || json.string("error") == "success" {
            return XunleiLoginStep(
                needSms: false,
                sessionKey: json.string("loginKey"),
                sessionId: json.string("sessionID"),
                nickname: json.string("nickName"),
                userID: json.string("userID"),
                message: "登录成功"
            )
        }
        // 触发验证面板（review_panel）→ 需要短信验证
        let error = json.string("error")
        let verifyType = json.string("verifyType")
        let needSms = error == "review_panel" || errorCode == "1007" || verifyType == "MEA" || !verifyType.isEmpty
        var message = json.string("errorDesc")
        if message.isEmpty { message = json.string("error_description") }
        return XunleiLoginStep(
            needSms: needSms,
            reviewUrl: json.string("reviewurl"),
            message: message
        )
    }

    /// 登录请求公共体（对齐官方 app 抓包字段；peerID/devicesign 用动态生成的设备指纹）
    private func baseLoginBody(
        deviceId: String,
        clientVersion: String,
        sdkVersion: String,
        creditKey: String = ""
    ) -> [String: Any] {
        [
            "protocolVersion": "301",
            "sequenceNo": String(Int.random(in: 10000000..<99999999)),
            "platformVersion": "10",
            "isCompressed": "0",
            "appid": "40",
            "clientVersion": clientVersion,
            "peerID": XunleiDeviceFingerprint.peerId(), // 动态设备 peerID
            "appName": "ANDROID-com.xunlei.downloadprovider",
            "sdkVersion": sdkVersion,
            "devicesign": XunleiDeviceFingerprint.deviceSign(), // 动态设备指纹（§8 公式）
            "netWorkType": "WIFI",
            "providerName": "NONE",
            "deviceModel": "M2004J7AC",
            "deviceName": "Xiaomi_M2004j7ac",
            "OSVersion": "12",
            "creditkey": creditKey,
            "hl": "zh-CN",
        ]
    }

    // ---------- Pan ----------

    /// 单页文件列表（个人网盘，parent_id 为空=根目录），返回 (文件, 下一页游标 or 空串=末页)
    private func getFilesPage(
        parentId: String,
        accessToken: String,
        deviceId: String,
        captchaToken: String,
        pageToken: String
    ) async throws -> (files: [ShareFile], next: String) {
        let filters = urlEncode("{\"trashed\":{\"eq\":false}}")
        let url = XunleiConstants.FILES_URL +
            "?parent_id=" + parentId +
            "&page_token=" + urlEncode(pageToken) +
            "&limit=100&with_audit=true&filters=" + filters
        return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "GET:/drive/v1/files") { t in
            try self.panRequest(url, accessToken: accessToken, deviceId: deviceId, captchaToken: t)
        } parse: { data in
            let files = self.parseFileArray(data.array("files"))
            let next = data.string("next_page_token")
            return (files: files, next: next.isEmpty ? "" : next)
        }
    }

    /// 文件列表（个人网盘，parent_id 为空=根目录；自动翻页，返回该目录下全部文件）
    func getFiles(
        parentId: String,
        accessToken: String,
        deviceId: String,
        captchaToken: String
    ) async throws -> [ShareFile]? {
        var all: [ShareFile] = []
        var token = ""
        for _ in 0..<100 { // 封顶 100 页，防异常死循环
            let page = try await getFilesPage(parentId: parentId, accessToken: accessToken, deviceId: deviceId, captchaToken: captchaToken, pageToken: token)
            all += page.files
            if page.next.isEmpty { return all.isEmpty ? nil : all }
            token = page.next
        }
        return all.isEmpty ? nil : all
    }

    /// 创建文件夹（个人网盘），返回新文件夹 id
    func createFolder(
        name: String,
        parentId: String,
        accessToken: String,
        deviceId: String,
        captchaToken: String
    ) async throws -> String? {
        let body: [String: Any] = [
            "kind": "drive#folder",
            "name": name,
            "parent_id": parentId,
            "space": "", // 官方 proto 要求字符串，数字会 400
        ]
        return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "POST:/drive/v1/files") { t in
            try self.panRequest(XunleiConstants.FILES_URL, accessToken: accessToken, deviceId: deviceId, captchaToken: t, jsonBody: body)
        } parse: { data in
            let id = data.string("id")
            return id.isEmpty ? nil : id
        }
    }

    /// 文件详情（返回下载直链 links.application/octet-stream.url）
    func getFileDetail(
        fileId: String,
        accessToken: String,
        deviceId: String,
        captchaToken: String
    ) async throws -> DownloadLink? {
        let url = "\(XunleiConstants.FILES_URL)/\(fileId)?_magic=2021&usage=PLAY&thumbnail_size=SIZE_LARGE" +
            "&with=hdr10&with=subtitle_files&with=task&with=public_share_tag"
        return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "GET:/drive/v1/files/\(fileId)") { t in
            try self.panRequest(url, accessToken: accessToken, deviceId: deviceId, captchaToken: t)
        } parse: { data in
            let links = data.object("links")
            let appNode = links.object("application/octet-stream")
            // Kotlin: links?.optJSONObject(...)?.optString("url") ?: data.optString("web_content_link") ?: ""
            // appNode 为 null 时才回退 web_content_link；appNode 存在但 url 为空串时仍用空串
            let urlStr = appNode.isNull ? data.string("web_content_link") : appNode.string("url")
            return DownloadLink(
                fid: data.string("id"),
                filename: data.string("name"),
                downloadUrl: urlStr,
                size: data.long("size")
            )
        }
    }

    /// 分享解析（share_id + 可选 pass_code）
    func getShare(
        shareId: String,
        passCode: String,
        accessToken: String,
        deviceId: String,
        captchaToken: String,
        pageToken: String = ""
    ) async throws -> XunleiShareResult? {
        let url = XunleiConstants.SHARE_URL +
            "?share_id=" + shareId +
            "&pass_code=" + urlEncode(passCode) +
            "&limit=100&page_token=" + urlEncode(pageToken) +
            "&thumbnail_size=SIZE_SMALL"
        let build: (String) throws -> URLRequest = { t in
            try self.panRequest(url, accessToken: accessToken, deviceId: deviceId, captchaToken: t)
        }
        let parse: (JSONValue) throws -> XunleiShareResult = { data in
            // 提取码状态检查：PASS_CODE_EMPTY / PASS_CODE_ERROR / PASS_CODE_NEED
            // 三种情况 files 为空数组且 HTTP 200，若不识别会被误判为「此目录为空」
            switch data.string("share_status") {
            case "PASS_CODE_EMPTY": throw ApiError("请输入提取码")
            case "PASS_CODE_ERROR": throw ApiError("提取码错误")
            case "PASS_CODE_NEED": throw ApiError("该分享需要提取码")
            default: break
            }
            let files = self.parseFileArray(data.array("files"))
            return XunleiShareResult(
                title: data.string("title"),
                files: files,
                passCodeToken: data.string("pass_code_token"),
                shareId: shareId,
                nextPageToken: data.string("next_page_token")
            )
        }
        // 游客模式（无 access_token）走匿名调用：不带验证码、也不刷新 token
        if accessToken.isEmpty {
            return try await panCallAnonymous(captchaToken: captchaToken, deviceId: deviceId, action: "GET:/drive/v1/share", build: build, parse: parse)
        } else {
            return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "GET:/drive/v1/share", build: build, parse: parse)
        }
    }

    /// 分享子目录文件列表（share/detail，parent_id + pass_code_token）
    func getShareDetail(
        shareId: String,
        parentId: String,
        passCodeToken: String,
        accessToken: String,
        deviceId: String,
        captchaToken: String,
        pageToken: String = ""
    ) async throws -> XunleiFilePage? {
        let url = XunleiConstants.SHARE_DETAIL_URL +
            "?share_id=" + shareId +
            "&parent_id=" + parentId +
            "&pass_code_token=" + urlEncode(passCodeToken) +
            "&limit=100&page_token=" + urlEncode(pageToken) +
            "&thumbnail_size=SIZE_SMALL"
        let build: (String) throws -> URLRequest = { t in
            try self.panRequest(url, accessToken: accessToken, deviceId: deviceId, captchaToken: t)
        }
        let parse: (JSONValue) throws -> XunleiFilePage = { data in
            XunleiFilePage(
                files: self.parseFileArray(data.array("files")),
                nextPageToken: data.string("next_page_token")
            )
        }
        if accessToken.isEmpty {
            return try await panCallAnonymous(captchaToken: captchaToken, deviceId: deviceId, action: "GET:/drive/v1/share/detail", build: build, parse: parse)
        } else {
            return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "GET:/drive/v1/share/detail", build: build, parse: parse)
        }
    }

    /// 转存到指定目录（官方同步返回 RESTORE_COMPLETE + trace_file_ids 映射），返回转存后的新文件 id
    func restore(
        shareId: String,
        passCodeToken: String,
        parentFolderId: String,
        fileIds: [String],
        accessToken: String,
        deviceId: String,
        captchaToken: String
    ) async throws -> String? {
        let body: [String: Any] = [
            "share_id": shareId,
            "pass_code_token": passCodeToken,
            "parent_id": parentFolderId,
            "ancestor_ids": [Any](),
            "file_ids": fileIds,
            "specify_parent_id": true,
        ]
        return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "POST:/drive/v1/share/restore") { t in
            try self.panRequest(XunleiConstants.RESTORE_URL, accessToken: accessToken, deviceId: deviceId, captchaToken: t, jsonBody: body)
        } parse: { data in
            // params.trace_file_ids 是 JSON 字符串：{"分享文件id":"转存后新id"}
            let trace = data.object("params").string("trace_file_ids")
            if let traceJson = JSONValue.parse(trace), traceJson.raw is [String: Any] {
                if let first = fileIds.first(where: { traceJson.has($0) }) {
                    let mapped = traceJson.string(first)
                    if !mapped.isEmpty { return mapped }
                }
            }
            let fid = data.string("file_id")
            return fid.isEmpty ? nil : fid
        }
    }

    /// 批量删除文件（转存后的临时文件；直链已自带签名，删除不影响下载）
    func batchDelete(
        ids: [String],
        accessToken: String,
        deviceId: String,
        captchaToken: String
    ) async throws -> Bool {
        let body: [String: Any] = [
            "ids": ids,
            "space": "",
        ]
        return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "POST:/drive/v1/files:batchDelete") { t in
            try self.panRequest("\(XunleiConstants.FILES_URL):batchDelete", accessToken: accessToken, deviceId: deviceId, captchaToken: t, jsonBody: body)
        } parse: { _ in true }
    }

    /// 轮询转存任务（最多 15 次 × 1s）
    func pollTask(taskId: String, accessToken: String, deviceId: String, captchaToken: String) async throws -> Bool {
        let url = "\(XunleiConstants.TASKS_URL)/\(taskId)?type=share"
        for _ in 0..<15 {
            var done = false
            do {
                done = try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "GET:/drive/v1/tasks/\(taskId)") { t in
                    try self.panRequest(url, accessToken: accessToken, deviceId: deviceId, captchaToken: t)
                } parse: { data in
                    let status = data.string("status").isEmpty ? data.string("phase") : data.string("status")
                    return status == "PHASE_TYPE_COMPLETE" || data.int("error_code") == 0
                }
            } catch {
                done = false
            }
            if done { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    /// 确保「YunX临时转存」目录存在，返回其 id
    func ensureTempDir(accessToken: String, deviceId: String, captchaToken: String) async throws -> String? {
        let root = (try await getFiles(parentId: "", accessToken: accessToken, deviceId: deviceId, captchaToken: captchaToken)) ?? []
        if let dir = root.first(where: { $0.isdir && $0.fname == XunleiConstants.TEMP_DIR_NAME }) {
            return dir.fid
        }
        return try await createFolder(name: XunleiConstants.TEMP_DIR_NAME, parentId: "", accessToken: accessToken, deviceId: deviceId, captchaToken: captchaToken)
    }

    // ---------- 云盘文件管理（迅雷网盘功能） ----------

    /// 网盘空间详情（GET /drive/v1/about：quota.limit / usage）
    func getQuota(accessToken: String, deviceId: String, captchaToken: String) async throws -> QuotaInfo? {
        do {
            return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "GET:/drive/v1/about") { t in
                try self.panRequest("\(XunleiConstants.PAN_BASE)/drive/v1/about", accessToken: accessToken, deviceId: deviceId, captchaToken: t)
            } parse: { data in
                let quota = data.object("quota")
                return QuotaInfo(
                    used: quota.long("usage"),
                    total: quota.long("limit"),
                    usedInTrash: quota.long("usage_in_trash")
                )
            }
        } catch {
            return nil
        }
    }

    /// 重命名（PATCH /drive/v1/files/{id}，body {"name"}）
    func renameFile(fileId: String, name: String, accessToken: String, deviceId: String, captchaToken: String) async throws -> Bool {
        let body: [String: Any] = ["name": name]
        return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "PATCH:/drive/v1/files/\(fileId)") { t in
            try self.panRequestM("\(XunleiConstants.FILES_URL)/\(fileId)", accessToken: accessToken, deviceId: deviceId, captchaToken: t, method: "PATCH", jsonBody: body)
        } parse: { data in
            !data.string("id").isEmpty
        }
    }

    /// 移动（batchMove：ids + to.parent_id）；返回 task_id
    func moveFile(fileIds: [String], toParentId: String, accessToken: String, deviceId: String, captchaToken: String) async throws -> String? {
        let body: [String: Any] = [
            "ids": fileIds,
            "to": ["parent_id": toParentId, "space": ""],
            "space": "",
        ]
        return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "POST:/drive/v1/files:batchMove") { t in
            try self.panRequestM(XunleiConstants.MOVE_URL, accessToken: accessToken, deviceId: deviceId, captchaToken: t, method: "POST", jsonBody: body)
        } parse: { data in
            let taskId = data.string("task_id")
            return taskId.isEmpty ? nil : taskId
        }
    }

    /// 创建分享（POST /drive/v1/share，迅雷分享带提取码；官方默认自动生成，可自定义 4 位）。
    /// - Parameters:
    ///   - expirationDays: "-1"=永久 "1"/"7"/"30"=天数（用 ShareExpire.xunleiDays 从中性码转换，别直接下发中性码）
    ///   - passCode: 自定义提取码（4 位字母数字，留空则服务端自动生成）
    /// - Returns: 分享信息（share_url/pass_code 直接返回）；接口不返回有效期，expiredType 填 UNKNOWN
    func createShare(
        fileIds: [String],
        title: String,
        expirationDays: String,
        accessToken: String,
        deviceId: String,
        captchaToken: String,
        passCode: String = ""
    ) async throws -> ShareInfo? {
        var params: [String: Any] = [
            "subscribe_push": "false",
            "WithPassCodeInLink": "true",
            "with_pass_code_in_link": "true",
        ]
        if !passCode.isEmpty { params["pass_code"] = passCode }
        let body: [String: Any] = [
            "file_ids": fileIds,
            "share_to": "copy",
            "params": params,
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "分享文件" : title,
            "restore_limit": "-1",
            "expiration_days": expirationDays,
        ]
        return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "POST:/drive/v1/share") { t in
            try self.panRequestM(XunleiConstants.SHARE_CREATE_URL, accessToken: accessToken, deviceId: deviceId, captchaToken: t, method: "POST", jsonBody: body)
        } parse: { data in
            let respTitle = data.string("title")
            return ShareInfo(
                shareUrl: data.string("share_url"),
                passcode: data.string("pass_code"),
                pwdId: data.string("share_id"),
                title: respTitle.isEmpty ? title : respTitle,
                // 响应的 data 里没有有效期字段，中性码由调用方覆盖
                expiredType: ShareExpire.UNKNOWN
            )
        }
    }

    /// 删除（batchTrash：ids + space，回收站）
    func deleteFiles(fileIds: [String], accessToken: String, deviceId: String, captchaToken: String) async throws -> Bool {
        let body: [String: Any] = [
            "ids": fileIds,
            "space": "",
        ]
        return try await panCall(captchaToken: captchaToken, deviceId: deviceId, action: "POST:/drive/v1/files:batchTrash") { t in
            try self.panRequestM(XunleiConstants.TRASH_URL, accessToken: accessToken, deviceId: deviceId, captchaToken: t, method: "POST", jsonBody: body)
        } parse: { _ in true }
    }

    // ---------- 请求构造 ----------

    private func parseFileArray(_ array: [JSONValue]) -> [ShareFile] {
        var result: [ShareFile] = []
        for item in array {
            // Kotlin 用 optJSONObject(i) 跳过非对象项
            guard item.raw is [String: Any] else { continue }
            result.append(
                ShareFile(
                    fid: item.string("id"),
                    fname: item.string("name"),
                    fsize: item.long("size"),
                    isdir: item.string("kind") == "drive#folder",
                    pdirFid: item.string("parent_id"),
                    fidToken: "",
                    modifyTime: item.string("modified_time")
                )
            )
        }
        return result
    }

    /// pan 请求（Bearer + 设备 + captcha 头，抓包确认无 x-signature）。
    /// accessToken 为空 = 游客模式：不写 Authorization 头。
    private func panRequest(
        _ url: String,
        accessToken: String,
        deviceId: String,
        captchaToken: String,
        jsonBody: [String: Any]? = nil,
        preferCachedToken: Bool = true
    ) throws -> URLRequest {
        var headers: [String: String] = [
            "User-Agent": XunleiConstants.WEB_UA,
            "X-Device-Id": deviceId,
            "X-Client-Version": "8.31.0.9726",
            "Content-Type": jsonContentType,
            "Origin": "https://pan.xunlei.com",
            "Referer": "https://pan.xunlei.com/",
        ]
        if !accessToken.isEmpty {
            // 登录态优先用刷新后的 currentAccessToken；preferCachedToken=false 时只认传入的 token
            let bearer = preferCachedToken ? (currentAccessToken.isEmpty ? accessToken : currentAccessToken) : accessToken
            headers["Authorization"] = "Bearer \(bearer)"
        }
        if !captchaToken.isEmpty { headers["X-Captcha-Token"] = captchaToken }
        return try makeRequest(url: url, method: jsonBody != nil ? "POST" : "GET", headers: headers, jsonBody: jsonBody)
    }

    /// pan 请求（支持 PATCH 等动词，云盘重命名 / 移动 / 建分享用）；accessToken 为空同 panRequest
    private func panRequestM(
        _ url: String,
        accessToken: String,
        deviceId: String,
        captchaToken: String,
        method: String,
        jsonBody: [String: Any]? = nil
    ) throws -> URLRequest {
        var headers: [String: String] = [
            "User-Agent": XunleiConstants.WEB_UA,
            "X-Device-Id": deviceId,
            "X-Client-Version": "8.31.0.9726",
            "Content-Type": jsonContentType,
            "Origin": "https://pan.xunlei.com",
            "Referer": "https://pan.xunlei.com/",
        ]
        if !accessToken.isEmpty {
            headers["Authorization"] = "Bearer \(currentAccessToken.isEmpty ? accessToken : currentAccessToken)"
        }
        if !captchaToken.isEmpty { headers["X-Captcha-Token"] = captchaToken }
        // Kotlin: body?.toRequestBody() ?: "{}".toRequestBody()
        switch method {
        case "PATCH":
            return try makeRequest(url: url, method: "PATCH", headers: headers, jsonBody: jsonBody ?? [:])
        case "GET":
            return try makeRequest(url: url, method: "GET", headers: headers, jsonBody: nil)
        default:
            return try makeRequest(url: url, method: "POST", headers: headers, jsonBody: jsonBody ?? [:])
        }
    }

    /// pan 请求带验证码自动刷新重试：失败 captcha_invalid → 用旧 token 换新 token → 重试一次
    private func panCall<T>(
        captchaToken: String,
        deviceId: String,
        action: String,
        build: (String) throws -> URLRequest,
        parse: (JSONValue) throws -> T
    ) async throws -> T {
        try await panCallInternal(captchaToken: captchaToken, deviceId: deviceId, action: action, anonymous: false, build: build, parse: parse)
    }

    /// 游客模式的 pan 调用（没有 access_token）：不带验证码、也不尝试刷新 token
    private func panCallAnonymous<T>(
        captchaToken: String,
        deviceId: String,
        action: String,
        build: (String) throws -> URLRequest,
        parse: (JSONValue) throws -> T
    ) async throws -> T {
        try await panCallInternal(captchaToken: captchaToken, deviceId: deviceId, action: action, anonymous: true, build: build, parse: parse)
    }

    private func panCallInternal<T>(
        captchaToken: String,
        deviceId: String,
        action: String,
        anonymous: Bool,
        build: (String) throws -> URLRequest,
        parse: (JSONValue) throws -> T
    ) async throws -> T {
        var token = anonymous ? captchaToken : (refreshedCaptcha ?? captchaToken)
        for attempt in 0..<2 {
            let response = try await send(try build(token))
            guard let json = JSONValue.parse(response.text) else {
                throw ApiError("响应解析失败（HTTP \(response.statusCode)）")
            }
            if !response.isSuccessful || json.has("error") {
                let err = json.string("error")
                // access_token 过期（401/unauthenticated）：refresh_token 换新 → 重新 init captcha → 重试
                if !anonymous && (response.statusCode == 401 || err == "unauthenticated") && attempt == 0 {
                    var refreshed: (String, String)? = nil
                    if let provider = refreshTokenProvider {
                        refreshed = await provider(deviceId)
                    }
                    if let refreshed = refreshed {
                        currentAccessToken = refreshed.0
                        if let newCaptcha = await initPanCaptcha(deviceId: deviceId, action: action, oldToken: token), !newCaptcha.isEmpty {
                            refreshedCaptcha = newCaptcha
                            token = newCaptcha
                        }
                        continue
                    }
                }
                if !anonymous && err == "captcha_invalid" && attempt == 0 {
                    // 用正确 action + captcha_sign 重新 init（携带旧 token），拿有效 token 后重试
                    if let newToken = await initPanCaptcha(deviceId: deviceId, action: action, oldToken: token), !newToken.isEmpty {
                        refreshedCaptcha = newToken
                        token = newToken
                        continue
                    }
                }
                var msg = json.string("error_description")
                if msg.isEmpty { msg = json.string("message") }
                if msg.isEmpty { msg = err }
                if msg.isEmpty { msg = "请求失败" }
                throw ApiError(msg)
            }
            let dataNode = json.object("data")
            return try parse(dataNode.isNull ? json : dataNode)
        }
        throw ApiError("验证码刷新后仍失败")
    }

    /// 用请求对应 action + 正确 captcha_sign 初始化 captcha（pan 专用，alist 算法已验证）。
    private func initPanCaptcha(deviceId: String, action: String, oldToken: String) async -> String? {
        let ts = String(Int64(Date().timeIntervalSince1970 * 1000))
        let sign = buildCaptchaSign(deviceId: deviceId, tsMs: ts)
        let meta: [String: Any] = [
            "client_version": XunleiConstants.APP_CLIENT_VERSION,
            "package_name": XunleiConstants.APP_PACKAGE_NAME,
            "timestamp": ts,
            "captcha_sign": sign,
            "user_id": currentUserId, // 真实 user_id，空会得到降级 token（POST 类接口拒绝）
        ]
        let body: [String: Any] = [
            "client_id": XunleiConstants.APP_CLIENT_ID,
            "action": action,
            "device_id": deviceId,
            "redirect_uri": "xlaccsdk01://xunlei.com/callback?state=harbor",
            "meta": meta,
            "captcha_token": oldToken,
        ]
        let headers = [
            "User-Agent": XunleiConstants.APP_UA,
            "Accept": "application/json;charset=UTF-8",
            "Content-Type": jsonContentType,
            "X-Client-Id": XunleiConstants.APP_CLIENT_ID,
            "X-Device-Id": deviceId,
            "X-Client-Version": "8.31.0.9726",
        ]
        do {
            let request = try makeRequest(url: XunleiConstants.CAPTCHA_INIT_URL, method: "POST", headers: headers, jsonBody: body)
            let response = try await send(request)
            let json = try decode(response)
            let token = json.string("captcha_token")
            return token.isEmpty ? nil : token
        } catch {
            return nil
        }
    }

    /// captcha_sign：client_id+client_version+package_name+device_id+timestamp_ms → 10 层 md5(raw+salt)，前缀 "1."
    private func buildCaptchaSign(deviceId: String, tsMs: String) -> String {
        var h = XunleiConstants.APP_CLIENT_ID + XunleiConstants.APP_CLIENT_VERSION +
            XunleiConstants.APP_PACKAGE_NAME + deviceId + tsMs
        for salt in XunleiConstants.CAPTCHA_SALTS {
            h = xunleiMD5Hex(h + salt)
        }
        return "1.\(h)"
    }

    // ---------- 口令 ----------

    /// 迅雷中文口令（如「张三丰资源」）→ 带提取码的分享链接（免登录）。
    func parseKouling(_ keyword: String) async throws -> String {
        let headers = [
            "User-Agent": XunleiKouling.USER_AGENT,
            "Accept": "*/*",
            "Origin": XunleiKouling.ORIGIN,
            "Referer": XunleiKouling.REFERER,
            "Accept-Language": "zh-CN",
        ]
        let request = try makeRequest(url: XunleiKouling.buildJumpUrl(keyword), method: "GET", headers: headers)
        let response = try await send(request)
        if !response.isSuccessful { throw ApiError("口令解析失败（HTTP \(response.statusCode)）") }
        guard let json = JSONValue.parse(response.text) else {
            throw ApiError("口令解析失败：响应格式异常")
        }
        let type = json.object("ext").string("kouling_type")
        if type != "share_page" { throw ApiError("口令「\(keyword)」没有对应的网盘分享") }
        guard let shareUrl = XunleiKouling.shareUrlFromLocation(json.string("location")) else {
            throw ApiError("口令「\(keyword)」没有对应的网盘分享")
        }
        return shareUrl
    }

    // ---------- 静态辅助 ----------

    /// 设备 ID：动态生成的设备指纹（iOS 侧持久化于 UserDefaults）
    static func newDeviceId() -> String { XunleiDeviceFingerprint.deviceId() }

    /// 解析 reviewurl（review_panel 返回的验证面板链接）的查询参数。
    static func parseReviewUrl(_ reviewUrl: String) -> [String: String] {
        var map: [String: String] = [:]
        guard let idx = reviewUrl.firstIndex(of: "?") else { return map }
        let query = String(reviewUrl[reviewUrl.index(after: idx)...])
        for pair in query.components(separatedBy: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2 {
                let decoded = parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? parts[1]
                map[parts[0]] = decoded
            } else if parts.count == 1 && !parts[0].isEmpty {
                map[parts[0]] = ""
            }
        }
        return map
    }
}

// MARK: - 迅雷分享解析仓库（对应 XunleiResolveRepository.kt）

/// 迅雷分享解析仓库：解析分享 → 转存到临时目录 → 文件详情取直链。
/// 认证用 access_token（经 AccountStore 提供），无需转存密码（pass_code 由分享提供）。
/// 列目录允许游客：未登录时 token 传空串，请求不带 Authorization；取直链 / 转存仍需登录。
final class XunleiResolveRepository: ShareResolveRepository {

    private let api: XunleiApi

    /// shareId → 提取码（转存时仍需携带）
    private var passCodes: [String: String] = [:]

    /// 游客模式自造的设备标识（迅雷请求需要 X-Device-Id；未登录时进程内复用，不落库）
    private lazy var guestDeviceId: String = XunleiApi.newDeviceId()

    init() {
        let api = XunleiApi()
        self.api = api
        // token 过期自动刷新回调：401 时用 refresh_token 换新 token 并落库（weak 避免自持有环）
        api.refreshTokenProvider = { [weak api] deviceId in
            guard let api = api else { return nil }
            return await XunleiResolveRepository.refreshAccessToken(api: api, deviceId: deviceId)
        }
    }

    // ---------- 账号 / 设备 / 验证码 provider ----------

    /// 登录态 access_token（未登录返回 nil）
    private func accountToken() async -> String? {
        let token = await MainActor.run { () -> String in
            guard let record = AccountStore.shared.record(for: .xunlei), record.loggedIn, !record.token.isEmpty else { return "" }
            return record.token
        }
        return token.isEmpty ? nil : token
    }

    /// 账号持久化的设备标识（未设置返回 nil）
    private func currentDeviceId() async -> String? {
        let id = await MainActor.run { () -> String in
            AccountStore.shared.record(for: .xunlei)?.deviceId ?? ""
        }
        return id.isEmpty ? nil : id
    }

    /// 账号持久化的 captcha_token（AccountRecord 未单独存该字段，返回空串兜底）
    private func captcha() async -> String { "" }

    /// 取 access_token 并缓存 user_id（captcha/init 需要，空 user_id 会得到降级 token）
    private func access() async throws -> String {
        try await ensureFreshToken() // token 过期则先自动刷新
        let t = try await token()
        api.cacheUserId(accessToken: t)
        return t
    }

    /// 列表用 token：未登录返回空串 ⇒ 走匿名分享接口
    private func accessOrEmpty() async throws -> String {
        if await accountToken() == nil { return "" }
        return try await access()
    }

    private func token() async throws -> String {
        guard let t = await accountToken() else { throw ApiError("请先登录迅雷网盘") }
        return t
    }

    /// token 即将过期（<60s）或已过期时，用 refresh_token 自动刷新
    private func ensureFreshToken() async throws {
        guard let acc = await accountToken() else { return }
        let exp = api.jwtExp(acc)
        if exp > 0 && exp - Int64(Date().timeIntervalSince1970) > 60 { return }
        // 刷新失败（refresh_token 被轮换 / 过期）→ 抛明确错误引导重新登录
        if await refreshTokens() == nil {
            throw ApiError("迅雷登录已过期，请重新登录")
        }
    }

    private func deviceId() async throws -> String {
        guard let d = await currentDeviceId() else { throw ApiError("缺少设备标识") }
        return d
    }

    /// 设备标识：未登录时回退游客设备标识，别让「缺少设备标识」把匿名列目录挡在门外
    private func deviceIdOrGuest() async -> String {
        if let d = await currentDeviceId() { return d }
        return guestDeviceId
    }

    /// 用持久化的 refresh_token 刷新并落库
    private func refreshTokens() async -> (String, String)? {
        let device = (await currentDeviceId()) ?? XunleiApi.newDeviceId()
        return await XunleiResolveRepository.refreshAccessToken(api: api, deviceId: device)
    }

    /// 读取 refresh_token → 刷新 → 落库；失败返回 nil。
    /// 注：AccountRecord 未持久化 authType，这里按 App 通道刷新；网页 token 需扩展记录该字段。
    private static func refreshAccessToken(api: XunleiApi, deviceId: String) async -> (String, String)? {
        let refreshToken = await MainActor.run { AccountStore.shared.record(for: .xunlei)?.refreshToken ?? "" }
        if refreshToken.isEmpty { return nil }
        guard let tokens = try? await api.refreshToken(refreshToken, deviceId: deviceId, authType: "") else { return nil }
        await MainActor.run {
            AccountStore.shared.update(.xunlei) { record in
                record.token = tokens.0
                record.refreshToken = tokens.1
            }
        }
        return tokens
    }

    // ---------- ShareResolveRepository ----------

    /// 迅雷中文口令（如「张三丰资源」）→ 带提取码的分享链接。免登录。
    func resolveKouling(_ keyword: String) async -> Result<String, Error> {
        do {
            return .success(try await api.parseKouling(keyword))
        } catch {
            return .failure(error)
        }
    }

    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        guard let parsed = ShareLinkParser.parse(link) else {
            throw ApiError("无法识别迅雷分享链接")
        }
        let shareId = parsed.shareId
        var effectivePwd = parsed.pwd ?? ""
        if let pwd = pwd, !pwd.isEmpty { effectivePwd = pwd }
        passCodes[shareId] = effectivePwd
        // 游客模式：未登录时 token 为空 → 匿名请求（无 Authorization 头）
        let access = try await accessOrEmpty()
        guard let result = try await api.getShare(
            shareId: shareId,
            passCode: effectivePwd,
            accessToken: access,
            deviceId: await deviceIdOrGuest(),
            captchaToken: await captcha()
        ) else {
            throw ApiError("未获取到分享信息")
        }
        return ShareSession(shareId: shareId, stoken: result.passCodeToken, title: result.title)
    }

    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        // 游客模式同样放行：无 token 时匿名列目录（下载 / 转存仍要求登录）
        let access = try await accessOrEmpty()
        let device = await deviceIdOrGuest()
        let captcha = await captcha()
        var files: [ShareFile] = []
        var pageToken = ""
        var pages = 0
        repeat {
            if dirFid.isEmpty || dirFid == "0" {
                guard let page = try await api.getShare(
                    shareId: session.shareId,
                    passCode: passCodes[session.shareId] ?? "",
                    accessToken: access,
                    deviceId: device,
                    captchaToken: captcha,
                    pageToken: pageToken
                ) else {
                    throw ApiError("未获取到文件列表")
                }
                files += page.files
                pageToken = page.nextPageToken
            } else {
                guard let page = try await api.getShareDetail(
                    shareId: session.shareId,
                    parentId: dirFid,
                    passCodeToken: session.stoken,
                    accessToken: access,
                    deviceId: device,
                    captchaToken: captcha,
                    pageToken: pageToken
                ) else {
                    throw ApiError("未获取到文件列表")
                }
                files += page.files
                pageToken = page.nextPageToken
            }
            pages += 1
        } while !pageToken.isEmpty && pages < 100
        return files
    }

    func ensureTempDir(cookie: String) async throws -> String {
        guard let dir = try await api.ensureTempDir(accessToken: try await access(), deviceId: try await deviceId(), captchaToken: await captcha()) else {
            throw ApiError("创建临时目录失败")
        }
        return dir
    }

    func transferFile(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        // 官方同步转存：restore 返回 trace_file_ids 映射，直接得到转存后的新文件 id（无需轮询）
        guard let newId = try await api.restore(
            shareId: session.shareId,
            passCodeToken: session.stoken,
            parentFolderId: toDirFid,
            fileIds: [file.fid],
            accessToken: try await access(),
            deviceId: try await deviceId(),
            captchaToken: await captcha()
        ) else {
            throw ApiError("转存失败")
        }
        return newId
    }

    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        guard let link = try await api.getFileDetail(
            fileId: fid,
            accessToken: try await access(),
            deviceId: try await deviceId(),
            captchaToken: await captcha()
        ) else {
            throw ApiError("获取下载链接失败")
        }
        return link
    }

    /// 迅雷取直链：转存 → 取详情直链 → 删除临时转存文件（直链自带签名，删除不影响下载）
    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        let dirFid = try await ensureTempDir(cookie: cookie)
        let savedFid = try await transferFile(session: session, file: file, toDirFid: dirFid, cookie: cookie)
        guard let link = try await api.getFileDetail(
            fileId: savedFid,
            accessToken: try await access(),
            deviceId: try await deviceId(),
            captchaToken: await captcha()
        ) else {
            throw ApiError("获取下载链接失败")
        }
        // 拿到直链后立即删除临时转存的文件（对齐官方 batchDelete；失败不阻断下载）
        _ = try? await api.batchDelete(ids: [savedFid], accessToken: try await access(), deviceId: try await deviceId(), captchaToken: await captcha())
        return link
    }
}
