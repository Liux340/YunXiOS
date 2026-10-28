/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：夸克网盘网络接口层 + 分享解析仓库。
 * 对应 Android 侧：
 *   - data/network/QuarkConstants.kt
 *   - data/network/QuarkApi.kt（含 QuarkCookieUtil）
 *   - data/repository/QuarkResolveRepository.kt
 */

import Foundation

// MARK: - 常量（对应 QuarkConstants.kt）

/// 夸克接口常量集合。
enum QuarkConstants {

    /// 夸克 PC 客户端 User-Agent，所有请求必须携带
    static let USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/130.0.0.0 Safari/537.36 QuarkPC/6.0.8.649"

    /// WebView 登录页（PC 环境）
    static let LOGIN_URL = "https://pan.quark.cn/?fr=pc&platform=pc"

    /// 提取 Cookie 的域名
    static let COOKIE_DOMAIN = "https://pan.quark.cn"

    /// 验证登录状态的接口
    static let ACCOUNT_INFO_URL = "https://pan.quark.cn/account/info"

    /// 解析/下载 API 强制 User-Agent
    static let API_USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "quark-cloud-drive/2.5.20 Chrome/100.0.4896.160 Electron/18.3.5.12-a038f7b798 Safari/537.36 Channel/pckk_other_ch"

    /// 业务 API 基础域名
    static let API_BASE = "https://drive-pc.quark.cn"

    /// 获取分享 Token
    static let SHARE_TOKEN_URL = API_BASE + "/1/clouddrive/share/sharepage/token?pr=ucpro&fr=pc"

    /// 验证分享提取码
    static let SHARE_PASSWORD_URL = API_BASE + "/1/clouddrive/share/password?pr=ucpro&fr=pc"

    /// 获取分享文件列表
    static let SHARE_DETAIL_URL = API_BASE + "/1/clouddrive/share/sharepage/detail?pr=ucpro&fr=pc"

    /// 获取下载直链
    static let DOWNLOAD_URL = API_BASE + "/1/clouddrive/file/download?pr=ucpro&fr=pc&sys=win32&ve=3.23.2"

    /// 根目录 fid
    static let DEFAULT_PDIR_FID = "0"

    /// 个人网盘文件列表 / 创建目录
    static let FILE_URL = API_BASE + "/1/clouddrive/file?pr=ucpro&fr=pc"

    /// 个人网盘文件列表（排序；抓包：pdir_fid=0 根目录，带完整 cookie）
    static let CLOUD_FILE_SORT_URL = API_BASE + "/1/clouddrive/file/sort?pr=ucpro&fr=pc"

    /// 转存分享文件
    static let SAVE_URL = API_BASE + "/1/clouddrive/share/sharepage/save?pr=ucpro&fr=pc"

    /// 异步任务查询
    static let TASK_URL = API_BASE + "/1/clouddrive/task?pr=ucpro&fr=pc"

    /// 删除文件（取链成功后清理临时转存；body: action_type=2 + filelist）
    static let DELETE_URL = API_BASE + "/1/clouddrive/file/delete?pr=ucpro&fr=pc&uc_param_str="

    /// 重命名文件（body: fid + file_name）
    static let RENAME_URL = API_BASE + "/1/clouddrive/file/rename?pr=ucpro&fr=pc&uc_param_str="

    /// 移动文件（body: action_type=1 + to_pdir_fid + filelist）
    static let MOVE_URL = API_BASE + "/1/clouddrive/file/move?pr=ucpro&fr=pc&uc_param_str="

    /// 创建分享（body: fid_list + title + url_type + passcode + expired_type）
    static let SHARE_CREATE_URL = API_BASE + "/1/clouddrive/share?pr=ucpro&fr=pc&uc_param_str="

    /// 查询分享信息（body: share_id → share_url / passcode / pwd_id）
    static let SHARE_INFO_URL = API_BASE + "/1/clouddrive/share/password?pr=ucpro&fr=pc&uc_param_str="

    /// 临时转存目录名
    static let TEMP_DIR_NAME = "YunX临时转存"

    /// 临时转存子目录前缀（唯一子目录 tr_<时间戳>_<随机>，供启动一次性清理识别）
    static let TEMP_SUBDIR_PREFIX = "tr_"

    /// 下载直链防盗链必须携带的 Referer
    static let DOWNLOAD_REFERER = "https://pan.quark.cn/"

    /// 会话刷新探测接口：任意接口均可，用于重新下发 __puus
    static let CONFIG_URL = API_BASE + "/1/clouddrive/config?pr=ucpro&fr=pc"

    /// __puus 有效期约 3 小时，提前到 90 分钟刷新
    static let PUUS_REFRESH_INTERVAL_MS: Int64 = 90 * 60 * 1000

    /// 关键 Cookie 字段，缺失则视为未登录
    static func isValidCookie(_ cookie: String?) -> Bool {
        guard let cookie = cookie else { return false }
        return cookie.contains("__pus=") && cookie.contains("__puus=")
    }
}

// MARK: - Cookie 工具（对应 QuarkCookieUtil）

/// 夸克 Cookie 工具：合并/剥离 __puus、__pus。
/// __puus 约 3 小时过期，是下载直链签名校验的关键字段。
enum QuarkCookieUtil {

    private static let TRACKED: Set<String> = ["__puus", "__pus"]

    /// 把响应 Set-Cookie 列表里的最新 __puus/__pus 合并回原 Cookie 串
    static func mergeFromSetCookies(_ original: String, _ setCookies: [String]) -> String {
        var cookie = original
        for sc in setCookies {
            let kv = substringBefore(sc, ";").trimmingCharacters(in: .whitespaces)
            guard let eq = kv.firstIndex(of: "="), eq != kv.startIndex else { continue }
            let name = String(kv[kv.startIndex..<eq])
            guard TRACKED.contains(name) else { continue }
            let value = String(kv[kv.index(after: eq)...])
            cookie = setOrReplace(cookie, name, value)
        }
        return cookie
    }

    /// 去掉 __puus，用于触发服务端重新下发
    static func withoutPuus(_ cookie: String) -> String {
        cookie.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("__puus=") }
            .joined(separator: "; ")
    }

    /// 设置或替换某个 Cookie 键值
    private static func setOrReplace(_ cookie: String, _ name: String, _ value: String) -> String {
        var parts = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let kv = "\(name)=\(value)"
        if let idx = parts.firstIndex(where: { $0.hasPrefix("\(name)=") }) {
            parts[idx] = kv
        } else {
            parts.append(kv)
        }
        return parts.joined(separator: "; ")
    }

    /// 取分隔符之前的子串
    private static func substringBefore(_ s: String, _ sep: Character) -> String {
        if let i = s.firstIndex(of: sep) { return String(s[s.startIndex..<i]) }
        return s
    }
}

// MARK: - 夸克 API（对应 QuarkApi.kt）

/// 夸克 API 封装：账号验证 + 分享解析 + 下载直链。
final class QuarkApi {

    /// Cookie 回写接收器：`(合并后的最新 Cookie, 本次请求所用的 Cookie)`。
    /// 每次响应把 Set-Cookie 合并后的最新 Cookie 回调，保持 __puus/__pus 新鲜。
    /// ★ 带上「本次请求的 Cookie」，是为了让上层只回写**这一份凭证所属的账号行**：多账号下载
    ///   （C1/C2）会拿别的账号取链，把它的 __puus 合并进主账号那行会让会话签名与 uid 对不上（412）。
    ///   基线版本此回调从未接线（会话续期不落库），本次一并接上。
    var cookieSink: ((String, String) -> Void)?

    /// 游客态令牌 `__pugs`（未登录访问分享时由响应 Set-Cookie 下发，约 3 小时有效）。
    /// 夸克游客直链（dl-guest-*）必须回带该令牌，缺了 CDN 直接 412；进程内复用。
    private(set) var guestPugs: String = ""

    // ---------- 账号 ----------

    /// 获取昵称（失败返回 nil，不抛错）
    func fetchNickname(cookie: String) async throws -> String? {
        do {
            let response = try await HTTPClient.api.get(
                QuarkConstants.ACCOUNT_INFO_URL,
                headers: [
                    "Cookie": cookie,
                    "User-Agent": QuarkConstants.API_USER_AGENT,
                ]
            )
            guard response.isSuccessful else { return nil }
            guard let json = JSONValue.parse(response.body) else { return nil }
            // 该接口无 status 字段，成功标志为 success:true / code:"OK"
            guard json.bool("success") else { return nil }
            let nickname = json.object("data").string("nickname")
            return nickname.isEmpty ? nil : nickname
        } catch {
            return nil
        }
    }

    // ---------- 分享解析 ----------

    /// 4.1 获取分享 Token（请求体携带 pwd_id/passcode）
    func getShareToken(shareId: String, pwd: String?, cookie: String) async throws -> ShareToken? {
        let body: [String: Any] = [
            "pwd_id": shareId,
            "passcode": pwd ?? "",
            "support_visit_limit_private_share": true,
        ]
        return try await parseData(url: QuarkConstants.SHARE_TOKEN_URL, cookie: cookie, body: body) { data in
            ShareToken(
                stoken: data.string("stoken"),
                title: data.string("title"),
                firstFid: data.string("first_fid")
            )
        }
    }

    /// 4.3 验证分享提取码
    func verifySharePassword(shareId: String, passcode: String, cookie: String) async throws -> Bool {
        do {
            let response = try await HTTPClient.api.postJSON(
                QuarkConstants.SHARE_PASSWORD_URL,
                headers: postHeaders(cookie),
                body: ["share_id": shareId, "passcode": passcode]
            )
            guard let json = JSONValue.parse(response.body) else { return false }
            return json.int("status") == 200
        } catch {
            return false
        }
    }

    /// 4.2 获取分享文件列表（sharepage/detail）
    /// 官方字段：file_name / size / dir(boolean) / share_fid_token，以抓包为准。
    func getShareFiles(
        shareId: String,
        stoken: String,
        pdirFid: String,
        cookie: String,
        page: Int = 1,
        size: Int = 100
    ) async throws -> [ShareFile]? {
        // 参数名必须为 pwd_id（值=分享链接短码），并追加 ver=2 / _page / _size 等固定参数
        let url = QuarkConstants.SHARE_DETAIL_URL
            + "&pwd_id=" + shareId
            + "&stoken=" + urlEncode(stoken)
            + "&pdir_fid=" + pdirFid
            + "&ver=2"
            + "&force=0"
            + "&_page=" + String(page)
            + "&_size=" + String(size)
            + "&_fetch_banner=0"
            + "&_fetch_share=0"
            + "&fetch_relate_conversation=0"
            + "&_fetch_total=1"
            + "&_sort=file_type:asc,file_name:asc"
        // 该接口需携带 Origin / Referer，否则可能返回 400
        return try await parseData(
            url: url,
            cookie: cookie,
            extraHeaders: ["Origin": "https://pan.quark.cn", "Referer": "https://pan.quark.cn/"]
        ) { data in
            data.array("list").compactMap { (item: JSONValue) -> ShareFile? in
                guard !item.isNull else { return nil }
                return ShareFile(
                    fid: item.string("fid"),
                    fname: item.string("file_name"),
                    fsize: item.long("size"),
                    isdir: item.bool("dir"),
                    pdirFid: item.string("pdir_fid"),
                    fidToken: item.string("share_fid_token"),
                    modifyTime: item.string("updated_at")
                )
            }
        }
    }

    // ---------- 个人网盘 / 转存 ----------

    /// 7.1 个人网盘文件列表（用于查找/确认临时目录）
    /// 个人网盘列表字段为 file_name / size / dir(boolean)，与分享列表的 fname / fsize / isdir(int) 不同，需兼容映射。
    func getFileList(
        pdirFid: String,
        cookie: String,
        page: Int = 1,
        size: Int = 100
    ) async throws -> [ShareFile]? {
        let url = QuarkConstants.FILE_URL + "&pdir_fid=\(pdirFid)&page=\(page)&size=\(size)"
        return try await parseData(url: url, cookie: cookie) { data in
            data.array("list").compactMap { (item: JSONValue) -> ShareFile? in
                guard !item.isNull else { return nil }
                let fileName = item.string("file_name")
                return ShareFile(
                    fid: item.string("fid"),
                    fname: fileName.isEmpty ? item.string("fname") : fileName,
                    fsize: item.has("size") ? item.long("size") : item.long("fsize"),
                    isdir: item.bool("dir") || item.int("isdir") == 1,
                    pdirFid: item.string("pdir_fid"),
                    fidToken: item.string("fid_token"),
                    modifyTime: item.string("modify_time")
                )
            }
        }
    }

    /// 云盘文件列表（网盘页浏览；抓包 /1/clouddrive/file/sort，pdir_fid=0 根目录）
    /// 自动翻页：单页满 size 继续，封顶 100 页防异常死循环；默认单页 100。
    func listCloudFiles(
        pdirFid: String,
        cookie: String,
        page: Int = 1,
        size: Int = 100
    ) async throws -> [ShareFile]? {
        var all: [ShareFile] = []
        var p = page
        while true {
            let url = QuarkConstants.CLOUD_FILE_SORT_URL
                + "&uc_param_str="
                + "&pdir_fid=" + pdirFid
                + "&_page=" + String(p)
                + "&_size=" + String(size)
                + "&_fetch_total=1"
                + "&_fetch_sub_dirs=0"
                + "&_sort=file_type:asc,updated_at:desc"
                + "&fetch_all_file=1"
                + "&fetch_risk_file_name=1"
            let files = try await parseData(
                url: url,
                cookie: cookie,
                extraHeaders: ["Origin": "https://pan.quark.cn", "Referer": "https://pan.quark.cn/"]
            ) { data in
                data.array("list").compactMap { item -> ShareFile? in
                    guard !item.isNull else { return nil }
                    let fileName = item.string("file_name")
                    return ShareFile(
                        fid: item.string("fid"),
                        fname: fileName.isEmpty ? item.string("fname") : fileName,
                        fsize: item.long("size"),
                        isdir: item.bool("dir"),
                        pdirFid: item.string("pdir_fid"),
                        fidToken: "",
                        modifyTime: item.string("updated_at")
                    )
                }
            }
            all += files
            // 本页未满 size → 已是最后一页；封顶 100 页防止异常死循环
            if files.count < size || p >= 100 { break }
            p += 1
        }
        return all.isEmpty ? nil : all
    }

    /// 创建目录（个人网盘），返回新目录 fid
    func createFolder(name: String, parentFid: String, cookie: String) async throws -> String? {
        let body: [String: Any] = [
            "pdir_fid": parentFid,
            "file_name": name,
            "dir_path": "",
            "dir_init_lock": false,
        ]
        return try await parseData(url: QuarkConstants.FILE_URL, cookie: cookie, body: body) { data in
            data.string("fid")
        }
    }

    /// 5. 转存分享文件到个人网盘目录，返回异步任务 id（可能为空）
    func saveShareFile(
        shareId: String,
        stoken: String,
        pdirFid: String,
        fid: String,
        fidToken: String,
        toPdirFid: String,
        cookie: String
    ) async throws -> String? {
        let body: [String: Any] = [
            "pwd_id": shareId,
            "stoken": stoken,
            "pdir_fid": pdirFid,
            "to_pdir_fid": toPdirFid,
            "fid_list": [fid],
            "fid_token_list": [fidToken],
            "scene": "link",
        ]
        return try await parseData(url: QuarkConstants.SAVE_URL, cookie: cookie, body: body) { data -> String? in
            let taskId = data.string("task_id")
            return taskId.isEmpty ? nil : taskId
        }
    }

    /// 轮询异步转存任务，直到完成或超时（最多 10 次 × 1s）
    /// 完成：finished_at > 0 或 status/task_status == 2；新 fid 在 data.save_as.save_as_top_fids[0]。
    func pollTask(taskId: String, cookie: String) async throws -> String? {
        let url = QuarkConstants.TASK_URL
            + "&task_id=" + urlEncode(taskId)
            + "&retry_index=0"
        for _ in 0..<10 {
            var savedFid: String?
            do {
                let response = try await HTTPClient.api.get(url, headers: getHeaders(cookie))
                if let json = JSONValue.parse(response.body), json.int("status") == 200 {
                    let data = json.object("data")
                    if !data.isNull {
                        let finished = data.long("finished_at") > 0
                            || data.int("status") == 2
                            || data.int("task_status") == 2
                        if finished {
                            let fids = data.object("save_as").array("save_as_top_fids")
                            if let first = fids.first {
                                let s = first.stringValue
                                if !s.isEmpty { savedFid = s }
                            }
                        }
                    }
                }
            } catch {
                savedFid = nil
            }
            if let savedFid = savedFid { return savedFid }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return nil
    }

    // ---------- 网盘空间详情 ----------

    /// 网盘空间详情（/1/clouddrive/member：total_capacity / use_capacity）
    func getQuota(cookie: String) async throws -> QuotaInfo? {
        let url = "https://drive-pc.quark.cn/1/clouddrive/member?pr=ucpro&fr=pc&fetch_subscribe=true&_ch=home"
        do {
            let response = try await HTTPClient.api.get(url, headers: getHeaders(cookie))
            guard let json = JSONValue.parse(response.body) else { return nil }
            let data = json.object("data")
            if data.isNull { return nil }
            return QuotaInfo(
                used: data.long("use_capacity"),
                total: data.long("total_capacity")
            )
        } catch {
            return nil
        }
    }

    // ---------- 下载直链 ----------

    /// 刷新会话 Cookie（剥离 __puus 后请求 /config，服务端 Set-Cookie 重新下发 __puus/__pus）。
    /// 失败返回 nil（调用方应回退原 Cookie）。
    func refreshSession(cookie: String) async throws -> String? {
        do {
            let response = try await HTTPClient.api.get(
                QuarkConstants.CONFIG_URL,
                headers: [
                    "Cookie": QuarkCookieUtil.withoutPuus(cookie),
                    "User-Agent": QuarkConstants.API_USER_AGENT,
                    "Referer": QuarkConstants.DOWNLOAD_REFERER,
                ]
            )
            let merged = QuarkCookieUtil.mergeFromSetCookies(cookie, response.setCookies)
            if merged != cookie { cookieSink?(merged, cookie) }
            return merged
        } catch {
            return nil
        }
    }

    /// 6.1 获取下载直链
    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink? {
        let body: [String: Any] = ["fids": [fid]]
        let response = try await HTTPClient.api.postJSON(
            QuarkConstants.DOWNLOAD_URL,
            headers: postHeaders(cookie),
            body: body
        )
        mergeCookieFromResponse(original: cookie, response: response)
        guard !response.body.isEmpty else {
            throw ApiError("获取下载链接失败：响应为空")
        }
        guard let json = JSONValue.parse(response.body) else {
            throw ApiError("响应解析失败")
        }
        let code = json.int("code")
        if json.int("status") != 200 && code != 0 {
            let msg = json.string("message")
            throw ApiError(msg.isEmpty ? "获取下载链接失败" : msg, code: code)
        }
        guard json.has("data") else { throw ApiError("响应缺少 data") }
        let array = json.array("data")
        if array.isEmpty { throw ApiError("未返回下载链接") }
        let item = array[0]
        let fileName = item.string("file_name")
        return DownloadLink(
            fid: item.string("fid"),
            filename: fileName.isEmpty ? item.string("filename") : fileName,
            downloadUrl: item.string("download_url"),
            size: item.long("size")
        )
    }

    /// 6.1b 游客分享取链（未登录直链，实测仅约 50MB 以内的小文件可用）。
    /// 响应 Set-Cookie 会下发游客态 `__pugs`，捕获后写入 DownloadLink.guestCookie 并缓存到 guestPugs。
    func getGuestShareDownloadLink(
        fid: String,
        fidToken: String,
        shareId: String,
        stoken: String
    ) async throws -> DownloadLink? {
        let body: [String: Any] = [
            "fids": [fid],
            "fids_token": [fidToken],
            "pwd_id": shareId,
            "stoken": stoken,
            "speedup_session": "",
            "token": "",
        ]
        let response = try await postJsonGuest(QuarkConstants.DOWNLOAD_URL, cookie: guestPugs, body: body)
        // 先取本次响应的 __pugs（与本次直链同响应绑定，不能用别的响应/上一次的值）
        let responsePugs = pugsFromSetCookies(response.setCookies)
        guard !response.body.isEmpty else {
            throw ApiError("获取下载链接失败：响应为空")
        }
        if let responsePugs = responsePugs { guestPugs = responsePugs }
        guard let json = JSONValue.parse(response.body) else {
            // 非 JSON（风控页/HTML 错误页）时带上 HTTP 状态码
            throw ApiError("响应解析失败（HTTP \(response.statusCode)）")
        }
        let code = json.int("code")
        if json.int("status") != 200 && code != 0 {
            throw ApiError(guestErrorMessage(code, json.string("message")), code: code)
        }
        guard json.has("data") else { throw ApiError("响应缺少 data") }
        let array = json.array("data")
        if array.isEmpty { throw ApiError("未返回下载链接") }
        let item = array[0]
        let fileName = item.string("file_name")
        return DownloadLink(
            fid: item.string("fid"),
            filename: fileName.isEmpty ? item.string("filename") : fileName,
            downloadUrl: item.string("download_url"),
            size: item.long("size"),
            guestCookie: responsePugs ?? guestPugs
        )
    }

    /// 游客取链的服务端错误码 → 中文提示（23018=超出游客大小上限、31001=需要登录）
    private func guestErrorMessage(_ code: Int, _ message: String) -> String {
        switch code {
        case 23018: return "该文件超出游客可获取的大小上限（夸克实测约 50MB），请先登录夸克网盘再下载"
        case 31001: return "该分享需要登录夸克网盘后才能下载"
        default: return message.isEmpty ? "获取下载链接失败" : message
        }
    }

    /// 从响应 Set-Cookie 里取出游客态令牌，返回可直接当 Cookie 头用的 `__pugs=值`；没有则 nil
    private func pugsFromSetCookies(_ setCookies: [String]) -> String? {
        for sc in setCookies {
            let head: String
            if let i = sc.firstIndex(of: ";") {
                head = String(sc[sc.startIndex..<i]).trimmingCharacters(in: .whitespaces)
            } else {
                head = sc.trimmingCharacters(in: .whitespaces)
            }
            if head.hasPrefix("__pugs=") && head.count > "__pugs=".count {
                return head
            }
        }
        return nil
    }

    /// 游客请求构造：Cookie 为空时干脆不发该头（首次取链手上没有任何令牌）
    private func postJsonGuest(_ url: String, cookie: String, body: [String: Any]) async throws -> HTTPResponse {
        var headers: [String: String] = [
            "User-Agent": QuarkConstants.API_USER_AGENT,
            "Content-Type": "application/json",
        ]
        if !cookie.trimmingCharacters(in: .whitespaces).isEmpty {
            headers["Cookie"] = cookie
        }
        return try await HTTPClient.api.postJSON(url, headers: headers, body: body)
    }

    /// 6.1c 免转存分享取链（登录态）：直接把分享凭证交给 download 接口换直链
    func getShareDownloadLinkWithoutSave(
        fid: String,
        fidToken: String,
        shareId: String,
        stoken: String,
        cookie: String
    ) async throws -> DownloadLink? {
        let body: [String: Any] = [
            "fids": [fid],
            "fids_token": [fidToken],
            "pwd_id": shareId,
            "stoken": stoken,
            // 与游客取链打的是同一个端点：speedup_session / token 留空即可
            "speedup_session": "",
            "token": "",
        ]
        let response = try await HTTPClient.api.postJSON(
            QuarkConstants.DOWNLOAD_URL,
            headers: postHeaders(cookie),
            body: body
        )
        mergeCookieFromResponse(original: cookie, response: response)
        guard !response.body.isEmpty else {
            throw ApiError("获取下载链接失败：响应为空")
        }
        guard let json = JSONValue.parse(response.body) else {
            throw ApiError("响应解析失败（HTTP \(response.statusCode)）")
        }
        let code = json.int("code")
        if json.int("status") != 200 && code != 0 {
            throw ApiError(noSaveErrorMessage(code, json.string("message")), code: code)
        }
        guard json.has("data") else { throw ApiError("响应缺少 data") }
        let array = json.array("data")
        if array.isEmpty { throw ApiError("未返回下载链接") }
        let item = array[0]
        let fileName = item.string("file_name")
        return DownloadLink(
            fid: item.string("fid"),
            filename: fileName.isEmpty ? item.string("filename") : fileName,
            downloadUrl: item.string("download_url"),
            size: item.long("size")
        )
    }

    /// 免转存取链的服务端错误码 → 中文提示（31001=登录态失效；23018=服务端仍按游客大小限制放行）
    private func noSaveErrorMessage(_ code: Int, _ message: String) -> String {
        switch code {
        case 31001: return "夸克登录态已失效，请到「网盘」页重新登录后再试"
        case 23018: return "服务端按游客限制拒绝了该文件（夸克约 50MB 上限）"
        default: return message.isEmpty ? "获取下载链接失败" : message
        }
    }

    /// 6.2 删除文件（取链成功后清理临时转存；action_type=2 + filelist + exclude_fids）
    func deleteFile(fid: String, cookie: String) async throws -> String? {
        let body: [String: Any] = [
            "action_type": 2,
            "filelist": [fid],
            "exclude_fids": [Any](),
        ]
        return try await parseData(url: QuarkConstants.DELETE_URL, cookie: cookie, body: body) { data -> String? in
            let taskId = data.string("task_id")
            return taskId.isEmpty ? nil : taskId
        }
    }

    // ---------- 云盘文件管理 ----------

    /// 重命名文件（POST file/rename）
    func renameFile(fid: String, newName: String, cookie: String) async throws -> Bool {
        do {
            let response = try await HTTPClient.api.postJSON(
                QuarkConstants.RENAME_URL,
                headers: postHeaders(cookie),
                body: ["fid": fid, "file_name": newName]
            )
            guard let json = JSONValue.parse(response.body) else { return false }
            return json.int("status") == 200
        } catch {
            return false
        }
    }

    /// 移动文件（action_type=1 + to_pdir_fid + filelist）；返回 task_id
    func moveFile(fid: String, toPdirFid: String, cookie: String) async throws -> String? {
        let body: [String: Any] = [
            "action_type": 1,
            "to_pdir_fid": toPdirFid,
            "filelist": [fid],
            "exclude_fids": [Any](),
        ]
        return try await parseData(url: QuarkConstants.MOVE_URL, cookie: cookie, body: body) { data -> String? in
            let taskId = data.string("task_id")
            return taskId.isEmpty ? nil : taskId
        }
    }

    /// 创建分享（异步任务）：创建 → task_id → 轮询取 share_id。
    /// urlType 1=链接无提取码 2=链接+提取码；expiredType 1=永久 2=一天 3=七天 4=三十天。
    func createShare(
        fidList: [String],
        title: String,
        urlType: Int,
        passcode: String,
        expiredType: Int,
        cookie: String
    ) async throws -> String? {
        var body: [String: Any] = [
            "fid_list": fidList,
            "title": title.trimmingCharacters(in: .whitespaces).isEmpty ? "分享文件" : title,
            "url_type": urlType,
            "expired_type": expiredType,
            "support_error_code": ["41060"],
        ]
        if !passcode.trimmingCharacters(in: .whitespaces).isEmpty {
            body["passcode"] = passcode
        }
        // 1) 创建分享 → task_id（异步，须轮询等待完成）
        let taskId = try await parseData(url: QuarkConstants.SHARE_CREATE_URL, cookie: cookie, body: body) { data -> String? in
            let t = data.string("task_id")
            return t.isEmpty ? nil : t
        }
        guard let taskId = taskId else { return nil }
        // 2) 轮询 task 直到完成，取 share_id（官方响应 status=2 + share_id）
        return try await pollShareTask(taskId, cookie: cookie)
    }

    /// 轮询分享创建任务（GET /1/clouddrive/task），返回 share_id；超时返回 nil
    private func pollShareTask(_ taskId: String, cookie: String) async throws -> String? {
        let url = QuarkConstants.TASK_URL
            + "&task_id=" + urlEncode(taskId)
            + "&retry_index=0"
        for _ in 0..<15 {
            var shareId: String?
            do {
                let response = try await HTTPClient.api.get(url, headers: getHeaders(cookie))
                if let json = JSONValue.parse(response.body), json.int("status") == 200 {
                    let data = json.object("data")
                    if !data.isNull {
                        let finished = data.long("finished_at") > 0 || data.int("status") == 2
                        if finished {
                            let s = data.string("share_id")
                            if !s.isEmpty { shareId = s }
                        }
                    }
                }
            } catch {
                shareId = nil
            }
            if let shareId = shareId { return shareId }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return nil
    }

    /// 查询分享信息（POST share/password body={share_id} → 链接/提取码/标题）
    func getShareInfo(shareId: String, cookie: String) async throws -> ShareInfo? {
        let body: [String: Any] = ["share_id": shareId]
        return try await parseData(url: QuarkConstants.SHARE_INFO_URL, cookie: cookie, body: body) { data in
            ShareInfo(
                shareUrl: data.string("share_url"),
                passcode: data.string("passcode"),
                pwdId: data.string("pwd_id"),
                title: data.string("title"),
                expiredType: data.int("expired_type")
            )
        }
    }

    // ---------- 请求构造与响应解析 ----------

    /// 通用 GET 头
    private func getHeaders(_ cookie: String) -> [String: String] {
        [
            "Cookie": cookie,
            "User-Agent": QuarkConstants.API_USER_AGENT,
        ]
    }

    /// 通用 POST JSON 头
    private func postHeaders(_ cookie: String) -> [String: String] {
        [
            "Cookie": cookie,
            "User-Agent": QuarkConstants.API_USER_AGENT,
            "Content-Type": "application/json",
        ]
    }

    /// 统一请求 + 解析：合并 Set-Cookie，校验 status==200，返回 data 交由 parser 转换。
    private func parseData<T>(
        url: String,
        cookie: String,
        body: [String: Any]? = nil,
        extraHeaders: [String: String] = [:],
        parser: (JSONValue) -> T
    ) async throws -> T {
        var headers = (body != nil) ? postHeaders(cookie) : getHeaders(cookie)
        for (k, v) in extraHeaders { headers[k] = v }
        let response: HTTPResponse
        if let body = body {
            response = try await HTTPClient.api.postJSON(url, headers: headers, body: body)
        } else {
            response = try await HTTPClient.api.get(url, headers: headers)
        }
        mergeCookieFromResponse(original: cookie, response: response)
        guard !response.body.isEmpty else {
            throw ApiError("请求失败：响应为空")
        }
        guard let json = JSONValue.parse(response.body) else {
            // 服务端返回非 JSON（多半是 HTML 错误页/风控页）时带上 HTTP 状态码
            throw ApiError("响应解析失败（HTTP \(response.statusCode)）")
        }
        if json.int("status") != 200 {
            // 透传服务端 message，如「提取码错误」「分享已失效」等
            let msg = json.string("message")
            throw ApiError(msg.isEmpty ? "请求失败" : msg)
        }
        let data = json.object("data")
        if data.isNull {
            throw ApiError("响应缺少 data")
        }
        return parser(data)
    }

    /// 从响应 Set-Cookie 合并 __puus/__pus 回原 Cookie 并回调 cookieSink（保持会话新鲜）
    private func mergeCookieFromResponse(original: String, response: HTTPResponse) {
        let setCookies = response.setCookies
        if setCookies.isEmpty { return }
        if original.isEmpty { return }
        let merged = QuarkCookieUtil.mergeFromSetCookies(original, setCookies)
        if merged != original { cookieSink?(merged, original) }
    }
}

// MARK: - 夸克分享解析仓库（对应 QuarkResolveRepository.kt）

/// 夸克分享解析仓库：token → 列表 → 转存临时目录 → 下载直链。
/// 所有 API 失败统一携带服务端 message（ApiError）透传给 UI。
final class QuarkResolveRepository: ShareResolveRepository {

    private let api = QuarkApi()

    init() {
        // Cookie 回写接线（基线缺失）：响应带 Set-Cookie 时按「本次请求的 Cookie」反查账号行落库，
        // 保持 __puus/__pus 新鲜；反查保证只写对应那一行，多账号轮换取链时不会串号（412）。
        api.cookieSink = { merged, requestCookie in
            let platform = SharePlatform.quark
            Task { @MainActor in
                AccountStore.shared.writeBackCookieByRequest(
                    merged: merged,
                    requestCookie: requestCookie,
                    platform: platform
                )
            }
        }
    }

    /// 创建分享会话：解析链接 → 获取 stoken（请求体携带提取码）。
    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        guard let parsed = ShareLinkParser.parse(link) else {
            throw ApiError("无法识别分享链接")
        }
        // pwd 为空时用链接里的
        let trimmedPwd = pwd?.trimmingCharacters(in: .whitespaces)
        let effectivePwd: String? = (trimmedPwd?.isEmpty == false) ? pwd : parsed.pwd
        guard let token = try await api.getShareToken(shareId: parsed.shareId, pwd: effectivePwd, cookie: cookie) else {
            throw ApiError("未获取到分享凭证")
        }
        return ShareSession(shareId: parsed.shareId, stoken: token.stoken, title: token.title)
    }

    /// 获取指定目录下的文件列表（分页：每页 100，最多 100 页）
    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        var all: [ShareFile] = []
        var page = 1
        var batch: [ShareFile] = []
        repeat {
            guard let files = try await api.getShareFiles(
                shareId: session.shareId,
                stoken: session.stoken,
                pdirFid: dirFid,
                cookie: cookie,
                page: page,
                size: 100
            ) else {
                throw ApiError("未获取到文件列表")
            }
            batch = files
            all += files
            page += 1
        } while batch.count == 100 && page <= 100
        return all
    }

    /// 确保「YunX临时转存」目录存在，返回其 fid；不存在则创建。
    func ensureTempDir(cookie: String) async throws -> String {
        guard let rootFiles = try await api.getFileList(pdirFid: QuarkConstants.DEFAULT_PDIR_FID, cookie: cookie) else {
            throw ApiError("获取网盘目录失败")
        }
        if let dir = rootFiles.first(where: { $0.isdir && $0.fname == QuarkConstants.TEMP_DIR_NAME }) {
            return dir.fid
        }
        guard let created = try await api.createFolder(
            name: QuarkConstants.TEMP_DIR_NAME,
            parentFid: QuarkConstants.DEFAULT_PDIR_FID,
            cookie: cookie
        ) else {
            throw ApiError("创建临时目录失败")
        }
        return created
    }

    /// 转存分享文件到临时目录，等待异步任务完成。
    /// 返回转存后的新 fid（取直链必须用它，分享 fid 转存后已变更）。
    func transferFile(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        try await transferFileTo(session: session, file: file, toDirFid: toDirFid, cookie: cookie)
    }

    /// 获取文件下载直链（转存后调用）
    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        guard let link = try await api.getDownloadLink(fid: fid, cookie: cookie) else {
            throw ApiError("获取下载链接失败")
        }
        return link
    }

    /// 夸克取直链（修复版）：
    ///  1) 每次转存落到「YunX临时转存」下的【唯一子目录 tr_<时间戳>_<随机>】，
    ///     使夸克 sharepage/save 去重键（to_pdir_fid）每次不同 → 永远生成新 fid。
    ///  2) 取链成功后【不立即删】，把临时子目录 fid 通过 DownloadLink.cleanupDirFid 带回，
    ///     由下载完成的 onComplete 回调删除，保证下载期间 fid 一直存活。
    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        let baseDir = try await ensureTempDir(cookie: cookie)

        // 唯一临时子目录：to_pdir_fid 每次不同 → 绕开夸克去重
        let subDirName = "\(QuarkConstants.TEMP_SUBDIR_PREFIX)\(Int(Date().timeIntervalSince1970 * 1_000_000))_\(Int.random(in: 0..<1_000_000))"
        guard let subDirFid = try await api.createFolder(name: subDirName, parentFid: baseDir, cookie: cookie) else {
            throw ApiError("创建临时转存目录失败")
        }

        let savedFid = try await transferFileTo(session: session, file: file, toDirFid: subDirFid, cookie: cookie)
        guard let link = try await api.getDownloadLink(fid: savedFid, cookie: cookie) else {
            throw ApiError("获取下载链接失败")
        }

        // 不在此删除！下载完成后再删整个子目录（含文件）
        return DownloadLink(
            fid: link.fid,
            filename: link.filename,
            downloadUrl: link.downloadUrl,
            size: link.size,
            cleanupDirFid: subDirFid,
            isHls: link.isHls,
            guestCookie: link.guestCookie
        )
    }

    /// 免转存取链（登录态）：不建临时目录、不转存，直接把分享凭证交给 file/download 换直链。
    /// 个别分享类型服务端仍要求「先转存再取链」，此时本方法会失败，由调用方回退到 getShareDownloadLink。
    func getShareDownloadLinkWithoutSave(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        guard let link = try await api.getShareDownloadLinkWithoutSave(
            fid: file.fid,
            fidToken: file.fidToken,
            shareId: session.shareId,
            stoken: session.stoken,
            cookie: cookie
        ) else {
            throw ApiError("获取下载链接失败")
        }
        return link
    }

    /// 游客取链（未登录）：不碰用户网盘，直接按分享参数打 download 接口，带回游客态 __pugs。
    /// 夸克只放行约 50MB 以内的小文件（超出报 23018）。
    func getGuestShareDownloadLink(session: ShareSession, file: ShareFile) async throws -> DownloadLink {
        guard let link = try await api.getGuestShareDownloadLink(
            fid: file.fid,
            fidToken: file.fidToken,
            shareId: session.shareId,
            stoken: session.stoken
        ) else {
            throw ApiError("获取下载链接失败")
        }
        return link
    }

    /// 转存分享文件到用户网盘指定目录（转存功能：不删除，长期保存）
    func saveToCloud(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        try await transferFileTo(session: session, file: file, toDirFid: toDirFid, cookie: cookie)
    }

    /// 转存到指定目录并轮询拿到新 fid（toDirFid 由调用方指定）
    private func transferFileTo(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        let taskId = try await api.saveShareFile(
            shareId: session.shareId,
            stoken: session.stoken,
            pdirFid: file.pdirFid,
            fid: file.fid,
            fidToken: file.fidToken,
            toPdirFid: toDirFid,
            cookie: cookie
        )
        guard let taskId = taskId else { throw ApiError("转存失败") }
        guard let savedFid = try await api.pollTask(taskId: taskId, cookie: cookie) else {
            throw ApiError("转存超时，请稍后重试")
        }
        return savedFid
    }

    /// 下载完成后清理：删除临时子目录（连同其中的转存文件）；失败不阻断
    func cleanupTempDir(dirFid: String, cookie: String) async {
        _ = try? await api.deleteFile(fid: dirFid, cookie: cookie)
    }
}
