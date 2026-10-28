/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：全局状态容器（对应 Android 侧 MainScreen 手工组装的各仓库/管理器）。
 */

import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppState: ObservableObject {

    let settings = SettingsStore.shared
    let accounts = AccountStore.shared
    let downloadManager = DownloadManager.shared

    /// 解析页输入框内容（供全局回填，例如剪贴板识别 / 收藏点击）
    @Published var resolveInput: String = ""

    /**
     * 深链接待办（对应 Android MainActivity 收到 intent 后的路由）：
     * 点链接 / Share Extension 分享进来的链接文本写到这里，由解析页消费并自动解析。
     * ★ 自动解析由目标页面自己判断（见 ResolveView 的 onReceive），
     *   避免"页面还没挂载就抢跑解析"。
     */
    struct DeepLinkRequest: Equatable {
        let text: String
        let token: Int
    }

    @Published var pendingDeepLink: DeepLinkRequest?

    /// 深链接自增令牌：同一句话重复进来（比如连点两次链接）也要被当成一次新的消费请求
    private var linkToken = 0

    /// 收到深链接文本（路由已在 DeepLinks.route 里做完开关过滤）。
    /// ★ 磁力链接：iOS 侧没有可用的 BT 下载内核（Android 靠 Gopeed 引擎，本项目未引入），
    ///   因此识别到但不假装能下——给出明确提示并把原文放进剪贴板，交由用户处理。
    func handleDeepLink(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if DeepLinks.isMagnet(trimmed) {
            UIPasteboard.general.string = trimmed
            show("iOS 版暂无磁力下载内核，磁力链接已复制到剪贴板")
            return
        }
        guard ShareLinkParser.parse(trimmed) != nil else {
            // 基线没有口令 / 整段文案的兜底解析链路，识别不出就直接提示
            UIPasteboard.general.string = trimmed
            show("链接无法识别，已复制到剪贴板可手动粘贴")
            return
        }
        linkToken += 1
        pendingDeepLink = DeepLinkRequest(text: trimmed, token: linkToken)
    }

    func consumeDeepLink(token: Int) {
        if pendingDeepLink?.token == token { pendingDeepLink = nil }
    }

    /// 全局 Snackbar 文案（对应 Android SnackbarController）
    @Published var toast: String?

    func show(_ message: String) {
        toast = message
        let current = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self?.toast == current { self?.toast = nil }
        }
    }

    init() {
        AppStateToast.delegate = self
    }

    /// 按平台返回解析仓库
    func repository(for platform: SharePlatform) -> ShareResolveRepository? {
        PlatformRegistry.shared.repository(for: platform)
    }

    /// 返回平台当前登录 Cookie / 凭证（未登录返回空串）
    func cookie(for platform: SharePlatform) -> String {
        accounts.cookie(for: platform)
    }

    /// 是否为「游客可解析」：夸克与 UC 未登录也可取链
    func canUseGuest(_ platform: SharePlatform) -> Bool {
        platform == .quark || platform == .uc || platform == .lanzou || platform == .ilanzou
    }
}
