/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：百度网盘网络接口层 + 分享解析仓库。
 * 对应 Kotlin：
 *   - data/network/BaiduConstants.kt
 *   - data/network/BaiduApi.kt（含 BaiduApiException → ApiError）
 *   - data/repository/BaiduResolveRepository.kt
 *
 * 全程仅依赖 Foundation + 项目内 HTTPClient / JSONValue / ApiError / ShareLinkParser。
 */

import Foundation

// MARK: - 文件级辅助（对应 Kotlin String.isBlank / takeIf { it.isNotBlank() }）

/// 是否为空 / 全空白（对应 Kotlin isBlank）
private func trimmedIsEmpty(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// 非空白则返回原值，否则返回 nil（对应 Kotlin takeIf { it.isNotBlank() }）
private func nonBlankString(_ value: String) -> String? {
    trimmedIsEmpty(value) ? nil : value
}

// MARK: - 常量（对应 BaiduConstants.kt）

/// 百度网盘登录与 API 相关常量（依据抓包 + 文档）。
enum BaiduConstants {

    /// WebView 登录页（提取 BDUSS/STOKEN）
    static let LOGIN_URL = "https://pan.baidu.com/"

    /// 提取 Cookie 的域名
    static let COOKIE_DOMAIN = "https://pan.baidu.com"

    /// PC 网页 UA（share/verify、xpan/share、gettemplatevariable 使用）
    static let UA_WEB =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    /// 百度客户端 UA（yun/api/list、filemanager、locatedownload 使用）
    static let UA_NETDISK =
        "netdisk;12.24.6;piano;android-android;16;JSbridge4.4.0;jointBridge;1.1.0"

    /// 百度网盘统一 app_id
    static let APP_ID = "250528"

    /// 临时转存目录名（对齐抓包）
    static let TEMP_DIR_NAME = "YunX临时转存"

    /// 关键 Cookie 字段，缺失 BDUSS 则视为未登录
    static func isValidCookie(_ cookie: String?) -> Bool {
        guard let cookie = cookie else { return false }
        return cookie.contains("BDUSS=")
    }
}

// MARK: - 数据模型（对应 BaiduApi.kt 中的 BaiduShareList / BaiduTransferResult）

/// 百度网盘分享解析数据（xpan/share list 响应）。
struct BaiduShareList {
    let title: String
    let shareId: String
    let uk: String
    let files: [ShareFile]
}

/// 百度转存结果：转存后的新 fs_id + 新路径（locatedownload 用路径）。
struct BaiduTransferResult {
    let fsId: String
    let path: String
}

// MARK: - BaiduApi

/// 百度网盘 API 封装（Cookie 认证）：登录态 BDUSS 经 Cookie 携带；
/// 分享解析链路 share/verify → xpan/share → share/transfer → filemetas。
/// 全部基于抓包字段，错误码用 errno（0 表示成功）判定。
///
/// 说明：Kotlin 原实现里部分方法（listDir / createDir / deleteFile / listCloudFiles /
/// renameFile / moveFiles / deleteFiles / getQuota / fetchNickname / getBdstoken）用
/// runCatching 吞掉异常并返回默认值；此处签名统一为 async throws（与任务要求一致），
/// 但内部以 do/catch 保持 Kotlin 的「失败返回默认值」语义。
final class BaiduApi {

    /// bdstoken 缓存（登录态内长期有效）
    private var cachedBdstoken: String?

    init() {}

    // ---------- 账号 ----------

    /// 获取昵称（gettemplatevariable 的 username 字段）；失败返回 nil
    func fetchNickname(cookie: String) async throws -> String? {
        guard let result = await templateVariable(cookie: cookie, fields: "[\"username\"]") else {
            return nil
        }
        return nonBlankString(result.string("username"))
    }

    /// 获取 bdstoken（gettemplatevariable，带缓存）
    func getBdstoken(cookie: String) async throws -> String? {
        if let cached = cachedBdstoken, !trimmedIsEmpty(cached) {
            return cached
        }
        guard let result = await templateVariable(cookie: cookie, fields: "[\"bdstoken\"]") else {
            return nil
        }
        guard let token = nonBlankString(result.string("bdstoken")) else { return nil }
        cachedBdstoken = token
        return token
    }

    /// gettemplatevariable 通用实现（失败返回 nil，对应 Kotlin runCatching）
    private func templateVariable(cookie: String, fields: String) async -> JSONValue? {
        let url = "https://pan.baidu.com/api/gettemplatevariable" +
            "?clienttype=0&app_id=\(BaiduConstants.APP_ID)&web=1&fields=" +
            urlEncode(fields)
        do {
            let resp = try await HTTPClient.api.get(url, headers: [
                "Cookie": cookie,
                "User-Agent": BaiduConstants.UA_WEB
            ])
            if !resp.isSuccessful { return nil }
            let json = JSONValue.parse(resp.text) ?? .null
            if json.int("errno") != 0 { return nil }
            let result = json.object("result")
            return result.isNull ? nil : result
        } catch {
            return nil
        }
    }

    // ---------- 分享解析 ----------

    /// 验证提取码：POST /share/verify，返回 randsk（URL 编码形式，直接作为 sekey 使用）。
    /// 失败抛 ApiError（携带服务端 errmsg）。
    func verifyShare(surl: String, pwd: String, cookie: String) async throws -> String {
        let json = try await postFormJson(
            "https://pan.baidu.com/share/verify?surl=\(surl)",
            headers: [
                "Cookie": cookie,
                "User-Agent": BaiduConstants.UA_WEB,
                "Referer": "https://pan.baidu.com/s/\(surl)"
            ],
            form: ["pwd": pwd, "vcode_str": "", "vcode": ""]
        )
        try checkErrno(json, "验证提取码失败")
        guard let randsk = nonBlankString(json.string("randsk")) else {
            throw ApiError("未返回分享密钥")
        }
        return randsk
    }

    /// 列出分享文件：GET xpan/share?method=list。
    /// 修复（文档《百度网盘解析问题修复》）：
    ///  - 顶层 root=1，子目录 root=0（root=1 下百度忽略 dir → 子文件夹进不去）；
    ///  - 子目录（root=0）必须携带 BDCLND cookie（= verify 返回的 randsk），否则 errno=2；
    ///  - sekey 为空（公共分享）时省略 &sekey= 参数；
    ///  - 无 sekey 却 errno!=0 → 实为加密分享，抛「该分享需要提取码」。
    /// - Parameter dir: 分享内目录路径，根目录传 "/"（子目录传 "/folder"）
    func listShare(surl: String, sekey: String, dir: String, cookie: String, page: Int = 1) async throws -> BaiduShareList {
        let isRoot = trimmedIsEmpty(dir) || dir == "/"
        let root = isRoot ? "1" : "0"
        let sekeyPart = sekey.isEmpty ? "" : "&sekey=\(sekey)"
        let dirParam = trimmedIsEmpty(dir) ? "/" : dir
        let url = "https://pan.baidu.com/rest/2.0/xpan/share?method=list" +
            "&shorturl=\(surl)&page=\(page)&num=100&root=\(root)&dir=" +
            urlEncode(dirParam) +
            sekeyPart
        // 子目录(root=0)必须携带 BDCLND（= verify 的 randsk），否则 errno=2；顶层(root=1)无需
        let authCookie = (!sekey.isEmpty && !cookie.contains("BDCLND="))
            ? "\(cookie); BDCLND=\(sekey)"
            : cookie
        let json = try await getJson(url, headers: [
            "Cookie": authCookie,
            "User-Agent": BaiduConstants.UA_WEB,
            "Referer": "https://pan.baidu.com/s/\(surl)"
        ])
        let errno = json.int("errno")
        if errno != 0 {
            // 无 sekey 却失败 → 多数情况是加密分享，提示用户索取提取码。
            // 但 errno=-6 是「未登录/身份验证失败」（游客模式下常见），单独区分。
            if trimmedIsEmpty(sekey) {
                throw ApiError(errno == -6
                    ? "该分享需要提取码，或需要登录百度网盘（errno=\(errno)）"
                    : "该分享需要提取码（errno=\(errno)）")
            }
            try checkErrno(json, "获取分享文件列表失败")
        }
        var files: [ShareFile] = []
        for item in json.array("list") {
            let isdir = item.string("isdir") == "1"
            let path = item.string("path")
            files.append(ShareFile(
                // 目录用 path 作 fid（导航传参），文件用 fs_id（转存传参）
                fid: isdir ? path : item.string("fs_id"),
                fname: item.string("server_filename"),
                fsize: item.long("size"),
                isdir: isdir,
                pdirFid: path,
                fidToken: "",
                modifyTime: item.string("server_mtime")
            ))
        }
        return BaiduShareList(
            title: json.string("title"),
            shareId: json.string("share_id"),
            uk: json.string("uk"),
            files: files
        )
    }

    // ---------- 个人网盘 / 转存 ----------

    /// 创建目录（个人网盘根目录下），返回是否成功。
    /// 官方新建文件夹用 api/create?a=commit（对齐抓包）：
    /// filemanager?opera=mkdir 在纯 Cookie 认证下恒 errno=2（接口校验路径不同）。
    func createDir(path: String, cookie: String) async throws -> Bool {
        guard let bdstoken = try await getBdstoken(cookie: cookie) else { return false }
        // UA 用 netdisk 客户端 + Referer yun.baidu.com/disk/main + body 完整参数
        let body = "path=\(urlEncode(path))&isdir=1&size&block_list=%5B%5D&method=post&dataType=json"
        let url = "https://pan.baidu.com/api/create?a=commit&channel=chunlei&web=1" +
            "&app_id=\(BaiduConstants.APP_ID)&clienttype=0&bdstoken=\(bdstoken)"
        do {
            let json = try await postRawJson(url, headers: [
                "Cookie": cookie,
                "User-Agent": BaiduConstants.UA_NETDISK,
                "Referer": "https://yun.baidu.com/disk/main",
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"
            ], body: body)
            return json.int("errno") == 0
        } catch {
            return false
        }
    }

    /// 列出个人网盘目录（检查临时转存目录是否存在），返回子项 path 集合
    func listDir(dir: String, cookie: String) async throws -> [String] {
        let url = "https://yun.baidu.com/api/list?clienttype=0&app_id=\(BaiduConstants.APP_ID)" +
            "&web=1&order=time&desc=1&dir=" + urlEncode(dir) + "&num=100&page=1"
        do {
            let json = try await getJson(url, headers: [
                "Cookie": cookie,
                "User-Agent": BaiduConstants.UA_NETDISK
            ])
            if json.int("errno") != 0 { return [] }
            return json.array("list").map { $0.string("path") }
        } catch {
            return []
        }
    }

    /// 转存分享文件到指定目录（同步返回结果）。
    /// - Returns: 转存后的新 fs_id + 新路径
    func transfer(
        shareId: String,
        uk: String,
        sekey: String,
        fsId: String,
        toDir: String,
        cookie: String
    ) async throws -> BaiduTransferResult {
        guard let bdstoken = try await getBdstoken(cookie: cookie) else {
            throw ApiError("获取 bdstoken 失败，请重新登录")
        }
        let url = "https://pan.baidu.com/share/transfer?shareid=\(shareId)&from=\(uk)" +
            "&channel=chunlei&sekey=\(sekey)&ondup=newcopy&web=1&app_id=\(BaiduConstants.APP_ID)" +
            "&bdstoken=\(bdstoken)&clienttype=0"
        // verify 响应会 Set-Cookie: BDCLND=<randsk>，transfer 必须携带（分享验证标识），
        // 缺失会 errno=2；BDCLND 值即 sekey（randsk），手动补齐
        let authCookie = cookie.contains("BDCLND=") ? cookie : "\(cookie); BDCLND=\(sekey)"
        let json = try await postFormJson(url, headers: [
            "Cookie": authCookie,
            "User-Agent": BaiduConstants.UA_WEB,
            "Origin": "https://pan.baidu.com",
            "Referer": "https://pan.baidu.com/s/",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"
        ], form: [
            "fsidlist": "[\"\(fsId)\"]",
            "path": toDir
        ])
        try checkErrno(json, "转存失败")
        let extra = json.object("extra")
        let first = extra.array("list").first
        guard let fsIdNew = first.flatMap({ nonBlankString($0.string("to_fs_id")) }) else {
            throw ApiError("转存失败：未返回新文件")
        }
        let pathNew = first.flatMap({ nonBlankString($0.string("to")) }) ?? "\(toDir)/"
        return BaiduTransferResult(fsId: fsIdNew, path: pathNew)
    }

    // ---------- 下载直链 ----------

    /// 获取高速下载直链（官方 locatedownload 接口，对齐 MoePal 抓包）：
    /// POST d.pcs.baidu.com/rest/2.0/pcs/file?method=locatedownload&path=<转存后完整路径>。
    /// 响应 urls[] 按 rank 返回多个候选 CDN 直链（自带 sign/expires，无需计算）：
    ///  - rank1 常为 d2-ant.baidu.com（encrypt=1 加密通道，内容需 AES-CTR 解密，且部分网络 TLS 握手失败）
    ///  - rank2+ 为 appallNN.baidupcs.com（encrypt=0 明文通道，可直接 Range 下载）
    /// 仅需 BDUSS 登录态 + 手机 UA；psign 为写死常量，rand/devuid 复用抓包常量即可。
    /// - Returns: 选中的 appall 明文直链；全部候选不可用时抛异常
    func locateDownload(path: String, cookie: String) async throws -> String {
        let time = Int(Date().timeIntervalSince1970)
        // 抓包常量：psign 写死；rand/devuid/cuid/deviceid 有 BDUSS 登录态时可直接复用
        let url = "https://d.pcs.baidu.com/rest/2.0/pcs/file" +
            "?method=locatedownload" +
            "&app_id=\(BaiduConstants.APP_ID)" +
            "&clienttype=17&ver=4.0" +
            "&ant=1&check_blue=1&es=1&esl=1&apn_id=1_-1" +
            "&freeisp=0&queryfree=0&use=1&dtype=1&eck=1&ehps=1" +
            "&err_ver=1.0&network_type=WIFI&channel=0" +
            "&path=\(urlEncode(path))" +
            "&time=\(time)" +
            "&rand=5ed606e9da222cde0474cdf70eda884b" +
            "&devuid=0F1E9FC2E084472DA5A61C4CF4C759AF" +
            "&cuid=0F1E9FC2E084472DA5A61C4CF4C759AF" +
            "&deviceid=348642637967375013" +
            "&psign=860a071f77c860e8cea06e4e54c518f3" +
            "&version=2.2.111.34&version_app=12.24.6&vip=0"
        let json = try await postRawJson(url, headers: [
            "Cookie": cookie,
            "User-Agent": BaiduConstants.UA_NETDISK,
            "Content-Type": "application/x-www-form-urlencoded"
        ], body: "0")
        try checkErrno(json, "获取高速下载链接失败")
        // 直链候选选择：优先 encrypt=0（明文，无需解密）的 https 直链（appall01/02）；
        // rank1 的 d2-ant 为 encrypt=1 加密通道（需 AES-CTR 解密且部分网络 TLS 握手失败），直接排除；
        // 全部为加密通道时退回第一个 https 候选（仍有尝试价值），最后兜底第一个候选。
        let candidates = json.array("urls").filter { !trimmedIsEmpty($0.string("url")) }
        // Kotlin optInt("encrypt", 1)：字段缺失时默认 1（非明文）
        let decryptable = candidates.filter { encryptValue($0) == 0 }
        let ordered = decryptable.filter { $0.string("url").hasPrefix("https") }
            + decryptable.filter { !$0.string("url").hasPrefix("https") }
        if let directUrl = ordered.first?.string("url") {
            return directUrl
        }
        if let directUrl = candidates.first(where: { $0.string("url").hasPrefix("https") })?.string("url") {
            return directUrl
        }
        if let directUrl = candidates.first?.string("url") {
            return directUrl
        }
        throw ApiError("未返回下载链接")
    }

    /// 获取下载直链：filemetas（按 fs_id 取链，个人网盘文件无 path 时使用）。
    /// 注意：该 dlink（d.pcs.baidu.com）在文件被删除后立即失效，仅限文件仍存在时下载。
    func fileMetasDlink(fsId: String, cookie: String) async throws -> String {
        guard let bdstoken = try await getBdstoken(cookie: cookie) else {
            throw ApiError("获取 bdstoken 失败，请重新登录")
        }
        let fsids = urlEncode("[\"\(fsId)\"]")
        let url = "https://pan.baidu.com/api/filemetas?dlink=1&fsids=\(fsids)&bdstoken=\(bdstoken)" +
            "&clienttype=0&app_id=\(BaiduConstants.APP_ID)&web=1"
        let json = try await getJson(url, headers: [
            "Cookie": cookie,
            "User-Agent": BaiduConstants.UA_WEB
        ])
        try checkErrno(json, "获取下载链接失败")
        guard let dlink = json.array("info").first.flatMap({ nonBlankString($0.string("dlink")) }) else {
            throw ApiError("未返回下载链接")
        }
        return dlink
    }

    /// 删除个人网盘文件（转存后清理），按完整路径删除
    func deleteFile(path: String, cookie: String) async throws -> Bool {
        guard let bdstoken = try await getBdstoken(cookie: cookie) else { return false }
        let url = "https://pan.baidu.com/api/filemanager?async=2&onnest=fail&opera=delete" +
            "&bdstoken=\(bdstoken)&newVerify=1&clienttype=0&app_id=\(BaiduConstants.APP_ID)&web=1"
        do {
            let json = try await postFormJson(url, headers: [
                "Cookie": cookie,
                "User-Agent": BaiduConstants.UA_NETDISK,
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"
            ], form: ["filelist": "[\"\(path)\"]"])
            return json.int("errno") == 0
        } catch {
            return false
        }
    }

    // ---------- 云盘文件管理（百度网盘功能） ----------

    /// 列出个人网盘目录（自动翻页，返回该目录下全部文件）。
    /// 单页 num=100（官方 page_size 上限）；本页未满 100 视为末页，封顶 100 页防异常死循环。
    /// 返回 ShareFile（fid=fs_id，fidToken=绝对路径 path）
    func listCloudFiles(dir: String, cookie: String) async throws -> [ShareFile] {
        var all: [ShareFile] = []
        var page = 1
        while true {
            let url = "https://yun.baidu.com/api/list?clienttype=0&app_id=\(BaiduConstants.APP_ID)" +
                "&web=1&order=time&desc=1&dir=" + urlEncode(dir) + "&num=100&page=\(page)"
            var pageFiles: [ShareFile] = []
            do {
                let json = try await getJson(url, headers: [
                    "Cookie": cookie,
                    "User-Agent": BaiduConstants.UA_NETDISK,
                    "X-Requested-With": "XMLHttpRequest",
                    "Referer": "https://yun.baidu.com/disk/main"
                ])
                if json.int("errno") == 0 {
                    for item in json.array("list") {
                        pageFiles.append(ShareFile(
                            fid: item.string("fs_id"),
                            fname: item.string("server_filename"),
                            fsize: item.long("size"),
                            isdir: item.int("isdir") == 1,
                            pdirFid: dir,
                            fidToken: item.string("path"),
                            modifyTime: item.string("server_mtime")
                        ))
                    }
                }
            } catch {
                pageFiles = []
            }
            // 空页（含单页请求失败）视为已到末页，停止翻页
            if pageFiles.isEmpty { break }
            all += pageFiles
            // 本页未满 100 → 已是最后一页；封顶 100 页防止异常死循环
            if pageFiles.count < 100 || page >= 100 { break }
            page += 1
        }
        return all
    }

    /// 重命名（filemanager opera=rename，按完整路径）
    func renameFile(path: String, newName: String, cookie: String) async throws -> Bool {
        guard let bdstoken = try await getBdstoken(cookie: cookie) else { return false }
        let filelist = "[{\"path\":\"\(path)\",\"newname\":\"\(newName)\"}]"
        let url = "https://yun.baidu.com/api/filemanager?async=0&onnest=fail&opera=rename" +
            "&bdstoken=\(bdstoken)&clienttype=0&app_id=\(BaiduConstants.APP_ID)&web=1"
        do {
            let json = try await postFormJson(url, headers: [
                "Cookie": cookie,
                "User-Agent": BaiduConstants.UA_NETDISK,
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": "https://yun.baidu.com/disk/main"
            ], form: ["filelist": filelist])
            return json.int("errno") == 0
        } catch {
            return false
        }
    }

    /// 移动单个/多个文件（filemanager opera=move，path→dest，newname 保持原名）
    func moveFiles(paths: [String], dest: String, cookie: String) async throws -> Bool {
        guard let bdstoken = try await getBdstoken(cookie: cookie) else { return false }
        let items = paths.map { p -> String in
            let name = p.components(separatedBy: "/").last ?? ""
            return "{\"path\":\"\(p)\",\"dest\":\"\(dest)\",\"newname\":\"\(name)\"}"
        }.joined(separator: ",")
        let url = "https://pan.baidu.com/api/filemanager?async=2&onnest=fail&opera=move" +
            "&bdstoken=\(bdstoken)&clienttype=0&app_id=\(BaiduConstants.APP_ID)&web=1"
        do {
            let json = try await postFormJson(url, headers: [
                "Cookie": cookie,
                "User-Agent": BaiduConstants.UA_NETDISK,
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": "https://yun.baidu.com/disk/main"
            ], form: ["filelist": "[\(items)]"])
            return json.int("errno") == 0
        } catch {
            return false
        }
    }

    /// 批量删除（filemanager opera=delete，按完整路径）
    func deleteFiles(paths: [String], cookie: String) async throws -> Bool {
        guard let bdstoken = try await getBdstoken(cookie: cookie) else { return false }
        let list = "[" + paths.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let url = "https://pan.baidu.com/api/filemanager?async=2&onnest=fail&opera=delete" +
            "&bdstoken=\(bdstoken)&newVerify=1&clienttype=0&app_id=\(BaiduConstants.APP_ID)&web=1"
        do {
            let json = try await postFormJson(url, headers: [
                "Cookie": cookie,
                "User-Agent": BaiduConstants.UA_NETDISK,
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "Referer": "https://yun.baidu.com/disk/main"
            ], form: ["filelist": list])
            return json.int("errno") == 0
        } catch {
            return false
        }
    }

    /// 百度创建分享结果。
    /// - Parameter expiredType: 服务端返回的有效期（0 永久 / 1 一天 / 7 七天 / 30 三十天）；
    ///   响应未返回该字段时为 nil，由调用方回退到用户所选值（别用 0 兜底——0 是「永久有效」，
    ///   会把创建失败静默显示成永久）。
    struct BaiduShareResult {
        let link: String
        let pwd: String
        let shareId: String
        let expiredType: Int?
    }

    /// 创建分享（share/set，按 fs_id 列表 + 有效期 period + 4 位提取码）
    /// - Parameter period: 百度 API 的有效期**字面值**：0=永久、1=一天、7=七天、30=三十天。
    ///   ⚠️ 不是 UI 中性码（1/2/3/4），调用方必须先用 ShareExpire.baiduPeriod 转换。
    func createShare(fsIds: [String], period: Int, pwd: String, cookie: String) async throws -> BaiduShareResult {
        guard let bdstoken = try await getBdstoken(cookie: cookie) else {
            throw ApiError("获取 bdstoken 失败，请重新登录")
        }
        let fidList = "[" + fsIds.joined(separator: ",") + "]"
        let url = "https://pan.baidu.com/share/set?channel=chunlei&web=1" +
            "&app_id=\(BaiduConstants.APP_ID)&bdstoken=\(bdstoken)&clienttype=0"
        let json = try await postFormJson(url, headers: [
            "Cookie": cookie,
            "User-Agent": BaiduConstants.UA_NETDISK,
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Referer": "https://yun.baidu.com/disk/main"
        ], form: [
            "fid_list": fidList,
            "schannel": "4",
            "channel_list": "[]",
            "period": "\(period)",
            "pwd": pwd
        ])
        try checkErrno(json, "创建分享失败")
        var link = json.string("shorturl")
        if trimmedIsEmpty(link) { link = json.string("link") }
        guard !trimmedIsEmpty(link) else { throw ApiError("未返回分享链接") }
        // 用「存在且为数字」判定：字段缺失 / 显式 null / 非数字一律回 nil，
        // 交给调用方回退到用户所选值（optInt 会把它们变成 0，而 0 是「永久有效」）。
        var expiredType: Int?
        if let raw = (json.raw as? [String: Any])?["expiredType"], let number = raw as? NSNumber {
            expiredType = number.intValue
        }
        return BaiduShareResult(
            link: link,
            pwd: pwd,
            shareId: json.string("shareid"),
            expiredType: expiredType
        )
    }

    // ---------- 网盘空间详情 ----------

    /// 网盘空间详情（GET yun.baidu.com/api/quota：total / used）
    func getQuota(cookie: String) async throws -> QuotaInfo? {
        let version = Int(Date().timeIntervalSince1970 * 1000)
        let url = "https://yun.baidu.com/api/quota?clienttype=0&app_id=\(BaiduConstants.APP_ID)" +
            "&web=1&channel=chunlei&version=\(version)"
        do {
            let json = try await getJson(url, headers: [
                "Cookie": cookie,
                "User-Agent": BaiduConstants.UA_NETDISK,
                "X-Requested-With": "XMLHttpRequest",
                "Referer": "https://yun.baidu.com/disk/main"
            ])
            if json.int("errno") != 0 { return nil }
            return QuotaInfo(used: json.long("used"), total: json.long("total"))
        } catch {
            return nil
        }
    }

    // ---------- 公共 ----------

    /// 发起 GET 并解析 JSON（对应 Kotlin executeJson 之前的请求构造）
    private func getJson(_ url: String, headers: [String: String]) async throws -> JSONValue {
        let resp = try await HTTPClient.api.get(url, headers: headers)
        return try executeJson(resp)
    }

    /// 发起表单 POST 并解析 JSON
    private func postFormJson(
        _ url: String,
        headers: [String: String],
        form: [String: String]
    ) async throws -> JSONValue {
        let resp = try await HTTPClient.api.postForm(url, headers: headers, form: form)
        return try executeJson(resp)
    }

    /// 发起原始 body 的 POST（用于 body 非标准表单的场景：createDir 的裸 size、locatedownload 的 "0"）
    private func postRawJson(_ url: String, headers: [String: String], body: String) async throws -> JSONValue {
        var headers = headers
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        }
        var request = try HTTPClient.api.makeRequest(url, method: "POST", headers: headers)
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await HTTPClient.api.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiError("响应异常")
        }
        var normalized: [String: [String]] = [:]
        for (key, value) in http.allHeaderFields {
            normalized["\(key)".lowercased(), default: []].append("\(value)")
        }
        return try executeJson(HTTPResponse(statusCode: http.statusCode, body: data, headers: normalized))
    }

    /// 解析响应体为 JSON（对应 Kotlin executeJson）
    private func executeJson(_ response: HTTPResponse) throws -> JSONValue {
        let body = response.text
        if body.isEmpty {
            throw ApiError("请求失败：响应为空")
        }
        guard let json = JSONValue.parse(body) else {
            throw ApiError("响应解析失败")
        }
        return json
    }

    /// 校验 errno（对应 Kotlin checkErrno）
    private func checkErrno(_ json: JSONValue, _ fallback: String) throws {
        let errno = json.int("errno")
        if errno != 0 {
            // 常见：errno=-12 提取码错误 / 403 分享已失效 / 31066 文件不存在
            var msg = json.string("err_msg")
            if trimmedIsEmpty(msg) { msg = json.string("show_msg") }
            if trimmedIsEmpty(msg) { msg = fallback }
            throw ApiError("\(msg)（errno=\(errno)）")
        }
    }

    /// 取 encrypt 字段（缺省视为 1，对应 Kotlin optInt("encrypt", 1)）
    private func encryptValue(_ item: JSONValue) -> Int {
        item.has("encrypt") ? item.int("encrypt") : 1
    }
}

// MARK: - BaiduResolveRepository

/// 百度分享解析仓库：verify 拿 sekey → xpan/share 列文件 → 转存临时目录（自动创建，失败回退根目录）
/// → locatedownload 拿 appall 高速链 → 立即删除临时转存。
/// 全部基于抓包链路（share/verify → xpan/share list → share/transfer → locatedownload）。
/// appall 直链 URL 自带签名、删除转存后仍有效，故取链成功后立即删除临时转存（失败不阻断）。
final class BaiduResolveRepository: ShareResolveRepository {

    private let api = BaiduApi()

    /// surl -> sekey（verify 返回的 randsk）
    private var sekeys: [String: String] = [:]

    /// surl -> (share_id, uk)，由列表接口返回（转存必需）
    private var shareInfos: [String: (shareId: String, uk: String)] = [:]

    init() {}

    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession {
        guard let parsed = ShareLinkParser.parse(link) else {
            throw ApiError("无法识别百度分享链接")
        }
        let surl = parsed.shareId
        // 修复：公共分享（pwd 为空）不强制提取码——跳过 verify，sekey 置空，
        // listShare 将不带 sekey 直接列出（抓包实证：公共分享无需 sekey/Cookie 即 errno=0）
        let providedPwd = pwd.flatMap { nonBlankString($0) }
        let effectivePwd = providedPwd ?? parsed.pwd
        let sekey: String
        if let effectivePwd = effectivePwd, !trimmedIsEmpty(effectivePwd) {
            sekey = try await api.verifyShare(surl: surl, pwd: effectivePwd, cookie: cookie)
        } else {
            sekey = ""
        }
        sekeys[surl] = sekey
        return ShareSession(shareId: surl, stoken: sekey, title: "")
    }

    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile] {
        let sekey = trimmedIsEmpty(session.stoken)
            ? (sekeys[session.shareId] ?? "")
            : session.stoken
        // 顶层 dirFid 为空/"/"；子目录 dirFid 为目录 path（如 /folder）
        var all: [ShareFile] = []
        var page = 1
        var result: BaiduShareList
        repeat {
            result = try await api.listShare(
                surl: session.shareId,
                sekey: sekey,
                dir: dirFid,
                cookie: cookie,
                page: page
            )
            all += result.files
            page += 1
        } while result.files.count == 100 && page <= 100
        // 缓存 share_id/uk（转存需要）
        shareInfos[session.shareId] = (shareId: result.shareId, uk: result.uk)
        return all
    }

    func ensureTempDir(cookie: String) async throws -> String {
        let dir = "/\(BaiduConstants.TEMP_DIR_NAME)"
        // 已存在则直接复用；不存在则创建（web UA 已修正）；创建失败回退根目录（鲁棒性）
        let list = (try? await api.listDir(dir: "/", cookie: cookie)) ?? []
        let exists = list.contains(dir)
        let created: Bool
        if exists {
            created = true
        } else {
            created = (try? await api.createDir(path: dir, cookie: cookie)) ?? false
        }
        return created ? dir : "/"
    }

    func transferFile(
        session: ShareSession,
        file: ShareFile,
        toDirFid: String,
        cookie: String
    ) async throws -> String {
        let info = try await requireShareInfo(session: session, cookie: cookie)
        let result = try await api.transfer(
            shareId: info.shareId,
            uk: info.uk,
            sekey: session.stoken,
            fsId: file.fid,
            toDir: toDirFid,
            cookie: cookie
        )
        return result.fsId
    }

    /// 个人网盘文件直链（filemetas）
    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink {
        let dlink = try await api.fileMetasDlink(fsId: fid, cookie: cookie)
        return DownloadLink(fid: fid, filename: "", downloadUrl: dlink, size: 0)
    }

    /// 百度取直链：转存临时目录（自动创建，失败回退根目录）→ locatedownload 拿 appall 高速链 → 立即删除临时转存（失败不阻断）
    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        let info = try await requireShareInfo(session: session, cookie: cookie)
        let dirPath = try await ensureTempDir(cookie: cookie)
        let transferred = try await api.transfer(
            shareId: info.shareId,
            uk: info.uk,
            sekey: session.stoken,
            fsId: file.fid,
            toDir: dirPath,
            cookie: cookie
        )
        // locatedownload 按转存后的完整路径取链，返回 appallNN.baidupcs.com CDN 直链
        // （自带 sign/expires，删除转存后仍有效；仅需 BDUSS + 手机 UA 即可满速下载）
        let dlink = try await api.locateDownload(path: transferred.path, cookie: cookie)
        // appall 直链不依赖转存文件存活：取链成功后立即删除临时转存，网盘不留残留
        await deleteTransferred(path: transferred.path, cookie: cookie)
        return DownloadLink(
            fid: transferred.fsId,
            filename: file.fname,
            downloadUrl: dlink,
            size: file.fsize
        )
    }

    /// 百度无「免转存取链」链路，回退到常规转存取链（与协议默认实现一致）。
    func getShareDownloadLinkWithoutSave(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        try await getShareDownloadLink(session: session, file: file, cookie: cookie)
    }

    /// 百度取链依赖 BDUSS 登录态，游客模式不支持（与协议默认实现一致）。
    func getGuestShareDownloadLink(session: ShareSession, file: ShareFile) async throws -> DownloadLink {
        throw YunXError.notLoggedIn
    }

    /// 下载完成后清理临时转存目录（按目录完整路径删除）。
    func cleanupTempDir(dirFid: String, cookie: String) async {
        let path = trimmedIsEmpty(dirFid) ? "/\(BaiduConstants.TEMP_DIR_NAME)" : dirFid
        _ = try? await api.deleteFile(path: path, cookie: cookie)
    }

    /// 删除转存文件（失败不阻断）；转存在临时目录时，删完文件后尝试删空目录
    private func deleteTransferred(path: String, cookie: String) async {
        _ = try? await api.deleteFile(path: path, cookie: cookie)
        let tempDir = "/\(BaiduConstants.TEMP_DIR_NAME)"
        if path.hasPrefix("\(tempDir)/") {
            _ = try? await api.deleteFile(path: tempDir, cookie: cookie)
        }
    }

    /// 取 share_id/uk：优先用列表接口缓存的，否则先列一次根目录
    private func requireShareInfo(session: ShareSession, cookie: String) async throws -> (shareId: String, uk: String) {
        if let info = shareInfos[session.shareId] { return info }
        let sekey = trimmedIsEmpty(session.stoken)
            ? (sekeys[session.shareId] ?? "")
            : session.stoken
        let result = try await api.listShare(surl: session.shareId, sekey: sekey, dir: "/", cookie: cookie)
        let info = (shareId: result.shareId, uk: result.uk)
        shareInfos[session.shareId] = info
        return info
    }
}
