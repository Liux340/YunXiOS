/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：蓝奏云网络接口层 + 分享解析仓库。
 * 对应 Android 侧：
 *   - data/network/LanzouConstants.kt
 *   - data/network/LanzouApi.kt
 *   - data/repository/LanzouResolveRepository.kt
 *
 * 蓝奏云是 HTML 页面解析型平台：分享页 HTML → 同源 iframe 下载页 → ajaxm/ajaxfile
 * 取下载参数 → HEAD 探测直链。所有正则基于 NSRegularExpression（不使用 Swift Regex 字面量）。
 */

import Foundation

// MARK: - 正则辅助

/// 蓝奏解析辅助：RegexUtil 只提供「单分组首次匹配」，这里补充多分组与全量匹配。
private enum LanzouRegex {

    /// 首次匹配并返回全部捕获组（下标 0 为整体匹配）。无匹配返回 nil。
    static func groups(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: text) else { return "" }
            return String(text[r])
        }
    }

    /// 全量匹配，返回指定捕获组（默认第 1 组）的列表。
    static func all(
        _ pattern: String,
        in text: String,
        group: Int = 1,
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.matches(in: text, options: [], range: range).compactMap { m in
            guard group < m.numberOfRanges, let r = Range(m.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    /// 整体是否匹配（正则须带 ^ $ 锚点）。
    static func fullMatch(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range) else { return false }
        return m.range == range
    }
}

// MARK: - 常量（对应 LanzouConstants.kt）

/// 蓝奏云常量（文档 §1）。
enum LanzouConstants {

    /// 浏览器 UA，所有网页请求携带
    static let WEB_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/131.0.0.0 Safari/537.36"

    /// 个人盘登录入口（文档 §1.2）
    static let MYDISK_URL = "https://pc.woozooo.com/mydisk.php"
    static let MYDISK_FILES_URL = "https://pc.woozooo.com/mydisk.php?item=files&action=index"
    static let DOUPLOAD_URL = "https://pc.woozooo.com/doupload.php"
    static let ORIGIN = "https://pc.woozooo.com"

    /// 原生账号密码登录（官网 accounts.woozooo.com）
    static let ACCOUNTS_URL = "https://accounts.woozooo.com/accounts.php"
    static let ACCOUNTS_ORIGIN = "https://accounts.woozooo.com"
    static let LOGIN_REF = "pc.woozooo.com"

    /// 个人盘根目录 folder_id
    static let ROOT_FOLDER_ID = "-1"

    /// 分页上限（文档 §B3/§B4）
    static let MAX_FILE_PAGES = 1000
    static let MAX_FOLDER_PAGES = 500

    /// 下载节点注入的 Cookie
    static let DOWN_IP_COOKIE = "down_ip=1"

    /// 文件夹 id 前缀 d: / 文件 id 前缀 f:
    static let FOLDER_PREFIX = "d:"
    static let FILE_PREFIX = "f:"

    /// 域名族：lanzou*、lan[zs]o[ux]，后缀 com/net/org/cn
    private static let HOST_PATTERN =
        #"^(?:[a-z0-9-]+\.)*(?:lanzou[a-z]?|lan[zs]o[ux])\.(?:com|net|org|cn)$"#

    static func isLanzouHost(_ host: String) -> Bool {
        LanzouRegex.fullMatch(HOST_PATTERN, in: host)
    }

    /// 将分享链接规范为 https、去掉 fragment、去掉多余尾部斜杠
    static func normalizeShareUrl(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let re = try? NSRegularExpression(pattern: "^http://", options: [.caseInsensitive]) {
            let range = NSRange(u.startIndex..<u.endIndex, in: u)
            u = re.stringByReplacingMatches(in: u, options: [], range: range, withTemplate: "https://")
        }
        if let hash = u.firstIndex(of: "#") {
            u = String(u[u.startIndex..<hash])
        }
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }
}

// MARK: - 数据模型

/// 个人盘登录态参数（文档 §B1）。
struct LanzouLoginParams {
    let uid: String
    let vei: String
}

/// 文件夹分页参数（文档 §A7）。
struct LanzouFolderParams {
    let lx: String
    let fid: String
    let t: String
    let k: String
}

/// 分享页解析结果。
struct LanzouSharePage {
    let shareUrl: String
    let baseUrl: String
    let title: String
    let isFolder: Bool
    let needsPwd: Bool
    let iframeUrl: String?
    let fileId: String?
    let folderParams: LanzouFolderParams?
    let html: String
    let singleFile: ShareFile?
}

// MARK: - Cookie 罐

/// 按域 Cookie 罐（对应 Kotlin 的 ConcurrentHashMap<String, MutableMap<String,String>>）。
private final class LanzouCookieJar {

    private var store: [String: [String: String]] = [:]
    private let lock = NSLock()

    func set(host: String, name: String, value: String) {
        guard !host.isEmpty, !name.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        store[host, default: [:]][name] = value
    }

    /// 按域拼 `k=v; k2=v2`
    func header(host: String) -> String {
        lock.lock(); defer { lock.unlock() }
        guard let map = store[host] else { return "" }
        return map.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    func all(host: String) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return store[host] ?? [:]
    }

    /// 吸收响应下发的 Set-Cookie（取每段首部的 name=value）
    func absorb(setCookies: [String], host: String) {
        guard !host.isEmpty else { return }
        for sc in setCookies {
            let first = sc.firstIndex(of: ";").map { String(sc[sc.startIndex..<$0]) } ?? sc
            let kv = first.trimmingCharacters(in: .whitespaces)
            guard let eq = kv.firstIndex(of: "="), eq != kv.startIndex else { continue }
            let name = String(kv[kv.startIndex..<eq])
            let value = String(kv[kv.index(after: eq)...])
            set(host: host, name: name, value: value)
        }
    }
}

// MARK: - URLSession 委托

/// 自定义 URLSession 委托：
/// - stopRedirect=true 时禁止自动跟随 3xx（用于逐跳检查 Location / 下载直链探测）；
/// - 携带 jar 时把每一跳响应的 Set-Cookie 写入 Cookie 罐（登录流程用）。
private final class LanzouSessionDelegate: NSObject, URLSessionTaskDelegate {

    private let stopRedirect: Bool
    private let jar: LanzouCookieJar?

    init(stopRedirect: Bool, jar: LanzouCookieJar? = nil) {
        self.stopRedirect = stopRedirect
        self.jar = jar
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let jar = jar, let host = response.url?.host {
            var setCookies: [String] = []
            for (key, value) in response.allHeaderFields where "\(key)".lowercased() == "set-cookie" {
                setCookies.append("\(value)")
            }
            jar.absorb(setCookies: setCookies, host: host)
        }
        completionHandler(stopRedirect ? nil : request)
    }
}

// MARK: - 蓝奏云 API（对应 LanzouApi.kt）

/// 蓝奏云 API 封装（文档 §3/§4）：
/// - 匿名分享：分享页 HTML → 同源 iframe → ajaxm/ajaxfile 取参数 → HEAD 探测直链 → 验证并下载；
/// - 个人盘：Cookie（ylogin + phpdisk_info）→ mydisk.php 取 uid/vei → doupload.php 系列 task。
final class LanzouApi {

    /// 共享 Cookie 罐（仅存放本地计算/注入的 down_ip、acw_sc__v2）
    private let cookieJar = LanzouCookieJar()

    /// 跟随重定向的会话（对应 Kotlin 默认 client）
    private lazy var followSession: URLSession = LanzouApi.makeSession(stopRedirect: false, jar: nil)

    /// 不跟随重定向的会话（对应 Kotlin noRedirect）
    private lazy var noRedirectSession: URLSession = LanzouApi.makeSession(stopRedirect: true, jar: nil)

    private static func makeSession(stopRedirect: Bool, jar: LanzouCookieJar?) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        let delegate = LanzouSessionDelegate(stopRedirect: stopRedirect, jar: jar)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: 请求构造与执行

    /// 构造请求（复用 HTTPClient 的 URL/代理处理）。
    private func buildRequest(
        _ url: String,
        method: String,
        headers: [String: String],
        form: [(String, String)]?
    ) throws -> URLRequest {
        var request = try HTTPClient.api.makeRequest(url, method: method, headers: headers)
        if let form = form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = form
                .map { "\(HTTPClient.formEncode($0.0))=\(HTTPClient.formEncode($0.1))" }
                .joined(separator: "&")
                .data(using: .utf8)
        }
        return request
    }

    /// 执行请求、归一化响应头，并按需把 Set-Cookie 写入 Cookie 罐。
    private func perform(
        _ request: URLRequest,
        session: URLSession,
        jar: LanzouCookieJar? = nil
    ) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiError("蓝奏响应异常")
        }
        var headers: [String: [String]] = [:]
        for (key, value) in http.allHeaderFields {
            headers["\(key)".lowercased(), default: []].append("\(value)")
        }
        let resp = HTTPResponse(statusCode: http.statusCode, body: data, headers: headers)
        if let jar = jar, let host = http.url?.host {
            jar.absorb(setCookies: resp.setCookies, host: host)
        }
        return resp
    }

    @discardableResult
    private func sendFollow(
        _ url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        form: [(String, String)]? = nil
    ) async throws -> HTTPResponse {
        let request = try buildRequest(url, method: method, headers: headers, form: form)
        return try await perform(request, session: followSession)
    }

    @discardableResult
    private func sendNoRedirect(
        _ url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        form: [(String, String)]? = nil
    ) async throws -> HTTPResponse {
        let request = try buildRequest(url, method: method, headers: headers, form: form)
        return try await perform(request, session: noRedirectSession)
    }

    private func delay(_ ms: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    // MARK: Cookie 辅助

    private func hostOf(_ url: String) -> String {
        URL(string: url)?.host ?? ""
    }

    private func setCookie(host: String, name: String, value: String) {
        cookieJar.set(host: host, name: name, value: value)
    }

    private func cookieHeader(_ host: String) -> String {
        cookieJar.header(host: host)
    }

    /// 合并按域 Cookie 罐与调用方追加的 Cookie 串（如 down_ip=1）。
    private func mergedCookie(host: String, extra: String?) -> String {
        var parts: [String] = []
        let base = cookieHeader(host)
        if !base.isEmpty { parts.append(base) }
        if let extra = extra, !extra.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(extra)
        }
        return parts.joined(separator: "; ")
    }

    // MARK: 个人盘（文档 §4）

    /// B1：从 mydisk.php 提取 uid / vei。
    func fetchLoginParams(cookie: String) async throws -> LanzouLoginParams? {
        let headers: [String: String] = [
            "Cookie": cookie,
            "User-Agent": LanzouConstants.WEB_UA,
            "Referer": LanzouConstants.MYDISK_URL,
            "Origin": LanzouConstants.ORIGIN,
        ]
        let resp = try await sendFollow(LanzouConstants.MYDISK_FILES_URL, headers: headers)
        if !resp.isSuccessful { throw ApiError("蓝奏登录态无效，请重新登录") }
        let html = resp.text
        // 文件页里形如：url:'/doupload.php?uid=4133097', data:{ 'vei':'B1UHVFBWVQgFB1JWAFo=' }
        let uid = (RegexUtil.firstGroup(#"uid['"]?\s*[=:]\s*['"]?(\d{1,20})"#, in: html) ?? "")
            .trimmingCharacters(in: .whitespaces)
        let vei = (RegexUtil.firstGroup(#"vei['"]?\s*[=:]\s*['"]?([A-Za-z0-9_\-+/=]{1,256})"#, in: html) ?? "")
            .trimmingCharacters(in: .whitespaces)
        if uid.isEmpty || vei.isEmpty {
            throw ApiError("蓝奏登录态无效，请重新登录")
        }
        return LanzouLoginParams(uid: uid, vei: vei)
    }

    /// 原生账号密码登录（官网 accounts.woozooo.com）：
    /// 1) POST /accounts.php（task=uselogin / username / password / ref），遇人机校验页重试（最多 4 次）；
    /// 2) 成功响应 `{zt:'1', msgs:<中转鉴权 URL>}` → GET msgs 下发登录 Cookie；
    /// 3) 返回 `ylogin=..; phpdisk_info=..` 汇总之 Cookie 串。
    func login(account: String, password: String) async throws -> String {
        let name = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || password.isEmpty {
            throw ApiError("请输入蓝奏云账号和密码")
        }
        let jar = LanzouCookieJar()
        let session = LanzouApi.makeSession(stopRedirect: false, jar: jar)
        defer { session.invalidateAndCancel() }

        let baseHeaders: [String: String] = [
            "User-Agent": LanzouConstants.WEB_UA,
            "Origin": LanzouConstants.ACCOUNTS_ORIGIN,
            "Referer": "\(LanzouConstants.ACCOUNTS_ORIGIN)/accounts.php?action=login&ref=\(LanzouConstants.LOGIN_REF)",
            "X-Requested-With": "XMLHttpRequest",
            "Accept": "application/json, text/javascript, */*; q=0.01",
        ]

        // 按请求 URL 的 host 注入对应域的 Cookie（对应 OkHttp CookieJar.loadForRequest）
        func withJarCookies(_ url: String, _ headers: [String: String]) -> [String: String] {
            var h = headers
            if let host = URL(string: url)?.host {
                let c = jar.header(host: host)
                if !c.isEmpty { h["Cookie"] = c }
            }
            return h
        }

        func postLogin() async throws -> String {
            let headers = withJarCookies(LanzouConstants.ACCOUNTS_URL, baseHeaders)
            let request = try buildRequest(
                LanzouConstants.ACCOUNTS_URL,
                method: "POST",
                headers: headers,
                form: [
                    ("task", "uselogin"),
                    ("username", name),
                    ("password", password),
                    ("ref", LanzouConstants.LOGIN_REF),
                ]
            )
            return try await perform(request, session: session, jar: jar).text
        }

        var body = try await postLogin()
        var attempt = 0
        while attempt < 4 && body.contains("arg1=") && !body.contains("\"zt\"") {
            guard let arg1 = RegexUtil.firstGroup(#"arg1\s*=\s*'([0-9A-Fa-f]{40})'"#, in: body) else { break }
            jar.set(host: "accounts.woozooo.com", name: "acw_sc__v2", value: acwScV2(arg1))
            body = try await postLogin()
            attempt += 1
        }

        guard let json = JSONValue.parse(body) else {
            throw ApiError("蓝奏云登录失败，请稍后重试")
        }
        if json.string("zt") != "1" {
            let msgs = json.string("msgs")
            throw ApiError(msgs.isEmpty ? "蓝奏云登录失败，请检查账号密码" : msgs)
        }
        let msgs = json.string("msgs")
        if !msgs.isEmpty {
            // 1) 访问中转鉴权 URL（跟随跳转、下发登录 Cookie），失败忽略
            if let request = try? buildRequest(
                msgs,
                method: "GET",
                headers: withJarCookies(msgs, [
                    "User-Agent": LanzouConstants.WEB_UA,
                    "Referer": "\(LanzouConstants.ACCOUNTS_ORIGIN)/",
                ]),
                form: nil
            ) {
                _ = try? await perform(request, session: session, jar: jar)
            }
            // 2) 再访问一次文件页：获取/固定 PHPSESSID（vei 与该会话绑定）
            if let request = try? buildRequest(
                LanzouConstants.MYDISK_FILES_URL,
                method: "GET",
                headers: withJarCookies(LanzouConstants.MYDISK_FILES_URL, [
                    "User-Agent": LanzouConstants.WEB_UA,
                    "Referer": LanzouConstants.MYDISK_URL,
                ]),
                form: nil
            ) {
                _ = try? await perform(request, session: session, jar: jar)
            }
        }
        // 汇总 pc.woozooo.com 域下全部 Cookie（含 PHPSESSID）
        let pc = jar.all(host: "pc.woozooo.com")
        let cookie = pc.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        if !cookie.contains("ylogin") || !cookie.contains("phpdisk_info") {
            throw ApiError("蓝奏云登录未获取到有效凭据，请重试")
        }
        return cookie
    }

    /// 计算 JS 人机校验 Cookie `acw_sc__v2`（固定公开变换，仅字符串运算、不执行页面脚本）。
    private func acwScV2(_ arg1: String) -> String {
        let pos = [15, 35, 29, 24, 33, 16, 1, 38, 10, 9, 19, 31, 40, 27, 22, 23, 25, 13, 6, 11,
                   39, 18, 20, 8, 14, 21, 32, 26, 2, 30, 7, 4, 17, 5, 3, 28, 34, 37, 12, 36]
        let mask = Array("3000176000856006061501533003690027800375")
        let chars = Array(arg1)
        var q = Array(repeating: Character("\0"), count: pos.count)
        for x in chars.indices {
            for z in pos.indices {
                if pos[z] == x + 1 { q[z] = chars[x] }
            }
        }
        let u = Array(String(q))
        var out = ""
        var i = 0
        while i + 2 <= u.count && i + 2 <= mask.count {
            let a = Int(String(u[i...i + 1]), radix: 16) ?? 0
            let b = Int(String(mask[i...i + 1]), radix: 16) ?? 0
            out += String(format: "%02x", a ^ b)
            i += 2
        }
        return out
    }

    /// 个人盘列目录：文件夹（task=47）+ 文件（task=5）合并。
    func listCloudFiles(cookie: String, uid: String, vei: String, folderId: String) async throws -> [ShareFile] {
        var result: [ShareFile] = []

        // 文件夹
        let folderJson = try await doupload(
            cookie: cookie, uid: uid, vei: vei,
            fields: [("task", "47"), ("folder_id", folderId)],
            allowEnd: true
        )
        for item in folderJson.array("text") {
            let id = firstNonBlank(item.string("fol_id"), item.string("id"))
            if id.isEmpty { continue }
            result.append(ShareFile(
                fid: LanzouConstants.FOLDER_PREFIX + id,
                fname: firstNonBlank(item.string("name"), item.string("name_all")),
                fsize: 0,
                isdir: true,
                pdirFid: folderId,
                fidToken: "",
                modifyTime: item.string("time")
            ))
        }

        // 文件
        var seen = Set<String>()
        var pg = 1
        while pg <= LanzouConstants.MAX_FILE_PAGES {
            let json = try await doupload(
                cookie: cookie, uid: uid, vei: vei,
                fields: [("task", "5"), ("folder_id", folderId), ("pg", "\(pg)")],
                allowEnd: true
            )
            let arr = json.array("text")
            if arr.isEmpty { break }
            var added = 0
            for item in arr {
                let id = item.string("id")
                if id.isEmpty || !seen.insert(id).inserted { continue }
                result.append(ShareFile(
                    fid: LanzouConstants.FILE_PREFIX + id,
                    fname: firstNonBlank(item.string("name_all"), item.string("name")),
                    fsize: parseDisplaySize(item.string("size")),
                    isdir: false,
                    pdirFid: folderId,
                    fidToken: "",
                    modifyTime: item.string("time")
                ))
                added += 1
            }
            if added == 0 { throw ApiError("蓝奏文件分页重复，请刷新后重试") }
            pg += 1
        }
        return result
    }

    /// B4：新建文件夹，返回新目录 id。
    func createFolder(cookie: String, uid: String, vei: String, parentId: String, name: String) async throws -> String {
        let json = try await doupload(
            cookie: cookie, uid: uid, vei: vei,
            fields: [
                ("task", "2"),
                ("parent_id", parentId),
                ("folder_name", name),
                ("folder_description", ""),
            ]
        )
        let text = json.string("text")
        if !LanzouRegex.fullMatch(#"^\d+$"#, in: text) {
            throw ApiError("蓝奏未返回新文件夹信息")
        }
        return text
    }

    /// B5：重命名文件夹。
    func renameFolder(cookie: String, uid: String, vei: String, folderId: String, newName: String) async throws {
        _ = try await doupload(
            cookie: cookie, uid: uid, vei: vei,
            fields: [
                ("task", "4"),
                ("folder_id", folderId),
                ("folder_name", newName),
                ("folder_description", ""),
            ]
        )
    }

    /// B6：重命名文件。
    func renameFile(cookie: String, uid: String, vei: String, fileId: String, newName: String) async throws {
        _ = try await doupload(
            cookie: cookie, uid: uid, vei: vei,
            fields: [("task", "46"), ("file_id", fileId), ("file_name", newName), ("type", "2")]
        )
    }

    /// B7：移动文件（逐个）。
    func moveFile(cookie: String, uid: String, vei: String, folderId: String, fileId: String) async throws {
        _ = try await doupload(
            cookie: cookie, uid: uid, vei: vei,
            fields: [("task", "20"), ("folder_id", folderId), ("file_id", fileId)]
        )
    }

    /// B8：删除文件夹。
    func deleteFolder(cookie: String, uid: String, vei: String, folderId: String) async throws {
        _ = try await doupload(cookie: cookie, uid: uid, vei: vei, fields: [("task", "3"), ("folder_id", folderId)])
    }

    /// B9：删除文件。
    func deleteFile(cookie: String, uid: String, vei: String, fileId: String) async throws {
        _ = try await doupload(cookie: cookie, uid: uid, vei: vei, fields: [("task", "6"), ("file_id", fileId)])
    }

    /// B10：获取文件分享链接。
    func createFileShare(cookie: String, uid: String, vei: String, fileId: String) async throws -> ShareInfo {
        let json = try await doupload(cookie: cookie, uid: uid, vei: vei, fields: [("task", "22"), ("file_id", fileId)])
        let info = json.object("info")
        guard !info.isNull else { throw ApiError("蓝奏未返回分享链接") }
        return buildShareInfo(info.string("f_id"), info.string("is_newd"), info.string("pwd"))
    }

    /// B11：获取文件夹分享链接。
    func createFolderShare(cookie: String, uid: String, vei: String, folderId: String) async throws -> ShareInfo {
        let json = try await doupload(cookie: cookie, uid: uid, vei: vei, fields: [("task", "18"), ("file_id", folderId)])
        let info = json.object("info")
        guard !info.isNull else { throw ApiError("蓝奏未返回分享链接") }
        return buildShareInfo(info.string("new_url"), info.string("is_newd"), info.string("pwd"))
    }

    // MARK: 匿名分享（文档 §3）

    /// A1/A2：获取分享页并解析（文件夹分享 / 文件分享）。
    func resolveShare(shareUrl: String, pwd: String?) async throws -> LanzouSharePage {
        let normalized = LanzouConstants.normalizeShareUrl(shareUrl)
        let html = try await fetchPageFollowingLanzou(normalized)
        guard let uri = URL(string: normalized), let scheme = uri.scheme, let host = uri.host else {
            throw ApiError("蓝奏分享链接无效")
        }
        let origin = "\(scheme)://\(host)"
        let title = extractTitle(html)
        let needsPwd = html.contains("请输入密码") || html.contains("id=\"pwbox\"") ||
            html.contains("input_password") || html.contains("密码不正确")
        let isFolder = html.contains("filemoreajax") || html.contains("class=\"filemore\"") ||
            html.contains("file_more")
        let iframeUrl = RegexUtil.firstGroup(#"<iframe[^>]+src=["']([^"']+)["']"#, in: html)
            .map { absolutize(origin, $0) }
        let fileId = RegexUtil.firstGroup(#"(?:ajaxm|ajaxfile)\.php\?file=(\d+)"#, in: html)
            ?? RegexUtil.firstGroup(#"name=["']file["']\s+value=["'](\d+)["']"#, in: html)
            ?? RegexUtil.firstGroup(#"file=(\d+)"#, in: html)
        var folderParams: LanzouFolderParams?
        if isFolder {
            let lx = jsVar(html, "lx")
            // fid 以页面 JS 变量为准，缺失则回退 URI 末段（非可选）
            let fid = jsVar(html, "fid") ?? substringAfterLastSlash(uri.path)
            let t = jsVar(html, "t")
            let k = jsVar(html, "k")
            if let lx = lx, let t = t, let k = k {
                folderParams = LanzouFolderParams(lx: lx, fid: fid, t: t, k: k)
            }
        }
        let trimmedPath = uri.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var shareId = substringAfterLastSlash(trimmedPath)
        if shareId.isEmpty { shareId = trimmedPath }
        // 单文件分享的展示大小：页面文本「文件大小：1.5 M」
        var displaySize: Int64 = 0
        if let g = LanzouRegex.groups(
            #"(?:文件大小|大小)\s*[:：]\s*([\d.]+)\s*([KMGT]?)(?:i?B)?"#,
            in: html
        ), g.count >= 3 {
            displaySize = parseDisplaySize("\(g[1]) \(g[2])")
        }
        let singleFile: ShareFile? = isFolder ? nil : ShareFile(
            fid: shareId,
            fname: title,
            fsize: displaySize,
            isdir: false,
            pdirFid: "",
            fidToken: ""
        )
        return LanzouSharePage(
            shareUrl: normalized,
            baseUrl: origin,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "蓝奏分享" : title,
            isFolder: isFolder,
            needsPwd: needsPwd,
            iframeUrl: iframeUrl,
            fileId: fileId,
            folderParams: folderParams,
            html: html,
            singleFile: singleFile
        )
    }

    /// A7：文件夹分页列表。
    func listShareFolder(page: LanzouSharePage, pwd: String?, dirFid: String) async throws -> [ShareFile] {
        guard let params = page.folderParams else {
            throw ApiError("蓝奏分享分页异常，请重试")
        }
        var all: [ShareFile] = []
        var seen = Set<String>()
        var pg = 1
        while pg <= LanzouConstants.MAX_FOLDER_PAGES {
            var attempt = 0
            var json: JSONValue?
            while attempt <= 2 {
                do {
                    json = try await formPost(
                        url: "\(page.baseUrl)/filemoreajax.php",
                        fields: [
                            ("lx", params.lx),
                            ("fid", params.fid),
                            ("t", params.t),
                            ("k", params.k),
                            ("pwd", pwd ?? ""),
                            ("pg", "\(pg)"),
                        ],
                        referer: page.shareUrl,
                        origin: page.baseUrl,
                        cookie: nil
                    )
                    break
                } catch {
                    attempt += 1
                    if attempt > 2 { throw ApiError("蓝奏请求过于频繁，请稍后再试") }
                    await delay(300)
                    json = nil
                }
            }
            guard let body = json else { break }
            let zt = body.int("zt")
            switch zt {
            case 1:
                break
            case 2:
                return all
            case 3:
                throw ApiError("蓝奏提取码错误，请检查后重新解析")
            case 4:
                pg -= 1
                if attempt >= 2 { throw ApiError("蓝奏请求过于频繁，请稍后再试") }
            default:
                throw ApiError("蓝奏解析失败，请确认分享链接和提取码后重试")
            }
            let arr = body.array("text")
            if arr.isEmpty { break }
            var added = 0
            for item in arr {
                let id = item.string("id")
                if id.isEmpty || !seen.insert(id).inserted { continue }
                all.append(ShareFile(
                    fid: id,
                    fname: firstNonBlank(item.string("name_all"), item.string("name")),
                    fsize: parseDisplaySize(item.string("size")),
                    isdir: false,
                    pdirFid: "",
                    fidToken: "",
                    modifyTime: item.string("time")
                ))
                added += 1
            }
            if added == 0 { throw ApiError("蓝奏分页重复，请重新打开目录") }
            pg += 1
        }
        return all
    }

    /// A2-A6：获取分享文件下载直链（匿名）。
    func getShareDownloadLink(page: LanzouSharePage, file: ShareFile, pwd: String?) async throws -> DownloadLink {
        let origin = page.baseUrl
        // A2：同源 iframe 下载页
        var html = page.html
        if let iframe = page.iframeUrl {
            let iframeHost = URL(string: iframe)?.host
            let shareHost = URL(string: page.shareUrl)?.host
            if let h = iframeHost, h.caseInsensitiveCompare(shareHost ?? "") == .orderedSame {
                html = try await fetchPage(iframe, referer: page.shareUrl, cookie: nil)
            } else if iframeHost != nil {
                throw ApiError("蓝奏下载页面地址异常，请检查分享链接")
            }
        }
        let fileId = page.fileId
            ?? RegexUtil.firstGroup(#"(?:ajaxm|ajaxfile)\.php\?file=(\d+)"#, in: html)
            ?? RegexUtil.firstGroup(#"file=(\d+)"#, in: html)
        guard let fileId = fileId else {
            throw ApiError("蓝奏解析失败，请确认分享链接和提取码后重试")
        }
        // A3：取下载参数
        let withPwd = !(pwd ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let ajaxUrl = resolveAjaxUrl(html, origin: origin, fileId: fileId, withPwd: withPwd)
        guard let sign = jsVar(html, "wp_sign") ?? jsVar(html, "sign") ?? inputValue(html, "sign") else {
            throw ApiError("蓝奏分享页缺少下载参数，请重新解析")
        }
        let ajaxData = jsVar(html, "ajaxdata")
        let kd = jsVarRaw(html, "kdns") ?? "1"
        var fields: [(String, String)] = []
        fields.append(("action", "downprocess"))
        fields.append(("sign", sign))
        if withPwd {
            fields.append(("p", pwd ?? ""))
            fields.append(("kd", "1"))
        } else {
            // 新版无密码协议：websignkey/signs 用 ajaxdata，websign 空，kd 用 kdns
            let key = ajaxData ?? jsVar(html, "websignkey") ?? inputValue(html, "websignkey") ?? ""
            fields.append(("signs", jsVar(html, "signs") ?? key))
            fields.append(("websignkey", key))
            fields.append(("websign", jsVar(html, "websign") ?? ""))
            fields.append(("kd", kd))
            fields.append(("ves", "1"))
        }
        let ajaxJson = try await formPost(
            url: ajaxUrl,
            fields: fields,
            referer: page.shareUrl,
            origin: origin,
            cookie: nil
        )
        try validateAjax(ajaxJson)
        let dom = ajaxJson.string("dom")
        let rel = ajaxJson.string("url")
        if dom.isEmpty || rel.isEmpty || rel.hasPrefix("/") || rel.contains("://") {
            throw ApiError("蓝奏解析失败，请确认分享链接和提取码后重试")
        }
        guard let domURL = URL(string: dom), let scheme = domURL.scheme, let host = domURL.host else {
            throw ApiError("蓝奏解析失败，请确认分享链接和提取码后重试")
        }
        let jump = "\(scheme)://\(host)/file/\(rel)"
        let (finalUrl, size) = try await probeAndVerify(jump, origin)
        let filename = file.fname.trimmingCharacters(in: .whitespaces).isEmpty ? ajaxJson.string("inf") : file.fname
        return DownloadLink(
            fid: file.fid,
            filename: filename,
            downloadUrl: finalUrl,
            size: size
        )
    }

    // MARK: 个人盘下载

    /// 个人盘文件下载：先用 task=22 生成分享链接，再走匿名分享链路取直链。
    func getPersonalDownloadLink(
        cookie: String,
        uid: String,
        vei: String,
        fileId: String,
        fileName: String
    ) async throws -> DownloadLink {
        let info = try await createFileShare(cookie: cookie, uid: uid, vei: vei, fileId: fileId)
        let page = try await resolveShare(shareUrl: info.shareUrl, pwd: info.passcode)
        let file = page.singleFile ?? ShareFile(
            fid: page.shareUrl,
            fname: fileName,
            fsize: 0,
            isdir: false,
            pdirFid: "",
            fidToken: ""
        )
        return try await getShareDownloadLink(page: page, file: file, pwd: info.passcode)
    }

    // MARK: 内部

    /// A4-A5：HEAD 探测直链，处理重定向 / 人机校验 / 验证并下载 / Range 回退。
    private func probeAndVerify(_ jump: String, _ shareOrigin: String) async throws -> (String, Int64) {
        var currentUrl = jump
        // 下载节点要求注入 down_ip=1 Cookie（文档 §A4）
        setCookie(host: hostOf(jump), name: "down_ip", value: "1")
        var confirmedHosts = Set<String>()
        var challenges = Set<String>()
        var visited = Set<String>()
        for _ in 0..<8 {
            guard let uri = URL(string: currentUrl), let host = uri.host else {
                throw ApiError("蓝奏下载地址暂时不可用，请稍后重试")
            }
            if !visited.insert(currentUrl).inserted {
                throw ApiError("蓝奏下载地址循环跳转，请重新解析")
            }
            let response = try await headRequest(currentUrl, shareOrigin)
            let code = response.statusCode
            if (300...399).contains(code) {
                guard let loc = response.header("Location") else {
                    throw ApiError("蓝奏下载地址暂时不可用，请稍后重试")
                }
                currentUrl = absolutize("\(uri.scheme ?? "https")://\(host)", loc)
                continue
            }
            if code == 200 || code == 206 {
                let size = responseSize(response)
                let contentType = response.header("Content-Type") ?? ""
                if contentType.contains("text/html") {
                    let body = try await httpGetText(currentUrl, shareOrigin)
                    // 下载节点可能先返回 acw_sc__v2 人机校验页：计算 Cookie 后重放
                    if let challenge = lanzouChallengeCookie(body) {
                        if !challenges.insert(host).inserted {
                            throw ApiError("蓝奏需要进一步验证，请在分享页完成验证后重试")
                        }
                        setCookie(host: host, name: "acw_sc__v2", value: challenge)
                        continue
                    }
                    if body.contains("验证并下载") {
                        if confirmedHosts.insert(host).inserted {
                            if let verified = try await submitVerify(currentUrl, body, shareOrigin) {
                                currentUrl = verified
                                continue
                            }
                        }
                        throw ApiError("蓝奏需要进一步验证，请在分享页完成验证后重试")
                    }
                    throw ApiError("蓝奏返回的是验证页面，未创建下载任务，请在分享页完成验证后重试")
                }
                // HEAD 未给大小或缺少 content-type：回退 GET Range
                if size <= 0 {
                    let fallback = try await rangeProbe(currentUrl, shareOrigin)
                    if fallback.1 > 0 { return (currentUrl, fallback.1) }
                }
                return (currentUrl, size)
            }
            if code == 403 || code == 404 || code == 410 {
                throw ApiError("蓝奏下载地址已失效，请稍后重新解析")
            }
            if code == 429 {
                throw ApiError("蓝奏下载请求过于频繁，请稍后再试")
            }
            let fallback = try await rangeProbe(currentUrl, shareOrigin)
            if fallback.1 > 0 { return (currentUrl, fallback.1) }
            throw ApiError("蓝奏下载地址暂时不可用，请稍后重试")
        }
        throw ApiError("蓝奏下载地址暂时不可用，请稍后重试")
    }

    /// A6：提交「验证并下载」，返回新的直链 URL 或 nil。
    private func submitVerify(_ nodeUrl: String, _ html: String, _ shareOrigin: String) async throws -> String? {
        guard let uri = URL(string: nodeUrl) else { return nil }
        // 新版确认页：data : { 'file':'<base64>','el':el,'sign':'<base64>' }
        let dataBlocks = LanzouRegex.all(
            #"data\s*:\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}"#,
            in: html,
            group: 1,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let dataMatch = dataBlocks.first { $0.contains("'file'") || $0.contains("\"file\"") }
        let file = dataMatch.flatMap {
            RegexUtil.firstGroup(#"['"]?file['"]?\s*:\s*['"]([^'"]+)['"]"#, in: $0)
        } ?? RegexUtil.firstGroup(#"name=["']file["'][^>]*value=["']([^"']+)["']"#, in: html)
        guard let file = file else { return nil }
        let sign = dataMatch.flatMap {
            RegexUtil.firstGroup(#"['"]?sign['"]?\s*:\s*['"]([^'"]+)['"]"#, in: $0)
        } ?? jsVar(html, "sign") ?? inputValue(html, "sign")
        guard let sign = sign else { return nil }
        // 节点页面 2 秒后才显示按钮，需等同样时长再提交
        await delay(2000)
        let scheme = uri.scheme ?? "https"
        let host = uri.host ?? ""
        let ajaxUrl = "\(scheme)://\(host)/ajax.php"
        let json: JSONValue
        do {
            json = try await formPost(
                url: ajaxUrl,
                fields: [("file", file), ("el", "2"), ("sign", sign)],
                referer: nodeUrl,
                origin: "\(scheme)://\(host)",
                cookie: nil
            )
        } catch {
            throw ApiError("蓝奏下载验证服务暂时不可用，请稍后重试")
        }
        let zt = json.int("zt")
        let url = json.string("url")
        if zt != 1 || url.isEmpty {
            // zt!=1 时 url 字段承载错误文案（如「验证码错误」）
            throw ApiError(url.isEmpty ? "蓝奏需要进一步验证，请在分享页完成验证后重试" : url)
        }
        if url == "?SignError" { throw ApiError("蓝奏下载验证已过期，请重新解析") }
        return url
    }

    private func headRequest(_ url: String, _ shareOrigin: String) async throws -> HTTPResponse {
        var headers: [String: String] = [
            "User-Agent": LanzouConstants.WEB_UA,
            "Referer": "\(shareOrigin)/",
        ]
        let c = mergedCookie(host: hostOf(url), extra: LanzouConstants.DOWN_IP_COOKIE)
        if !c.isEmpty { headers["Cookie"] = c }
        return try await sendNoRedirect(url, method: "HEAD", headers: headers)
    }

    private func rangeProbe(_ url: String, _ shareOrigin: String) async throws -> (String, Int64) {
        var headers: [String: String] = [
            "User-Agent": LanzouConstants.WEB_UA,
            "Referer": "\(shareOrigin)/",
            "Range": "bytes=0-8191",
        ]
        let c = mergedCookie(host: hostOf(url), extra: LanzouConstants.DOWN_IP_COOKIE)
        if !c.isEmpty { headers["Cookie"] = c }
        let resp = try await sendNoRedirect(url, method: "GET", headers: headers)
        var size: Int64 = 0
        if let cr = resp.header("Content-Range"),
           let last = cr.split(separator: "/").last,
           let v = Int64(last) {
            size = v
        }
        return (url, size)
    }

    private func httpGetText(_ url: String, _ referer: String?) async throws -> String {
        var headers: [String: String] = ["User-Agent": LanzouConstants.WEB_UA]
        if let referer = referer { headers["Referer"] = referer }
        let c = mergedCookie(host: hostOf(url), extra: LanzouConstants.DOWN_IP_COOKIE)
        if !c.isEmpty { headers["Cookie"] = c }
        return try await sendFollow(url, headers: headers).text
    }

    /// HEAD/GET 响应的大小（优先 Content-Range，其次 200 的 Content-Length）。
    private func responseSize(_ resp: HTTPResponse) -> Int64 {
        if let cr = resp.header("Content-Range") {
            if let last = cr.split(separator: "/").last, let v = Int64(last) { return v }
            return 0
        }
        if resp.statusCode == 200 {
            return Int64(resp.header("Content-Length") ?? "") ?? 0
        }
        return 0
    }

    private func fetchPageFollowingLanzou(_ url: String) async throws -> String {
        var current = url
        var challenged = Set<String>()
        for _ in 0..<8 {
            let host = hostOf(current)
            var headers: [String: String] = [
                "User-Agent": LanzouConstants.WEB_UA,
                "Referer": current,
            ]
            let c = cookieHeader(host)
            if !c.isEmpty { headers["Cookie"] = c }
            let resp = try await sendNoRedirect(current, headers: headers)
            let code = resp.statusCode
            if (300...399).contains(code) {
                guard let loc = resp.header("Location") else {
                    throw ApiError("蓝奏页面跳转次数过多，请重新解析")
                }
                let next = absolutize(current, loc)
                guard let nextHost = URL(string: next)?.host, LanzouConstants.isLanzouHost(nextHost) else {
                    throw ApiError("蓝奏分享链接无效")
                }
                current = next
                continue
            }
            let body = resp.text
            if body.count > 2_000_000 { throw ApiError("蓝奏分享页面过大或异常") }
            // 分享页可能先返回 acw_sc__v2 人机校验页：计算 Cookie 后重放
            if let challenge = lanzouChallengeCookie(body) {
                if !challenged.insert(host).inserted {
                    throw ApiError("蓝奏需要进一步验证，请在分享页完成验证后重试")
                }
                setCookie(host: host, name: "acw_sc__v2", value: challenge)
                continue
            }
            if body.contains("文件已取消") || body.contains("不存在") {
                throw ApiError("蓝奏文件已取消分享或不存在")
            }
            if body.contains("请求过于频繁") || body.contains("稍后再试") {
                throw ApiError("蓝奏请求过于频繁，请稍后再试")
            }
            return body
        }
        throw ApiError("蓝奏页面跳转次数过多，请重新解析")
    }

    private func fetchPage(_ url: String, referer: String?, cookie: String?) async throws -> String {
        var headers: [String: String] = [
            "User-Agent": LanzouConstants.WEB_UA,
            "Referer": referer ?? url,
        ]
        let c = mergedCookie(host: hostOf(url), extra: cookie)
        if !c.isEmpty { headers["Cookie"] = c }
        let resp = try await sendFollow(url, headers: headers)
        if !resp.isSuccessful { throw ApiError("蓝奏文件已取消分享或不存在") }
        return resp.text
    }

    private func validateAjax(_ json: JSONValue) throws {
        if json.int("zt") == 1 { return }
        let inf = json.string("inf")
        if inf.contains("密码") || inf.contains("提取码") {
            throw ApiError("蓝奏提取码错误，请检查后重新解析")
        }
        if inf.contains("不存在") || inf.contains("取消") || inf.contains("过期") || inf.contains("删除") {
            throw ApiError("蓝奏文件已取消分享或不存在")
        }
        if inf.contains("频繁") || inf.contains("次数") || inf.contains("稍后") {
            throw ApiError("蓝奏请求过于频繁，请稍后再试")
        }
        throw ApiError("蓝奏解析失败，请确认分享链接和提取码后重试")
    }

    /// doupload.php 系列统一请求；allowEnd 时 zt==2 视为成功（列表结束）。
    private func doupload(
        cookie: String,
        uid: String,
        vei: String,
        fields: [(String, String)],
        allowEnd: Bool = false
    ) async throws -> JSONValue {
        let url = "\(LanzouConstants.DOUPLOAD_URL)?uid=\(uid)&vei=\(vei)"
        let headers: [String: String] = [
            "Cookie": cookie,
            "User-Agent": LanzouConstants.WEB_UA,
            "Referer": LanzouConstants.MYDISK_URL,
            "Origin": LanzouConstants.ORIGIN,
            "X-Requested-With": "XMLHttpRequest",
        ]
        let resp = try await sendFollow(url, method: "POST", headers: headers, form: fields)
        if resp.statusCode == 401 || resp.statusCode == 403 {
            throw ApiError("蓝奏登录已过期，请重新网页登录")
        }
        guard let json = JSONValue.parse(resp.body) else {
            throw ApiError("蓝奏文件操作失败，请在官网检查权限和文件类型")
        }
        let zt = json.has("zt") ? json.int("zt") : -1
        if zt == 1 { return json }
        if zt == 2 && allowEnd { return json }
        if zt == 4 { throw ApiError("蓝奏请求频繁，请稍后重试") }
        if zt == 9 { throw ApiError("蓝奏登录已过期，请重新网页登录") }
        throw ApiError("蓝奏文件操作失败（\(zt)），请在官网检查权限和文件类型")
    }

    private func formPost(
        url: String,
        fields: [(String, String)],
        referer: String,
        origin: String,
        cookie: String?
    ) async throws -> JSONValue {
        let body = try await formPostRaw(url: url, fields: fields, referer: referer, origin: origin, cookie: cookie)
        guard let json = JSONValue.parse(body) else {
            if body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                throw ApiError("蓝奏返回了验证页面，请稍后重试或在分享页完成验证")
            }
            throw ApiError("蓝奏解析服务响应异常，请稍后重试")
        }
        return json
    }

    private func formPostRaw(
        url: String,
        fields: [(String, String)],
        referer: String,
        origin: String,
        cookie: String?
    ) async throws -> String {
        var headers: [String: String] = [
            "User-Agent": LanzouConstants.WEB_UA,
            "Referer": referer,
            "Origin": origin,
            "X-Requested-With": "XMLHttpRequest",
        ]
        let c = mergedCookie(host: hostOf(url), extra: cookie)
        if !c.isEmpty { headers["Cookie"] = c }
        let resp = try await sendNoRedirect(url, method: "POST", headers: headers, form: fields)
        if resp.statusCode == 429 { throw ApiError("蓝奏请求过于频繁，请稍后再试") }
        let body = resp.text
        if body.count > 4_000_000 { throw ApiError("蓝奏解析服务返回内容过大，请稍后重试") }
        if !resp.isSuccessful && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ApiError("蓝奏解析服务响应异常（HTTP \(resp.statusCode)），请稍后重试")
        }
        return body
    }

    private func buildShareInfo(_ raw: String, _ domain: String, _ pwd: String) -> ShareInfo {
        let base: String
        if domain.isEmpty {
            base = "https://pan.lanzoui.com"
        } else if domain.contains("://") {
            base = domain
        } else {
            base = "https://\(domain)"
        }
        let url: String
        if raw.contains("://") {
            url = raw
        } else {
            let origin: String
            if let u = URL(string: base), let s = u.scheme, let h = u.host {
                origin = "\(s)://\(h)"
            } else {
                origin = base
            }
            url = "\(origin)/\(raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        }
        return ShareInfo(
            shareUrl: url,
            passcode: pwd,
            pwdId: raw,
            title: "蓝奏云分享",
            // ShareExpire.UNKNOWN = 0（Android 侧)
            expiredType: 0
        )
    }

    private func extractTitle(_ html: String) -> String {
        if let t = RegexUtil.firstGroup(#"<title>([^<]*)</title>"#, in: html) {
            let clean = t
                .replacingOccurrences(of: " - 蓝奏云", with: "")
                .replacingOccurrences(of: "蓝奏云", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !clean.contains("密码") { return clean }
        }
        if let n = RegexUtil.firstGroup(#"class=["']n["']>([^<]+)<"#, in: html) {
            return n.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let f = RegexUtil.firstGroup(#"var\s+filename\s*=\s*['"]([^'"]+)['"]"#, in: html) {
            return f
        }
        return ""
    }

    private func jsVar(_ html: String, _ name: String) -> String? {
        RegexUtil.firstGroup(#"(?:(?:var|let|const)\s+)?\#(name)\s*=\s*['"]([^'"]*)['"]"#, in: html)
    }

    /// 读取未加引号的 JS 变量值（如 `var kdns = 0`）。
    private func jsVarRaw(_ html: String, _ name: String) -> String? {
        guard let v = RegexUtil.firstGroup(#"(?:var|let|const)\s+\#(name)\s*=\s*([^;,\n\r]+)"#, in: html) else {
            return nil
        }
        return v
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }

    /// 页面若是 acw_sc__v2 校验页则返回应设置的 Cookie 值。
    private func lanzouChallengeCookie(_ source: String) -> String? {
        guard let arg1 = RegexUtil.firstGroup(#"\barg1\s*=\s*'([0-9A-Fa-f]{40})'"#, in: source) else {
            return nil
        }
        return acwScV2(arg1)
    }

    /// 下载接口 URL：优先页面里的 domain1/domain2（新版在 apifile.woozooo.com，跨域），
    /// 其次页面中出现的绝对 ajaxm/ajaxfile 地址，最后回退同源。
    private func resolveAjaxUrl(_ html: String, origin: String, fileId: String, withPwd: Bool) -> String {
        if let d1 = jsVar(html, "domain1"), d1.contains("/ajax") { return d1 }
        if let d2 = jsVar(html, "domain2"), d2.contains("/ajax") { return d2 }
        if let abs = RegexUtil.firstGroup(
            #"https?://[^'"\s]+/(?:ajaxm|ajaxfile)\.php\?file=\d+"#,
            in: html,
            group: 0
        ), !abs.isEmpty {
            return abs
        }
        return withPwd ? "\(origin)/ajaxfile.php?file=\(fileId)" : "\(origin)/ajaxm.php?file=\(fileId)"
    }

    private func inputValue(_ html: String, _ name: String) -> String? {
        RegexUtil.firstGroup(
            #"<input[^>]*name=["']\#(name)["'][^>]*value=["']([^"']*)["']"#,
            in: html
        ) ?? RegexUtil.firstGroup(
            #"<input[^>]*value=["']([^"']*)["'][^>]*name=["']\#(name)["']"#,
            in: html
        )
    }

    private func absolutize(_ base: String, _ target: String) -> String {
        if target.hasPrefix("http://") || target.hasPrefix("https://") { return target }
        guard let u = URL(string: base), let scheme = u.scheme, let host = u.host else { return target }
        let root = "\(scheme)://\(host)"
        return target.hasPrefix("/") ? root + target : "\(root)/\(target)"
    }

    private func substringAfterLastSlash(_ s: String) -> String {
        if let i = s.lastIndex(of: "/") { return String(s[s.index(after: i)...]) }
        return s
    }

    private func parseDisplaySize(_ text: String) -> Int64 {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }
        guard let g = LanzouRegex.groups(#"([\d.]+)\s*([KMGT]?)"#, in: t), g.count >= 3,
              let value = Double(g[1]) else {
            return 0
        }
        let unit = g[2].uppercased()
        let factor: Int64
        switch unit {
        case "K": factor = 1024
        case "M": factor = 1024 * 1024
        case "G": factor = 1024 * 1024 * 1024
        case "T": factor = 1024 * 1024 * 1024 * 1024
        default: factor = 1
        }
        return Int64(value * Double(factor))
    }

    private func firstNonBlank(_ values: String...) -> String {
        for v in values where !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}

// MARK: - 蓝奏云分享解析仓库（对应 LanzouResolveRepository.kt）

/// 蓝奏云分享解析仓库（文档 §3）：**匿名**，无需登录。
/// 分享页 HTML → 文件夹分页（filemoreajax）/ 单文件 → 下载参数（ajaxm/ajaxfile）→ HEAD 探测直链。
/// 解析出的分享页缓存在内存中（按分享 URL 作 key），供后续列目录 / 取链复用。
final class LanzouResolveRepository: ShareResolveRepository {

    private let api = LanzouApi()

    private var pageCache: [String: LanzouSharePage] = [:]

    init() {}

    /// 创建分享会话：解析分享链接，校验是否需要提取码。
    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        let page = try await api.resolveShare(shareUrl: link, pwd: pwd)
        if page.needsPwd && (pwd ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw ApiError("此蓝奏分享需要提取码，请填写后重新解析")
        }
        pageCache[page.shareUrl] = page
        return ShareSession(shareId: page.shareUrl, stoken: pwd ?? "", title: page.title)
    }

    /// 列出目录：文件夹分享走分页接口，单文件分享直接返回该文件。
    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        guard let page = pageCache[session.shareId] else {
            throw ApiError("蓝奏分享会话已失效，请重新解析")
        }
        let pwd = session.stoken.trimmingCharacters(in: .whitespaces).isEmpty ? nil : session.stoken
        if page.isFolder {
            return try await api.listShareFolder(page: page, pwd: pwd, dirFid: dirFid)
        }
        if let single = page.singleFile { return [single] }
        return []
    }

    /// 蓝奏分享不支持转存。
    func ensureTempDir(cookie: String) async throws -> String {
        throw ApiError("蓝奏分享暂不支持直接转存，请下载后上传")
    }

    /// 蓝奏分享不支持转存。
    func transferFile(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        throw ApiError("蓝奏分享暂不支持直接转存，请下载后上传")
    }

    /// 蓝奏分享请使用 getShareDownloadLink。
    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        throw ApiError("蓝奏分享请使用 getShareDownloadLink")
    }

    /// 获取分享文件下载直链（匿名）。
    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        guard let page = pageCache[session.shareId] else {
            throw ApiError("蓝奏分享会话已失效，请重新解析")
        }
        let pwd = session.stoken.trimmingCharacters(in: .whitespaces).isEmpty ? nil : session.stoken
        return try await api.getShareDownloadLink(page: page, file: file, pwd: pwd)
    }

    /// 游客取链：蓝奏分享本身即为匿名链路，与登录态一致。
    func getGuestShareDownloadLink(session: ShareSession, file: ShareFile) async throws -> DownloadLink {
        guard let page = pageCache[session.shareId] else {
            throw ApiError("蓝奏分享会话已失效，请重新解析")
        }
        let pwd = session.stoken.trimmingCharacters(in: .whitespaces).isEmpty ? nil : session.stoken
        return try await api.getShareDownloadLink(page: page, file: file, pwd: pwd)
    }
}
