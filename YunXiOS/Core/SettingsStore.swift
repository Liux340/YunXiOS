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
