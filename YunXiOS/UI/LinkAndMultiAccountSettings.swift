/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：设置页「链接唤起」与「多账号下载」两个子页
 * （对应 ui/screens/LinkOpenScreen.kt + MultiAccountDownloadScreen.kt）。
 *
 * ★ 与 Android 的语义差别（诚实标注，非移植遗漏）：
 *   Android 用 activity-alias 注册链接，关掉某项 = 禁用组件，系统就真的不再把那种链接派给云析；
 *   iOS 的注册写在 Info.plist / 域主 AASA 文件里，运行时改不了，所以这里的关火是**应用内拦截**：
 *   链接仍会唤起 App，但我们不处理它（DeepLinks.route 返回 .disabled 并提示）。
 *   用户看到的"接管范围"一致，实现层次不同。
 */

import SwiftUI

// MARK: - 链接唤起

struct LinkOpenSettingsView: View {

    @ObservedObject private var settings = SettingsStore.shared
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                ForEach(LinkOpenTarget.allCases) { target in
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(target.displayName, isOn: Binding(
                            get: { settings.linkOpen(target) },
                            set: { enabled in
                                settings.setLinkOpen(target, enabled: enabled)
                                appState.show("\(target.displayName)：\(enabled ? "已接管" : "不再处理")")
                            }
                        ))
                        Text(target.sample)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let note = target.availabilityNote {
                            Text(note)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            } header: {
                Text("由云析接管的链接类型")
            } footer: {
                Text("关闭后，这类链接即使打开了云析也不会被处理。iOS 无法像 Android 那样禁用系统级注册项，注册本身始终存在——这里的开关只决定「要不要接住它」。")
                    .font(.caption2)
            }

            Section {
                Text("iOS 上从外部拿分享链接的两条路径：\n1) yunx://resolve?url=… 自有协议；\n2) 在浏览器 / 其它 App 里点「分享 → 云析」。")
                    .font(.caption2)
                HStack {
                    Text("网盘域名直开（Universal Link）")
                    Spacer()
                    Text("受域主限制不可用")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("说明")
            }
        }
        .navigationTitle("链接唤起")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 多账号下载（实验性 C1 / C2）

struct MultiAccountDownloadSettingsView: View {

    @ObservedObject private var settings = SettingsStore.shared

    /// 开启前的二次风控确认（与上游一致：实验性开关不静默生效）
    @State private var pendingEnable: PendingToggle?

    enum PendingToggle {
        case c1
        case c2
    }

    /// C1 支持轮换的平台（与上游同口径：只覆盖「取链接口按参数收凭证」的平台）
    private let c1Platforms: [SharePlatform] = [.quark, .uc, .xunlei, .baidu, .c139, .pan115, .lanzou]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("多账号下载（按文件轮换账号取链）", isOn: Binding(
                        get: { settings.multiAccountDownload },
                        set: { turningOn($0, which: .c1) }
                    ))
                    HStack(spacing: 8) {
                        Text("绕开单账号的并发与限速限制")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ExperimentalBadge()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("单文件多源分片（依赖上一项）", isOn: Binding(
                        get: { settings.multiSourceDownload },
                        set: { turningOn($0, which: .c2) }
                    ))
                    .disabled(!settings.multiAccountDownload)
                    HStack(spacing: 8) {
                        Text("同一文件用多个账号各取一条直链，分片轮流交给不同源")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ExperimentalBadge()
                    }
                    Text("当前 iOS 版尚未实现多源分片调度，开启后不会生效（建议保持关闭）")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            } header: {
                Text("实验性")
            } footer: {
                Text("关闭「多账号下载」会同时关掉「单文件多源分片」。取链与下载请求头始终使用同一份凭证，避免直链与身份配成两个账号导致 CDN 412/403。")
                    .font(.caption2)
            }

            Section {
                ForEach(c1Platforms) { platform in
                    HStack {
                        PlatformBadge(platform: platform)
                        Text(platform.displayName)
                        Spacer()
                        Text(accountStatus(platform))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("支持轮换的平台（该平台已登录 ≥2 个账号才会轮换）")
            } footer: {
                Text("123 云盘 / 光鸭 / 蓝奏云优享版的凭证由各自仓库内部绑定主账号，本次未纳入轮换，它们的行为与开启前一致。")
                    .font(.caption2)
            }
        }
        .navigationTitle("多账号下载")
        .navigationBarTitleDisplayMode(.inline)
        .alert(pendingTitle, isPresented: Binding(
            get: { pendingEnable != nil },
            set: { if !$0 { pendingEnable = nil } }
        )) {
            Button("仍要开启") {
                switch pendingEnable {
                case .c1: settings.multiAccountDownload = true
                case .c2: settings.multiSourceDownload = true
                case nil: break
                }
                pendingEnable = nil
            }
            Button("取消", role: .cancel) { pendingEnable = nil }
        } message: {
            Text(pendingMessage)
        }
    }

    private func turningOn(_ value: Bool, which: PendingToggle) {
        if value {
            // 开启需要二次确认（实验性 + 风控风险）；关闭立即生效
            pendingEnable = which
        } else {
            switch which {
            case .c1: settings.multiAccountDownload = false
            case .c2: settings.multiSourceDownload = false
            }
        }
    }

    private var pendingTitle: String {
        switch pendingEnable {
        case .c1: return "开启多账号下载？"
        case .c2: return "开启单文件多源分片？"
        case nil: return "开启实验性功能？"
        }
    }

    private var pendingMessage: String {
        switch pendingEnable {
        case .c1:
            return "批量下载会按文件在不同账号之间轮换取链。若某个账号的 Cookie 已失效，那一次取链会失败并被计入失败数；风控严格的网盘可能对频繁切换账号敏感。"
        case .c2:
            return "同一文件会用多个账号各取一条直链、分片轮流下载。当前 iOS 版尚未实现该调度，开启后不会有效果。"
        case nil:
            return ""
        }
    }

    private func accountStatus(_ platform: SharePlatform) -> String {
        let count = AccountStore.shared.accountCount(for: platform)
        if count >= 2 { return "\(count) 个账号可轮换" }
        if count == 1 { return "仅 1 个账号" }
        return "未登录"
    }
}
