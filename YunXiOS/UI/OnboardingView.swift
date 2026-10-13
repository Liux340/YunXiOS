/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：首次启动引导（对应 ui/screens/OnboardingScreen.kt + SafetyNoticeDialog）。
 */

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(YunXTheme.brand)
                        .frame(maxWidth: .infinity)

                    Text("云析 · YunX")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity)

                    Text("粘贴分享链接，直接高速下载")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)

                    Group {
                        featureRow(icon: "link", title: "分享链接解析",
                                   detail: "识别夸克 / UC / 迅雷 / 百度 / 139 / 123 / 115 / 光鸭 / 蓝奏云 / 蓝奏云优享版 分享链接，自动匹配提取码")
                        featureRow(icon: "bolt.horizontal", title: "高速下载",
                                   detail: "Range 分片并发 + 断点续传，可按平台单独设置线程数")
                        featureRow(icon: "lock.shield", title: "凭证安全",
                                   detail: "Cookie / JWT 经 AES-GCM 加密后存入 Keychain 保护的本地存储")
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("免责声明", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text("本项目仅供个人学习与技术交流，请勿用于商业用途。下载内容版权归原作者所有，请在下载后 24 小时内删除。使用本项目产生的任何后果由使用者自行承担。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("本应用移植自开源项目 YunX，遵循 GNU AGPL-3.0 协议。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("使用前请阅读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("开始使用", action: onFinish)
                }
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled()
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(YunXTheme.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}
