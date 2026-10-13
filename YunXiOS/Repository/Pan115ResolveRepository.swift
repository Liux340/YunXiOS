/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：115 网盘接口层 + 分享解析仓库。
 * 对应 Android 侧：
 *   - data/network/Pan115Constants.kt
 *   - data/network/Pan115Crypto.kt
 *   - data/network/Pan115Api.kt
 *   - data/repository/Pan115ResolveRepository.kt
 * 仅依赖 Foundation（RSA/AES 类的私有协议用纯 Swift 大整数实现）。
 */

import Foundation

// MARK: - 115 网盘常量（对应 Pan115Constants.kt）

enum Pan115Constants {

    // ---------- 基址 ----------

    /// 业务 API 主域（个人盘 + 分享接口同域）
    static let API_BASE = "https://webapi.115.com"
    /// 网页版登录入口
    static let WEB_LOGIN_URL = "https://115.com/"
    /// 分享链接域名
    static let SHARE_HOST = "https://115cdn.com"
    /// 通用 Referer
    static let REFERER = "https://115.com/"
    /// 直链下载必须携带的 Referer
    static let DOWNLOAD_REFERER = "https://115.com/"

    // ---------- 接口路径 ----------

    /// 登录态校验 + 昵称
    static let USER_INFO_URL = "\(API_BASE)/user/info?ct=json"
    /// 个人盘列目录
    static let FILES_URL = "\(API_BASE)/files"
    /// 个人盘空间信息
    static let INDEX_INFO_URL = "\(API_BASE)/files/index_info?count_space_nums=1"
    /// 新建文件夹
    static let FILE_ADD_URL = "\(API_BASE)/files/add"
    /// 移动 / 复制
    static let FILE_MOVE_URL = "\(API_BASE)/files/move"
    /// 移动异步进度
    static let MOVE_PROGRESS_URL = "\(API_BASE)/files/move_progress"
    /// 重命名
    static let FILE_RENAME_URL = "\(API_BASE)/files/batch_rename"
    /// 删除（进回收站）
    static let FILE_DELETE_URL = "\(API_BASE)/rb/delete"
    /// 个人盘直链（仅小文件可用，大文件 50028）
    static let FILE_DOWNLOAD_URL = "\(API_BASE)/files/download"
    /// 「电脑端」直链接口（加密协议）
    static let APP_DOWNLOAD_URL = "https://proapi.115.com/app/chrome/downurl"
    /// 首次分享前的协议确认
    static let ALLOW_PROTOCOL_URL = "\(API_BASE)/user/allow_protocol"
    /// 创建分享
    static let SHARE_SEND_URL = "\(API_BASE)/share/send"
    /// 修改分享
    static let SHARE_UPDATE_URL = "\(API_BASE)/share/updateshare"
    /// 分享详情回读
    static let SHARE_INFO_URL = "\(API_BASE)/share/shareinfo"
    /// 分享列目录
    static let SHARE_SNAP_URL = "\(API_BASE)/share/snap"
    /// 分享直链
    static let SHARE_DOWNLOAD_URL = "\(API_BASE)/share/downurl"
    /// 转存
    static let SHARE_RECEIVE_URL = "\(API_BASE)/share/receive"

    // ---------- 请求参数 ----------

    static let AID_PERSONAL = "1"
    static let ROOT_CID = "0"
    static let PAGE_LIMIT = 100
    static let SHARE_PAGE_LIMIT = 100
    static let MOVE_POLL_MAX = 20
    static let MOVE_POLL_INTERVAL_MS: Int64 = 400
    static let TEMP_DIR_NAME = "YunX临时转存"
    static let TEMP_SUBDIR_PREFIX = "tr_"

    // ---------- 公共请求头 ----------

    static let WEB_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"

    static let X_REQUESTED_WITH = "XMLHttpRequest"

    /// 下载专用客户端 UA 的版本号兜底值
    static let CLIENT_UA_VERSION_FALLBACK = "36.0.1"

    /// 115 客户端版本接口
    static let APP_VERSION_URL = "https://appversion.115.com/1/web/1.0/api/chrome"

    // ---------- 可变客户端 UA（对应 Kotlin 的 @Volatile var CLIENT_UA） ----------

    private static let clientLock = NSLock()
    private static var _clientUA = "Mozilla/5.0 115Browser/\(CLIENT_UA_VERSION_FALLBACK)"

    /// 下载专用客户端 UA（进程级缓存，可被 applyClientVersion 刷新）
    static var CLIENT_UA: String {
        clientLock.lock(); defer { clientLock.unlock() }
        return _clientUA
    }

    /// 拼客户端 UA
    static func clientUa(version: String) -> String { "Mozilla/5.0 115Browser/\(version)" }

    /// 用最新客户端版本号刷新 CLIENT_UA（非法值忽略，失败保留旧值）
    static func applyClientVersion(_ version: String?) {
        let value = (version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 16,
              let first = value.first, first.isNumber,
              value.allSatisfy({ $0.isNumber || $0 == "." }) else { return }
        clientLock.lock(); defer { clientLock.unlock() }
        if _clientUA.hasSuffix("/\(value)") { return }
        _clientUA = clientUa(version: value)
    }

    // ---------- 其它 ----------

    static let SHARE_LINK_HOST = "115cdn.com"
    static let COOKIE_DOMAIN = "https://115.com"
    static let COOKIE_DOMAIN_BACKUP = "https://webapi.115.com"

    /// 需要保留的 Cookie 字段
    static let COOKIE_KEEP_KEYS: Set<String> = ["UID", "CID", "SEID", "KID", "PHPSESSID", "GST", "USERSESSIONID"]

    // ---------- 错误码 ----------

    static let ERRNO_LOGIN_TIMEOUT = 990001
    static let ERRNO_NEED_CODE = 4100012
    static let ERRNO_WRONG_CODE = 4100008
    static let ERRNO_SHARE_GONE = 4100026
    static let ERRNO_EMPTY_FOLDER = 4100016
    static let ERRNO_BUSY = 990009
    static let ERRNO_NEED_CONFIRM = 800007
    static let ERRNO_WEB_SIZE_LIMIT = 50028
    static let ERRNO_CLIENT_TOO_OLD = 50029

    // ---------- 工具方法 ----------

    /// 分享页 Referer
    static func shareReferer(shareCode: String, receiveCode: String) -> String {
        if receiveCode.isEmpty { return "\(SHARE_HOST)/s/\(shareCode)" }
        return "\(SHARE_HOST)/s/\(shareCode)?password=\(receiveCode)&"
    }

    /// 取 Cookie 中某字段的值
    static func cookieValue(_ cookie: String, _ name: String) -> String? {
        for part in cookie.components(separatedBy: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces)
            if pair.hasPrefix("\(name)=") {
                let value = String(pair.dropFirst(name.count + 1))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// 登录态 Cookie 是否可用（只校验 UID）
    static func hasLoginCookie(_ cookie: String) -> Bool { cookieValue(cookie, "UID") != nil }

    /// Cookie 中 UID 的纯数字前缀（创建分享 / 分享直链的 user_id 都要它）
    static func extractUserId(_ cookie: String) -> String? {
        guard let uid = cookieValue(cookie, "UID") else { return nil }
        let prefix = uid.prefix(while: { $0 != "_" })
        let text = String(prefix)
        return text.isEmpty ? nil : text
    }

    /// 合并多段 Cookie
    static func mergeCookies(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: "; ")
    }

    /// 从 WebView 的 CookieManager 提取登录 Cookie
    static func extractCookies(_ getCookie: (String) -> String?) -> String {
        var result: [(String, String)] = []
        var seen = Set<String>()
        for domain in [COOKIE_DOMAIN, COOKIE_DOMAIN_BACKUP] {
            guard let raw = getCookie(domain) else { continue }
            for kv in raw.components(separatedBy: ";") {
                let pair = kv.trimmingCharacters(in: .whitespaces)
                guard let eq = pair.firstIndex(of: "="), eq != pair.startIndex else { continue }
                let key = String(pair[..<eq])
                let value = String(pair[pair.index(after: eq)...])
                if COOKIE_KEEP_KEYS.contains(key) && !seen.contains(key) {
                    seen.insert(key)
                    result.append((key, value))
                }
            }
        }
        return result.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
    }

    /// 登录 Cookie 是否形似可用（UID + SEID）
    static func isValidCookie(_ cookie: String?) -> Bool {
        guard let cookie = cookie, !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        func has(_ name: String) -> Bool {
            cookie.components(separatedBy: ";").contains { part in
                let pair = part.trimmingCharacters(in: .whitespaces)
                return pair.hasPrefix("\(name)=") && pair.count > name.count + 1
            }
        }
        return has("UID") && has("SEID")
    }

    /// 分享会话 token：`<receive_code>|<分享者 user_id>`
    static func encodeShareToken(receiveCode: String, userId: String) -> String { "\(receiveCode)|\(userId)" }

    /// 反解 encodeShareToken；格式异常时把整串当提取码、UID 视为空
    static func decodeShareToken(_ token: String) -> (receiveCode: String, userId: String) {
        guard let idx = token.firstIndex(of: "|") else { return (token, "") }
        return (String(token[..<idx]), String(token[token.index(after: idx)...]))
    }
}

// MARK: - 115 有效期中性码映射（对应 ShareExpire.kt 的 115 段落）

/// 115 的 share_duration 档位与本项目中性码不同（无 30 天、多 3/15 天），单独占 101..105 码位。
private enum Pan115ShareExpire {
    static let UNKNOWN = 0
    static let FOREVER = 101
    static let ONE_DAY = 102
    static let THREE_DAYS = 103
    static let SEVEN_DAYS = 104
    static let FIFTEEN_DAYS = 105

    /// 115 码位 → share_duration（-1 = 长期）
    static func duration(of expiredType: Int) throws -> String {
        switch expiredType {
        case FOREVER: return "-1"
        case ONE_DAY: return "1"
        case THREE_DAYS: return "3"
        case SEVEN_DAYS: return "7"
        case FIFTEEN_DAYS: return "15"
        default: throw ApiError("未知的分享有效期代码：\(expiredType)")
        }
    }

    /// share_duration 字符串 → 115 码位（认不出返回 UNKNOWN）
    static func codeOf(_ duration: String) -> Int {
        switch duration.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "-1": return FOREVER
        case "1": return ONE_DAY
        case "3": return THREE_DAYS
        case "7": return SEVEN_DAYS
        case "15": return FIFTEEN_DAYS
        default: return UNKNOWN
        }
    }

    /// 115 返回的有效期文案（形如 `15天` / `长期`）→ 115 码位
    static func codeOfText(_ text: String) -> Int {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return UNKNOWN }
        if value.contains("长期") || value.contains("永久") { return FOREVER }
        let days = String(value.prefix(while: { $0.isNumber }))
        return days.isEmpty ? UNKNOWN : codeOf(days)
    }
}

// MARK: - 115 私有下载协议加解密（对应 Pan115Crypto.kt）

/// 115「电脑端」下载接口（proapi.115.com/app/chrome/downurl）的请求/响应加解密。
///
/// 协议结构：
/// - 请求：`data = base64( RSA( 16字节key || 密文 ) )`，RSA 为 1024 位、指数 65537、128 字节分块；
/// - 响应：`base64( RSA密文 )` → 去掉前 16 字节（服务端 salt）后按 12/4 两段 XOR 解出明文 JSON。
///
/// 这套「RSA」在客户端侧只是 `modPow(e)`（服务端拿私钥做「加密」，本质是签名），
/// 所以公钥就能解回来。Java 用 `BigInteger.modPow` 实现，这里用纯 Swift 大整数复刻同样的运算，
/// 逐字节与参考实现（115drive-webdav / 115-minus）保持一致。
enum Pan115Crypto {

    /// XOR 密钥表（144 字节）
    private static let keyTable: [UInt8] = [
        0xf0, 0xe5, 0x69, 0xae, 0xbf, 0xdc, 0xbf, 0x8a,
        0x1a, 0x45, 0xe8, 0xbe, 0x7d, 0xa6, 0x73, 0xb8,
        0xde, 0x8f, 0xe7, 0xc4, 0x45, 0xda, 0x86, 0xc4,
        0x9b, 0x64, 0x8b, 0x14, 0x6a, 0xb4, 0xf1, 0xaa,
        0x38, 0x01, 0x35, 0x9e, 0x26, 0x69, 0x2c, 0x86,
        0x00, 0x6b, 0x4f, 0xa5, 0x36, 0x34, 0x62, 0xa6,
        0x2a, 0x96, 0x68, 0x18, 0xf2, 0x4a, 0xfd, 0xbd,
        0x6b, 0x97, 0x8f, 0x4d, 0x8f, 0x89, 0x13, 0xb7,
        0x6c, 0x8e, 0x93, 0xed, 0x0e, 0x0d, 0x48, 0x3e,
        0xd7, 0x2f, 0x88, 0xd8, 0xfe, 0xfe, 0x7e, 0x86,
        0x50, 0x95, 0x4f, 0xd1, 0xeb, 0x83, 0x26, 0x34,
        0xdb, 0x66, 0x7b, 0x9c, 0x7e, 0x9d, 0x7a, 0x81,
        0x32, 0xea, 0xb6, 0x33, 0xde, 0x3a, 0xa9, 0x59,
        0x34, 0x66, 0x3b, 0xaa, 0xba, 0x81, 0x60, 0x48,
        0xb9, 0xd5, 0x81, 0x9c, 0xf8, 0x6c, 0x84, 0x77,
        0xff, 0x54, 0x78, 0x26, 0x5f, 0xbe, 0xe8, 0x1e,
        0x36, 0x9f, 0x34, 0x80, 0x5c, 0x45, 0x2c, 0x9b,
        0x76, 0xd5, 0x1b, 0x8f, 0xcc, 0xc3, 0xb8, 0xf5,
    ]

    /// 12 字节长密钥
    private static let longKey: [UInt8] = [
        0x78, 0x06, 0xad, 0x4c, 0x33, 0x86, 0x5d, 0x18, 0x4c, 0x01, 0x3f, 0x46,
    ]

    /// 1024 位 RSA 公钥模数
    private static let modulus = BigUInt(hex:
        "8686980c0f5a24c4b9d43020cd2c22703ff3f450756529058b1cf88f09b86021" +
        "36477198a6e2683149659bd122c33592fdb5ad47944ad1ea4d36c6b172aad633" +
        "8c3bb6ac6227502d010993ac967d1aef00f0c8e038de2e4d3bc2ec368af2e9f1" +
        "0a6f1eda4f7262f136420c07c331b871bf139f74f3010e3c4fe57df3afb71683")

    /// 公钥指数 65537
    private static let exponent = BigUInt(bytes: [0x01, 0x00, 0x01])

    /// RSA 分块：加密 117 字节（128 - 11），解密 128 字节
    private static let rsaEncodeBlock = 117
    private static let rsaBlock = 128

    /// 生成一次请求用的 16 字节 key
    static func newKey() -> [UInt8] { (0..<16).map { _ in UInt8.random(in: 0...255) } }

    /// 明文 payload → 请求体 `data` 参数值（base64）
    static func encode(_ payload: String, key: [UInt8]) throws -> String {
        guard key.count == 16 else { throw ApiError("115 下载协议要求 16 字节 key") }
        var body = Array(payload.utf8)
        symmetricEncode(&body, key: key)
        let plain = key + body
        let out = rsaEncrypt(plain)
        return Data(out).base64EncodedString()
    }

    /// 响应 `data` 字段（base64）→ 明文 JSON
    static func decode(_ data: String, key: [UInt8]) throws -> String {
        guard key.count == 16 else { throw ApiError("115 下载协议要求 16 字节 key") }
        guard let raw = Data(base64Encoded: data, options: [.ignoreUnknownCharacters]) else {
            throw ApiError("115 下载响应 base64 解析失败")
        }
        let decrypted = try rsaDecrypt([UInt8](raw))
        guard decrypted.count > 16 else { throw ApiError("115 下载响应长度异常") }
        let salt = Array(decrypted[0..<16])
        var body = Array(decrypted[16...])
        symmetricDecode(&body, key: key, salt: salt)
        return String(decoding: body, as: UTF8.self)
    }

    // ---------- 对称变换 ----------

    /// XOR → 反转 → 用长密钥再 XOR
    private static func symmetricEncode(_ data: inout [UInt8], key: [UInt8]) {
        xorTransform(&data, key: deriveKey(seed: key, size: 4))
        data.reverse()
        xorTransform(&data, key: longKey)
    }

    /// 用服务端 salt 反 XOR → 反转 → 用我们的 key 再 XOR
    private static func symmetricDecode(_ data: inout [UInt8], key: [UInt8], salt: [UInt8]) {
        xorTransform(&data, key: deriveKey(seed: salt, size: 12))
        data.reverse()
        xorTransform(&data, key: deriveKey(seed: key, size: 4))
    }

    /// key[i] = ((seed[i] + KEY_TABLE[size*i]) & 0xff) ^ KEY_TABLE[size*(size-1-i)]
    private static func deriveKey(seed: [UInt8], size: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: size)
        for i in 0..<size {
            let left = Int(keyTable[size * i])
            let right = Int(keyTable[size * (size - 1 - i)])
            let s = Int(seed[i % seed.count])
            out[i] = UInt8((((s + left) & 0xff) ^ right) & 0xff)
        }
        return out
    }

    /// 先处理 len%4 的前缀，其余整体平移
    private static func xorTransform(_ data: inout [UInt8], key: [UInt8]) {
        let offset = data.count % 4
        if offset > 0 {
            for i in 0..<offset { data[i] = data[i] ^ key[i % key.count] }
        }
        if data.count > offset {
            for i in offset..<data.count { data[i] = data[i] ^ key[(i - offset) % key.count] }
        }
    }

    // ---------- RSA（实为公钥 modPow） ----------

    /// RSA 分块「加密」：PKCS#1 v1.5 填充后按公钥指数做 modPow
    private static func rsaEncrypt(_ input: [UInt8]) -> [UInt8] {
        var out = [UInt8]()
        var offset = 0
        while offset < input.count {
            let size = min(rsaEncodeBlock, input.count - offset)
            var block = [UInt8](repeating: 0xff, count: rsaBlock)
            block[0] = 0
            block[1] = 2
            let separator = rsaBlock - size - 1
            block[separator] = 0
            for i in 0..<size { block[separator + 1 + i] = input[offset + i] }
            let value = BigUInt(bytes: block)
            let enc = value.modPow(exp: exponent, mod: modulus)
            out.append(contentsOf: enc.toFixedBytes(rsaBlock))
            offset += size
        }
        return out
    }

    /// RSA 分块「解密」：服务端用私钥加密，这里用公钥指数还原
    private static func rsaDecrypt(_ input: [UInt8]) throws -> [UInt8] {
        var out = [UInt8]()
        var offset = 0
        while offset < input.count {
            let size = min(rsaBlock, input.count - offset)
            let block = Array(input[offset..<(offset + size)])
            let value = BigUInt(bytes: block)
            let plain = value.modPow(exp: exponent, mod: modulus).toFixedBytes(rsaBlock)
            // PKCS#1 v1.5：0x00 0x02 <填充> 0x00 <数据>，从第 2 字节起找第一个 0x00
            var start = -1
            var i = 2
            while i < plain.count {
                if plain[i] == 0 { start = i + 1; break }
                i += 1
            }
            guard start >= 1 && start < plain.count else {
                throw ApiError("115 下载响应缺少 RSA 分隔符")
            }
            out.append(contentsOf: plain[start...])
            offset += size
        }
        return out
    }
}

// MARK: - 纯 Swift 大整数（只实现 115 协议所需的运算）

/// 只读大整数，用于复刻 Java BigInteger 的 `modPow`。
/// 小端 UInt32 肢体存储，仅在 1024 位模数下使用：乘/除通过「双倍-相加」保持结果 < m，
/// 因此无需通用除法（初值若 ≥ m，因 m ≥ 2^1023、输入 < 2^1024，最多减一次即可）。
private struct BigUInt {

    /// 小端肢体（已归一化，去掉高位 0）
    private let limbs: [UInt32]

    init(limbs: [UInt32]) {
        var l = limbs
        while let last = l.last, last == 0 { l.removeLast() }
        self.limbs = l
    }

    /// 大端字节序构造
    init(bytes: [UInt8]) {
        var l: [UInt32] = []
        var idx = bytes.count
        while idx > 0 {
            var v: UInt32 = 0
            var k: UInt32 = 0
            var count = 0
            while count < 4 && idx > 0 {
                idx -= 1
                v |= UInt32(bytes[idx]) << (8 * k)
                k += 1
                count += 1
            }
            l.append(v)
        }
        self.init(limbs: l)
    }

    /// 十六进制构造
    init(hex: String) {
        var chars = Array(hex)
        if chars.count % 2 == 1 { chars.insert("0", at: 0) }
        var bytes = [UInt8]()
        var i = 0
        while i < chars.count {
            let hi = UInt8(String(chars[i]), radix: 16) ?? 0
            let lo = UInt8(String(chars[i + 1]), radix: 16) ?? 0
            bytes.append((hi << 4) | lo)
            i += 2
        }
        self.init(bytes: bytes)
    }

    var isZero: Bool { limbs.isEmpty }

    var bitLength: Int {
        guard let last = limbs.last else { return 0 }
        return limbs.count * 32 - last.leadingZeroBitCount
    }

    func bit(_ index: Int) -> Bool {
        let limbIndex = index / 32
        if limbIndex >= limbs.count { return false }
        return (limbs[limbIndex] >> UInt32(index % 32)) & 1 == 1
    }

    func compare(_ other: BigUInt) -> Int {
        if limbs.count != other.limbs.count { return limbs.count < other.limbs.count ? -1 : 1 }
        var i = limbs.count - 1
        while i >= 0 {
            if limbs[i] != other.limbs[i] { return limbs[i] < other.limbs[i] ? -1 : 1 }
            i -= 1
        }
        return 0
    }

    func adding(_ other: BigUInt) -> BigUInt {
        let n = max(limbs.count, other.limbs.count)
        var result: [UInt32] = []
        var carry: UInt64 = 0
        for i in 0..<n {
            let a = i < limbs.count ? UInt64(limbs[i]) : 0
            let b = i < other.limbs.count ? UInt64(other.limbs[i]) : 0
            let sum = a + b + carry
            result.append(UInt32(sum & 0xffffffff))
            carry = sum >> 32
        }
        if carry > 0 { result.append(UInt32(carry)) }
        return BigUInt(limbs: result)
    }

    /// 假定 self >= other
    func subtracting(_ other: BigUInt) -> BigUInt {
        var result: [UInt32] = []
        var borrow: Int64 = 0
        for i in 0..<limbs.count {
            let a = Int64(limbs[i])
            let b = i < other.limbs.count ? Int64(other.limbs[i]) : 0
            var diff = a - b - borrow
            if diff < 0 {
                diff += Int64(0x1_0000_0000)
                borrow = 1
            } else {
                borrow = 0
            }
            result.append(UInt32(diff & 0xffffffff))
        }
        return BigUInt(limbs: result)
    }

    func doubling() -> BigUInt { adding(self) }

    /// 固定 [count] 字节大端表示（左补 0；超出时取低位）
    func toFixedBytes(_ count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        var outIndex = count - 1
        var limbIndex = 0
        while outIndex >= 0 && limbIndex < limbs.count {
            let limb = limbs[limbIndex]
            var k: UInt32 = 0
            var written = 0
            while written < 4 && outIndex >= 0 {
                out[outIndex] = UInt8((limb >> (8 * k)) & 0xff)
                outIndex -= 1
                k += 1
                written += 1
            }
            limbIndex += 1
        }
        return out
    }

    /// 结果 < mod 的模乘：双倍-相加，避免通用除法
    private static func modMul(_ a: BigUInt, _ b: BigUInt, _ mod: BigUInt) -> BigUInt {
        if b.isZero { return BigUInt(limbs: []) }
        var result = BigUInt(limbs: [])
        var i = b.bitLength - 1
        while i >= 0 {
            result = result.doubling()
            if result.compare(mod) >= 0 { result = result.subtracting(mod) }
            if b.bit(i) {
                result = result.adding(a)
                if result.compare(mod) >= 0 { result = result.subtracting(mod) }
            }
            i -= 1
        }
        return result
    }

    /// 模幂（复刻 BigInteger.modPow；此处指数的底先按 115 模数特性解一次冗余）
    func modPow(exp: BigUInt, mod: BigUInt) -> BigUInt {
        var base = self
        // 115 模数 m ≥ 2^1023、输入 < 2^1024，故最多减一次即完成取模
        if base.compare(mod) >= 0 { base = base.subtracting(mod) }
        var result = BigUInt(limbs: [1])
        let bits = exp.bitLength
        var i = 0
        while i < bits {
            if exp.bit(i) { result = BigUInt.modMul(result, base, mod) }
            if i < bits - 1 { base = BigUInt.modMul(base, base, mod) }
            i += 1
        }
        return result
    }
}

// MARK: - 115 分页结果

/// 115 个人盘列表分页结果
struct Pan115FilePage {
    let files: [ShareFile]
    let total: Int
}

/// 115 分享列目录结果：文件列表 + 总数 + 分享者 UID + 标题 + 分享状态
struct Pan115SharePage {
    let files: [ShareFile]
    let total: Int
    let userId: String
    let title: String
    let shareState: Int
}

// MARK: - 115 网盘接口（对应 Pan115Api.kt）

final class Pan115Api {

    private let client = HTTPClient.api

    /// 首次分享前的协议确认只需一次
    private let flagLock = NSLock()
    private var _protocolAllowed = false
    private var _clientVersionFetched = false

    private var protocolAllowed: Bool {
        get { flagLock.lock(); defer { flagLock.unlock() }; return _protocolAllowed }
        set { flagLock.lock(); _protocolAllowed = newValue; flagLock.unlock() }
    }
    private var clientVersionFetched: Bool {
        get { flagLock.lock(); defer { flagLock.unlock() }; return _clientVersionFetched }
        set { flagLock.lock(); _clientVersionFetched = newValue; flagLock.unlock() }
    }

    // ---------- 客户端版本（取直链必需） ----------

    /// 刷新客户端版本号（进程内只拉一次，失败保留兜底值）
    func refreshClientVersion() async {
        if clientVersionFetched { return }
        clientVersionFetched = true
        if let json = try? await getJson(Pan115Constants.APP_VERSION_URL, cookie: "", referer: Pan115Constants.REFERER) {
            let win = json.object("data").object("win")
            Pan115Constants.applyClientVersion(win.string("version_code"))
        }
    }

    // ---------- 用户信息（文档 §1.1） ----------

    /// 校验登录态并取昵称：GET /user/info?ct=json；失效返回 nil
    func fetchNickname(cookie: String) async -> String? {
        do {
            let json = try await getJson(Pan115Constants.USER_INFO_URL, cookie: cookie, referer: Pan115Constants.REFERER)
            try checkState(json, "获取用户信息失败")
            let value = json.string("data")
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }

    /// 网盘空间：GET /files/index_info?count_space_nums=1
    func getQuota(cookie: String) async -> QuotaInfo? {
        do {
            let json = try await getJson(Pan115Constants.INDEX_INFO_URL, cookie: cookie, referer: Pan115Constants.REFERER)
            try checkState(json, "获取空间信息失败")
            let space = json.object("data").object("space_info")
            if space.isNull { return nil }
            let total = space.object("all_total").long("size")
            let used = space.object("all_use").long("size")
            return QuotaInfo(used: used, total: total, usedInTrash: 0)
        } catch {
            return nil
        }
    }

    // ---------- 个人盘（文档 §2、§3） ----------

    /// 列目录：GET /files
    func listFiles(
        cid: String,
        cookie: String,
        offset: Int = 0,
        limit: Int = Pan115Constants.PAGE_LIMIT
    ) async throws -> Pan115FilePage {
        var url = Pan115Constants.FILES_URL
        url += "?aid=\(Pan115Constants.AID_PERSONAL)"
        url += "&cid=\(urlEncode(cid.isEmpty ? Pan115Constants.ROOT_CID : cid))"
        url += "&o=user_ptime&asc=0"
        url += "&offset=\(offset)"
        url += "&show_dir=1"
        url += "&limit=\(limit)"
        url += "&snap=0&natsort=1&record_open_time=1&count_folders=1"
        url += "&format=json"
        let json = try await getJson(url, cookie: cookie, referer: Pan115Constants.REFERER)
        try checkState(json, "获取文件列表失败")
        return Pan115FilePage(files: parsePersonalFiles(json), total: json.int("count"))
    }

    /// 个人盘直链：先走电脑端加密接口，失败退回网页端接口
    func getDownloadLink(file: ShareFile, cookie: String) async throws -> DownloadLink? {
        let pickCode = file.fidToken
        if pickCode.isEmpty { throw ApiError("缺少 pickcode，无法获取下载链接") }
        await refreshClientVersion()
        if let appLink = try? await getAppDownloadLink(pickCode: pickCode, cookie: cookie) {
            return DownloadLink(
                fid: file.fid,
                filename: appLink.filename.isEmpty ? file.fname : appLink.filename,
                downloadUrl: appLink.downloadUrl,
                size: appLink.size > 0 ? appLink.size : file.fsize,
                cleanupDirFid: nil,
                isHls: false,
                guestCookie: appLink.guestCookie
            )
        }
        return try await getWebDownloadLink(pickCode: pickCode, file: file, cookie: cookie)
    }

    /// 网页端直链：GET /files/download?pickcode=<pc>
    private func getWebDownloadLink(pickCode: String, file: ShareFile, cookie: String) async throws -> DownloadLink? {
        await refreshClientVersion()
        let url = "\(Pan115Constants.FILE_DOWNLOAD_URL)?pickcode=\(urlEncode(pickCode))"
        let resp = try await client.get(
            url,
            headers: headers(cookie: cookie, referer: Pan115Constants.DOWNLOAD_REFERER, userAgent: Pan115Constants.CLIENT_UA)
        )
        let (json, cdnCookie) = try execute(resp)
        try checkState(json, "获取下载链接失败")
        let data = json.object("data")
        if data.isNull { return nil }
        let fileUrl = data.string("file_url")
        if fileUrl.isEmpty { return nil }
        return DownloadLink(
            fid: file.fid,
            filename: data.string("file_name").isEmpty ? file.fname : data.string("file_name"),
            downloadUrl: fileUrl,
            size: Int64(data.string("file_size")) ?? file.fsize,
            cleanupDirFid: nil,
            isHls: false,
            guestCookie: cdnCookie ?? ""
        )
    }

    /// 「电脑端」直链：POST https://proapi.115.com/app/chrome/downurl?t=<unix秒>
    func getAppDownloadLink(pickCode: String, cookie: String) async throws -> DownloadLink? {
        if pickCode.isEmpty { return nil }
        let key = Pan115Crypto.newKey()
        let payloadData = try JSONSerialization.data(withJSONObject: ["pickcode": pickCode], options: [])
        let payload = String(data: payloadData, encoding: .utf8) ?? "{}"
        let encoded = try Pan115Crypto.encode(payload, key: key)
        let url = "\(Pan115Constants.APP_DOWNLOAD_URL)?t=\(Int(Date().timeIntervalSince1970))"
        let resp = try await client.postForm(
            url,
            headers: headers(cookie: cookie, referer: Pan115Constants.DOWNLOAD_REFERER, userAgent: Pan115Constants.CLIENT_UA),
            form: ["data": encoded]
        )
        let (json, cdnCookie) = try execute(resp)
        try checkState(json, "获取下载链接失败")
        let encrypted = json.string("data")
        if encrypted.isEmpty { return nil }
        let decodedText = try Pan115Crypto.decode(encrypted, key: key)
        guard let decoded = JSONValue.parse(decodedText) else { return nil }
        let dict = decoded.raw as? [String: Any] ?? [:]
        var info: JSONValue? = nil
        for (_, value) in dict {
            let jv = JSONValue(value)
            if !jv.object("url").isNull { info = jv; break }
        }
        guard let info = info else { return nil }
        let fileUrl = info.object("url").string("url")
        if fileUrl.isEmpty { return nil }
        let pick = info.string("pick_code")
        let sizeStr = Int64(info.string("file_size"))
        let size: Int64
        if let s = sizeStr {
            size = s
        } else {
            size = info.has("file_size") ? info.long("file_size") : -1
        }
        return DownloadLink(
            fid: pick.isEmpty ? pickCode : pick,
            filename: info.string("file_name"),
            downloadUrl: fileUrl,
            size: size,
            cleanupDirFid: nil,
            isHls: false,
            guestCookie: cdnCookie ?? ""
        )
    }

    /// 新建文件夹：POST /files/add → data.cid
    func createDir(pid: String, name: String, cookie: String) async throws -> String? {
        let json = try await postForm(
            Pan115Constants.FILE_ADD_URL,
            cookie: cookie,
            referer: Pan115Constants.REFERER,
            form: ["pid": pid.isEmpty ? Pan115Constants.ROOT_CID : pid, "cname": name]
        )
        try checkState(json, "新建文件夹失败")
        let cid = json.string("cid")
        if !cid.isEmpty { return cid }
        let inner = json.object("data").string("cid")
        return inner.isEmpty ? nil : inner
    }

    /// 重命名：POST /files/batch_rename
    func rename(id: String, newName: String, cookie: String) async throws {
        let json = try await postForm(
            Pan115Constants.FILE_RENAME_URL,
            cookie: cookie,
            referer: Pan115Constants.REFERER,
            form: [
                "fid": id,
                "file_name": newName,
                "files_new_name[\(id)]": newName,
            ]
        )
        try checkState(json, "重命名失败")
    }

    /// 移动：POST /files/move（异步，响应含 move_proid 时轮询进度）
    func move(fids: [String], toPid: String, cookie: String) async throws {
        let ids = fids.filter { !$0.isEmpty }
        if ids.isEmpty { throw ApiError("请选择要移动的文件") }
        var form: [String: String] = ["pid": toPid.isEmpty ? Pan115Constants.ROOT_CID : toPid]
        for (index, id) in ids.enumerated() { form["fid[\(index)]"] = id }
        let json = try await postForm(
            Pan115Constants.FILE_MOVE_URL,
            cookie: cookie,
            referer: Pan115Constants.REFERER,
            form: form
        )
        try checkState(json, "移动失败")
        var moveId = json.string("move_proid")
        if moveId.isEmpty { moveId = json.object("data").string("move_proid") }
        if moveId.isEmpty { return }
        for _ in 0..<Pan115Constants.MOVE_POLL_MAX {
            try? await Task.sleep(nanoseconds: UInt64(Pan115Constants.MOVE_POLL_INTERVAL_MS) * 1_000_000)
            guard let progress = try? await getJson(
                "\(Pan115Constants.MOVE_PROGRESS_URL)?move_proid=\(urlEncode(moveId))",
                cookie: cookie,
                referer: Pan115Constants.REFERER
            ) else { return }
            if !progress.bool("state") { return }
            let data = progress.object("data")
            if data.isNull { return }
            let percent = doubleValue(data, "percent")
            let count = data.int("count")
            if percent >= 100.0 || count <= 0 { return }
        }
    }

    /// 删除（进回收站）：POST /rb/delete；errno=800007 时按文档再确认一次
    func delete(fids: [String], pid: String, cookie: String) async throws {
        let ids = fids.filter { !$0.isEmpty }
        if ids.isEmpty { throw ApiError("请选择要删除的文件") }
        var form: [String: String] = ["pid": pid.isEmpty ? Pan115Constants.ROOT_CID : pid]
        for (index, id) in ids.enumerated() { form["fid[\(index)]"] = id }
        form["ignore_warn"] = "1"
        var json = try await postForm(Pan115Constants.FILE_DELETE_URL, cookie: cookie, referer: Pan115Constants.REFERER, form: form)
        if errnoOf(json) == Pan115Constants.ERRNO_NEED_CONFIRM {
            json = try await postForm(Pan115Constants.FILE_DELETE_URL, cookie: cookie, referer: Pan115Constants.REFERER, form: form)
        }
        try checkState(json, "删除失败")
    }

    // ---------- 分享解析（文档 §3） ----------

    /// 分享列目录：GET /share/snap（cid=0 为分享根）
    func getSharePage(
        shareCode: String,
        receiveCode: String,
        cid: String,
        cookie: String,
        offset: Int = 0,
        limit: Int = Pan115Constants.SHARE_PAGE_LIMIT
    ) async throws -> Pan115SharePage {
        var url = Pan115Constants.SHARE_SNAP_URL
        url += "?share_code=\(urlEncode(shareCode))"
        url += "&receive_code=\(urlEncode(receiveCode))"
        url += "&offset=\(offset)"
        url += "&limit=\(limit)"
        url += "&asc=0&cid=\(urlEncode(cid.isEmpty ? Pan115Constants.ROOT_CID : cid))"
        url += "&format=json"
        let json = try await getJson(
            url,
            cookie: cookie,
            referer: Pan115Constants.shareReferer(shareCode: shareCode, receiveCode: receiveCode)
        )
        try checkState(json, "获取分享列表失败")
        let data = json.object("data")
        if data.isNull {
            return Pan115SharePage(files: [], total: 0, userId: "", title: "", shareState: 0)
        }
        let shareInfo = data.object("shareinfo")
        let shareState = data.has("share_state") ? data.int("share_state") : shareInfo.int("share_state")
        return Pan115SharePage(
            files: parseShareFiles(data),
            total: data.int("count"),
            userId: data.object("userinfo").string("user_id"),
            title: shareInfo.string("share_title"),
            shareState: shareState
        )
    }

    /// 分享直链：GET /share/downurl（user_id 必须是分享者 UID，必须用客户端 UA）
    func getShareDownloadLink(
        shareCode: String,
        receiveCode: String,
        userId: String,
        file: ShareFile,
        cookie: String
    ) async throws -> DownloadLink? {
        if userId.isEmpty { throw ApiError("缺少分享者标识，请重新解析分享链接") }
        await refreshClientVersion()
        var url = Pan115Constants.SHARE_DOWNLOAD_URL
        url += "?dl=1"
        url += "&user_id=\(urlEncode(userId))"
        url += "&share_code=\(urlEncode(shareCode))"
        url += "&file_id=\(urlEncode(file.fid))"
        if !receiveCode.isEmpty { url += "&receive_code=\(urlEncode(receiveCode))" }
        let referer = Pan115Constants.shareReferer(shareCode: shareCode, receiveCode: receiveCode)
        let resp = try await client.get(
            url,
            headers: headers(cookie: cookie, referer: referer, userAgent: Pan115Constants.CLIENT_UA)
        )
        let (json, cdnCookie) = try execute(resp)
        try checkState(json, "获取下载链接失败")
        let data = json.object("data")
        if data.isNull { return nil }
        var fileUrl = data.string("file_url_302")
        if fileUrl.isEmpty { fileUrl = data.string("file_url") }
        if fileUrl.isEmpty { fileUrl = data.object("url").string("url") }
        if fileUrl.isEmpty { return nil }
        return DownloadLink(
            fid: file.fid,
            filename: data.string("fn").isEmpty ? file.fname : data.string("fn"),
            downloadUrl: fileUrl,
            size: Int64(data.string("fs")) ?? file.fsize,
            cleanupDirFid: nil,
            isHls: false,
            guestCookie: cdnCookie ?? ""
        )
    }

    /// 转存到自己的网盘：POST /share/receive
    func receiveShare(shareCode: String, receiveCode: String, fileId: String, toCid: String, cookie: String) async throws {
        let json = try await postForm(
            Pan115Constants.SHARE_RECEIVE_URL,
            cookie: cookie,
            referer: Pan115Constants.REFERER,
            form: [
                "share_code": shareCode,
                "receive_code": receiveCode,
                "file_id": fileId,
                "cid": toCid.isEmpty ? Pan115Constants.ROOT_CID : toCid,
            ]
        )
        try checkState(json, "转存失败")
    }

    // ---------- 创建分享（文档 §2） ----------

    /// 创建分享并设置有效期（duration 为 -1/1/3/5/7/15）
    func createShare(fileIds: [String], duration: String, cookie: String) async throws -> ShareInfo {
        guard let userId = Pan115Constants.extractUserId(cookie) else {
            throw ApiError("登录态缺少用户标识，请重新登录115网盘")
        }
        let ids = fileIds.filter { !$0.isEmpty }
        if ids.isEmpty { throw ApiError("请选择要分享的文件") }
        await allowProtocol(cookie: cookie)
        let idText = ids.joined(separator: ",")
        // 预检（ignore_warn=0）拿统计与提示，失败不阻塞真正创建
        _ = try? await postForm(
            Pan115Constants.SHARE_SEND_URL,
            cookie: cookie,
            referer: Pan115Constants.REFERER,
            form: ["user_id": userId, "file_ids": idText, "ignore_warn": "0"]
        )
        let json = try await postForm(
            Pan115Constants.SHARE_SEND_URL,
            cookie: cookie,
            referer: Pan115Constants.REFERER,
            form: ["user_id": userId, "file_ids": idText, "ignore_warn": "1"]
        )
        try checkState(json, "创建分享失败")
        let data = json.object("data")
        func field(_ name: String) -> String {
            if !data.isNull {
                let v = data.string(name)
                if !v.isEmpty { return v }
            }
            return json.string(name)
        }
        let shareCode = field("share_code")
        if shareCode.isEmpty { throw ApiError("创建分享失败：响应缺少分享编号") }

        var updateJson: JSONValue? = nil
        var updateError: String? = nil
        do {
            updateJson = try await postForm(
                Pan115Constants.SHARE_UPDATE_URL,
                cookie: cookie,
                referer: Pan115Constants.REFERER,
                form: ["share_code": shareCode, "share_duration": duration]
            )
        } catch {
            updateError = error.localizedDescription
        }
        let applied = updateJson?.bool("state") ?? false
        let expiredType: Int
        if applied {
            expiredType = Pan115ShareExpire.codeOf(duration)
        } else {
            expiredType = Pan115ShareExpire.codeOfText(field("share_ex_duration"))
        }
        let warning: String?
        if applied {
            warning = nil
        } else {
            var reason: String? = nil
            if let uj = updateJson {
                var r = uj.string("error")
                if r.isEmpty { r = uj.string("msg") }
                if !r.isEmpty { reason = r }
            }
            let finalReason = reason ?? updateError ?? "未知原因"
            warning = "分享已创建，但有效期设置未生效（当时按服务端默认档位）：\(finalReason)"
        }
        let shareUrl = field("share_url")
        let passcode = field("receive_code").isEmpty ? field("sys_receive_code") : field("receive_code")
        return ShareInfo(
            shareUrl: shareUrl.isEmpty ? "\(Pan115Constants.SHARE_HOST)/s/\(shareCode)" : shareUrl,
            passcode: passcode,
            pwdId: shareCode,
            title: field("share_title"),
            expiredType: expiredType,
            warning: warning
        )
    }

    // ---------- 内部实现 ----------

    /// 首次分享前确认「公开分享」协议（失败忽略）
    private func allowProtocol(cookie: String) async {
        if protocolAllowed { return }
        _ = try? await postForm(
            Pan115Constants.ALLOW_PROTOCOL_URL,
            cookie: cookie,
            referer: Pan115Constants.REFERER,
            form: ["action": "pubshare"]
        )
        protocolAllowed = true
    }

    /// 个人盘列表解析：文件夹无 fid（自身 ID 在 cid），文件的 cid 是父目录
    private func parsePersonalFiles(_ json: JSONValue) -> [ShareFile] {
        var result: [ShareFile] = []
        for item in json.array("data") {
            let fid = item.string("fid")
            let isDir = fid.isEmpty
            let id = isDir ? item.string("cid") : fid
            if id.isEmpty { continue }
            result.append(ShareFile(
                fid: id,
                fname: item.string("n"),
                fsize: isDir ? 0 : item.long("s"),
                isdir: isDir,
                pdirFid: isDir ? item.string("pid") : item.string("cid"),
                fidToken: item.string("pc"),
                modifyTime: item.string("t")
            ))
        }
        return result
    }

    /// 分享列表解析：fc == 0 为目录，目录 ID 取 cid、文件 ID 取 fid
    private func parseShareFiles(_ data: JSONValue) -> [ShareFile] {
        var result: [ShareFile] = []
        for item in data.array("list") {
            let fid = item.string("fid")
            let fc = item.has("fc") ? item.int("fc") : (fid.isEmpty ? 0 : 1)
            let isDir = fc == 0
            let id = isDir ? item.string("cid") : fid
            if id.isEmpty { continue }
            result.append(ShareFile(
                fid: id,
                fname: item.string("n"),
                fsize: isDir ? 0 : item.long("s"),
                isdir: isDir,
                pdirFid: isDir ? item.string("pid") : item.string("cid"),
                fidToken: "",
                modifyTime: item.string("t")
            ))
        }
        return result
    }

    /// 公共请求头（桌面 UA + X-Requested-With + Referer + Cookie）
    private func headers(cookie: String, referer: String, userAgent: String = Pan115Constants.WEB_UA) -> [String: String] {
        var h: [String: String] = [
            "User-Agent": userAgent,
            "Accept": "application/json, text/plain, */*",
            "X-Requested-With": Pan115Constants.X_REQUESTED_WITH,
            "Referer": referer,
        ]
        if !cookie.isEmpty { h["Cookie"] = cookie }
        return h
    }

    private func getJson(_ url: String, cookie: String, referer: String) async throws -> JSONValue {
        let resp = try await client.get(url, headers: headers(cookie: cookie, referer: referer))
        return try parseJSON(resp)
    }

    private func postForm(
        _ url: String,
        cookie: String,
        referer: String,
        form: [String: String],
        userAgent: String = Pan115Constants.WEB_UA
    ) async throws -> JSONValue {
        let resp = try await client.postForm(
            url,
            headers: headers(cookie: cookie, referer: referer, userAgent: userAgent),
            form: form
        )
        return try parseJSON(resp)
    }

    /// 执行请求：返回响应 JSON 与响应头里下发的「下载专用 Cookie」
    private func execute(_ resp: HTTPResponse) throws -> (json: JSONValue, cookie: String?) {
        let cookie = downloadCookie(resp.setCookies)
        return (try parseJSON(resp), cookie)
    }

    private func parseJSON(_ resp: HTTPResponse) throws -> JSONValue {
        let body = resp.text
        if body.isEmpty {
            if !resp.isSuccessful { throw ApiError("请求失败（HTTP \(resp.statusCode)）") }
            throw ApiError("请求失败：响应为空（\(resp.statusCode)）")
        }
        guard let json = JSONValue.parse(body) else {
            throw ApiError("响应解析失败")
        }
        return json
    }

    /// 从 Set-Cookie 里取第一个 `name=value`（优先 path 绑定的那条）
    private func downloadCookie(_ headers: [String]) -> String? {
        var fallback: String? = nil
        for raw in headers {
            let pair = (raw.components(separatedBy: ";").first ?? "").trimmingCharacters(in: .whitespaces)
            let name = pair.components(separatedBy: "=").first ?? ""
            if name.isEmpty || !pair.contains("=") { continue }
            let lower = name.lowercased()
            if lower == "expires" || lower == "path" || lower == "domain" { continue }
            if fallback == nil { fallback = pair }
            if let path = pathAttribute(raw), !path.isEmpty, path != "/" { return pair }
        }
        return fallback
    }

    /// 取 Set-Cookie 的 path 属性值（等价 Kotlin 正则 `[;\s]path=([^;]+)`，这里手工扫描避免正则字面量）
    private func pathAttribute(_ raw: String) -> String? {
        for comp in raw.components(separatedBy: ";") {
            let t = comp.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("path=") {
                return String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func errnoOf(_ json: JSONValue) -> Int {
        json.has("errno") ? json.int("errno") : json.int("errNo")
    }

    private func doubleValue(_ json: JSONValue, _ key: String) -> Double {
        guard let dict = json.raw as? [String: Any], let v = dict[key] else { return 0 }
        if let n = v as? NSNumber { return n.doubleValue }
        if let d = v as? Double { return d }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }

    /// 成功判定：state == true；失败按抓包错误码给出可读提示（文档 §7）
    private func checkState(_ json: JSONValue, _ fallback: String) throws {
        if json.bool("state") { return }
        let errno = errnoOf(json)
        let raw = json.string("error").isEmpty ? json.string("msg") : json.string("error")
        let message: String
        switch errno {
        case Pan115Constants.ERRNO_LOGIN_TIMEOUT:
            message = "登录已过期，请重新登录115网盘"
        case Pan115Constants.ERRNO_NEED_CODE:
            message = "该分享需要访问码，请填写访问码后重试"
        case Pan115Constants.ERRNO_WRONG_CODE:
            message = "访问码错误，请检查后重试"
        case Pan115Constants.ERRNO_SHARE_GONE:
            message = "分享链接不存在或已被删除"
        case Pan115Constants.ERRNO_EMPTY_FOLDER:
            message = "不允许分享空文件夹"
        case Pan115Constants.ERRNO_BUSY:
            message = "上一次操作还没完成，请稍后重试"
        case Pan115Constants.ERRNO_WEB_SIZE_LIMIT:
            message = "115 拒绝向网页端下发该文件的直链（文件过大），请改用115电脑端/手机客户端下载"
        case Pan115Constants.ERRNO_CLIENT_TOO_OLD:
            message = "115 判定当前标识版本过低、拒绝下发直链，请改用115电脑端/手机客户端下载"
        default:
            message = raw.isEmpty ? fallback : raw
        }
        let suffix = (errno != 0 && !message.contains("\(errno)")) ? "（errno=\(errno)）" : ""
        throw ApiError(message + suffix)
    }
}

// MARK: - 115 分享解析仓库（对应 Pan115ResolveRepository.kt）

/// 115 网盘分享解析仓库：share/snap 列目录 → share/downurl 取直链。
///
/// 两个与其它平台不同的点：
/// - 直链必须带**分享者** user_id，它只出现在 snap 的 userinfo 里，故 createSession 先探分享根目录，
///   把「提取码|分享者UID」塞进 stoken 带走；
/// - share/receive 转存不回传新文件 id，转存后要重新列目标目录按文件名认领。
final class Pan115ResolveRepository: ShareResolveRepository {

    private let api = Pan115Api()

    /// init() 无参
    init() {}

    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        guard let parsed = ShareLinkParser.parse(link) else {
            throw ApiError("无法识别分享链接")
        }
        // 提取码优先级：用户手输 > 链接 ?password= 或文案「访问码：xxxx」
        let receiveCode = (pwd?.isEmpty == false) ? (pwd ?? "") : (parsed.pwd ?? "")
        // 先探分享根目录：校验提取码 + 拿分享者 UID 与标题
        let page = try await api.getSharePage(
            shareCode: parsed.shareId,
            receiveCode: receiveCode,
            cid: Pan115Constants.ROOT_CID,
            cookie: cookie
        )
        return ShareSession(
            shareId: parsed.shareId,
            stoken: Pan115Constants.encodeShareToken(receiveCode: receiveCode, userId: page.userId),
            title: page.title.isEmpty ? parsed.shareId : page.title
        )
    }

    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        let (receiveCode, _) = Pan115Constants.decodeShareToken(session.stoken)
        // 分享里的目录 ID 就是 cid（文件夹项没有 fid），根目录固定 "0"
        let cid = dirFid.isEmpty ? Pan115Constants.ROOT_CID : dirFid
        var all: [ShareFile] = []
        var offset = 0
        while true {
            let page = try await api.getSharePage(
                shareCode: session.shareId,
                receiveCode: receiveCode,
                cid: cid,
                cookie: cookie,
                offset: offset,
                limit: Pan115Constants.SHARE_PAGE_LIMIT
            )
            all.append(contentsOf: page.files)
            offset += page.files.count
            // 115 的 offset 是索引分页：空页 / 不足一页 / 已取满 count 都说明到底了
            let done = page.files.isEmpty ||
                page.files.count < Pan115Constants.SHARE_PAGE_LIMIT ||
                (page.total > 0 && all.count >= page.total)
            if done { break }
        }
        return all
    }

    /// 确保「YunX临时转存」下的**唯一子目录**存在，返回子目录 cid
    func ensureTempDir(cookie: String) async throws -> String {
        if !Pan115Constants.hasLoginCookie(cookie) {
            throw ApiError("请先登录115网盘")
        }
        let root = try await api.listFiles(cid: Pan115Constants.ROOT_CID, cookie: cookie, offset: 0)
        let tempRoot: String
        if let existing = root.files.first(where: { $0.isdir && $0.fname == Pan115Constants.TEMP_DIR_NAME }) {
            tempRoot = existing.fid
        } else if let created = try await api.createDir(
            pid: Pan115Constants.ROOT_CID, name: Pan115Constants.TEMP_DIR_NAME, cookie: cookie
        ) {
            tempRoot = created
        } else {
            throw ApiError("创建115临时目录失败")
        }
        // 唯一子目录名（对应 Kotlin System.nanoTime()，仅需唯一）
        let subName = "\(Pan115Constants.TEMP_SUBDIR_PREFIX)\(UInt64(Date().timeIntervalSince1970 * 1_000_000_000))"
        guard let sub = try await api.createDir(pid: tempRoot, name: subName, cookie: cookie) else {
            throw ApiError("创建115临时转存目录失败")
        }
        return sub
    }

    /// 下载完成（或用户取消）后清理：删掉本次转存的唯一子目录
    func cleanupTempDir(dirFid: String, cookie: String) async {
        if dirFid.isEmpty || !Pan115Constants.hasLoginCookie(cookie) { return }
        do {
            let root = try await api.listFiles(cid: Pan115Constants.ROOT_CID, cookie: cookie, offset: 0)
            guard let tempRoot = root.files
                .first(where: { $0.isdir && $0.fname == Pan115Constants.TEMP_DIR_NAME })?.fid else { return }
            try await api.delete(fids: [dirFid], pid: tempRoot, cookie: cookie)
        } catch {
            // 忽略清理失败
        }
    }

    /// 转存到自己的网盘：POST /share/receive，转存后按文件名认领新 fid
    func transferFile(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        if !Pan115Constants.hasLoginCookie(cookie) {
            throw ApiError("请先登录115网盘")
        }
        let (receiveCode, _) = Pan115Constants.decodeShareToken(session.stoken)
        let targetCid = toDirFid.isEmpty ? Pan115Constants.ROOT_CID : toDirFid
        try await api.receiveShare(
            shareCode: session.shareId,
            receiveCode: receiveCode,
            fileId: file.fid,
            toCid: targetCid,
            cookie: cookie
        )
        guard let fid = await waitNewFid(cid: targetCid, name: file.fname, cookie: cookie) else {
            throw ApiError("转存已完成，但未在目标目录找到文件，请到115网盘查看")
        }
        return fid
    }

    /// 转存后列表有延迟，最多重试 5 次、每次间隔 500ms，按文件名找回新文件
    private func waitNewFile(cid: String, name: String, cookie: String) async -> ShareFile? {
        let dotIndex = name.lastIndex(of: ".")
        let base = dotIndex == nil ? name : String(name[..<dotIndex!])
        let ext = dotIndex == nil ? "" : String(name[name.index(after: dotIndex!)...])
        for index in 0..<5 {
            if index > 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
            guard let page = try? await api.listFiles(
                cid: cid, cookie: cookie, offset: 0, limit: Pan115Constants.PAGE_LIMIT
            ) else { continue }
            if let hit = page.files.first(where: { matchesName($0.fname, name: name, base: base, ext: ext) }) {
                return hit
            }
        }
        return nil
    }

    private func waitNewFid(cid: String, name: String, cookie: String) async -> String? {
        let file = await waitNewFile(cid: cid, name: name, cookie: cookie)
        return file?.fid
    }

    /// 文件名是否为「原名」或重名后的「原名(序号).后缀」
    private func matchesName(_ candidate: String, name: String, base: String, ext: String) -> Bool {
        if candidate == name { return true }
        if !candidate.hasPrefix("\(base)(") { return false }
        return ext.isEmpty ? candidate.hasSuffix(")") : candidate.hasSuffix(".\(ext)")
    }

    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        throw ApiError("115 分享请使用 getShareDownloadLink")
    }

    /// 分享直链：先走网页端 share/downurl，失败时登录态退回「转存 + 电脑端加密接口取链」
    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        let (receiveCode, userId) = Pan115Constants.decodeShareToken(session.stoken)
        var webError: Error? = nil
        var link: DownloadLink? = nil
        do {
            link = try await api.getShareDownloadLink(
                shareCode: session.shareId,
                receiveCode: receiveCode,
                userId: userId,
                file: file,
                cookie: cookie
            )
        } catch {
            webError = error
        }
        let resolved: DownloadLink
        if let l = link {
            resolved = l
        } else if Pan115Constants.hasLoginCookie(cookie) {
            resolved = try await downloadViaTempTransfer(
                session: session, file: file, receiveCode: receiveCode, cookie: cookie
            )
        } else {
            // 未登录只能走网页端，原样抛出 115 的提示（比如 50029）
            throw webError ?? ApiError("获取下载链接失败")
        }
        // 文件名以列表为准（downurl 的 fn 偶发为空）
        return DownloadLink(
            fid: resolved.fid,
            filename: file.fname.isEmpty ? resolved.filename : file.fname,
            downloadUrl: resolved.downloadUrl,
            size: resolved.size,
            cleanupDirFid: resolved.cleanupDirFid,
            isHls: resolved.isHls,
            guestCookie: resolved.guestCookie
        )
    }

    /// 分享文件的「电脑端」通道：转存到临时子目录 → 认领新文件（拿 pickcode）→ 电脑端接口取链
    private func downloadViaTempTransfer(
        session: ShareSession,
        file: ShareFile,
        receiveCode: String,
        cookie: String
    ) async throws -> DownloadLink {
        if !Pan115Constants.hasLoginCookie(cookie) {
            throw ApiError("该分享文件需要115电脑端才能下载，请先到「网盘」页登录115网盘")
        }
        try await ensureEnoughSpace(size: file.fsize, cookie: cookie)
        let tempDir = try await ensureTempDir(cookie: cookie)
        try await api.receiveShare(
            shareCode: session.shareId,
            receiveCode: receiveCode,
            fileId: file.fid,
            toCid: tempDir,
            cookie: cookie
        )
        guard let saved = await waitNewFile(cid: tempDir, name: file.fname, cookie: cookie) else {
            // 转存成功但没认领到文件：别把垃圾留在用户网盘里
            await cleanupTempDir(dirFid: tempDir, cookie: cookie)
            throw ApiError("分享文件转存后未取到下载链接，请稍后重试")
        }
        let linkOpt = try? await api.getAppDownloadLink(pickCode: saved.fidToken, cookie: cookie)
        guard let link = linkOpt else {
            // 取链也失败：转存进来的文件同样不能留在用户网盘里
            await cleanupTempDir(dirFid: tempDir, cookie: cookie)
            throw ApiError("该分享文件暂时无法获取电脑端下载链接，请稍后重试")
        }
        return DownloadLink(
            fid: saved.fid,
            filename: file.fname.isEmpty ? link.filename : file.fname,
            downloadUrl: link.downloadUrl,
            size: link.size > 0 ? link.size : saved.fsize,
            cleanupDirFid: tempDir,
            isHls: link.isHls,
            guestCookie: link.guestCookie
        )
    }

    /// 转存前先核对剩余空间（拿不到空间信息时放行）
    private func ensureEnoughSpace(size: Int64, cookie: String) async throws {
        if size <= 0 { return }
        guard let quota = await api.getQuota(cookie: cookie) else { return }
        let free = quota.total - quota.used
        if free >= 1 && free < size {
            throw ApiError(
                "网盘剩余空间不足：该分享内容需要 \(readableSize(size))，可用 \(readableSize(free))，请先清理空间或改用其它方式下载"
            )
        }
    }

    /// 体积展示（只用于错误提示）
    private func readableSize(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var i = 0
        while value >= 1024 && i < units.count - 1 {
            value /= 1024
            i += 1
        }
        return String(format: "%.1f %@", value, units[i])
    }
}
