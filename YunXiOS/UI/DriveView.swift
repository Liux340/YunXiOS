/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：网盘账号页（对应 ui/screens/DriveScreen.kt 与各平台登录页）。
 */

import SwiftUI

struct DriveView: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var accounts = AccountStore.shared

    @State private var webLoginPlatform: SharePlatform?
    @State private var passwordPlatform: SharePlatform?

    private let platforms: [SharePlatform] = [
        .quark, .uc, .xunlei, .baidu, .c139, .pan123, .pan115, .guangya, .lanzou, .ilanzou,
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(platforms) { platform in
                        platformRow(platform)
                    }
                } footer: {
                    Text("夸克 / UC / 百度 / 139 / 115 使用网页登录（提取 Cookie）；蓝奏云 / 蓝奏云优享版 / 123 云盘使用账号密码登录。Cookie 与令牌均经 AES-GCM 加密存储。")
                        .font(.caption2)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("网盘")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $webLoginPlatform) { platform in
                WebLoginSheet(
                    platform: platform,
                    onCancel: { webLoginPlatform = nil },
                    onSuccess: { cookie in
                        AccountLoginService.saveWebCookie(cookie, platform: platform)
                        webLoginPlatform = nil
                        appState.show("\(platform.displayName) 已登录")
                    }
                )
            }
            .sheet(item: $passwordPlatform) { platform in
                PasswordLoginSheet(
                    platform: platform,
                    onCancel: { passwordPlatform = nil },
                    onSuccess: {
                        passwordPlatform = nil
                        appState.show("\(platform.displayName) 已登录")
                    }
                )
            }
        }
        .navigationViewStyle(.stack)
    }

    private func platformRow(_ platform: SharePlatform) -> some View {
        let loggedIn = accounts.isLoggedIn(platform)
        let nickname = accounts.record(for: platform)?.nickname ?? ""

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(YunXTheme.platformColor(platform).opacity(0.16))
                    .frame(width: 40, height: 40)
                Text(platform.shortLabel)
                    .font(.caption.bold())
                    .foregroundColor(YunXTheme.platformColor(platform))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(platform.displayName).font(.subheadline.weight(.medium))
                Text(statusText(loggedIn: loggedIn, nickname: nickname, platform: platform))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if loggedIn {
                Button("退出") {
                    accounts.logout(platform)
                    appState.show("已退出 \(platform.displayName)")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            } else {
                Button("登录") {
                    beginLogin(platform)
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .disabled(!canLogin(platform))
            }
        }
        .padding(.vertical, 4)
    }

    private func statusText(loggedIn: Bool, nickname: String, platform: SharePlatform) -> String {
        if loggedIn {
            return nickname.isEmpty ? "已登录" : "已登录：\(nickname)"
        }
        if !canLogin(platform) {
            return "验证码登录暂未接入界面"
        }
        return platform.usesWebLogin ? "未登录 · 网页登录" : "未登录 · 账号密码"
    }

    private func canLogin(_ platform: SharePlatform) -> Bool {
        platform.usesWebLogin || platform.isPasswordLogin
    }

    private func beginLogin(_ platform: SharePlatform) {
        if platform.usesWebLogin {
            webLoginPlatform = platform
        } else if platform.isPasswordLogin {
            passwordPlatform = platform
        } else {
            appState.show("该平台登录方式暂未接入界面")
        }
    }
}

/// 账号密码登录弹窗（蓝奏云 / 蓝奏云优享版 / 123 云盘）
private struct PasswordLoginSheet: View {

    let platform: SharePlatform
    let onCancel: () -> Void
    let onSuccess: () -> Void

    @State private var account = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("账号（手机号 / 邮箱 / 用户名）", text: $account)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    SecureField("密码", text: $password)
                } header: {
                    Text("\(platform.displayName) 账号")
                } footer: {
                    if let error = error {
                        Text(error).foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if working {
                            HStack { ProgressView(); Text("登录中…") }
                        } else {
                            Text("登录")
                        }
                    }
                    .disabled(working || account.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("\(platform.displayName) 登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消", action: onCancel)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func submit() async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await AccountLoginService.loginWithPassword(
                platform: platform, account: account, password: password
            )
            onSuccess()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
