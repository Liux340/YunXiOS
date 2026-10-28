/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：深链接文本提取（对应 util/DeepLinks.kt + util/LinkOpener.kt 的判定部分）。
 *
 * 只负责「从 URL / 分享文本里取出待处理的文本」，不碰网络也不碰界面状态：
 * 拿到的可能是分享链接、中文口令，或一整句带链接的文案 —— 统一交给
 * ShareLinkParser / 口令兜底链路自己认。
 *
 * ★ 与 Android 的差异（平台限制，非移植遗漏）：
 *   Android 用 activity-alias 直接注册各网盘域名（intent-filter），iOS 的 Universal Link
 *   必须由**域主**在 https://domain/.well-known/apple-app-site-association 放校验文件，
 *   第三方网盘域名（pan.quark.cn 等）我们无从托管，因此 iOS 侧的接管路径为：
 *     1) yunx:// 自有协议（本文件解析）；
 *     2) Share Extension「分享 → 云析」，把文本编码成 yunx://resolve?url=… 唤起主 App；
 *   两条最终都汇到 textFrom 同一条链路，行为与 Android 的 VIEW / SEND 一致。
 */

import Foundation

/// 深链接提取结果
enum DeepLinkOutcome: Equatable {
    /// 取到待解析文本（链接 / 口令 / 带链接文案）
    case text(String)
    /// 磁力链接：走下载页「添加下载任务」，不进解析页
    case magnet(String)
    /// 该输入不是可处理的深链接
    case ignored
    /// 命中了注册项，但用户在设置里关掉了它
    case disabled(LinkOpenTarget)
}

enum DeepLinks {

    /// 自有协议 scheme：`yunx://resolve?url=<编码后的分享链接>&pwd=<提取码>`
    static let schemePrefix = "yunx://"

    /// `yunx://` 里承载真实分享链接的参数名
    private static let paramURL = "url"

    /// `yunx://` 里可选的提取码参数名
    private static let paramPwd = "pwd"

    /// 磁力链接 scheme（与 Android 的 MagnetLink 口径一致：整串含参数原样返回）
    static let magnetPrefix = "magnet:"

    // MARK: - 入口

    /**
     * 从「点链接进来的 URL」取出待处理文本。
     *
     * - `yunx://`：拆出 url 参数并把 pwd 拼回链接；
     * - `magnet:`：整串原样返回（含参数）；
     * - 其它（https 直链等，来自 Share Extension 的链接分享）：原样返回。
     */
    static func text(fromURL url: URL) -> String? {
        text(fromRaw: url.absoluteString)
    }

    /// 字符串入口（纯逻辑，便于单测：不需要构造真实 URL）
    static func text(fromRaw raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if isMagnet(trimmed) { return trimmed }
        guard trimmed.lowercased().hasPrefix(schemePrefix) else { return trimmed }
        return viewText(trimmed)
    }

    /// Share Extension / 快捷指令带过来的纯文本（对应 Android 的 EXTRA_TEXT / PROCESS_TEXT）
    static func text(fromSharedText shared: String) -> String? {
        let trimmed = shared.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 磁力链接判定（大小写不敏感）
    static func isMagnet(_ value: String) -> Bool {
        value.lowercased().hasPrefix(magnetPrefix)
    }

    /**
     * 完整路由：提取 + 命中平台判定 + 应用设置里的「链接唤起」开关。
     *
     * ★ 这里的开关过滤等价 Android 的「启停 activity-alias」：Android 靠关组件让系统不再把
     *   该域名派给云析，iOS 无法动态改注册，故在**应用内**拦下并提示，效果一致（用户点了但
     *   我们不处理），差别是链接仍会唤起 App。
     * ★ `.magnet` 表示「识别为磁力且用户允许接管」：能不能真的下由上层决定
     *   （当前 iOS 版无 BT 内核，AppState 会提示并复制到剪贴板，不假装能下载）。
     * ★ @MainActor：要读 SettingsStore（主隔离），调用点都在 UI 层。
     */
    @MainActor
    static func route(url: URL, settings: SettingsStore) -> DeepLinkOutcome {
        guard let text = text(fromURL: url) else { return .ignored }
        return route(text: text, settings: settings)
    }

    /// 分享文本的路由（Share Extension 传入的文本）
    @MainActor
    static func route(text: String, settings: SettingsStore) -> DeepLinkOutcome {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .ignored }

        if isMagnet(value) {
            guard settings.linkOpen(.magnet) else { return .disabled(.magnet) }
            return .magnet(value)
        }

        guard let parsed = ShareLinkParser.parse(value) else {
            // 不是网盘链接：可能是中文口令或一整句文案，仍交给解析页做兜底识别
            let target = LinkOpenTarget.share
            guard settings.linkOpen(target) else { return .disabled(target) }
            return .text(value)
        }

        guard let target = LinkOpenTarget(platform: parsed.platform) else { return .text(value) }
        guard settings.linkOpen(target) else { return .disabled(target) }
        return .text(value)
    }

    // MARK: - yunx:// 拆解

    /// 自有协议：url 参数里才是真正的分享链接（URL 编码过），pwd 参数拼回链接
    private static func viewText(_ raw: String) -> String? {
        let url = queryParam(raw, name: paramURL).flatMap { urlDecode($0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if url.isEmpty { return nil }
        let pwd = queryParam(raw, name: paramPwd).flatMap { urlDecode($0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 提取码可以放在单独的 pwd 参数里：拼回链接（解析链路会从 ?pwd= 里认出来）
        if pwd.isEmpty || url.range(of: "pwd=", options: .caseInsensitive) != nil { return url }
        return url + (url.contains("?") ? "&pwd=\(pwd)" : "?pwd=\(pwd)")
    }

    /// 取查询参数（取第一个同名参数；值已编码，所以不担心值里出现裸 &）
    private static func queryParam(_ data: String, name: String) -> String? {
        guard let questionMark = data.firstIndex(of: "?") else { return nil }
        let query = String(data[data.index(after: questionMark)...])
        if query.isEmpty { return nil }
        for pair in query.split(separator: "&") {
            let segment = String(pair)
            let key = String(segment.prefix(while: { $0 != "=" }))
            if key == name, let eq = segment.firstIndex(of: "=") {
                let value = String(segment[segment.index(after: eq)...])
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// URL 解码（等价 Java `URLDecoder.decode(value, "UTF-8")`：先把裸 + 当空格，再 percent-decode；
    /// 失败时原样返回，与 Android 的 runCatching 口径一致）
    private static func urlDecode(_ value: String) -> String? {
        let plusAsSpace = value.replacingOccurrences(of: "+", with: " ")
        return plusAsSpace.removingPercentEncoding ?? value
    }
}
