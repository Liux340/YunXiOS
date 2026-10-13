/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：解析页状态机（对应 ui/viewmodel/ResolveViewModel.kt）。
 * 流程：分享链接 → 取会话 → 列目录 → 取直链（免转存 / 转存 / 游客）→ 入队下载。
 */

import Foundation
import SwiftUI

/// 下载请求头（按平台给出 UA / Referer，保证 CDN 防盗链放行）
enum DownloadHeaders {

    static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    static func headers(for platform: SharePlatform, cookie: String) -> [String: String] {
        var headers: [String: String] = [:]
        switch platform {
        case .quark:
            headers["User-Agent"] = QuarkConstants.API_USER_AGENT
            headers["Referer"] = QuarkConstants.DOWNLOAD_REFERER
        case .uc:
            headers["User-Agent"] = UCConstants.USER_AGENT
            headers["Referer"] = UCConstants.DOWNLOAD_REFERER
        case .baidu:
            headers["User-Agent"] = BaiduConstants.UA_NETDISK
            headers["Referer"] = "https://pan.baidu.com/"
        case .pan115:
            headers["User-Agent"] = Pan115Constants.WEB_UA
            headers["Referer"] = Pan115Constants.DOWNLOAD_REFERER
        case .pan123:
            headers["User-Agent"] = Pan123Constants.WEB_UA
            headers["Referer"] = Pan123Constants.DOWNLOAD_REFERER
        case .guangya:
            headers["User-Agent"] = GuangYaConstants.WEB_UA
            headers["Referer"] = GuangYaConstants.DOWNLOAD_REFERER
        case .lanzou:
            headers["User-Agent"] = LanzouConstants.WEB_UA
        case .ilanzou:
            headers["User-Agent"] = ILanzouConstants.WEB_UA
            headers["Referer"] = ILanzouConstants.DOWNLOAD_REFERER
        case .xunlei:
            headers["User-Agent"] = XunleiConstants.WEB_UA
            headers["Referer"] = XunleiKouling.REFERER
        case .c139, .github:
            headers["User-Agent"] = desktopUA
        }
        if !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        return headers
    }
}

@MainActor
final class ResolveViewModel: ObservableObject {

    /// 直链弹窗状态
    struct LinkDialog: Identifiable {
        let id = UUID()
        let fileName: String
        let size: Int64
        let link: DownloadLink
        let platform: SharePlatform
        let headers: [String: String]
        let directory: String
    }

    @Published var input: String = ""
    @Published var isWorking = false
    @Published var statusText: String = ""
    @Published var errorMessage: String?
    @Published var platform: SharePlatform?
    @Published var shareTitle: String = ""
    @Published var files: [ShareFile] = []
    @Published var linkDialog: LinkDialog?
    @Published var busyFileId: String?

    private var session: ShareSession?
    private var dirStack: [String] = []
    private var dirFid: String = "0"
    private var directoryPath: [String] = []

    private let accounts = AccountStore.shared
    private let registry = PlatformRegistry.shared

    var canGoBack: Bool { !dirStack.isEmpty }

    var breadcrumb: String {
        guard let platform = platform else { return "" }
        let parts = [platform.displayName, shareTitle] + directoryPath
        return parts.filter { !$0.isEmpty }.joined(separator: " / ")
    }

    // MARK: - 解析入口

    func parseAndOpen() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "请先粘贴分享链接"
            return
        }
        guard let parsed = ShareLinkParser.parse(text) else {
            errorMessage = "无法识别分享链接（支持夸克 / UC / 迅雷 / 百度 / 139 / 123 / 115 / 光鸭 / 蓝奏云 / 蓝奏云优享版）"
            return
        }
        guard let repository = registry.repository(for: parsed.platform) else {
            errorMessage = "暂不支持该平台"
            return
        }

        errorMessage = nil
        isWorking = true
        statusText = "正在获取分享信息…"
        platform = parsed.platform
        defer { isWorking = false; statusText = "" }

        do {
            let cookie = accounts.credential(for: parsed.platform)
            let session = try await repository.createSession(link: text, pwd: parsed.pwd, cookie: cookie)
            self.session = session
            self.shareTitle = session.title
            self.dirStack = []
            self.directoryPath = []
            self.dirFid = parsed.platform.rootFid
            statusText = "正在读取文件列表…"
            try await loadFiles(repository: repository)
        } catch {
            errorMessage = message(of: error)
            files = []
        }
    }

    // MARK: - 目录导航

    func open(_ file: ShareFile) async {
        guard file.isdir, let repository = currentRepository() else { return }
        isWorking = true
        statusText = "正在读取目录…"
        defer { isWorking = false; statusText = "" }
        do {
            dirStack.append(dirFid)
            directoryPath.append(file.fname)
            dirFid = file.fid
            try await loadFiles(repository: repository)
        } catch {
            errorMessage = message(of: error)
        }
    }

    func goBack() async {
        guard let repository = currentRepository(), let previous = dirStack.popLast() else { return }
        isWorking = true
        statusText = "正在读取目录…"
        defer { isWorking = false; statusText = "" }
        if !directoryPath.isEmpty { directoryPath.removeLast() }
        dirFid = previous
        do {
            try await loadFiles(repository: repository)
        } catch {
            errorMessage = message(of: error)
        }
    }

    private func loadFiles(repository: ShareResolveRepository) async throws {
        guard let session = session else { return }
        let cookie = accounts.credential(for: platform ?? .quark)
        files = try await repository.listFiles(session: session, dirFid: dirFid, cookie: cookie)
    }

    private func currentRepository() -> ShareResolveRepository? {
        guard let platform = platform else { return nil }
        return registry.repository(for: platform)
    }

    // MARK: - 取直链

    func requestDownload(_ file: ShareFile) async {
        guard let repository = currentRepository(), let session = session, let platform = platform else { return }
        errorMessage = nil
        isWorking = true
        statusText = "正在获取下载直链…"
        busyFileId = file.id
        defer { isWorking = false; statusText = ""; busyFileId = nil }

        let cookie = accounts.credential(for: platform)
        let loggedIn = accounts.isLoggedIn(platform)

        do {
            let link: DownloadLink
            if loggedIn {
                if platform == .quark {
                    // 夸克优先免转存取链，失败再回退「转存 → 取链」（与 Android 一致）
                    do {
                        link = try await repository.getShareDownloadLinkWithoutSave(session: session, file: file, cookie: cookie)
                    } catch {
                        link = try await repository.getShareDownloadLink(session: session, file: file, cookie: cookie)
                    }
                } else {
                    link = try await repository.getShareDownloadLink(session: session, file: file, cookie: cookie)
                }
            } else {
                // 游客态：目前夸克 / UC 支持
                link = try await repository.getGuestShareDownloadLink(session: session, file: file)
            }

            let directory = ([shareTitle] + directoryPath)
                .filter { !$0.isEmpty }
                .joined(separator: "/")
            linkDialog = LinkDialog(
                fileName: link.filename.isEmpty ? file.fname : link.filename,
                size: link.size > 0 ? link.size : file.fsize,
                link: link,
                platform: platform,
                headers: DownloadHeaders.headers(for: platform, cookie: cookie),
                directory: directory
            )
        } catch {
            errorMessage = message(of: error)
        }
    }

    /// 把直链加入下载队列
    func enqueue(_ dialog: LinkDialog) {
        DownloadManager.shared.enqueue(
            link: dialog.link,
            platform: dialog.platform,
            relativeDirectory: dialog.directory,
            headers: dialog.headers
        )
        linkDialog = nil
        AppStateToast.show("已加入下载：\(dialog.fileName)")
    }

    func copyLink(_ dialog: LinkDialog) {
        UIPasteboard.general.string = dialog.link.downloadUrl
        AppStateToast.show("直链已复制")
    }

    // MARK: - 工具

    private func message(of error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
