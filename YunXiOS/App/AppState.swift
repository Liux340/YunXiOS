/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：全局状态容器（对应 Android 侧 MainScreen 手工组装的各仓库/管理器）。
 */

import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    let settings = SettingsStore.shared
    let accounts = AccountStore.shared
    let downloadManager = DownloadManager.shared

    /// 解析页输入框内容（供全局回填，例如剪贴板识别 / 收藏点击）
    @Published var resolveInput: String = ""

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
