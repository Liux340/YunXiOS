/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：设置项唯一入口（对应 data/prefs/SettingsRepository.kt）。
 * 使用 UserDefaults 持久化，键名与 Android 侧保持一致语义。
 */

import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    // MARK: - 默认值

    enum Defaults {
        static let maxConcurrentDownloads = 3
        static let defaultThreads = 8
        static let defaultSpeedLimit = 0        // KB/s，0 表示不限速
        static let defaultDownloadDir = "下载"
    }

    private init() {}

    /// 全局下载并发任务数（1...10）
    var maxConcurrentDownloads: Int {
        get { clampInt(defaults.object(forKey: "max_concurrent_downloads") as? Int ?? Defaults.maxConcurrentDownloads, 1, 10) }
        set { defaults.set(clampInt(newValue, 1, 10), forKey: "max_concurrent_downloads"); objectWillChange.send() }
    }

    /// 单任务分片并发线程数（1...32）
    var defaultThreads: Int {
        get { clampInt(defaults.object(forKey: "default_threads") as? Int ?? Defaults.defaultThreads, 1, 32) }
        set { defaults.set(clampInt(newValue, 1, 32), forKey: "default_threads"); objectWillChange.send() }
    }

    /// 全局限速（KB/s，0 不限速）
    var speedLimitKBps: Int {
        get { max(0, defaults.object(forKey: "speed_limit_kbps") as? Int ?? Defaults.defaultSpeedLimit) }
        set { defaults.set(max(0, newValue), forKey: "speed_limit_kbps"); objectWillChange.send() }
    }

    /// 文件名多行显示
    var fileNameMultiLine: Bool {
        get { defaults.bool(forKey: "file_name_multi_line") }
        set { defaults.set(newValue, forKey: "file_name_multi_line"); objectWillChange.send() }
    }

    /// 剪贴板自动识别
    var clipboardDetect: Bool {
        get { defaults.object(forKey: "clipboard_detect") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "clipboard_detect"); objectWillChange.send() }
    }

    /// 下载保存目录（应用沙箱 Documents 下的相对目录）
    var downloadDirName: String {
        get { defaults.string(forKey: "download_dir_name") ?? Defaults.defaultDownloadDir }
        set { defaults.set(newValue, forKey: "download_dir_name"); objectWillChange.send() }
    }

    /// 已通过引导页
    var onboardingDone: Bool {
        get { defaults.bool(forKey: "onboarding_done") }
        set { defaults.set(newValue, forKey: "onboarding_done") }
    }

    // MARK: - 链接唤起（对应 Android LinkOpener 的组件启停意愿）

    /// 某个深链接注册项是否接管（默认开，与 Android 清单默认 enabled 一致）
    func linkOpen(_ target: LinkOpenTarget) -> Bool {
        guard let object = defaults.object(forKey: target.prefKey) else { return true }
        if let boolValue = object as? Bool { return boolValue }
        return (object as? NSNumber)?.boolValue ?? true
    }

    func setLinkOpen(_ target: LinkOpenTarget, enabled: Bool) {
        defaults.set(enabled, forKey: target.prefKey)
        objectWillChange.send()
    }

    // MARK: - 多账号下载（实验性 C1 / C2，对应 Android SettingsRepository）

    /// 多账号下载（**实验性**，代号 C1）：默认关。
    /// 批量下载按文件轮换该网盘的不同账号取链，绕开单账号并发/限速。
    var multiAccountDownload: Bool {
        get { defaults.bool(forKey: "multi_account_download") }
        set {
            defaults.set(newValue, forKey: "multi_account_download")
            // 关闭 C1 时强制关掉 C2（C2 依赖 C1）：口径与 Android 集中在这一处
            if !newValue { defaults.set(false, forKey: "multi_source_download") }
            objectWillChange.send()
        }
    }

    /// 单文件多源分片（**实验性**，代号 C2）：默认关，**依赖 multiAccountDownload**。
    var multiSourceDownload: Bool {
        get { defaults.bool(forKey: "multi_source_download") && multiAccountDownload }
        set {
            // C2 只能在 C1 开着时打开
            defaults.set(newValue && multiAccountDownload, forKey: "multi_source_download")
            objectWillChange.send()
        }
    }

    /// C2 是否真正生效（开关开着且 C1 也开着）
    func multiSourceActive() -> Bool { multiAccountDownload && multiSourceDownload }

    /// 代理主机
    var proxyHost: String {
        get { defaults.string(forKey: "proxy_host") ?? "" }
        set {
            defaults.set(newValue, forKey: "proxy_host")
            applyProxy()
        }
    }

    /// 代理端口
    var proxyPort: Int {
        get { defaults.object(forKey: "proxy_port") as? Int ?? 0 }
        set {
            defaults.set(newValue, forKey: "proxy_port")
            applyProxy()
        }
    }

    /// 按平台取分片线程数（对应 downloadThreadsFor）
    func downloadThreads(for platform: String) -> Int {
        let key = "download_threads_\(platform)"
        return clampInt(defaults.object(forKey: key) as? Int ?? defaultThreads, 1, 32)
    }

    func setDownloadThreads(_ value: Int, for platform: String) {
        defaults.set(clampInt(value, 1, 32), forKey: "download_threads_\(platform)")
    }

    func applyProxy() {
        let host = proxyHost.trimmingCharacters(in: .whitespaces)
        HTTPClient.proxy = ProxyConfig(host: host.isEmpty ? nil : host, port: proxyPort)
    }

    private func clampInt(_ value: Int, _ minValue: Int, _ maxValue: Int) -> Int {
        min(max(value, minValue), maxValue)
    }
}
