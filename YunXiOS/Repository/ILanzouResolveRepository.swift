/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：蓝奏云优享版网络接口层与分享解析仓库。
 * 对应 Kotlin：
 *   - data/network/ILanzouConstants.kt
 *   - data/network/ILanzouApi.kt
 *   - data/repository/ILanzouResolveRepository.kt
 *
 * 平台说明：蓝奏优享（ilanzou）没有独立的“分享解析”接口。其分享目录 / 取链走本站 Web
 * 分享页协议（apix 主机：/unproved/share/list、/unproved/file/redirect，匿名可用），
 * 转存仍走个人盘接口（apis 主机：/proved/file/transfer）需登录 appToken。
 * 认证参数 appToken + uuid 走 URL query，appToken 特殊编码（%3A 还原为冒号）。
 */

import Foundation

// MARK: - 常量

/// 蓝奏云优享版常量（文档 §1）
enum ILanzouConstants {

    static let API_BASE = "https://apis.ilanzou.com"
    static let WEB_SITE = "https://www.ilanzou.com"

    /// 下载请求头（文档 §4.1）
    static let DOWNLOAD_REFERER = WEB_SITE + "/"
    static let DOWNLOAD_ORIGIN = WEB_SITE

    static let WEB_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    static let DEV_TYPE = "6"
    static let DEV_MODEL = "chrome"
    static let DEV_VERSION = "125"

    /// 页大小固定 60（文档 §3.1）
    static let PAGE_SIZE = 60

    // ---------- 端点 ----------
    static let GET_UUID = API_BASE + "/unproved/getUuid"
    static let LOGIN = API_BASE + "/unproved/login"
    static let ACCOUNT_MAP = API_BASE + "/proved/user/account/map"
    static let FILE_LIST = API_BASE + "/proved/record/file/list"
    static let FOLDER_SAVE = API_BASE + "/proved/file/folder/save"
    static let FOLDER_EDIT = API_BASE + "/proved/file/folder/edit"
    static let FILE_EDIT = API_BASE + "/proved/file/edit"
    static let FOLDER_MOVE = API_BASE + "/proved/file/folder/move"
    static let FILE_DELETE = API_BASE + "/proved/file/delete"
    static let FILE_REDIRECT = API_BASE + "/unproved/file/redirect"

    // ---------- 分享（本站 Web 分享页走后端 apix，与个人盘 apis 不同） ----------
    /// 分享业务主机（分享页 JS config.apiBaseURL = https://apix.ilanzou.com/）
    static let SHARE_API_BASE = "https://apix.ilanzou.com"
    static let SHARE_LIST = SHARE_API_BASE + "/unproved/share/list"
    static let SHARE_REDIRECT = SHARE_API_BASE + "/unproved/file/redirect"
    /// 分享页 Referer（分享页地址为 {WEB_SITE}/s/<shareId>）
    static let SHARE_REFERER_PREFIX = WEB_SITE + "/s/"
    /// 分享页 devModel 与网页一致（首字母大写）
    static let SHARE_DEV_MODEL = "Chrome"
    /// 分享转存（需登录）：/proved/file/transfer + 轮询 /proved/file/transfer/num
    static let FILE_TRANSFER = API_BASE + "/proved/file/transfer"
    static let FILE_TRANSFER_NUM = API_BASE + "/proved/file/transfer/num"

    /// 根目录 id
    static let ROOT_FOLDER_ID = "0"

    /// AES 密钥（文档 §6.1）
    static let AES_KEY = "lanZouY-disk-app"

    /// 文件夹 id 前缀 d: / 文件 id 前缀 f:（文档 §3.1 ID 规范）
    static let FOLDER_PREFIX = "d:"
    static let FILE_PREFIX = "f:"

    static func newUuid() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var value = ""
        value.reserveCapacity(16)
        for _ in 0..<16 { value.append(chars[Int.random(in: 0..<chars.count)]) }
        return value
    }
}

// MARK: - AES-128 / ECB / PKCS7（纯 Foundation 实现）

/// 蓝奏优享直链参数需 AES-ECB 加密后转十六进制（文档 §6.1）。
/// Foundation 不提供 AES，CryptoKit 也不提供 ECB 模式，故此处以纯 Swift 实现 AES-128 ECB/PKCS7。
private enum ILanzouAES {

    static func encryptECBHex(key: String, plaintext: String) -> String {
        guard let cipher = AES128ECB(key: Array(key.utf8)) else { return "" }
        return cipher.encryptHex(Array(plaintext.utf8))
    }

    private struct AES128ECB {

        private let roundKeys: [UInt8]

        /// AES S 盒
        private static let sbox: [UInt8] = [
            0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
            0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
            0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
            0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
            0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
            0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
            0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
            0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
            0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
            0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
            0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
            0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
            0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
            0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
            0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
            0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
        ]

        /// 轮常量
        private static let rcon: [UInt8] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]

        init?(key: [UInt8]) {
            guard key.count == 16 else { return nil }
            var w = [UInt8](repeating: 0, count: 176) // 44 字 × 4 字节
            for i in 0..<16 { w[i] = key[i] }
            var i = 4
            while i < 44 {
                var temp = Array(w[(i - 1) * 4 ..< i * 4])
                if i % 4 == 0 {
                    temp = [temp[1], temp[2], temp[3], temp[0]] // RotWord
                    for j in 0..<4 { temp[j] = Self.sbox[Int(temp[j])] } // SubWord
                    temp[0] ^= Self.rcon[i / 4 - 1]
                }
                for j in 0..<4 { w[i * 4 + j] = w[(i - 4) * 4 + j] ^ temp[j] }
                i += 1
            }
            roundKeys = w
        }

        func encryptHex(_ data: [UInt8]) -> String {
            var input = data
            let pad = 16 - (input.count % 16) // PKCS7：至少补 1 字节
            input.append(contentsOf: [UInt8](repeating: UInt8(pad), count: pad))
            var out = [UInt8]()
            out.reserveCapacity(input.count)
            var offset = 0
            while offset < input.count {
                out.append(contentsOf: encryptBlock(Array(input[offset ..< offset + 16])))
                offset += 16
            }
            return out.map { String(format: "%02x", Int($0)) }.joined()
        }

        // 状态按列主序：state[4 * 列 + 行]
        private func encryptBlock(_ block: [UInt8]) -> [UInt8] {
            var state = block
            addRoundKey(&state, round: 0)
            for round in 1..<10 {
                subBytes(&state)
                shiftRows(&state)
                mixColumns(&state)
                addRoundKey(&state, round: round)
            }
            subBytes(&state)
            shiftRows(&state)
            addRoundKey(&state, round: 10)
            return state
        }

        private func addRoundKey(_ state: inout [UInt8], round: Int) {
            let base = round * 16
            for i in 0..<16 { state[i] ^= roundKeys[base + i] }
        }

        private func subBytes(_ state: inout [UInt8]) {
            for i in 0..<16 { state[i] = Self.sbox[Int(state[i])] }
        }

        private func shiftRows(_ state: inout [UInt8]) {
            var out = state
            for r in 1..<4 {
                for c in 0..<4 { out[4 * c + r] = state[4 * ((c + r) % 4) + r] }
            }
            state = out
        }

        private func mixColumns(_ state: inout [UInt8]) {
            var out = state
            for c in 0..<4 {
                let a0 = state[4 * c], a1 = state[4 * c + 1], a2 = state[4 * c + 2], a3 = state[4 * c + 3]
                out[4 * c] = gmul(a0, 2) ^ gmul(a1, 3) ^ a2 ^ a3
                out[4 * c + 1] = a0 ^ gmul(a1, 2) ^ gmul(a2, 3) ^ a3
                out[4 * c + 2] = a0 ^ a1 ^ gmul(a2, 2) ^ gmul(a3, 3)
                out[4 * c + 3] = gmul(a0, 3) ^ a1 ^ a2 ^ gmul(a3, 2)
            }
            state = out
        }

        /// GF(2^8) 乘法
        private func gmul(_ a: UInt8, _ b: UInt8) -> UInt8 {
            var p: UInt8 = 0
            var aa = a
            var bb = b
            for _ in 0..<8 {
                if bb & 1 != 0 { p ^= aa }
                let hi = aa & 0x80
                aa <<= 1
                if hi != 0 { aa ^= 0x1b }
                bb >>= 1
            }
            return p
        }
    }
}

// MARK: - 账号信息与来源

/// 蓝奏优享账号信息
struct ILanzouAccountInfo {
    let userId: String
    let account: String
    let nickname: String
}

/// 蓝奏优享账号快照（对应 ILanzouAccountEntity 中本仓库读取的字段）
struct ILanzouAccount {
    var appToken: String = ""
    var uuid: String = ""
    var userId: String = ""
    var nickname: String = ""
    var account: String = ""
    var password: String = ""
}

/// 账号来源（对应 ILanzouAccountRepository.getAccount）。
/// 具体实现由应用层注入（如读取全局账号存储）；本层不直接依赖账号持久化。
protocol ILanzouAccountProviding {
    func currentAccount() async -> ILanzouAccount?
}

/// 默认账号来源：未接入账号存储，视为未登录（游客）。
/// 此时 appToken 由调用方经 `cookie` 参数透传，userId 为空串（等价未登录取链）。
struct GuestILanzouAccountProvider: ILanzouAccountProviding {
    func currentAccount() async -> ILanzouAccount? { nil }
}

// MARK: - ILanzouApi

/// 访问验证标记（409 + text/html）：exec 捕获后最多重放一次
private struct ILanzouAccessChallenge: Error {}

/// 请求语义：登录请求对 code -1/-2 的报错方式与普通请求不同
private enum ILanzouRequestKind {
    case normal
    case login
}

/// 不跟随重定向的 URLSession 委托（对应 OkHttp followRedirects(false)）
private final class ILanzouNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// 蓝奏云优享版 API 封装（文档 §1-§4）。
/// 认证参数 appToken + uuid 走 URL query；appToken 特殊编码（%3A 还原为冒号）。
final class ILanzouApi {

    private let redirectDelegate = ILanzouNoRedirectDelegate()

    /// 取直链需读取 302 Location，故单独使用不跟随重定向的会话
    private lazy var noRedirectSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config, delegate: self.redirectDelegate, delegateQueue: nil)
    }()

    init() {}

    // ---------- 认证 ----------

    /// 获取设备标识（文档 §2.1）
    func getUuid() async throws -> String {
        let url = buildUrl(ILanzouConstants.GET_UUID, uuid: "", appToken: nil, extra: true, params: [])
        let json = try await exec("GET", url)
        let uuid = json.string("uuid")
        if !isFullMatch("^[A-Za-z0-9_-]{8,128}$", uuid) {
            throw ApiError("蓝奏优享未返回有效设备标识")
        }
        return uuid
    }

    /// 账号密码登录（文档 §2.2），返回 appToken
    func login(loginName: String, loginPwd: String, uuid: String) async throws -> String {
        let name = loginName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || loginPwd.isEmpty { throw ApiError("请输入蓝奏优享账号和密码") }
        if name.count > 254 { throw ApiError("蓝奏优享用户名过长") }
        if loginPwd.count > 256 { throw ApiError("蓝奏优享密码过长") }
        let url = buildUrl(ILanzouConstants.LOGIN, uuid: uuid, appToken: nil, extra: true, params: [])
        let json = try await execLogin(url, jsonBody: ["loginName": name, "loginPwd": loginPwd])
        let token = json.object("data").string("appToken")
        if token.count < 16 || !isFullMatch("^[A-Za-z0-9._~+/=:!%&?\\-]+$", token) {
            throw ApiError("蓝奏优享未返回登录凭据，请切换网页登录")
        }
        return token
    }

    /// 账号信息（文档 §2.3）
    func fetchAccountInfo(appToken: String, uuid: String) async throws -> ILanzouAccountInfo? {
        do {
            let url = buildUrl(ILanzouConstants.ACCOUNT_MAP, uuid: uuid, appToken: appToken, extra: true, params: [])
            let json = try await exec("GET", url)
            let map = json.object("map")
            if map.isNull { return nil }
            var userId = firstNonBlank(map.string("userId"), map.string("userId"))
            if userId.isEmpty {
                let numeric = lanzouOptInt(map, "userId", 0)
                userId = numeric != 0 ? String(numeric) : ""
            }
            if userId.isEmpty { return nil }
            var nickname = firstNonBlank(map.string("nickName"), map.string("nickname"), map.string("account"))
            if nickname.isEmpty { nickname = "蓝奏优享用户" }
            return ILanzouAccountInfo(userId: userId, account: map.string("account"), nickname: nickname)
        } catch {
            return nil
        }
    }

    /// 容量信息（文档 §2.3）：KiB → 字节
    func getQuota(appToken: String, uuid: String) async throws -> QuotaInfo? {
        do {
            let url = buildUrl(ILanzouConstants.ACCOUNT_MAP, uuid: uuid, appToken: appToken, extra: true, params: [])
            let json = try await exec("GET", url)
            let map = json.object("map")
            if map.isNull { return nil }
            let used = map.long("usedSize") * 1024
            let total = (map.long("totalSize") + map.long("vipSize") + map.long("rewardSize")) * 1024
            return QuotaInfo(used: used, total: total)
        } catch {
            return nil
        }
    }

    // ---------- 文件管理 ----------

    /// 文件列表（文档 §3.1）：自动翻页，合并文件夹与文件
    func listFiles(appToken: String, uuid: String, folderId: String) async throws -> [ShareFile] {
        var all: [ShareFile] = []
        var seen = Set<String>()
        var page = 1
        while page <= 1000 {
            let params: [(String, String)] = [
                ("offset", String(page)),
                ("limit", String(ILanzouConstants.PAGE_SIZE)),
                ("folderId", folderId),
                ("type", "0"),
            ]
            let url = buildUrl(ILanzouConstants.FILE_LIST, uuid: uuid, appToken: appToken, extra: true, params: params)
            let json = try await exec("GET", url)
            let list = json.array("list")
            if list.isEmpty { break }
            var added = 0
            for item in list {
                if let file = parseItem(item), seen.insert(file.fid).inserted {
                    all.append(file)
                    added += 1
                }
            }
            if added == 0 { throw ApiError("蓝奏优享分页重复或不完整，请重新打开目录") }
            let totalPage = lanzouOptInt(json, "totalPage", 0)
            if totalPage > 0 && page >= totalPage { break }
            if totalPage <= 0 && list.count < ILanzouConstants.PAGE_SIZE { break }
            page += 1
        }
        return all
    }

    /// 新建目录（文档 §3.2）
    func createDir(appToken: String, uuid: String, parentId: String, name: String) async throws -> String {
        let url = buildUrl(ILanzouConstants.FOLDER_SAVE, uuid: uuid, appToken: appToken, extra: true, params: [])
        let body: [String: Any] = [
            "folderDesc": "",
            "folderId": ifBlank(parentId, ILanzouConstants.ROOT_FOLDER_ID),
            "folderName": name,
        ]
        let json = try await exec("POST", url, jsonBody: body)
        var id = ""
        if let first = json.array("list").first {
            id = firstNonBlank(first.string("id"), String(lanzouOptInt(first, "id", 0)))
        }
        if id.isEmpty || id == "0" { throw ApiError("蓝奏优享未返回新文件夹信息，请刷新确认") }
        return id
    }

    /// 目录重命名（文档 §3.3）
    func renameFolder(appToken: String, uuid: String, folderId: String, newName: String) async throws {
        let url = buildUrl(ILanzouConstants.FOLDER_EDIT, uuid: uuid, appToken: appToken, extra: true, params: [])
        let body: [String: Any] = [
            "folderDesc": "",
            "folderId": folderId,
            "folderName": newName,
        ]
        _ = try await exec("POST", url, jsonBody: body)
    }

    /// 文件重命名（文档 §3.3）
    func renameFile(appToken: String, uuid: String, fileId: String, newName: String) async throws {
        let url = buildUrl(ILanzouConstants.FILE_EDIT, uuid: uuid, appToken: appToken, extra: true, params: [])
        let body: [String: Any] = [
            "fileDesc": "",
            "fileId": fileId,
            "fileName": newName,
        ]
        _ = try await exec("POST", url, jsonBody: body)
    }

    /// 移动（文档 §3.4）：folderIds / fileIds 逗号连接
    func moveEntries(
        appToken: String,
        uuid: String,
        folderIds: [String],
        fileIds: [String],
        targetId: String
    ) async throws {
        let url = buildUrl(ILanzouConstants.FOLDER_MOVE, uuid: uuid, appToken: appToken, extra: true, params: [])
        let body: [String: Any] = [
            "folderIds": folderIds.joined(separator: ","),
            "fileIds": fileIds.joined(separator: ","),
            "targetId": ifBlank(targetId, ILanzouConstants.ROOT_FOLDER_ID),
        ]
        _ = try await exec("POST", url, jsonBody: body)
    }

    /// 删除（文档 §3.5）
    func deleteEntries(
        appToken: String,
        uuid: String,
        folderIds: [String],
        fileIds: [String]
    ) async throws {
        let url = buildUrl(ILanzouConstants.FILE_DELETE, uuid: uuid, appToken: appToken, extra: true, params: [])
        let body: [String: Any] = [
            "folderIds": folderIds.joined(separator: ","),
            "fileIds": fileIds.joined(separator: ","),
            "status": 0,
        ]
        _ = try await exec("POST", url, jsonBody: body)
    }

    // ---------- 下载（文档 §4.1） ----------

    /// 获取下载地址：302 Location 或 JSON url / data.url；expectedSize 未知（0，交给下载引擎探测）
    func getDownloadLink(
        appToken: String,
        uuid: String,
        fileId: String,
        userId: String
    ) async throws -> DownloadLink {
        let ts = currentMillis()
        let encTs = aesHex(String(ts))
        // 参考实现（wenxi ilanzou.dart）：downloadId = encrypt('<fileId>|<userId>')，auth = encrypt('<fileId>|<毫秒时间戳>')
        let params: [(String, String)] = [
            ("enable", "1"),
            ("downloadId", aesHex("\(fileId)|\(userId)")),
            ("auth", aesHex("\(fileId)|\(ts)")),
            ("timestamp", encTs),
        ]
        // 该接口不带 extra=2，且 timestamp 与 auth 使用同一 ts
        let url = buildUrl(
            ILanzouConstants.FILE_REDIRECT, uuid: uuid, appToken: appToken,
            extra: false, params: params, timestamp: encTs
        )
        let response = try await performNoRedirect(url)
        if (300...399).contains(response.statusCode), let location = response.header("Location"), !location.isEmpty {
            // Location 可能是相对路径，按 API 基址解析为绝对地址后返回
            let resolved = resolveURL(location, against: ILanzouConstants.API_BASE)
            return DownloadLink(fid: ILanzouConstants.FILE_PREFIX + fileId, filename: "", downloadUrl: resolved, size: 0)
        }
        guard let json = JSONValue.parse(response.body) else {
            throw ApiError("蓝奏优享未返回下载地址")
        }
        try checkCode(json)
        let link = firstNonBlank(json.string("url"), json.object("data").string("url"))
        if link.isEmpty { throw ApiError("蓝奏优享未返回下载地址，请检查文件权限") }
        return DownloadLink(fid: ILanzouConstants.FILE_PREFIX + fileId, filename: "", downloadUrl: link, size: 0)
    }

    // ---------- 分享（本站分享页协议：/unproved/share/list） ----------

    /// 分享文件列表（匿名可用）。`folderId` 为空时返回分享根条目；传入数字目录 id 时返回该目录内容。自动翻页（页大小 60）。
    func shareList(shareId: String, folderId: String?, uuid: String) async throws -> [ShareFile] {
        var all: [ShareFile] = []
        var seen = Set<String>()
        var page = 1
        while page <= 1000 {
            var params: [(String, String)] = []
            if let folderId = folderId, !folderId.isEmpty { params.append(("folderId", folderId)) }
            params.append(("offset", String(page)))
            params.append(("limit", String(ILanzouConstants.PAGE_SIZE)))
            let url = shareUrl(ILanzouConstants.SHARE_LIST, uuid: uuid, shareId: shareId, params: params)
            let json = try await execShare(url)
            let list = json.array("list")
            if list.isEmpty { break }
            var added = 0
            for item in list {
                if let file = parseItem(item), seen.insert(file.fid).inserted {
                    all.append(file)
                    added += 1
                }
            }
            if added == 0 { break }
            let totalPage = lanzouOptInt(json, "totalPage", 0)
            if totalPage > 0 && page >= totalPage { break }
            if totalPage <= 0 && list.count < ILanzouConstants.PAGE_SIZE { break }
            page += 1
        }
        return all
    }

    /// 分享文件下载取链（匿名可用）：/unproved/file/redirect 返回 302 Location 或 JSON url。
    /// downloadId = AES('<fileId>|<userId>')、auth = AES('<fileId>|<ts>')（userId 未登录为空串）。
    func shareDownload(shareId: String, fileId: String, userId: String, uuid: String) async throws -> DownloadLink {
        let ts = currentMillis()
        let params: [(String, String)] = [
            ("downloadId", aesHex("\(fileId)|\(userId)")),
            ("enable", "1"),
            ("devType", ILanzouConstants.DEV_TYPE),
            ("uuid", uuid),
            ("timestamp", aesHex(String(ts))),
            ("auth", aesHex("\(fileId)|\(ts)")),
            ("shareId", shareId),
        ]
        let query = params.map { "\($0.0)=\(encodeToken($0.1))" }.joined(separator: "&")
        let url = ILanzouConstants.SHARE_REDIRECT + "?" + query
        let response = try await performNoRedirect(url)
        if (300...399).contains(response.statusCode), let location = response.header("Location"), !location.isEmpty {
            let resolved = resolveURL(location, against: ILanzouConstants.SHARE_API_BASE)
            return DownloadLink(fid: ILanzouConstants.FILE_PREFIX + fileId, filename: "", downloadUrl: resolved, size: 0)
        }
        guard let json = JSONValue.parse(response.body) else {
            throw ApiError("蓝奏优享未返回下载地址")
        }
        let link = firstNonBlank(json.string("url"), json.object("data").string("url"))
        if link.isEmpty {
            throw ApiError(firstNonBlank(json.string("msg"), "蓝奏优享未返回下载地址，请检查文件权限"))
        }
        return DownloadLink(fid: ILanzouConstants.FILE_PREFIX + fileId, filename: "", downloadUrl: link, size: 0)
    }

    /// 分享转存（需登录）：返回 transferKey（可能为空，表示同步完成）
    func transferShare(
        appToken: String,
        uuid: String,
        shareId: String,
        fileIds: [String],
        folderIds: [String],
        targetFolderId: String
    ) async throws -> String {
        let url = buildUrl(ILanzouConstants.FILE_TRANSFER, uuid: uuid, appToken: appToken, extra: true, params: [])
        let body: [String: Any] = [
            "targetFileId": fileIds.joined(separator: ","),
            "targetFolderId": folderIds.joined(separator: ","),
            "folderId": ifBlank(targetFolderId, ILanzouConstants.ROOT_FOLDER_ID),
            "shareId": shareId,
        ]
        let json = try await exec("POST", url, jsonBody: body)
        return firstNonBlank(
            json.object("data").string("transferKey"),
            json.object("map").string("transferKey"),
            json.string("transferKey"),
            json.string("data")
        )
    }

    /// 分享转存进度：map.num == 1 表示完成
    func transferCount(appToken: String, uuid: String, transferKey: String) async throws -> Int {
        let url = buildUrl(
            ILanzouConstants.FILE_TRANSFER_NUM, uuid: uuid, appToken: appToken,
            extra: true, params: [("transferKey", transferKey)]
        )
        let json = try await exec("GET", url)
        return lanzouOptInt(json.object("map"), "num", 0)
    }

    // ---------- 内部 ----------

    /// 解析列表项：fileType == 2 为文件夹
    private func parseItem(_ item: JSONValue) -> ShareFile? {
        let fileType = lanzouOptInt(item, "fileType", 0)
        if fileType == 2 {
            let fid = firstNonBlank(item.string("folderId"), String(lanzouOptInt(item, "folderId", 0)))
            if fid.isEmpty || fid == "0" { return nil }
            return ShareFile(
                fid: ILanzouConstants.FOLDER_PREFIX + fid,
                fname: item.string("folderName"),
                fsize: 0,
                isdir: true,
                pdirFid: "",
                fidToken: "",
                modifyTime: firstNonBlank(item.string("updTime"), item.string("addTime"))
            )
        } else {
            let fid = firstNonBlank(item.string("fileId"), String(lanzouOptInt(item, "fileId", 0)))
            if fid.isEmpty || fid == "0" { return nil }
            return ShareFile(
                fid: ILanzouConstants.FILE_PREFIX + fid,
                fname: item.string("fileName"),
                fsize: item.long("fileSize") * 1024,
                isdir: false,
                pdirFid: "",
                fidToken: "",
                modifyTime: firstNonBlank(item.string("updTime"), item.string("addTime"))
            )
        }
    }

    /// 组装个人盘接口 URL（带 appToken）
    private func buildUrl(
        _ path: String,
        uuid: String,
        appToken: String?,
        extra: Bool,
        params: [(String, String)],
        timestamp: String? = nil
    ) -> String {
        let ts = timestamp ?? aesHex(String(currentMillis()))
        var parts: [(String, String)] = []
        parts.append(("uuid", uuid))
        parts.append(("devType", ILanzouConstants.DEV_TYPE))
        parts.append(("devCode", uuid))
        parts.append(("devModel", ILanzouConstants.DEV_MODEL))
        parts.append(("devVersion", ILanzouConstants.DEV_VERSION))
        parts.append(("appVersion", ""))
        parts.append(("timestamp", ts))
        if let appToken = appToken, !appToken.isEmpty { parts.append(("appToken", appToken)) }
        if extra { parts.append(("extra", "2")) }
        parts.append(contentsOf: params)
        let query = parts.map { "\($0.0)=\(encodeToken($0.1))" }.joined(separator: "&")
        return "\(path)?\(query)"
    }

    /// appToken 特殊编码：标准 query 编码后把 %3A 还原为字面冒号
    private func encodeToken(_ value: String) -> String {
        return urlEncode(value).replacingOccurrences(of: "%3A", with: ":")
    }

    private func commonHeaders(json: Bool) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": ILanzouConstants.WEB_UA,
            "Origin": ILanzouConstants.WEB_SITE,
            "Referer": ILanzouConstants.DOWNLOAD_REFERER,
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            // 该站 CDN/WAF（ESA + acw_tc）会对浏览器式请求放行、对“裸”HTTP 客户端返回空列表，
            // 故补全 Chrome 客户端提示头（与网页端一致），否则 share/list 恒为空。
            "sec-ch-ua": "\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": "\"Windows\"",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-site",
        ]
        if json { headers["Content-Type"] = "application/json; charset=utf-8" }
        return headers
    }

    /// 分享专用 URL 组装：公共参数 + shareId + 业务参数（不带 appToken）
    private func shareUrl(
        _ path: String,
        uuid: String,
        shareId: String,
        params: [(String, String)]
    ) -> String {
        var parts: [(String, String)] = []
        parts.append(("uuid", uuid))
        parts.append(("devType", ILanzouConstants.DEV_TYPE))
        parts.append(("devCode", uuid))
        parts.append(("devModel", ILanzouConstants.SHARE_DEV_MODEL))
        parts.append(("devVersion", ILanzouConstants.DEV_VERSION))
        parts.append(("appVersion", ""))
        parts.append(("timestamp", aesHex(String(currentMillis()))))
        parts.append(("extra", "2"))
        parts.append(("shareId", shareId))
        parts.append(contentsOf: params)
        let query = parts.map { "\($0.0)=\(encodeToken($0.1))" }.joined(separator: "&")
        return "\(path)?\(query)"
    }

    /// 分享接口执行：非 200 时用服务端 msg（如「分享id不能为空」「参数缺失」），不当成登录失效
    private func execShare(_ url: String) async throws -> JSONValue {
        let response = try await HTTPClient.api.get(url, headers: commonHeaders(json: false))
        guard let json = JSONValue.parse(response.body) else {
            throw ApiError("蓝奏优享分享请求失败（\(response.statusCode)）")
        }
        let code = lanzouOptInt(json, "code", -1)
        if code != 200 {
            throw ApiError(firstNonBlank(json.string("msg"), "蓝奏优享分享请求失败（\(code)）"))
        }
        return json
    }

    /// 执行请求并校验业务码；409 + text/html 访问验证自动重试一次
    @discardableResult
    private func exec(_ method: String, _ url: String, jsonBody: [String: Any]? = nil) async throws -> JSONValue {
        do {
            return try await perform(kind: .normal, method: method, url: url, jsonBody: jsonBody)
        } catch is ILanzouAccessChallenge {
            // 访问验证：按文档「设置 Cookie 后最多重放一次」；无 JS 计算 acw_sc__v2，二次仍失败即提示
            do {
                return try await perform(kind: .normal, method: method, url: url, jsonBody: jsonBody)
            } catch is ILanzouAccessChallenge {
                throw ApiError("蓝奏优享的访问验证未通过，请稍后重试或使用网页登录")
            }
        }
    }

    /// 登录专用执行：登录失败（如「用户账号不存在」「密码错误」）应原样透出服务端 msg，故单独处理；仍保留 409 重试
    private func execLogin(_ url: String, jsonBody: [String: Any]) async throws -> JSONValue {
        do {
            return try await perform(kind: .login, method: "POST", url: url, jsonBody: jsonBody)
        } catch is ILanzouAccessChallenge {
            do {
                return try await perform(kind: .login, method: "POST", url: url, jsonBody: jsonBody)
            } catch is ILanzouAccessChallenge {
                throw ApiError("蓝奏优享的访问验证未通过，请稍后重试")
            }
        }
    }

    private func perform(
        kind: ILanzouRequestKind,
        method: String,
        url: String,
        jsonBody: [String: Any]?
    ) async throws -> JSONValue {
        let response: HTTPResponse
        if method == "POST" {
            response = try await HTTPClient.api.postJSON(url, headers: commonHeaders(json: true), body: jsonBody ?? [:])
        } else {
            response = try await HTTPClient.api.get(url, headers: commonHeaders(json: false))
        }
        return try interpret(response, kind: kind)
    }

    /// 统一解释响应：登录态与普通态对 HTTP 状态码 / 业务码的处理不同
    private func interpret(_ response: HTTPResponse, kind: ILanzouRequestKind) throws -> JSONValue {
        let contentType = response.header("Content-Type") ?? ""
        if !response.isSuccessful {
            if kind == .normal, response.statusCode == 401 || response.statusCode == 403 {
                throw ApiError("蓝奏优享登录已过期，请重新登录")
            }
            if response.statusCode == 409 && contentType.contains("text/html") {
                throw ILanzouAccessChallenge()
            }
            if kind == .login {
                throw ApiError("蓝奏优享请求失败（\(response.statusCode)）")
            }
            throw ApiError("蓝奏优享请求失败（\(response.statusCode)），请检查登录信息或稍后重试")
        }
        guard let json = JSONValue.parse(response.body) else {
            if contentType.contains("text/html") { throw ILanzouAccessChallenge() }
            if kind == .login {
                throw ApiError("蓝奏优享请求失败（\(response.statusCode)）")
            }
            throw ApiError("蓝奏优享请求失败（\(response.statusCode)），请检查登录信息或稍后重试")
        }
        if kind == .login {
            if lanzouOptInt(json, "code", -1) != 200 {
                throw ApiError(firstNonBlank(json.string("msg"), "蓝奏优享登录失败，请检查账号密码"))
            }
            return json
        }
        try checkCode(json)
        return json
    }

    private func checkCode(_ json: JSONValue) throws {
        let code = lanzouOptInt(json, "code", -1)
        if code == 200 { return }
        if code == -1 || code == -2 { throw ApiError("蓝奏优享登录已过期，请重新登录") }
        throw ApiError("蓝奏优享请求失败（\(code)），请检查登录信息或稍后重试")
    }

    /// 不跟随重定向执行 GET，便于读取 302 Location
    private func performNoRedirect(_ url: String) async throws -> HTTPResponse {
        let request = try HTTPClient.api.makeRequest(url, method: "GET", headers: commonHeaders(json: false))
        let (data, response) = try await noRedirectSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiError("蓝奏优享响应异常")
        }
        var headers: [String: [String]] = [:]
        for (key, value) in http.allHeaderFields {
            headers["\(key)".lowercased(), default: []].append("\(value)")
        }
        return HTTPResponse(statusCode: http.statusCode, body: data, headers: headers)
    }

    private func aesHex(_ plain: String) -> String {
        return ILanzouAES.encryptECBHex(key: ILanzouConstants.AES_KEY, plaintext: plain)
    }

    private func firstNonBlank(_ values: String...) -> String {
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private func ifBlank(_ value: String, _ fallback: String) -> String {
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
    }

    /// 整串匹配（等价 Kotlin Regex.matches）
    private func isFullMatch(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return false }
        return match.range == range
    }

    /// 相对 Location 按基址解析为绝对地址（对应 java.net.URI(base).resolve(location)）
    private func resolveURL(_ location: String, against base: String) -> String {
        if let baseURL = URL(string: base), let resolved = URL(string: location, relativeTo: baseURL) {
            return resolved.absoluteString
        }
        return location
    }

    private func currentMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - ILanzouResolveRepository

/// 蓝奏云优享版分享解析仓库。
///
/// 平台差异：
/// - 目录：/unproved/share/list（匿名可用）——根目录不传 folderId，子目录传数字 id；
/// - 取链：/unproved/file/redirect（匿名可用，302 Location）；
/// - 转存：/proved/file/transfer（需登录 appToken）。
final class ILanzouResolveRepository: ShareResolveRepository {

    private let api: ILanzouApi
    private let accountProvider: ILanzouAccountProviding

    private let stateLock = NSLock()
    private var cachedUuid: String?

    init(accountProvider: ILanzouAccountProviding = GuestILanzouAccountProvider()) {
        self.api = ILanzouApi()
        self.accountProvider = accountProvider
    }

    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        guard let parsed = ShareLinkParser.parse(link), !parsed.shareId.isEmpty else {
            throw ApiError("无法识别蓝奏云优享版分享链接")
        }
        return ShareSession(shareId: parsed.shareId, stoken: parsed.shareId, title: "蓝奏云优享版分享")
    }

    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        let id = try await uuid()
        return try await api.shareList(shareId: session.stoken, folderId: folderIdOf(dirFid), uuid: id)
    }

    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        if file.isdir { throw ApiError("文件夹无法直接下载") }
        let fileId = removingPrefix(file.fid, ILanzouConstants.FILE_PREFIX)
        // downloadId = AES('<fileId>|<userId>')：未登录传空串，登录则用当前账号 userId
        let account = await accountProvider.currentAccount()
        let userId = account?.userId ?? ""
        let id = try await uuid()
        return try await api.shareDownload(shareId: session.stoken, fileId: fileId, userId: userId, uuid: id)
    }

    func getGuestShareDownloadLink(session: ShareSession, file: ShareFile) async throws -> DownloadLink {
        if file.isdir { throw ApiError("文件夹无法直接下载") }
        let fileId = removingPrefix(file.fid, ILanzouConstants.FILE_PREFIX)
        let id = try await uuid()
        return try await api.shareDownload(shareId: session.stoken, fileId: fileId, userId: "", uuid: id)
    }

    func transferFile(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        let account = await accountProvider.currentAccount()
        let accountToken = (account?.appToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let appToken = cookie.isEmpty ? accountToken : cookie
        if appToken.isEmpty { throw ApiError("请先登录蓝奏云优享版") }

        let target = toDirFid.isEmpty ? ILanzouConstants.ROOT_FOLDER_ID : toDirFid
        let fileIds = file.isdir ? [] : [removingPrefix(file.fid, ILanzouConstants.FILE_PREFIX)]
        let folderIds = file.isdir ? [removingPrefix(file.fid, ILanzouConstants.FOLDER_PREFIX)] : []
        let key = try await api.transferShare(
            appToken: appToken, uuid: uuid(), shareId: session.stoken,
            fileIds: fileIds, folderIds: folderIds, targetFolderId: target
        )
        if !key.isEmpty {
            var done = false
            for _ in 0..<30 {
                if done { continue }
                try? await Task.sleep(nanoseconds: 500_000_000) // delay(500)
                let count = (try? await api.transferCount(appToken: appToken, uuid: uuid(), transferKey: key)) ?? 0
                if count == 1 { done = true }
            }
            if !done { throw ApiError("蓝奏优享仍在处理转存，请稍后刷新列表") }
        }
        return target
    }

    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        throw ApiError("蓝奏优享分享请使用 getShareDownloadLink")
    }

    func ensureTempDir(cookie: String) async throws -> String {
        throw ApiError("蓝奏优享分享无需临时目录")
    }

    // MARK: - 私有

    private func folderIdOf(_ dirFid: String) -> String? {
        if dirFid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if dirFid.hasPrefix(ILanzouConstants.FOLDER_PREFIX) {
            let value = removingPrefix(dirFid, ILanzouConstants.FOLDER_PREFIX)
            return value.isEmpty ? nil : value
        }
        if dirFid == ILanzouConstants.ROOT_FOLDER_ID { return nil }
        return dirFid
    }

    private func removingPrefix(_ value: String, _ prefix: String) -> String {
        return value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
    }

    private func uuid() async throws -> String {
        stateLock.lock()
        let cached = cachedUuid
        stateLock.unlock()
        if let cached = cached { return cached }

        let account = await accountProvider.currentAccount()
        let existing = account?.uuid ?? ""
        let value: String
        if isValidUuid(existing) {
            value = existing
        } else {
            value = try await api.getUuid()
        }
        stateLock.lock()
        cachedUuid = value
        stateLock.unlock()
        return value
    }

    private func isValidUuid(_ uuid: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^[A-Za-z0-9_-]{8,128}$") else { return false }
        let range = NSRange(uuid.startIndex..<uuid.endIndex, in: uuid)
        guard let match = regex.firstMatch(in: uuid, options: [], range: range) else { return false }
        return match.range == range
    }
}

// MARK: - 工具

/// optInt(key, default)：仅当键存在且可转为数值时取值，否则返回默认值（对应 JSONObject.optInt）
private func lanzouOptInt(_ json: JSONValue, _ key: String, _ defaultValue: Int) -> Int {
    guard let dict = json.raw as? [String: Any], let value = dict[key], !(value is NSNull) else {
        return defaultValue
    }
    if let number = value as? NSNumber { return number.intValue }
    if let text = value as? String, let parsed = Int(text) { return parsed }
    return defaultValue
}
