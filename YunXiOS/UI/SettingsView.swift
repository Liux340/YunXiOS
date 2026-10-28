/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：设置页（对应 ui/screens/SettingsScreen.kt + AboutScreen.kt）。
 */

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showResetConfirm = false

    /// 「链接唤起」的接管数量摘要
    private var linkOpenSummary: String {
        let on = LinkOpenTarget.allCases.filter { settings.linkOpen($0) }.count
        let total = LinkOpenTarget.allCases.count
        return on == total ? "全部接管" : "已接管 \(on)/\(total)"
    }

    var body: some View {
        NavigationView {
            Form {

                Section {
                    Stepper(
                        "最大并发下载数：\(settings.maxConcurrentDownloads)",
                        value: Binding(
                            get: { settings.maxConcurrentDownloads },
                            set: { settings.maxConcurrentDownloads = $0 }
                        ),
                        in: 1...10
                    )

                    Stepper(
                        "默认分片线程数：\(settings.defaultThreads)",
                        value: Binding(
                            get: { settings.defaultThreads },
                            set: { settings.defaultThreads = $0 }
                        ),
                        in: 1...32
                    )

                    Stepper(
                        "限速：\(settings.speedLimitKBps == 0 ? "不限速" : "\(settings.speedLimitKBps) KB/s")",
                        value: Binding(
                            get: { settings.speedLimitKBps },
                            set: { settings.speedLimitKBps = $0 }
                        ),
                        in: 0...102400,
                        step: 512
                    )

                    TextField("下载目录名", text: Binding(
                        get: { settings.downloadDirName },
                        set: { settings.downloadDirName = $0 }
                    ))
                } header: {
                    Text("下载")
                } footer: {
                    Text("任务保存到「文件」App → 我的 iPhone → 云析 → 下载目录。限速对分片下载生效，0 表示不限速。")
                }

                Section {
                    Toggle("多行显示文件名", isOn: Binding(
                        get: { settings.fileNameMultiLine },
                        set: { settings.fileNameMultiLine = $0 }
                    ))
                    Toggle("剪贴板自动识别", isOn: Binding(
                        get: { settings.clipboardDetect },
                        set: { settings.clipboardDetect = $0 }
                    ))
                } header: {
                    Text("外观与交互")
                }

                Section {
                    NavigationLink {
                        LinkOpenSettingsView().environmentObject(appState)
                    } label: {
                        HStack {
                            Text("链接唤起")
                            Spacer()
                            Text(linkOpenSummary).font(.caption).foregroundColor(.secondary)
                        }
                    }

                    NavigationLink {
                        MultiAccountDownloadSettingsView()
                    } label: {
                        HStack {
                            Text("多账号下载")
                            ExperimentalBadge()
                            Spacer()
                            Text(settings.multiAccountDownload ? "已开启" : "默认关闭")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("集成与提速")
                } footer: {
                    Text("「链接唤起」管理哪些分享链接由云析接住；「多账号下载」为实验性功能，需先在网盘页为同一平台登录多个账号。")
                }

                Section {
                    TextField("代理主机（留空为直连）", text: Binding(
                        get: { settings.proxyHost },
                        set: { settings.proxyHost = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                    TextField("代理端口", text: Binding(
                        get: { settings.proxyPort == 0 ? "" : String(settings.proxyPort) },
                        set: { settings.proxyPort = Int($0) ?? 0 }
                    ))
                    .keyboardType(.numberPad)
                } header: {
                    Text("网络")
                } footer: {
                    Text("仅支持 HTTP 代理；修改后立即生效。")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("开源协议")
                        Spacer()
                        Text("AGPL-3.0").foregroundColor(.secondary)
                    }
                    Link("上游项目 YunX", destination: URL(string: "https://github.com/CYQawa/YunX")!)
                } header: {
                    Text("关于")
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Text("清空全部账号与下载记录")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .alert("确认清空？", isPresented: $showResetConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { resetAll() }
            } message: {
                Text("将退出所有网盘账号并删除本地下载记录（已下载的文件不会被删除）。")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func resetAll() {
        for platform in SharePlatform.allCases {
            AccountStore.shared.logout(platform)
        }
        for task in DownloadManager.shared.tasks {
            DownloadManager.shared.remove(task.id)
        }
        appState.show("已清空账号与下载记录")
    }
}
