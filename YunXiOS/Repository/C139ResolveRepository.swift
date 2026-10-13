/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：139（和彩云）网络接口层 + 分享解析仓库。
 * 对应 Android 侧：
 *   - data/network/C139Constants.kt
 *   - data/network/C139Api.kt
 *   - data/repository/C139ResolveRepository.kt
 *
 * 说明：源实现使用 AES/CBC/PKCS5Padding（固定密钥 +随机 IV 前置）加解密分享接口。
 * CryptoKit 仅提供 AES.GCM / ChaChaPoly，不含 CBC 模式，故这里使用系统自带的
 * CommonCrypto（Apple SDK 内置，非第三方库）实现 AES-CBC；摘要使用 CryptoKit 的 MD5。
 */

import Foundation
import CryptoKit
import CommonCrypto
import Compression

// MARK: - 文件级工具

/// 把 `[String: Any]` 序列化为紧凑 JSON 字符串（对应 Kotlin JSONObject.toString()）。
/// 注意：签名与请求体必须使用同一份字符串，故只在调用处序列化一次后复用。
private func c139JsonString(_ obj: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

/// 对应 Kotlin `optBoolean(key, default)`：缺失 / NSNull / 不可解析时返回默认值。
private func c139OptBool(_ json: JSONValue, _ key: String, default value: Bool) -> Bool {
    guard let dict = json.raw as? [String: Any], let raw = dict[key], !(raw is NSNull) else {
        return value
    }
    if let b = raw as? Bool { return b }
    if let n = raw as? NSNumber { return n.boolValue }
    if let s = raw as? String {
        let t = s.lowercased()
        if t == "true" || t == "1" { return true }
        if t == "false" || t == "0" { return false }
        return value
    }
    return value
}

/// 对应 Kotlin `JSONObject.isNull(key)`：键缺失或值为 JSON null 时返回 true。
private func c139IsNullKey(_ json: JSONValue, _ key: String) -> Bool {
    guard let dict = json.raw as? [String: Any], let raw = dict[key] else { return true }
    return raw is NSNull
}

/// 分享有效期中性码（对应 Kotlin model/ShareExpire.kt 的常量）。
private enum C139ShareExpire {
    static let unknown = 0
    static let forever = 1
    static let oneDay = 2
    static let sevenDays = 3
    static let thirtyDays = 4
}

// MARK: - C139Constants

/// 139 网盘（中国移动·和彩云）登录 / 接口常量。
/// 对应 Kotlin `object C139Constants`。
enum C139Constants {

    // ---------- 登录 / Cookie ----------

    /// WebView 登录页（移动版页面渲染稳定）
    static let loginUrl = "https://yun.139.com/m/#/login"
    /// 提取 Cookie 的主域名（fast login 核心：Os_SSo_Sid + RMKEY）
    static let cookieDomain = "https://mail.10086.cn"
    /// 备用 Cookie 域名（authorization / ud_id 等在此域）
    static let cookieDomainBackup = "https://yun.139.com"

    // ---------- 分享 host（§9/§12） ----------

    static let shareBase = "https://share-kd-njs.yun.139.com"
    /// 分享列目录（7.13+ 请求/响应加密）
    static let shareListUrl = "\(shareBase)/yun-share/richlifeApp/devapp/IOutLink/getOutLinkInfoV6"
    /// 分享取直链（7.13+ 请求/响应加密）
    static let shareLinkUrl = "\(shareBase)/yun-share/richlifeApp/devapp/IOutLink/dlFromOutLinkV3"
    /// 分享标题信息（getOutLinkGeneral → outLinkGeneral[].lkName）
    static let shareGeneralUrl = "\(shareBase)/yun-share/richlifeApp/devapp/IOutLink/getOutLinkGeneral"

    /// §14 分享接口 AES-CBC 固定密钥（16 字节，所有账号共用）
    static let shareAesKey = "PVGDwmcvfs1uV3d1"

    // ---------- 个人网盘管理（明文 JSON，无 Cookie；host personal-kd-njs） ----------

    static let cloudBase = "https://personal-kd-njs.yun.139.com"

    // —— 渠道/上下文头（缺失 → 04000005 认证失败；值来自成功抓包写死）——
    static let yunChannelSource = "10000034"
    static let mcloudVersion = "7.17.9"
    static let mcloudClient = "10701"
    static let mcloudChannel = "1000101"
    static let yunModuleType = "100"
    static let m4cSrc = "10002"
    static let m4cCaller = "PC"
    static let xDeviceinfo = "||9|7.17.9|chrome|116.0.0.0|2cdaf7ada9e353c70eba99092e177991||windows 10||zh-CN|||"
    static let xClientInfo = "||9|7.17.9|chrome|116.0.0.0|2cdaf7ada9e353c70eba99092e177991||windows 10||zh-CN|||dW5kZWZpbmVk||"

    /// 列目录（可加 type:"folder" 仅列文件夹）
    static let fileListUrl = "\(cloudBase)/hcy/file/list"
    /// 新建目录 / 上传预创建（靠 `type` 区分：folder = 建目录、file = 上传）
    static let fileCreateUrl = "\(cloudBase)/hcy/file/create"
    /// 重命名
    static let fileUpdateUrl = "\(cloudBase)/hcy/file/update"
    /// 移动（异步，返回 taskId）
    static let batchMoveUrl = "\(cloudBase)/hcy/file/batchMove"
    /// 删除（异步移入回收站，返回 taskId）
    static let batchTrashUrl = "\(cloudBase)/hcy/recyclebin/batchTrash"
    /// 下载直链（OBS 预签名，900s 有效）
    static let downloadUrl = "\(cloudBase)/hcy/file/getDownloadUrl"
    /// 异步任务轮询
    static let taskGetUrl = "\(cloudBase)/hcy/task/get"
    /// 创建分享（yun.139.com orchestration，需 Cookie + mcloud-skey + Authorization）
    static let outlinkCreateUrl = "https://yun.139.com/orchestration/personalCloud-rebuild/outlink/v1.0/getOutLink"

    /// 转存：创建任务（share host，AES 加密）
    static let transferCreateUrl = "\(shareBase)/yun-share/richlifeApp/devapp/IBatchOprTask/createOuterLinkBatchOprTask"
    /// 转存：查询结果（share host，AES 加密）
    static let transferQueryUrl = "\(shareBase)/yun-share/richlifeApp/devapp/IBatchOprTask/queryBatchOprTaskDetail"

    /// 分享接口必带设备/渠道上下文头（缺任一即 9530）
    static let shareXDeviceinfo = "||3|12.27.0|||||chrome 150.0.0.0|360X444|zh-cn|||"
    static let shareXHuaweiChannelsrc = "10245500"
    static let shareXMmSource = "0002"

    /// 分享接口 User-Agent（必须浏览器/WebView UA，不能用 okhttp/4.x）
    static let shareMobileUA =
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/150.0.0.0 Mobile Safari/537.36"

    /// PC 桌面 UA
    static let pcUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/120.0.0.0 Safari/537.36"

    /// 快速登录必须同时存在的关键字段（路径 A）
    private static let requiredFastKeys: Set<String> = ["Os_SSo_Sid", "RMKEY"]

    /// 尽量保留的字段
    private static let keepKeys: Set<String> = [
        "Os_SSo_Sid", "RMKEY", "UserData", "Login_UserNumber",
        "_139_index_isLoginType", "UUIDToken", "JSESSIONID",
        "areaCode8011", "provCode8011",
        "authorization", "auth_token", "token", "ud_id",
        "ORCHES-I-ACCOUNT-SIMPLIFY", "ORCHES-I-ACCOUNT-ENCRYPT", "nation_code",
        "platform", "cutover_status", "isUserDomainError", "a_k", "skey", "WT_FPC",
        "hecaiyun_stay_url", "hecaiyun_stay_time",
        "hecaiyundata2021jssdkcross", "sajssdk_2015_cross_new_user",
    ]

    /// 从 Cookie 提取登录态（mail.10086.cn 优先，yun.139.com 兜底，只收 KEEP_KEYS）。
    static func extractCookies(_ getCookie: (String) -> String?) -> String {
        var out: [(String, String)] = []
        var seen = Set<String>()
        for domain in [cookieDomain, cookieDomainBackup] {
            guard let raw = getCookie(domain) else { continue }
            for kv in raw.split(separator: ";") {
                let item = kv.trimmingCharacters(in: .whitespaces)
                guard let eq = item.firstIndex(of: "="), eq != item.startIndex else { continue }
                let key = String(item[item.startIndex..<eq])
                let value = String(item[item.index(after: eq)...])
                if keepKeys.contains(key) && !seen.contains(key) {
                    seen.insert(key)
                    out.append((key, value))
                }
            }
        }
        return out.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
    }

    /// 关键字段是否齐全（路径 A 双字段 或 路径 B authorization 任一成立即有效）。
    static func isValidCookie(_ cookie: String?) -> Bool {
        guard let cookie = cookie,
              !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let parts = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        // 路径 B：网页版直接给的 authorization
        if parts.contains(where: { $0.hasPrefix("authorization=") && $0.count > "authorization=".count }) {
            return true
        }
        // 路径 A：fast login 双字段
        return requiredFastKeys.allSatisfy { key in
            parts.contains { $0.hasPrefix("\(key)=") && $0.count > key.count + 1 }
        }
    }

    /// 提取 authorization（形如 "Basic cGM6..."）；没有返回 nil。
    static func extractAuthorization(_ cookie: String?) -> String? {
        guard let cookie = cookie,
              !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        for kv in cookie.split(separator: ";") {
            let item = kv.trimmingCharacters(in: .whitespaces)
            if item.hasPrefix("authorization=") {
                let value = String(item.dropFirst("authorization=".count))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// 提取完整账号（解析接口用，必须完整手机号）。
    /// 优先 ORCHES-I-ACCOUNT-ENCRYPT（base64 解码）→ authorization 解码 → Login_UserNumber。
    static func extractAccountFull(_ cookie: String?) -> String? {
        guard let cookie = cookie,
              !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // 1) ORCHES-I-ACCOUNT-ENCRYPT：base64 手机号
        for kv in cookie.split(separator: ";") {
            let item = kv.trimmingCharacters(in: .whitespaces)
            if item.hasPrefix("ORCHES-I-ACCOUNT-ENCRYPT=") {
                let value = String(item.dropFirst("ORCHES-I-ACCOUNT-ENCRYPT=".count))
                if !value.isEmpty, let decoded = base64Decode(value), !decoded.isEmpty { return decoded }
            }
        }
        // 2) authorization："Basic base64(pc:账号:authToken)"
        if let auth = extractAuthorization(cookie) {
            var b64 = auth
            if b64.hasPrefix("Basic") { b64 = String(b64.dropFirst("Basic".count)) }
            b64 = b64.trimmingCharacters(in: .whitespacesAndNewlines)
            if let decoded = base64Decode(b64) {
                let parts = decoded.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                if parts.count > 1, !parts[1].isEmpty { return parts[1] }
            }
        }
        // 3) Login_UserNumber：手机号/账号
        for kv in cookie.split(separator: ";") {
            let item = kv.trimmingCharacters(in: .whitespaces)
            if item.hasPrefix("Login_UserNumber=") {
                let value = String(item.dropFirst("Login_UserNumber=".count))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// 提取账号昵称（脱敏手机号 → base64 手机号 → Login_UserNumber）。
    static func extractAccount(_ cookie: String?) -> String? {
        guard let cookie = cookie,
              !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // 1) ORCHES-I-ACCOUNT-SIMPLIFY：脱敏手机号，形如 177****8634
        for kv in cookie.split(separator: ";") {
            let item = kv.trimmingCharacters(in: .whitespaces)
            if item.hasPrefix("ORCHES-I-ACCOUNT-SIMPLIFY=") {
                let value = String(item.dropFirst("ORCHES-I-ACCOUNT-SIMPLIFY=".count))
                if !value.isEmpty { return value }
            }
        }
        // 2) ORCHES-I-ACCOUNT-ENCRYPT：base64 手机号
        for kv in cookie.split(separator: ";") {
            let item = kv.trimmingCharacters(in: .whitespaces)
            if item.hasPrefix("ORCHES-I-ACCOUNT-ENCRYPT=") {
                let value = String(item.dropFirst("ORCHES-I-ACCOUNT-ENCRYPT=".count))
                if !value.isEmpty {
                    if let decoded = base64Decode(value), !decoded.isEmpty { return decoded }
                    return value
                }
            }
        }
        // 3) Login_UserNumber：手机号/账号
        for kv in cookie.split(separator: ";") {
            let item = kv.trimmingCharacters(in: .whitespaces)
            if item.hasPrefix("Login_UserNumber=") {
                let value = String(item.dropFirst("Login_UserNumber=".count))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// 宽松 base64 解码（对应 Kotlin `Base64.decode(v, Base64.DEFAULT)`）。
    private static func base64Decode(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value, options: [.ignoreUnknownCharacters]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - C139Api

/// 139 网盘 API 封装（对应 Kotlin `class C139Api`）。
/// 登录态：cookie（含账号信息，authorization 可选）。
final class C139Api {

    /// 每次请求动态获取全局客户端
    private let client = HTTPClient.api

    /// AES-CBC 固定密钥字节（16 字节）
    private let shareAesKey: [UInt8] = Array(C139Constants.shareAesKey.utf8)

    // 时间戳格式：yyyy-MM-dd HH:mm:ss
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // ---------- 结果类型 ----------

    /// 异步任务状态（移动/删除轮询）
    struct C139TaskStatus {
        let status: String
        let progress: Int
        let results: [(String, String)]
    }

    /// 转存结果（分享导入）
    struct C139TransferResult {
        let done: Bool
        let mapping: [String: String]
    }

    // ---------- mcloud-sign 签名（§4） ----------

    private func md5(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// §4.1：encodeURIComponent（+→%20，并还原 ! ' ( ) *，其余字节 %HH 大写）。
    private func encodeURIComponent(_ s: String) -> String {
        // Java URLEncoder 保留 A-Za-z0-9 与 . - * _，替换后 ! ' ( ) * 亦为字面量
        let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!*'()")
        var out = ""
        for byte in s.utf8 {
            if byte == 0x20 {
                out += "%20"
            } else {
                let ch = Character(UnicodeScalar(byte))
                if unreserved.contains(ch) {
                    out.append(ch)
                } else {
                    out += String(format: "%%%02X", byte)
                }
            }
        }
        return out
    }

    /// §4.2 calSign：body' 单字符 ASCII 升序 → base64 → md5(base64) + md5(ts:rand) → md5 → upper。
    func calSign(bodyJson: String, ts: String, rand: String) -> String {
        let encoded = encodeURIComponent(bodyJson)
        let sorted = String(encoded.sorted())
        let b64 = Data(sorted.utf8).base64EncodedString()
        let res = md5(b64) + md5("\(ts):\(rand)")
        return md5(res).uppercased()
    }

    /// 生成 mcloud-sign 头值：<ts>,<rand>,<sign>；ts 格式 YYYY-MM-DD HH:MM:SS，rand 16 位字母数字。
    func signHeader(bodyJson: String) -> String {
        let ts = Self.timestampFormatter.string(from: Date())
        let pool = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let rand = String((0..<16).map { _ in pool.randomElement()! })
        return "\(ts),\(rand),\(calSign(bodyJson: bodyJson, ts: ts, rand: rand))"
    }

    /// 从 authorization（"Basic base64(pc:账号:authToken)"）解码账号。
    func accountFromAuthorization(_ authorization: String) -> String? {
        var b64 = authorization
        if b64.hasPrefix("Basic") { b64 = String(b64.dropFirst("Basic".count)) }
        b64 = b64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]),
              let decoded = String(data: data, encoding: .utf8) else { return nil }
        let parts = decoded.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1, !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    // ---------- §14 分享接口 AES-CBC 加解密 ----------

    /// 通用 AES-CBC/PKCS7 运算。
    private func aesCBC(_ op: CCOperation, key: [UInt8], iv: [UInt8], input: Data) throws -> Data {
        let outCapacity = input.count + Int(kCCBlockSizeAES128)
        var out = Data(count: outCapacity)
        var moved = 0
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
            input.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            op,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, input.count,
                            outPtr.baseAddress, outCapacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else {
            throw ApiError("AES 运算失败（status=\(status)）")
        }
        return out.prefix(moved)
    }

    /// 明文 JSON → 加密 base64（IV(16B) 前置）。
    private func encryptBody(_ plaintext: String) throws -> String {
        let iv = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let ct = try aesCBC(CCOperation(kCCEncrypt), key: shareAesKey, iv: iv, input: Data(plaintext.utf8))
        return (Data(iv) + ct).base64EncodedString()
    }

    /// 加密 base64 → 明文 JSON；解密后若为 gzip（首 2 字节 0x1f 0x8b）先解压。
    private func decryptBody(_ b64: String) throws -> String {
        guard let raw = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]), raw.count > 16 else {
            throw ApiError("响应解密失败：非法的加密体")
        }
        let iv = [UInt8](raw.prefix(16))
        let ct = Data(raw.dropFirst(16))
        var data = try aesCBC(CCOperation(kCCDecrypt), key: shareAesKey, iv: iv, input: ct)
        // alist YunCrypto 同款：解密后若为 gzip 则尝试解压（iOS 无 Foundation gzip API，用 Compression 流式解码兜底）
        if data.count > 2 && data[0] == 0x1f && data[1] == 0x8b {
            if let inflated = C139Gzip.inflate(data) {
                data = inflated
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    // ---------- 分享解析（§15） ----------

    /// 分享标题：getOutLinkGeneral（匿名）→ outLinkGeneral[].lkName；失败返回 nil。
    func getOutLinkTitle(linkId: String) async throws -> String? {
        let req: [String: Any] = ["linkID": linkId, "isPasswd": 1, "account": ""]
        let plain = c139JsonString(["getOutLinkGeneralReq": req])
        let resp = try await sharePostAnonymous(C139Constants.shareGeneralUrl, plainBody: plain)
        let resultCode = resp.string("resultCode")
        if !resultCode.isEmpty && resultCode != "0" { return nil }
        if !c139OptBool(resp, "success", default: true) { return nil }
        let data = resp.object("data").object("getOutLinkGeneralResp")
        if data.isNull { return nil }
        let array = data.array("outLinkGeneral")
        guard let first = array.first else { return nil }
        let lkName = first.string("lkName")
        return lkName.isEmpty ? nil : lkName
    }

    /// 分享明文提取码：getOutLinkGeneral（匿名）→ outLinkGeneral[].passwd。
    func getOutLinkPassword(linkId: String) async throws -> String? {
        let req: [String: Any] = ["linkID": linkId, "isPasswd": 1, "account": ""]
        let plain = c139JsonString(["getOutLinkGeneralReq": req])
        let resp = try await sharePostAnonymous(C139Constants.shareGeneralUrl, plainBody: plain)
        let resultCode = resp.string("resultCode")
        if !resultCode.isEmpty && resultCode != "0" { return nil }
        if !c139OptBool(resp, "success", default: true) { return nil }
        let data = resp.object("data").object("getOutLinkGeneralResp")
        if data.isNull { return nil }
        let array = data.array("outLinkGeneral")
        guard let first = array.first else { return nil }
        let passwd = first.string("passwd")
        return passwd.isEmpty ? nil : passwd
    }

    /// 分享列目录：getOutLinkInfoV6（匿名调用）。
    /// 同时解析 caLst（子文件夹）+ coLst（文件/嵌套文件夹）并合并返回（文件夹在前）。
    func getShareFiles(
        linkId: String,
        pcaId: String,
        passwd: String,
        begin: Int = 1,
        end: Int = 200
    ) async throws -> [ShareFile] {
        let req: [String: Any] = [
            "account": "",
            "linkID": linkId,
            "passwd": passwd,
            "caSrt": 1,
            "coSrt": 1,
            "srtDr": 0,
            "bNum": begin,
            "pCaID": pcaId,
            "eNum": end,
        ]
        let plain = c139JsonString(["getOutLinkInfoReq": req])
        let resp = try await sharePostAnonymous(C139Constants.shareListUrl, plainBody: plain)
        let resultCode = resp.string("resultCode")
        if !resultCode.isEmpty && resultCode != "0" {
            let desc = resp.string("desc")
            throw ApiError(desc.isEmpty ? "获取文件列表失败（\(resultCode)）" : desc)
        }
        if !c139OptBool(resp, "success", default: true) {
            let desc = resp.string("desc")
            throw ApiError(desc.isEmpty ? "获取文件列表失败" : desc)
        }
        let data = resp.object("data")
        if data.isNull { return [] }

        var result: [ShareFile] = []
        // 1) 子文件夹列表 caLst
        for item in data.array("caLst") {
            let udTime = item.string("udTime")
            result.append(ShareFile(
                fid: item.string("caID"),
                fname: item.string("caName"),
                fsize: 0,
                isdir: true,
                pdirFid: pcaId,
                fidToken: "",
                modifyTime: udTime.isEmpty ? item.string("ctTime") : udTime
            ))
        }
        // 2) 文件列表 coLst（含 coType==2 的文件夹）
        for item in data.array("coLst") {
            let udTime = item.string("udTime")
            result.append(ShareFile(
                fid: item.string("coID"),
                fname: item.string("coName"),
                fsize: item.long("coSize"),
                isdir: c139OptBool(item, "isdir", default: item.int("coType") == 2),
                pdirFid: pcaId,
                fidToken: "",
                modifyTime: udTime.isEmpty ? item.string("ctTime") : udTime
            ))
        }
        return result
    }

    /// 分享下载：dlFromOutLinkV3 → data.redrUrl（OBS S3 签名直链，900s 有效）。
    func getShareDownloadLink(
        coId: String,
        linkId: String,
        account: String,
        authorization: String?
    ) async throws -> DownloadLink? {
        let reqV3: [String: Any] = [
            "account": account,
            "linkID": linkId,
            "coIDLst": ["item": [coId]],
            "commonAccountInfo": ["account": account, "accountType": 1],
        ]
        let plain = c139JsonString(["dlFromOutLinkReqV3": reqV3])
        let resp = try await sharePostEncrypted(C139Constants.shareLinkUrl, plainBody: plain, authorization: authorization)
        let resultCode = resp.string("resultCode")
        if !resultCode.isEmpty && resultCode != "0" {
            let desc = resp.string("desc")
            throw ApiError(desc.isEmpty ? "获取下载链接失败（\(resultCode)）" : desc)
        }
        if !c139OptBool(resp, "success", default: true) {
            let desc = resp.string("desc")
            throw ApiError(desc.isEmpty ? "获取下载链接失败" : desc)
        }
        let data = resp.object("data")
        if data.isNull { return nil }
        let url = data.string("redrUrl")
        if url.isEmpty { return nil }
        var filename = data.string("fileName")
        if filename.isEmpty { filename = data.string("coName") }
        if filename.isEmpty { filename = coId }
        let size = c139IsNullKey(data, "coSize") ? data.long("size") : data.long("coSize")
        return DownloadLink(fid: coId, filename: filename, downloadUrl: url, size: size)
    }

    // ---------- 个人网盘管理（明文 JSON + Authorization + mcloud-sign，无 Cookie） ----------

    /// 单页列目录（含翻页游标）；返回 (文件列表, 下一页游标 or nil=末页)。
    private func fetchCloudPage(
        parentFileId: String,
        cookie: String,
        pageCursor: String?
    ) async throws -> (files: [ShareFile], next: String?)? {
        guard let authorization = C139Constants.extractAuthorization(cookie) else {
            throw ApiError("登录态缺少 authorization，请重新登录")
        }
        // pageCursor 必须是真正的 JSON null；误传字符串 "null" 会导致翻页原地打转
        let cursorValue: Any
        if let pc = pageCursor, !pc.isEmpty, pc != "null" {
            cursorValue = pc
        } else {
            cursorValue = NSNull()
        }
        let req: [String: Any] = [
            "pageInfo": ["pageSize": 100, "pageCursor": cursorValue],
            "orderBy": "updated_at",
            "orderDirection": "DESC",
            "parentFileId": parentFileId,
            "imageThumbnailStyleList": ["Small", "Large"],
        ]
        let resp = try await cloudPost(C139Constants.fileListUrl, plainBody: c139JsonString(req), authorization: authorization)
        try checkCloud(resp, "获取文件列表失败")
        let data = resp.object("data")
        if data.isNull { return nil }
        var files: [ShareFile] = []
        for item in data.array("items") {
            files.append(ShareFile(
                fid: item.string("fileId"),
                fname: item.string("name"),
                fsize: item.long("size"),
                isdir: item.string("type") == "folder",
                pdirFid: parentFileId,
                fidToken: item.string("fileId"),
                modifyTime: item.string("updatedAt")
            ))
        }
        // nextPageCursor 为 JSON null 或字符串 "null" 均视为末页
        let next: String?
        if c139IsNullKey(data, "nextPageCursor") {
            next = nil
        } else {
            let cursor = data.string("nextPageCursor")
            next = (cursor.isEmpty || cursor == "null") ? nil : cursor
        }
        return (files, next)
    }

    /// 列目录（自动翻页，返回该目录下全部文件）。
    func listCloudFiles(
        parentFileId: String,
        cookie: String,
        pageCursor: String? = nil
    ) async throws -> [ShareFile] {
        var all: [ShareFile] = []
        var seen = Set<String>()
        var cursor = pageCursor
        for _ in 0..<200 {   // 封顶 200 页，防异常死循环
            guard let page = try await fetchCloudPage(parentFileId: parentFileId, cookie: cookie, pageCursor: cursor) else {
                return all
            }
            for f in page.files where !f.fid.isEmpty {
                if seen.insert(f.fid).inserted { all.append(f) }
            }
            guard let next = page.next else { return all }   // 末页
            if next == cursor { return all }                 // 游标未推进，立即终止
            cursor = next
        }
        return all
    }

    /// 仅列文件夹（移动到…目标选择）。
    func listFolders(parentFileId: String, cookie: String) async throws -> [ShareFile] {
        guard let authorization = C139Constants.extractAuthorization(cookie) else {
            throw ApiError("登录态缺少 authorization，请重新登录")
        }
        let req: [String: Any] = [
            "pageInfo": ["pageSize": 100, "pageCursor": NSNull()],
            "orderBy": "updated_at",
            "orderDirection": "DESC",
            "parentFileId": parentFileId,
            "imageThumbnailStyleList": ["Small", "Large"],
            "type": "folder",
        ]
        let resp = try await cloudPost(C139Constants.fileListUrl, plainBody: c139JsonString(req), authorization: authorization)
        try checkCloud(resp, "获取文件夹列表失败")
        let data = resp.object("data")
        if data.isNull { return [] }
        return data.array("items").map { item in
            ShareFile(
                fid: item.string("fileId"),
                fname: item.string("name"),
                fsize: 0,
                isdir: true,
                pdirFid: parentFileId,
                fidToken: item.string("fileId"),
                modifyTime: item.string("updatedAt")
            )
        }
    }

    /// 新建文件夹（个人盘）：POST /hcy/file/create（type='folder'）。返回新文件夹 fileId。
    func createDir(parentFileId: String, name: String, cookie: String) async throws -> String {
        guard let authorization = C139Constants.extractAuthorization(cookie) else {
            throw ApiError("登录态缺少 authorization，请重新登录")
        }
        let req: [String: Any] = [
            "parentFileId": parentFileId,
            "name": name,
            "description": "",
            "type": "folder",
            "fileRenameMode": "force_rename",
        ]
        let resp = try await cloudPost(C139Constants.fileCreateUrl, plainBody: c139JsonString(req), authorization: authorization)
        try checkCloud(resp, "新建文件夹失败")
        let fileId = resp.object("data").string("fileId")
        if fileId.isEmpty { throw ApiError("移动云盘未返回文件夹编号") }
        return fileId
    }

    /// 重命名。
    func renameFile(fileId: String, newName: String, cookie: String) async throws -> Bool {
        guard let authorization = C139Constants.extractAuthorization(cookie) else {
            throw ApiError("登录态缺少 authorization，请重新登录")
        }
        let req: [String: Any] = ["fileId": fileId, "name": newName, "description": ""]
        let resp = try await cloudPost(C139Constants.fileUpdateUrl, plainBody: c139JsonString(req), authorization: authorization)
        try checkCloud(resp, "重命名失败")
        return true
    }

    /// 移动（异步），返回 taskId。
    func moveFiles(fileIds: [String], toParentFileId: String, cookie: String) async throws -> String? {
        guard let authorization = C139Constants.extractAuthorization(cookie) else {
            throw ApiError("登录态缺少 authorization，请重新登录")
        }
        let req: [String: Any] = ["fileIds": fileIds, "toParentFileId": toParentFileId]
        let resp = try await cloudPost(C139Constants.batchMoveUrl, plainBody: c139JsonString(req), authorization: authorization)
        try checkCloud(resp, "移动失败")
        let taskId = resp.object("data").string("taskId")
        return taskId.isEmpty ? nil : taskId
    }

    /// 删除（异步，移入回收站），返回 taskId。
    func deleteFiles(fileIds: [String], cookie: String) async throws -> String? {
        guard let authorization = C139Constants.extractAuthorization(cookie) else {
            throw ApiError("登录态缺少 authorization，请重新登录")
        }
        let req: [String: Any] = ["fileIds": fileIds]
        let resp = try await cloudPost(C139Constants.batchTrashUrl, plainBody: c139JsonString(req), authorization: authorization)
        try checkCloud(resp, "删除失败")
        let taskId = resp.object("data").string("taskId")
        return taskId.isEmpty ? nil : taskId
    }

    /// 异步任务轮询（移动/删除），返回状态。
    func getTask(taskId: String, cookie: String) async throws -> C139TaskStatus {
        guard let authorization = C139Constants.extractAuthorization(cookie) else {
            throw ApiError("登录态缺少 authorization，请重新登录")
        }
        let req: [String: Any] = ["taskId": taskId]
        let resp = try await cloudPost(C139Constants.taskGetUrl, plainBody: c139JsonString(req), authorization: authorization)
        try checkCloud(resp, "查询任务失败")
        let data = resp.object("data")
        if data.isNull { return C139TaskStatus(status: "", progress: 0, results: []) }
        let taskInfo = data.object("taskInfo")
        var results: [(String, String)] = []
        for item in data.array("batchFileResults") {
            results.append((item.string("fileId"), item.string("errCode")))
        }
        return C139TaskStatus(status: taskInfo.string("status"), progress: taskInfo.int("progress"), results: results)
    }

    /// 下载直链（OBS 预签名，900s 有效）。
    func getDownloadUrl(fileId: String, cookie: String) async throws -> DownloadLink? {
        guard let authorization = C139Constants.extractAuthorization(cookie) else {
            throw ApiError("登录态缺少 authorization，请重新登录")
        }
        let resp = try await cloudPost(C139Constants.downloadUrl, plainBody: c139JsonString(["fileId": fileId]), authorization: authorization)
        try checkCloud(resp, "获取下载链接失败")
        let data = resp.object("data")
        if data.isNull { return nil }
        let url = data.string("url")
        if url.isEmpty { return nil }
        // getDownloadUrl 响应不含 name（仅 url/expiration/size）；文件名由调用方用列表 name 填充
        return DownloadLink(fid: fileId, filename: data.string("name"), downloadUrl: url, size: data.long("size"))
    }

    /// 创建分享（getOutLink，需 Cookie + mcloud-skey；提取码系统自动生成）。
    /// - Parameter period 有效期天数：nil=永久（不传 period 字段）、1/7/30=天数。
    func createShare(
        coIDLst: [String],
        caIDLst: [String],
        period: Int?,
        dedicatedName: String,
        cookie: String
    ) async throws -> ShareInfo {
        guard let authorization = C139Constants.extractAuthorization(cookie) else {
            throw ApiError("登录态缺少 authorization，请重新登录")
        }
        guard let account = accountFromAuthorization(authorization) else {
            throw ApiError("无法从登录态解析账号，请重新登录")
        }
        var getOutLinkReq: [String: Any] = [
            "subLinkType": 0,
            "encrypt": 1,
            "coIDLst": coIDLst,
            "caIDLst": caIDLst,
            "pubType": 1,
            "dedicatedName": dedicatedName,
            "periodUnit": 1,
            "viewerLst": [],
            "extInfo": ["isWatermark": 0, "shareChannel": "3001"],
            "commonAccountInfo": ["account": account, "accountType": 1],
        ]
        if let period = period { getOutLinkReq["period"] = period }
        let plain = c139JsonString(["getOutLinkReq": getOutLinkReq])
        let resp = try await cloudPost(C139Constants.outlinkCreateUrl, plainBody: plain, authorization: authorization, cookie: cookie, needSkey: true)
        if !c139OptBool(resp, "success", default: true) || resp.string("code") != "0" {
            let message = resp.string("message")
            throw ApiError(message.isEmpty ? "创建分享失败" : message)
        }
        let set = resp.object("data").object("getOutLinkRes").array("getOutLinkResSet").first
        guard let item = set else { throw ApiError("创建分享失败：未返回链接") }
        let linkUrl = item.string("linkUrl")
        if linkUrl.isEmpty { throw ApiError("创建分享失败：未返回链接") }
        // 139 响应不返回有效期，只能按请求时用的天数回填中性码
        let expiredType: Int
        switch period {
        case .none: expiredType = C139ShareExpire.forever
        case .some(1): expiredType = C139ShareExpire.oneDay
        case .some(7): expiredType = C139ShareExpire.sevenDays
        case .some(30): expiredType = C139ShareExpire.thirtyDays
        default: expiredType = C139ShareExpire.unknown
        }
        return ShareInfo(
            shareUrl: linkUrl,
            passcode: item.string("passwd"),
            pwdId: item.string("linkID"),
            title: dedicatedName,
            expiredType: expiredType
        )
    }

    // ---------- 网盘空间详情 ----------

    /// 网盘空间详情（diskSize/freeDiskSize，单位 MB；需 Cookie+mcloud-skey）。
    func getQuota(cookie: String) async throws -> QuotaInfo? {
        guard let authorization = C139Constants.extractAuthorization(cookie) else { return nil }
        guard let account = accountFromAuthorization(authorization) else { return nil }
        do {
            let req: [String: Any] = [
                "userDomainId": "",
                "commonAccountInfo": ["account": account, "accountType": 1],
            ]
            let resp = try await cloudPost(
                "https://user-njs.yun.139.com/user/disk/quota/detail",
                plainBody: c139JsonString(req),
                authorization: authorization,
                cookie: cookie,
                needSkey: true
            )
            try checkCloud(resp, "获取空间详情失败")
            let data = resp.object("data")
            if data.isNull { return nil }
            let total = data.long("diskSize") * 1024 * 1024
            let free = data.long("freeDiskSize")
            let used: Int64
            // quotaList[0] = 个人云（我的文件）已用（MB）
            if let first = data.array("quotaList").first, !first.isNull {
                used = first.long("usedSize") * 1024 * 1024
            } else {
                used = total - free * 1024 * 1024
            }
            return QuotaInfo(used: used, total: total)
        } catch {
            return nil
        }
    }

    // ---------- 转存（分享导入，share host AES 加密） ----------

    /// 创建转存任务，返回 taskID（含 sk* 前缀）。
    func createTransferTask(
        coIDLst: [String],
        catalogIDLst: [String],
        toFolderId: String,
        linkID: String,
        account: String,
        authorization: String?
    ) async throws -> String? {
        let taskInfo: [String: Any] = [
            "contentInfoList": coIDLst.map { "/\($0)" },
            "catalogInfoList": catalogIDLst,
            "newCatalogID": toFolderId,
            "linkID": linkID,
            "newCatalogName": "手机图片",
            "needPassword": true,
        ]
        let req: [String: Any] = [
            "createOuterLinkBatchOprTaskReq": [
                "msisdn": account,
                "ownerAccount": "",
                "taskType": 1,
                "taskInfo": taskInfo,
                "linkID": linkID,
                "needPassword": true,
            ],
            "commonAccountInfo": ["account": account, "accountType": 1],
        ]
        let resp = try await sharePostEncrypted(C139Constants.transferCreateUrl, plainBody: c139JsonString(req), authorization: authorization)
        let resultCode = resp.string("resultCode")
        let code = resultCode.isEmpty ? resp.string("code") : resultCode
        if !code.isEmpty && code != "0" {
            let desc = resp.string("desc")
            throw ApiError(desc.isEmpty ? "创建转存任务失败（\(code)）" : desc)
        }
        let taskID = resp.object("data").string("taskID")
        return taskID.isEmpty ? nil : taskID
    }

    /// 查询转存结果。
    func queryTransferTask(taskID: String, account: String, authorization: String?) async throws -> C139TransferResult {
        let req: [String: Any] = [
            "queryBatchOprTaskDetailReq": [
                "taskID": taskID,
                "msisdn": account,
                "commonAccountInfo": ["account": account, "accountType": 1],
            ],
        ]
        let resp = try await sharePostEncrypted(C139Constants.transferQueryUrl, plainBody: c139JsonString(req), authorization: authorization)
        let resultCode = resp.string("resultCode")
        let code = resultCode.isEmpty ? resp.string("code") : resultCode
        if !code.isEmpty && code != "0" {
            let desc = resp.string("desc")
            throw ApiError(desc.isEmpty ? "查询转存结果失败（\(code)）" : desc)
        }
        let data = resp.object("data")
        if data.isNull { return C139TransferResult(done: false, mapping: [:]) }
        let task = data.object("batchOprTask")
        let done = (task.int("progress") >= 100) && (task.int("taskStatus") == 2)
        var mapping: [String: String] = [:]
        for item in data.object("contentList").array("idRspInfo") where item.string("reason") == "0000" {
            mapping[item.string("srcId")] = item.string("rstId")
        }
        return C139TransferResult(done: done, mapping: mapping)
    }

    // ---------- 请求构造与响应解析 ----------

    /// 原始 POST：body 为已构造好的字符串（签名与请求体逐字节一致）。
    private func postRaw(_ url: String, headers: [String: String], body: String) async throws -> String {
        var request = try client.makeRequest(url, method: "POST", headers: headers)
        request.httpBody = Data(body.utf8)
        let (data, _) = try await client.data(for: request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 个人网盘管理专用 POST（明文 JSON，Authorization + mcloud-sign 按明文算）。
    private func cloudPost(
        _ url: String,
        plainBody: String,
        authorization: String,
        cookie: String? = nil,
        needSkey: Bool = false
    ) async throws -> JSONValue {
        var headers: [String: String] = [
            "Authorization": authorization,
            "mcloud-sign": signHeader(bodyJson: plainBody),
            "x-yun-channel-source": C139Constants.yunChannelSource,
            "x-yun-app-channel": C139Constants.yunChannelSource,
            "x-huawei-channelSrc": C139Constants.yunChannelSource,
            "mcloud-version": C139Constants.mcloudVersion,
            "mcloud-client": C139Constants.mcloudClient,
            "mcloud-channel": C139Constants.mcloudChannel,
            "mcloud-route": "001",
            "x-yun-module-type": C139Constants.yunModuleType,
            "x-yun-api-version": "v1",
            "x-yun-svc-type": "1",
            "x-SvcType": "1",
            "caller": "web",
            "x-inner-ntwk": "2",
            "CMS-DEVICE": "default",
            "x-m4c-src": C139Constants.m4cSrc,
            "x-m4c-caller": C139Constants.m4cCaller,
            "X-Deviceinfo": C139Constants.xDeviceinfo,
            "x-yun-client-info": C139Constants.xClientInfo,
            "INNER-HCY-ROUTER-HTTPS": "1",
            "Sec-Fetch-Site": "same-site",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "X-Requested-With": "mark.via",
            "Content-Type": "application/json;charset=UTF-8",
            "User-Agent": C139Constants.pcUA,
            "Origin": "https://yun.139.com",
            "Referer": "https://yun.139.com/",
            "Accept": "application/json, text/plain, */*",
        ]
        if let cookie = cookie {
            headers["Cookie"] = cookie
            if needSkey, let skey = skeyFrom(cookie), !skey.isEmpty {
                headers["mcloud-skey"] = skey
            }
        }
        let text = try await postRaw(url, headers: headers, body: plainBody)
        if text.isEmpty { throw ApiError("请求失败：响应为空") }
        guard let json = JSONValue.parse(text) else { throw ApiError("响应解析失败") }
        return json
    }

    /// 管理接口成功判定：success==true 且 code ∈ {"0000","0"}。
    private func checkCloud(_ json: JSONValue, _ fallback: String) throws {
        let code = json.string("code")
        if c139OptBool(json, "success", default: true) && (code == "0000" || code == "0") { return }
        let message = json.string("message")
        throw ApiError("\((message.isEmpty ? fallback : message))（code=\(code)）")
    }

    /// 从 Cookie 中提取 mcloud-skey。
    private func skeyFrom(_ cookie: String) -> String? {
        for kv in cookie.split(separator: ";") {
            let item = kv.trimmingCharacters(in: .whitespaces)
            if item.hasPrefix("skey=") { return String(item.dropFirst("skey=".count)) }
        }
        return nil
    }

    /// 响应解析：优先按加密体解密，失败则兼容明文透传。
    private func decodeResponse(_ text: String) throws -> JSONValue {
        if text.isEmpty { throw ApiError("请求失败：响应为空") }
        if let decrypted = try? decryptBody(text), let json = JSONValue.parse(decrypted) {
            return json
        }
        if let json = JSONValue.parse(text) { return json }
        throw ApiError("响应解析失败")
    }

    /// 匿名 POST（列表端点 getOutLinkInfoV6 专用）：不带 Authorization/mcloud-sign，body 加密。
    /// 必须带 hcy-cool-flag: 1（网关解密开关，缺它业务层拿不到明文 → 9530）。
    private func sharePostAnonymous(_ url: String, plainBody: String) async throws -> JSONValue {
        let encrypted = try encryptBody(plainBody)
        let headers: [String: String] = [
            "hcy-cool-flag": "1",
            "x-deviceinfo": C139Constants.shareXDeviceinfo,
            "x-huawei-channelsrc": C139Constants.shareXHuaweiChannelsrc,
            "x-mm-source": C139Constants.shareXMmSource,
            "Content-Type": "application/json;charset=UTF-8",
            "User-Agent": C139Constants.shareMobileUA,
            "Origin": "https://yun.139.com",
            "Referer": "https://yun.139.com/",
            "Accept": "application/json, text/plain, */*",
        ]
        let text = try await postRaw(url, headers: headers, body: encrypted)
        return try decodeResponse(text)
    }

    /// 分享专用 POST：body 加密发送，mcloud-sign 按明文算，必须带 hcy-cool-flag: 1。
    private func sharePostEncrypted(_ url: String, plainBody: String, authorization: String?) async throws -> JSONValue {
        let encrypted = try encryptBody(plainBody)
        var headers: [String: String] = [
            "hcy-cool-flag": "1",
            "x-deviceinfo": C139Constants.shareXDeviceinfo,
            "x-huawei-channelsrc": C139Constants.shareXHuaweiChannelsrc,
            "x-mm-source": C139Constants.shareXMmSource,
            "mcloud-sign": signHeader(bodyJson: plainBody),
            "Content-Type": "application/json;charset=UTF-8",
            "User-Agent": C139Constants.shareMobileUA,
            "Origin": "https://yun.139.com",
            "Referer": "https://yun.139.com/",
            "Accept": "application/json, text/plain, */*",
        ]
        if let authorization = authorization, !authorization.isEmpty {
            headers["Authorization"] = authorization
        }
        let text = try await postRaw(url, headers: headers, body: encrypted)
        return try decodeResponse(text)
    }
}

// MARK: - C139ResolveRepository

/// 139（和彩云）分享解析仓库：cookie → getOutLinkInfoV6 列目录 → dlFromOutLinkV3 直链。
/// 139 分享无需转存（share host 直接列目录 + 取直链）；列目录允许游客（匿名端点），取直链要求登录。
final class C139ResolveRepository: ShareResolveRepository {

    private let api = C139Api()

    init() {}

    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        guard let parsed = ShareLinkParser.parse(link) else {
            throw ApiError("无法识别分享链接")
        }
        // 139 分享无 token：shareId 即 linkID，stoken 暂存提取码
        // 密码优先级：用户手输 > 139 getOutLinkGeneral 明文回吐的 passwd（避免下载因缺密码报 9188）
        let leakedPwd = (try? await api.getOutLinkPassword(linkId: parsed.shareId)) ?? nil
        let userPwd = (pwd?.isEmpty == false) ? pwd : nil
        let passwd = userPwd ?? leakedPwd ?? ""
        // 标题从 getOutLinkGeneral 拿（失败回退短链 ID）
        let fetchedTitle = (try? await api.getOutLinkTitle(linkId: parsed.shareId)) ?? nil
        let title = (fetchedTitle?.isEmpty == false) ? fetchedTitle! : parsed.shareId
        return ShareSession(shareId: parsed.shareId, stoken: passwd, title: title)
    }

    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        // 列表端点为匿名调用（无需 authorization/account）
        // pCaID 根目录必须传 "root"（空串会报 pCaID不能为空），子目录传父 caID / coID
        let pcaId = (dirFid == "0" || dirFid.isEmpty) ? "root" : dirFid
        var all: [ShareFile] = []
        var begin = 1
        var batch: [ShareFile] = []
        repeat {
            batch = try await api.getShareFiles(
                linkId: session.shareId,
                pcaId: pcaId,
                passwd: session.stoken,
                begin: begin,
                end: begin + 199
            )
            all += batch
            begin += 200
        } while batch.count == 200 && begin <= 20_000
        return all
    }

    /// 139 分享不需要转存/个人网盘直链，保留空实现避免误用。
    func ensureTempDir(cookie: String) async throws -> String {
        throw ApiError("139 分享无需转存")
    }

    func transferFile(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        guard let account = C139Constants.extractAccountFull(cookie) else {
            throw ApiError("登录态缺少账号信息，请重新登录")
        }
        let authorization = C139Constants.extractAuthorization(cookie)
        // 139 转存：创建批量任务（AES 加密接口）→ 轮询查询结果 → 返回转存后新 fileId
        guard let taskId = try await api.createTransferTask(
            coIDLst: [file.fid],
            catalogIDLst: [],
            toFolderId: toDirFid,
            linkID: session.shareId,
            account: account,
            authorization: authorization
        ) else {
            throw ApiError("创建转存任务失败")
        }
        var newId: String?
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 800_000_000)
            let result = try await api.queryTransferTask(taskID: taskId, account: account, authorization: authorization)
            if result.done {
                newId = result.mapping[file.fid]
                break
            }
        }
        guard let id = newId else { throw ApiError("转存超时或失败") }
        return id
    }

    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        throw ApiError("139 分享请使用 getShareDownloadLink")
    }

    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        guard let account = C139Constants.extractAccountFull(cookie) else {
            throw ApiError("登录态缺少账号信息，请重新登录")
        }
        let authorization = C139Constants.extractAuthorization(cookie)
        guard let link = try await api.getShareDownloadLink(
            coId: file.fid,
            linkId: session.shareId,
            account: account,
            authorization: authorization
        ) else {
            throw ApiError("获取下载链接失败")
        }
        // 文件名用列表里的 coName（dlFromOutLinkV3 响应不含文件名，否则会 fallback 成 coID 乱码）
        let name = file.fname.isEmpty ? link.filename : file.fname
        return DownloadLink(
            fid: link.fid,
            filename: name,
            downloadUrl: link.downloadUrl,
            size: link.size,
            cleanupDirFid: link.cleanupDirFid,
            isHls: link.isHls,
            guestCookie: link.guestCookie
        )
    }
}

/// gzip/zlib 解压兜底（对应 alist YunCrypto 的解压分支）。
/// 使用 Compression 框架的流式解码接口；解码失败返回 nil，由调用方保留原始数据。
enum C139Gzip {

    static func inflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var output = Data()
        let result: Data? = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = base
            stream.src_size = data.count
            while true {
                stream.dst_ptr = buffer
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    output.append(buffer, count: bufferSize - stream.dst_size)
                    if status == COMPRESSION_STATUS_END { return output }
                    if stream.src_size == 0 { return nil }
                default:
                    return nil
                }
            }
        }
        return result
    }
}
