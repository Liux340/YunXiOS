/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：UC 网盘网络接口层与分享解析仓库。
 * 对应 Android 侧：
 *   - data/network/UCConstants.kt
 *   - data/network/UCApi.kt（含 UCCookieUtil）
 *   - data/repository/UCResolveRepository.kt
 * 仅复用 Core 层基础设施（HTTPClient / JSONValue / ApiError / ShareLinkParser / Models）。
 */

import Foundation

// MARK: - UCConstants

/// UC 网盘登录与 API 相关常量（依据 uckk.md）。
/// 与夸克网盘共用 API 结构，仅域名、参数、UA 不同。
enum UCConstants {

    /// UC 网盘客户端 User-Agent
    static let USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    /// 官方 Web 客户端页面（Referer/Origin 基准域名；UC OSS 直链按 Referer 档位限速）
    static let WEB_ORIGIN = "https://drive.uc.cn"
    /// 下载 OSS 直链必须携带的 Referer（缺它被 Callback 限速 ~100KB/s）
    static let DOWNLOAD_REFERER = "\(WEB_ORIGIN)/"
    /// WebView 登录页
    static let LOGIN_URL = "https://drive.uc.cn/"

    /// 提取 Cookie 的域名
    static let COOKIE_DOMAIN = "https://drive.uc.cn"

    /// 验证登录状态的接口
    static let ACCOUNT_INFO_URL = "https://drive.uc.cn/account/info"

    /// 业务 API 基础域名
    static let API_BASE = "https://pc-api.uc.cn"

    /// 获取分享 Token（与夸克路径相同，仅域名/pr 不同）
    static let SHARE_TOKEN_URL = "\(API_BASE)/1/clouddrive/share/sharepage/token?pr=UCBrowser&fr=pc"

    /// 获取分享文件列表（UC 用 v2/detail）
    static let SHARE_DETAIL_URL = "\(API_BASE)/1/clouddrive/share/sharepage/v2/detail?pr=UCBrowser&fr=pc"

    /// 转存分享详情（官方下载流程实际使用的文件列表接口，GET + query 带 stoken）。
    /// 该接口返回的 share_fid_token 与 stoken 绑定，download 才能通过 token 校验。
    static let TRANSFER_SHARE_DETAIL_URL = "\(API_BASE)/1/clouddrive/transfer_share/detail?entry=ft&fr=pc&pr=UCBrowser"

    /// 获取下载直链（官方抓包：entry=ft）
    static let DOWNLOAD_URL = "\(API_BASE)/1/clouddrive/file/download?entry=ft&fr=pc&pr=UCBrowser"

    /// 转码播放流（非会员视频下载绕过会员墙；返回 m3u8/fmp4 分片地址）。
    /// 注意：play 是个人云盘播放动作，不需要 entry=ft（分享转存通道参数），带它反而可能返回非 0。
    static let PLAY_URL = "\(API_BASE)/1/clouddrive/file/v2/play/project?pr=UCBrowser&fr=pc"

    /// 分享视频预览（GET，返回 data.play_info.url 原画 OSS 直链；走播放回调 checkplay，不换片）
    static let VIDEO_PREVIEW_URL = "\(API_BASE)/1/clouddrive/share/sharepage/video_preview"

    /// 根目录 fid
    static let DEFAULT_PDIR_FID = "0"

    /// 个人网盘文件列表 / 创建目录
    static let FILE_URL = "\(API_BASE)/1/clouddrive/file?pr=UCBrowser&fr=pc"

    /// 转存分享文件
    static let SAVE_URL = "\(API_BASE)/1/clouddrive/share/sharepage/save?pr=UCBrowser&fr=pc"

    /// 异步任务查询
    static let TASK_URL = "\(API_BASE)/1/clouddrive/task?pr=UCBrowser&fr=pc"

    /// 云盘文件列表（排序；抓包 pc-api.uc.cn/1/clouddrive/file/sort）
    static let CLOUD_FILE_SORT_URL = "\(API_BASE)/1/clouddrive/file/sort?pr=UCBrowser&fr=pc"

    /// 重命名文件（body: fid + file_name）
    static let RENAME_URL = "\(API_BASE)/1/clouddrive/file/rename?pr=UCBrowser&fr=pc"

    /// 移动文件（body: action_type=1 + to_pdir_fid + filelist）
    static let MOVE_URL = "\(API_BASE)/1/clouddrive/file/move?pr=UCBrowser&fr=pc"

    /// 创建分享（body: fid_list + title + url_type + passcode + expired_type + public_search）
    static let SHARE_CREATE_URL = "\(API_BASE)/1/clouddrive/share?pr=UCBrowser&fr=pc"

    /// 查询分享信息（body: share_id → share_url / passcode / pwd_id）
    static let SHARE_INFO_URL = "\(API_BASE)/1/clouddrive/share/password?pr=UCBrowser&fr=pc"

    /// UC 云盘客户端 UA（抓包：uc-cloud-drive Electron）
    static let CLOUD_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "uc-cloud-drive/1.6.1 Chrome/100.0.4896.160 Electron/18.3.5.16-b62cf9c50d Safari/537.36 Channel/ucpan_other_ch"

    /// 游客（未登录）链路专用 UA：uc-cloud-drive Electron 客户端。
    /// 取链与下字节都用它 —— 游客链路的风控比登录态严；登录态仍用 USER_AGENT。
    static let GUEST_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "uc-cloud-drive/2.5.20 Chrome/100.0.4896.160 Electron/18.3.5.4-b478491100 Safari/537.36 Channel/pckk_other_ch"

    /// 与 GUEST_UA 配套的 Sec-Ch-Ua（LinkSwift 分享页匿名链路同款头）
    static let GUEST_SEC_CH_UA = "\"Not=A?Brand\";v=\"99\", \"Chromium\";v=\"100\", \"Google Chrome\";v=\"100\""

    /// 云盘下载直链（抓包：?pr=UCBrowser&fr=pc&sys=win32&ve=1.6.1；个人云盘文件用）
    static let CLOUD_DOWNLOAD_URL = "\(API_BASE)/1/clouddrive/file/download"

    /// 删除文件（body: action_type=2 + filelist + exclude_fids）
    static let DELETE_URL = "\(API_BASE)/1/clouddrive/file/delete?pr=UCBrowser&fr=pc"

    /// 临时转存目录名
    static let TEMP_DIR_NAME = "YunX临时转存"

    /// 会话刷新探测接口：任意接口均可，用于重新下发 __puus
    static let CONFIG_URL = "\(API_BASE)/1/clouddrive/config?pr=UCBrowser&fr=pc"

    /// __puus 有效期约 3 小时，提前到 90 分钟刷新（对齐 AList 100±5 分钟）
    static let PUUS_REFRESH_INTERVAL_MS: Int64 = 90 * 60 * 1000

    /// 关键 Cookie 字段，缺失则视为未登录（UC 与夸克共用）
    static func isValidCookie(_ cookie: String?) -> Bool {
        guard let cookie = cookie else { return false }
        return cookie.contains("__pus=") && cookie.contains("__puus=")
    }
}

// MARK: - UCCookieUtil

/// UC Cookie 工具：合并/剥离 __puus、__pus（与夸克共用，对应 AList pkg/cookie）。
/// __puus 约 3 小时过期，是取链接口（/file/download 等）必须携带的有效会话字段。
enum UCCookieUtil {

    private static let tracked = ["__puus", "__pus"]

    /// 把响应 Set-Cookie 列表里的最新 __puus/__pus 合并回原 Cookie 串
    static func mergeFromSetCookies(original: String, setCookies: [String]) -> String {
        var cookie = original
        for sc in setCookies {
            let head = sc.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            let kv = head.trimmingCharacters(in: .whitespaces)
            guard let eq = kv.firstIndex(of: "="), eq != kv.startIndex else { continue }
            let name = String(kv[kv.startIndex..<eq])
            guard tracked.contains(name) else { continue }
            let value = String(kv[kv.index(after: eq)...])
            cookie = setOrReplace(cookie: cookie, name: name, value: value)
        }
        return cookie
    }

    /// 去掉 __puus，用于触发服务端重新下发（AList refreshPuus）
    static func withoutPuus(_ cookie: String) -> String {
        cookie.split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("__puus=") }
            .joined(separator: "; ")
    }

    private static func setOrReplace(cookie: String, name: String, value: String) -> String {
        var parts = cookie.split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let kv = "\(name)=\(value)"
        if let idx = parts.firstIndex(where: { $0.hasPrefix("\(name)=") }) {
            parts[idx] = kv
        } else {
            parts.append(kv)
        }
        return parts.joined(separator: "; ")
    }
}

// MARK: - 内部 JSON 辅助

/// 取数组：key 存在且值非 null 时返回数组，否则返回 nil（对应 Kotlin optJSONArray 的 null 语义）
private func jsonArrayOrNil(_ v: JSONValue, _ key: String) -> [JSONValue]? {
    guard v.has(key), !v.object(key).isNull else { return nil }
    return v.array(key)
}

/// 取字幕段/字符串数组的首元素非空值（对应 optJSONArray(0)?.takeIf { isNotBlank }）
private func firstNonBlankString(_ array: [JSONValue]) -> String? {
    guard let first = array.first else { return nil }
    let s = first.stringValue
    return s.isEmpty ? nil : s
}

/// 统一 SHA 无关的延时（对应 Kotlin delay(ms)）
private func delay(ms: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
}

// MARK: - UCApi

/// UC 网盘 API 封装：账号验证 + 分享解析 + 下载直链。
/// 与夸克 API 结构一致，仅域名/UA/pr 参数不同。
final class UCApi {

    /// Cookie 回写接收器（推荐由 UCAccountRepository 注入并落库）：
    /// 每次响应把 Set-Cookie 合并后的最新 Cookie 回调，保持 __puus/__pus 始终新鲜。
    var cookieSink: ((String) -> Void)?

    /// 游客态令牌 `__pugs`（未登录取链响应 Set-Cookie 下发，3 小时有效）。
    /// UC 下载层只认这一个 cookie：缺它 OSS 直链直接 403（RequestDeniedByCallback）。
    /// 进程内复用，登录态路径完全不受影响（只在 getGuestShareDownloadLink 里读写）。
    private(set) var guestPugs: String = ""

    // MARK: 账号

    /// 获取账号昵称（GET account/info）
    func fetchNickname(cookie: String) async throws -> String? {
        do {
            let resp = try await HTTPClient.api.get(UCConstants.ACCOUNT_INFO_URL, headers: [
                "Cookie": cookie,
                "User-Agent": UCConstants.USER_AGENT,
            ])
            guard resp.isSuccessful else { return nil }
            guard let json = JSONValue.parse(resp.body) else { return nil }
            guard json.bool("success") else { return nil }
            let nickname = json.object("data").string("nickname")
            return nickname.isEmpty ? nil : nickname
        } catch {
            return nil
        }
    }

    // MARK: 分享解析

    /// 获取分享 Token（POST sharepage/token）
    func getShareToken(shareId: String, pwd: String?, cookie: String) async throws -> ShareToken? {
        let body: [String: Any] = [
            "pwd_id": shareId,
            "passcode": pwd ?? "",
            "share_for_transfer": true,
        ]
        return try await parsePost(url: UCConstants.SHARE_TOKEN_URL, cookie: cookie, body: body) { data in
            ShareToken(
                stoken: data.string("stoken"),
                title: data.string("title"),
                firstFid: data.string("first_fid")
            )
        }
    }

    /// 获取转存分享文件列表（transfer_share/detail，官方下载流程）。
    /// GET + query 携带 stoken → 返回的 share_fid_token 与 stoken 绑定，download 才能通过校验。
    func getTransferShareFiles(
        shareId: String,
        stoken: String,
        pdirFid: String,
        cookie: String,
        page: Int = 1,
        size: Int = 50
    ) async throws -> [ShareFile]? {
        var url = UCConstants.TRANSFER_SHARE_DETAIL_URL
        url += "&pwd_id=" + shareId
        url += "&pdir_fid=" + pdirFid
        url += "&fetch_file_list=1"
        url += "&passcode="
        url += "&_page=\(page)"
        url += "&_size=\(size)"
        url += "&_fetch_total=1"
        url += "&_fetch_task=1"
        url += "&_fetch_share=1"
        url += "&_sort="
        url += "&stoken=" + urlEncode(stoken)

        let headers = [
            "Origin": "https://fast.uc.cn",
            "Referer": "https://fast.uc.cn/",
        ]
        return try await parseGet(url: url, cookie: cookie, extraHeaders: headers) { data in
            // 兼容 data.list 或 data.detail_info.list 两种结构
            let array = jsonArrayOrNil(data, "list")
                ?? jsonArrayOrNil(data.object("detail_info"), "list")
                ?? []
            return array.map { item in
                ShareFile(
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

    /// 获取分享文件列表（sharepage/v2/detail，UC 官方为 POST + JSON body）
    func getShareFiles(
        shareId: String,
        pwd: String?,
        pdirFid: String,
        cookie: String,
        page: Int = 1,
        size: Int = 50
    ) async throws -> [ShareFile]? {
        var body: [String: Any] = [
            "pwd_id": shareId,
            "passcode": pwd ?? "",
            "force": 0,
            "page": page,
            "size": size,
            "fetch_banner": 1,
            "fetch_share": 1,
            "fetch_total": 1,
            "sort": "file_type:asc,file_name:asc",
            "banner_platform": "other",
            "web_platform": "windows",
            "fetch_error_background": 1,
        ]
        // 子目录时追加 pdir_fid（根目录官方不传）
        if !pdirFid.isEmpty && pdirFid != UCConstants.DEFAULT_PDIR_FID {
            body["pdir_fid"] = pdirFid
        }
        let headers = [
            "Origin": "https://drive.uc.cn",
            "Referer": "https://drive.uc.cn/",
            "Content-Type": "application/json;charset=UTF-8",
        ]
        return try await parsePost(url: "\(UCConstants.SHARE_DETAIL_URL)&ve=2.5.20", cookie: cookie, body: body, extraHeaders: headers) { data in
            // UC v2/detail：文件列表在 data.detail_info.list（不是 data.list）
            let array = data.object("detail_info").array("list")
            return array.map { item in
                ShareFile(
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

    // MARK: 个人网盘 / 转存

    /// 个人网盘文件列表（/1/clouddrive/file）
    func getFileList(
        pdirFid: String,
        cookie: String,
        page: Int = 1,
        size: Int = 100
    ) async throws -> [ShareFile]? {
        let url = "\(UCConstants.FILE_URL)&pdir_fid=\(pdirFid)&page=\(page)&size=\(size)"
        return try await parseGet(url: url, cookie: cookie) { data in
            data.array("list").map { item in
                let fileName = item.string("file_name")
                let name = fileName.isEmpty ? item.string("fname") : fileName
                let fsize: Int64 = item.has("size") ? item.long("size") : item.long("fsize")
                let isdir = item.bool("dir") || item.int("isdir") == 1
                return ShareFile(
                    fid: item.string("fid"),
                    fname: name,
                    fsize: fsize,
                    isdir: isdir,
                    pdirFid: item.string("pdir_fid"),
                    fidToken: item.string("fid_token"),
                    modifyTime: item.string("modify_time")
                )
            }
        }
    }

    /// 创建目录（POST /1/clouddrive/file）→ 返回新目录 fid
    func createFolder(name: String, parentFid: String, cookie: String) async throws -> String? {
        let body: [String: Any] = [
            "pdir_fid": parentFid,
            "file_name": name,
            "dir_path": "",
            "dir_init_lock": false,
        ]
        return try await parsePost(url: UCConstants.FILE_URL, cookie: cookie, body: body) { data in
            data.string("fid")
        }
    }

    /// 转存分享文件（POST share/sharepage/save）→ 返回 task_id
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
        return try await parsePost(url: UCConstants.SAVE_URL, cookie: cookie, body: body) { data in
            let taskId = data.string("task_id")
            return taskId.isEmpty ? nil : taskId
        }
    }

    /// 轮询异步任务（最多 10 次，每次间隔 1s）→ 返回转存后的新 fid；超时返回 nil
    func pollTask(taskId: String, cookie: String) async throws -> String? {
        let url = "\(UCConstants.TASK_URL)&task_id=\(urlEncode(taskId))&retry_index=0"
        for _ in 0..<10 {
            var savedFid: String? = nil
            do {
                let resp = try await HTTPClient.api.get(url, headers: [
                    "Cookie": cookie,
                    "User-Agent": UCConstants.USER_AGENT,
                ])
                if let json = JSONValue.parse(resp.body), json.int("status") == 200, !json.object("data").isNull {
                    let data = json.object("data")
                    let finished = data.long("finished_at") > 0
                        || data.int("status") == 2
                        || data.int("task_status") == 2
                    if finished {
                        savedFid = firstNonBlankString(data.object("save_as").array("save_as_top_fids"))
                    }
                }
            } catch {
                savedFid = nil
            }
            if let savedFid = savedFid { return savedFid }
            await delay(ms: 1000)
        }
        return nil
    }

    // MARK: 下载直链

    /// 刷新会话 Cookie（对应 AList refreshPuus）：
    /// 剥离 __puus 后请求任意接口（/config），服务端会在 Set-Cookie 中重新下发 __puus/__pus。
    /// @return 合并了最新 __puus/__pus 的 Cookie；失败返回 nil（调用方应回退原 Cookie）。
    func refreshSession(cookie: String) async throws -> String? {
        do {
            let resp = try await HTTPClient.api.get(UCConstants.CONFIG_URL, headers: [
                "Cookie": UCCookieUtil.withoutPuus(cookie),
                "User-Agent": UCConstants.USER_AGENT,
                "Referer": UCConstants.DOWNLOAD_REFERER,
            ])
            let merged = UCCookieUtil.mergeFromSetCookies(original: cookie, setCookies: resp.setCookies)
            if merged != cookie { cookieSink?(merged) }
            return merged
        } catch {
            return nil
        }
    }

    /// UC 官方下载流程（抓包）：不需要先转存！
    /// POST file/download?entry=ft&fr=pc&pr=UCBrowser
    /// body: {"fids":[分享fid],"pwd_id":短码,"stoken":token接口返回,"fids_token":[分享fid_token]}
    func getShareDownloadLink(
        fid: String,
        fidToken: String,
        stoken: String,
        pwdId: String,
        cookie: String
    ) async throws -> DownloadLink? {
        let body: [String: Any] = [
            "fids": [fid],
            "pwd_id": pwdId,
            "stoken": stoken,
            "fids_token": [fidToken],
        ]
        let resp = try await HTTPClient.api.postJSON(UCConstants.DOWNLOAD_URL, headers: [
            "Cookie": cookie,
            "User-Agent": UCConstants.USER_AGENT,
            "Content-Type": "application/json",
        ], body: body)
        guard let json = JSONValue.parse(resp.body) else {
            throw ApiError("响应解析失败")
        }
        if json.int("status") != 200 {
            let message = json.string("message")
            throw ApiError(message.isEmpty ? "获取下载链接失败" : message)
        }
        guard let array = jsonArrayOrNil(json, "data"), let item = array.first else {
            throw ApiError("未返回下载链接")
        }
        let fileName = item.string("file_name")
        return DownloadLink(
            fid: item.string("fid"),
            filename: fileName.isEmpty ? item.string("filename") : fileName,
            downloadUrl: item.string("download_url"),
            size: item.long("size")
        )
    }

    /// 游客分享取链（未登录直链）：与 getShareDownloadLink 同一个端点、同一个 body
    /// （不带账号 Cookie，只带分享参数 + uc-cloud-drive 客户端 UA）。
    /// 下载层只认服务端随本次响应 Set-Cookie 下发的游客态 `__pugs`（缺它 CDN 直接 403）。
    /// @throws ApiError 需登录（31001）、超出游客大小上限（23018）、令牌失效（14001/41020）等
    func getGuestShareDownloadLink(
        fid: String,
        fidToken: String,
        stoken: String,
        pwdId: String
    ) async throws -> DownloadLink? {
        let body: [String: Any] = [
            "fids": [fid],
            "pwd_id": pwdId,
            "stoken": stoken,
            "fids_token": [fidToken],
        ]
        var headers: [String: String] = [
            "User-Agent": UCConstants.GUEST_UA,
            "Sec-Ch-Ua": UCConstants.GUEST_SEC_CH_UA,
            "Content-Type": "application/json",
        ]
        if !guestPugs.isEmpty { headers["Cookie"] = guestPugs }
        let resp = try await HTTPClient.api.postJSON(UCConstants.DOWNLOAD_URL, headers: headers, body: body)
        // 先取本次响应的 __pugs（与本次直链同响应绑定，不能用别的响应/上一次的值）
        let responsePugs = pugsFromSetCookies(resp.setCookies)
        if let responsePugs = responsePugs { guestPugs = responsePugs }
        guard let json = JSONValue.parse(resp.body) else {
            // 非 JSON（风控页/HTML 错误页）时带上 HTTP 状态码，便于分辨 401/403 与分享失效
            throw ApiError("响应解析失败（HTTP \(resp.statusCode)）")
        }
        let code = json.int("code")
        if json.int("status") != 200 && code != 0 {
            throw ApiError(guestErrorMessage(code: code, message: json.string("message")), code: code)
        }
        guard let array = jsonArrayOrNil(json, "data") else { throw ApiError("响应缺少 data") }
        guard let item = array.first else { throw ApiError("未返回下载链接") }
        let fileName = item.string("file_name")
        return DownloadLink(
            fid: item.string("fid"),
            filename: fileName.isEmpty ? item.string("filename") : fileName,
            downloadUrl: item.string("download_url"),
            size: item.long("size"),
            guestCookie: responsePugs ?? guestPugs
        )
    }

    /// 登录态下载直链（个人云盘/转存后文件，POST file/download）
    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink? {
        let body: [String: Any] = ["fids": [fid]]
        let resp = try await HTTPClient.api.postJSON(UCConstants.DOWNLOAD_URL, headers: [
            "Cookie": cookie,
            "User-Agent": UCConstants.USER_AGENT,
            "Content-Type": "application/json",
        ], body: body)
        guard let json = JSONValue.parse(resp.body) else {
            throw ApiError("响应解析失败")
        }
        if json.int("status") != 200 && json.int("code") != 0 {
            let message = json.string("message")
            throw ApiError(message.isEmpty ? "获取下载链接失败" : message, code: json.int("code"))
        }
        guard let array = jsonArrayOrNil(json, "data") else { throw ApiError("响应缺少 data") }
        guard let item = array.first else { throw ApiError("未返回下载链接") }
        let fileName = item.string("file_name")
        return DownloadLink(
            fid: item.string("fid"),
            filename: fileName.isEmpty ? item.string("filename") : fileName,
            downloadUrl: item.string("download_url"),
            size: item.long("size")
        )
    }

    // MARK: 云盘文件管理（UC 网盘功能）

    /// 网盘空间详情（/1/clouddrive/member：total_capacity / use_capacity，CLOUD_UA）
    func getQuota(cookie: String) async throws -> QuotaInfo? {
        let url = "https://pc-api.uc.cn/1/clouddrive/member?pr=UCBrowser&fr=pc&fetch_subscribe=true&_ch=home"
        do {
            let resp = try await HTTPClient.api.get(url, headers: [
                "Cookie": cookie,
                "User-Agent": UCConstants.CLOUD_UA,
                "Origin": "https://drive.uc.cn",
                "Referer": "https://drive.uc.cn/",
            ])
            guard let json = JSONValue.parse(resp.body), !json.object("data").isNull else { return nil }
            let data = json.object("data")
            return QuotaInfo(
                used: data.long("use_capacity"),
                total: data.long("total_capacity")
            )
        } catch {
            return nil
        }
    }

    /// 云盘下载直链（抓包：个人云盘文件用 CLOUD_DOWNLOAD_URL，非 entry=ft 分享通道）
    func cloudGetDownloadLink(fid: String, cookie: String) async throws -> DownloadLink? {
        let body: [String: Any] = ["fids": [fid]]
        let resp = try await HTTPClient.api.postJSON(UCConstants.CLOUD_DOWNLOAD_URL, headers: [
            "Cookie": cookie,
            "User-Agent": UCConstants.CLOUD_UA,
            "Origin": "https://drive.uc.cn",
            "Referer": "https://drive.uc.cn/",
            "Content-Type": "application/json;charset=UTF-8",
        ], body: body)
        guard let json = JSONValue.parse(resp.body) else {
            throw ApiError("响应解析失败")
        }
        if json.int("status") != 200 && json.int("code") != 0 {
            let message = json.string("message")
            throw ApiError(message.isEmpty ? "获取下载链接失败" : message, code: json.int("code"))
        }
        guard let array = jsonArrayOrNil(json, "data") else { throw ApiError("响应缺少 data") }
        guard let item = array.first else { throw ApiError("未返回下载链接") }
        let fileName = item.string("file_name")
        return DownloadLink(
            fid: item.string("fid"),
            filename: fileName.isEmpty ? item.string("filename") : fileName,
            downloadUrl: item.string("download_url"),
            size: item.long("size")
        )
    }

    /// 分享视频预览（原画直链，绕过非会员视频下载被换成宣传片的问题）。
    /// GET share/sharepage/video_preview？pwd_id/stoken/fid/fid_token →
    /// data.play_info.url（原画 OSS 直链）+ size。仅对分享态视频有意义（约 3 小时有效）。
    func getVideoPreview(
        pwdId: String,
        stoken: String,
        fid: String,
        fidToken: String,
        cookie: String
    ) async throws -> DownloadLink? {
        var url = UCConstants.VIDEO_PREVIEW_URL
        url += "?pr=UCBrowser&fr=h5"
        url += "&pwd_id=" + urlEncode(pwdId)
        url += "&stoken=" + urlEncode(stoken)
        url += "&fid=" + urlEncode(fid)
        url += "&fid_token=" + urlEncode(fidToken)
        do {
            let resp = try await HTTPClient.api.get(url, headers: [
                "Cookie": cookie,
                "User-Agent": UCConstants.USER_AGENT,
                "Origin": UCConstants.WEB_ORIGIN,
                "Referer": UCConstants.DOWNLOAD_REFERER,
                "Content-Type": "application/json",
            ])
            guard let json = JSONValue.parse(resp.body) else { return nil }
            if json.int("status") != 200 && json.int("code") != 0 { return nil }
            let playInfo = json.object("data").object("play_info")
            guard !playInfo.isNull else { return nil }
            let directUrl = playInfo.string("url")
            guard !directUrl.isEmpty else { return nil }
            return DownloadLink(
                fid: fid,
                filename: "",
                downloadUrl: directUrl,
                size: playInfo.long("size")
            )
        } catch {
            return nil
        }
    }

    /// UC 转码播放流（绕过非会员视频下载被换成宣传片的问题）。
    /// POST file/v2/play/project → data.video_list[].video_info.url（m3u8/fmp4）。
    /// 先试带 pr/fr 的主路径；失败则用裸路径重试。
    func getPlayLink(fid: String, cookie: String) async throws -> PlayLink? {
        if let link = try await playProject(url: UCConstants.PLAY_URL, fid: fid, cookie: cookie) {
            return link
        }
        return try await playProject(url: "\(UCConstants.API_BASE)/1/clouddrive/file/v2/play/project", fid: fid, cookie: cookie)
    }

    private func playProject(url: String, fid: String, cookie: String) async throws -> PlayLink? {
        let body: [String: Any] = [
            "fid": fid,
            "resolutions": "low,normal,high,super,2k,4k",
            "supports": "fmp4_av,m3u8,dolby_vision",
        ]
        do {
            let resp = try await HTTPClient.api.postJSON(url, headers: [
                "Cookie": cookie,
                "User-Agent": UCConstants.USER_AGENT,
                "Content-Type": "application/json;charset=UTF-8",
                "Origin": UCConstants.WEB_ORIGIN,
                "Referer": UCConstants.DOWNLOAD_REFERER,
            ], body: body)
            guard let json = JSONValue.parse(resp.body) else { return nil }
            if json.int("status") != 200 && json.int("code") != 0 { return nil }
            let list = json.object("data").array("video_list")
            for item in list {
                let info = item.object("video_info")
                let u = info.string("url")
                if u.isEmpty { continue }
                let format = info.string("format")
                return PlayLink(
                    url: u,
                    resolution: info.string("resolution"),
                    format: format,
                    isHls: u.contains(".m3u8") || format.lowercased().contains("m3u8")
                )
            }
            return nil
        } catch {
            return nil
        }
    }

    /// 删除文件（抓包：action_type=2 + filelist + exclude_fids）；返回 task_id
    func deleteFile(fid: String, cookie: String) async throws -> String? {
        let body: [String: Any] = [
            "action_type": 2,
            "filelist": [fid],
            "exclude_fids": [],
        ]
        return try await parsePost(url: UCConstants.DELETE_URL, cookie: cookie, body: body) { data in
            let taskId = data.string("task_id")
            return taskId.isEmpty ? nil : taskId
        }
    }

    /// 云盘文件列表（抓包 /1/clouddrive/file/sort，pdir_fid=0 根目录）
    /// 自动翻页：单页满 size 继续，封顶 100 页防异常死循环；默认单页 100（接口支持）。
    func listCloudFiles(
        pdirFid: String,
        cookie: String,
        page: Int = 1,
        size: Int = 100
    ) async throws -> [ShareFile]? {
        var all: [ShareFile] = []
        var p = page
        while true {
            var url = UCConstants.CLOUD_FILE_SORT_URL
            url += "&pdir_fid=" + pdirFid
            url += "&_page=\(p)"
            url += "&_size=\(size)"
            url += "&_fetch_total=1"
            url += "&_fetch_sub_dirs=0"
            url += "&_sort=file_type%3Aasc%2Cupdated_at%3Adesc"
            let headers = [
                "Origin": "https://drive.uc.cn",
                "Referer": "https://drive.uc.cn/",
                "User-Agent": UCConstants.CLOUD_UA,
            ]
            let files = try await parseGet(url: url, cookie: cookie, extraHeaders: headers) { data -> [ShareFile] in
                data.array("list").map { item in
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

    /// 重命名（抓包：POST file/rename）
    func renameFile(fid: String, newName: String, cookie: String) async throws -> Bool {
        let body: [String: Any] = [
            "fid": fid,
            "file_name": newName,
        ]
        do {
            let resp = try await HTTPClient.api.postJSON(UCConstants.RENAME_URL, headers: [
                "Cookie": cookie,
                "User-Agent": UCConstants.USER_AGENT,
                "Content-Type": "application/json",
            ], body: body)
            let json = JSONValue.parse(resp.body) ?? .null
            return json.int("status") == 200
        } catch {
            return false
        }
    }

    /// 移动（抓包：action_type=1 + to_pdir_fid + filelist）；返回 task_id
    func moveFile(fid: String, toPdirFid: String, cookie: String) async throws -> String? {
        let body: [String: Any] = [
            "action_type": 1,
            "to_pdir_fid": toPdirFid,
            "filelist": [fid],
            "exclude_fids": [],
        ]
        return try await parsePost(url: UCConstants.MOVE_URL, cookie: cookie, body: body) { data in
            let taskId = data.string("task_id")
            return taskId.isEmpty ? nil : taskId
        }
    }

    /// 创建分享（抓包：POST /1/clouddrive/share，url_type 1=无提取码 2=带提取码，
    /// expired_type 1永久/2一天/3七天/4三十天）。
    /// 注意：分享创建是异步任务——响应只有 data.task_id，必须轮询 /1/clouddrive/task 直到完成拿到 share_id。
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
            "title": title.isEmpty ? "分享文件" : title,
            "url_type": urlType,
            "expired_type": expiredType,
            "public_search": passcode.isEmpty ? 1 : 0,
        ]
        if !passcode.isEmpty { body["passcode"] = passcode }
        // 1) 创建分享 → task_id（异步，须轮询等待完成）
        let taskId = try await parsePost(url: UCConstants.SHARE_CREATE_URL, cookie: cookie, body: body) { data in
            let t = data.string("task_id")
            return t.isEmpty ? nil : t
        }
        guard let taskId = taskId else { return nil }
        // 2) 轮询 task 直到完成，取 share_id
        return try await pollShareTask(taskId: taskId, cookie: cookie)
    }

    /// 轮询分享创建任务（GET /1/clouddrive/task），返回 share_id；超时返回 nil
    private func pollShareTask(taskId: String, cookie: String) async throws -> String? {
        let url = "\(UCConstants.TASK_URL)&task_id=\(urlEncode(taskId))&retry_index=0"
        for _ in 0..<15 {
            var shareId: String? = nil
            do {
                let resp = try await HTTPClient.api.get(url, headers: [
                    "Cookie": cookie,
                    "User-Agent": UCConstants.USER_AGENT,
                ])
                if let json = JSONValue.parse(resp.body), json.int("status") == 200, !json.object("data").isNull {
                    let data = json.object("data")
                    let finished = data.long("finished_at") > 0 || data.int("status") == 2
                    if finished {
                        let sid = data.string("share_id")
                        if !sid.isEmpty { shareId = sid }
                    }
                }
            } catch {
                shareId = nil
            }
            if let shareId = shareId { return shareId }
            await delay(ms: 1000)
        }
        return nil
    }

    /// 查询分享信息（抓包：POST share/password body={share_id} → 链接/提取码/标题）
    func getShareInfo(shareId: String, cookie: String) async throws -> ShareInfo? {
        let body: [String: Any] = ["share_id": shareId]
        return try await parsePost(url: UCConstants.SHARE_INFO_URL, cookie: cookie, body: body) { data in
            ShareInfo(
                shareUrl: data.string("share_url"),
                passcode: data.string("passcode"),
                pwdId: data.string("pwd_id"),
                title: data.string("title"),
                expiredType: data.int("expired_type")
            )
        }
    }

    // MARK: 请求构造与响应解析

    /// POST JSON + parseData（合并 Set-Cookie 并回调 cookieSink）
    private func parsePost<T>(
        url: String,
        cookie: String,
        body: [String: Any],
        extraHeaders: [String: String] = [:],
        parser: (JSONValue) -> T
    ) async throws -> T {
        var headers: [String: String] = [
            "Cookie": cookie,
            "User-Agent": UCConstants.USER_AGENT,
            "Content-Type": "application/json",
        ]
        for (k, v) in extraHeaders { headers[k] = v }
        let resp = try await HTTPClient.api.postJSON(url, headers: headers, body: body)
        mergeCookieFromResponse(original: cookie, resp: resp)
        return try decode(resp, parser: parser)
    }

    /// GET + parseData（合并 Set-Cookie 并回调 cookieSink）
    private func parseGet<T>(
        url: String,
        cookie: String,
        extraHeaders: [String: String] = [:],
        parser: (JSONValue) -> T
    ) async throws -> T {
        var headers: [String: String] = [
            "Cookie": cookie,
            "User-Agent": UCConstants.USER_AGENT,
        ]
        for (k, v) in extraHeaders { headers[k] = v }
        let resp = try await HTTPClient.api.get(url, headers: headers)
        mergeCookieFromResponse(original: cookie, resp: resp)
        return try decode(resp, parser: parser)
    }

    /// 统一响应解析（对应 Kotlin parseData：非 JSON → 带 HTTP 码；status!=200 → 透传 message；缺 data → 抛错）
    private func decode<T>(_ resp: HTTPResponse, parser: (JSONValue) -> T) throws -> T {
        guard let json = JSONValue.parse(resp.body) else {
            throw ApiError("响应解析失败（HTTP \(resp.statusCode)）")
        }
        if json.int("status") != 200 {
            let message = json.string("message")
            throw ApiError(message.isEmpty ? "请求失败" : message)
        }
        let data = json.object("data")
        guard !data.isNull else { throw ApiError("响应缺少 data") }
        return parser(data)
    }

    /// 从响应 Set-Cookie 合并 __puus/__pus 回原 Cookie 并回调 cookieSink（保持会话新鲜）
    private func mergeCookieFromResponse(original: String, resp: HTTPResponse) {
        let setCookies = resp.setCookies
        if setCookies.isEmpty || original.isEmpty { return }
        let merged = UCCookieUtil.mergeFromSetCookies(original: original, setCookies: setCookies)
        if merged != original { cookieSink?(merged) }
    }

    /// 游客取链的服务端错误码 → 中文提示（错误码表对齐 panweb-parser 的 UC 适配器）
    private func guestErrorMessage(code: Int, message: String) -> String {
        switch code {
        case 31001: return "该分享需要登录 UC 网盘后才能下载"
        case 23018: return "该文件超出游客可获取的大小上限，请先登录 UC 网盘再下载"
        case 14001: return "分享已失效或提取码有误，请重新解析"
        case 41020: return "文件令牌已过期，请重新解析分享"
        default: return message.isEmpty ? "获取下载链接失败" : message
        }
    }

    /// 从响应 Set-Cookie 里取出游客态令牌，返回可直接当 Cookie 头用的 `__pugs=值`；没有则 nil
    private func pugsFromSetCookies(_ setCookies: [String]) -> String? {
        for sc in setCookies {
            let head = sc.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            let kv = head.trimmingCharacters(in: .whitespaces)
            if kv.hasPrefix("__pugs=") && kv.count > "__pugs=".count {
                return kv
            }
        }
        return nil
    }
}

// MARK: - UCResolveRepository

/// UC 分享解析仓库：token → 列表 → 转存临时目录 → 下载直链。
final class UCResolveRepository: ShareResolveRepository {

    private let api = UCApi()

    /// 常见视频扩展名（分享视频走 video_preview 原画直链绕过会员墙）
    private let videoExts: Set<String> = ["mp4", "mkv", "mov", "avi", "webm", "flv", "ts", "m3u8", "wmv", "rmvb"]

    init() {}

    private func isVideo(_ name: String) -> Bool {
        let ext = name.split(separator: ".").last.map { String($0).lowercased() } ?? ""
        return videoExts.contains(ext)
    }

    // MARK: ShareResolveRepository

    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        guard let parsed = ShareLinkParser.parse(link) else {
            throw ApiError("无法识别分享链接")
        }
        let effectivePwd = (pwd?.isEmpty == false) ? pwd : parsed.pwd
        guard let token = try await api.getShareToken(shareId: parsed.shareId, pwd: effectivePwd, cookie: cookie) else {
            throw ApiError("未获取到分享凭证")
        }
        return ShareSession(shareId: parsed.shareId, stoken: token.stoken, title: token.title)
    }

    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        // 必须用 transfer_share/detail（带 stoken），返回的 share_fid_token 与 stoken 绑定
        var all: [ShareFile] = []
        var page = 1
        while true {
            guard let batch = try await api.getTransferShareFiles(
                shareId: session.shareId,
                stoken: session.stoken,
                pdirFid: dirFid,
                cookie: cookie,
                page: page,
                size: 50
            ) else {
                throw ApiError("未获取到文件列表")
            }
            all += batch
            page += 1
            if batch.count != 50 || page > 100 { break }
        }
        return all
    }

    func ensureTempDir(cookie: String) async throws -> String {
        guard let rootFiles = try await api.getFileList(pdirFid: UCConstants.DEFAULT_PDIR_FID, cookie: cookie) else {
            throw ApiError("获取网盘目录失败")
        }
        if let dir = rootFiles.first(where: { $0.isdir && $0.fname == UCConstants.TEMP_DIR_NAME }) {
            return dir.fid
        }
        guard let fid = try await api.createFolder(name: UCConstants.TEMP_DIR_NAME, parentFid: UCConstants.DEFAULT_PDIR_FID, cookie: cookie) else {
            throw ApiError("创建临时目录失败")
        }
        return fid
    }

    func transferFile(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String {
        guard let taskId = try await api.saveShareFile(
            shareId: session.shareId,
            stoken: session.stoken,
            pdirFid: file.pdirFid,
            fid: file.fid,
            fidToken: file.fidToken,
            toPdirFid: toDirFid,
            cookie: cookie
        ) else {
            throw ApiError("转存失败")
        }
        guard let savedFid = try await api.pollTask(taskId: taskId, cookie: cookie) else {
            throw ApiError("转存超时，请稍后重试")
        }
        return savedFid
    }

    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        guard let link = try await api.getDownloadLink(fid: fid, cookie: cookie) else {
            throw ApiError("获取下载链接失败")
        }
        return link
    }

    /// UC 官方下载流程：无需转存！
    /// 直接用分享 fid + fid_token + stoken + pwd_id 调 download 接口取直链。
    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        // 视频：优先用分享态 video_preview 取**原画**直链（走播放回调 checkplay，不换片，绕过宣传片替换）
        if isVideo(file.fname) {
            if let preview = try await api.getVideoPreview(
                pwdId: session.shareId,
                stoken: session.stoken,
                fid: file.fid,
                fidToken: file.fidToken,
                cookie: cookie
            ) {
                return DownloadLink(
                    fid: file.fid,
                    filename: file.fname,
                    downloadUrl: preview.downloadUrl,
                    size: preview.size,
                    isHls: false
                )
            }
        }
        guard let link = try await api.getShareDownloadLink(
            fid: file.fid,
            fidToken: file.fidToken,
            stoken: session.stoken,
            pwdId: session.shareId,
            cookie: cookie
        ) else {
            throw ApiError("获取下载链接失败")
        }
        return link
    }

    /// 免转存取链（登录态）：UC 的 getShareDownloadLink 本身即免转存，行为一致。
    func getShareDownloadLinkWithoutSave(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        try await getShareDownloadLink(session: session, file: file, cookie: cookie)
    }

    /// 游客取链（未登录）：与登录态同一条 download 接口，只是不带账号 Cookie，
    /// 由服务端下发游客态 __pugs（UC 实测大文件也放行，不做大小限制）。
    /// 视频不走 video_preview —— 那条链路依赖登录态，这里直接取普通直链。
    func getGuestShareDownloadLink(session: ShareSession, file: ShareFile) async throws -> DownloadLink {
        guard let link = try await api.getGuestShareDownloadLink(
            fid: file.fid,
            fidToken: file.fidToken,
            stoken: session.stoken,
            pwdId: session.shareId
        ) else {
            throw ApiError("获取下载链接失败")
        }
        return link
    }

    /// 下载完成后清理临时转存目录（尽力而为，失败忽略）。
    func cleanupTempDir(dirFid: String, cookie: String) async {
        guard !dirFid.isEmpty else { return }
        _ = try? await api.deleteFile(fid: dirFid, cookie: cookie)
    }
}
