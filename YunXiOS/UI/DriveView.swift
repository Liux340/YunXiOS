/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：网盘账号页（对应 ui/screens/DriveScreen.kt + AccountListSection.kt + 各平台登录页）。
 *
 * ★ 多账号：一个平台可挂多个账号，主账号带徽标；账号弹窗提供「设主账号 / 备注 / 退出该账号 /
 *   添加账号」。添加账号前会先清 WebView 登录态（见 WebSessionCleaner），否则网页登录型平台
 *   会把已有登录态再存一遍，加进来的还是同一个账号。
 */

import SwiftUI

struct DriveView: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var accounts = AccountStore.shared

    /// 网页登录目标（nil = 未打开）
    @State private var webLogin: LoginRequest?
    /// 账号密码登录目标
    @State private var passwordLogin: LoginRequest?
    /// 账号管理弹窗的平台
    @State private var managing: SharePlatform?

    /// 一次登录请求：落哪一行 + 是否「添加账号」
    struct LoginRequest: Identifiable {
        let platform: SharePlatform
        let accountId: String?
        let newAccount: Bool
        var id: String { "\(platform.rawValue)|\(accountId ?? "_")|\(newAccount)" }
    }

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
                    Text("夸克 / UC / 百度 / 139 / 115 使用网页登录（提取 Cookie）；蓝奏云 / 蓝奏云优享版 / 123 云盘使用账号密码登录。Cookie 与令牌均经 AES-GCM 加密存储。每个平台可添加多个账号，日常取链走主账号；开启「多账号下载」后批量下载会按文件轮换账号取链。")
                        .font(.caption2)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("网盘")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $webLogin) { request in
                WebLoginSheet(
                    platform: request.platform,
                    onCancel: { webLogin = nil },
                    onSuccess: { cookie in
                        AccountLoginService.saveWebCookie(
                            cookie,
                            platform: request.platform,
                            accountId: request.accountId,
                            newAccount: request.newAccount
                        )
                        webLogin = nil
                        finishLogin(platform: request.platform, newAccount: request.newAccount)
                    }
                )
            }
            .sheet(item: $passwordLogin) { request in
                PasswordLoginSheet(
                    platform: request.platform,
                    accountId: request.accountId,
                    newAccount: request.newAccount,
                    onCancel: { passwordLogin = nil },
                    onSuccess: {
                        passwordLogin = nil
                        finishLogin(platform: request.platform, newAccount: request.newAccount)
                    }
                )
            }
            .sheet(item: $managing) { platform in
                AccountListSheet(platform: platform, beginLogin: { request in
                    managing = nil
                    // 稍等一下再开登录弹窗，避免 sheet 与 sheet 直接打架
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if platform.usesWebLogin {
                            webLogin = request
                        } else {
                            passwordLogin = request
                        }
                    }
                })
                // sheet 内容不在本视图层级里，EnvironmentObject 必须显式注入
                .environmentObject(appState)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 平台行

    private func platformRow(_ platform: SharePlatform) -> some View {
        let count = accounts.accountCount(for: platform)
        let primary = accounts.record(for: platform)
        let loggedIn = accounts.isLoggedIn(platform)

        return Button {
            if count > 0 {
                managing = platform
            } else {
                beginLogin(LoginRequest(platform: platform, accountId: nil, newAccount: false))
            }
        } label: {
            HStack(spacing: 12) {
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
                    Text(statusText(loggedIn: loggedIn, count: count, primary: primary, platform: platform))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if count > 1 {
                    Text("\(count) 账号")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(YunXTheme.brand)
                        .clipShape(Capsule())
                }

                if count == 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "person.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusText(
        loggedIn: Bool,
        count: Int,
        primary: AccountRecord?,
        platform: SharePlatform
    ) -> String {
        if count > 0 {
            let name = primary?.displayName ?? ""
            let suffix = count > 1 ? "（共 \(count) 个）" : ""
            return loggedIn && !name.isEmpty
                ? "主账号：\(name)\(suffix)"
                : "已保存 \(count) 个账号\(suffix)"
        }
        if !canLogin(platform) {
            return "验证码登录暂未接入界面"
        }
        return platform.usesWebLogin ? "未登录 · 网页登录" : "未登录 · 账号密码"
    }

    private func canLogin(_ platform: SharePlatform) -> Bool {
        platform.usesWebLogin || platform.isPasswordLogin
    }

    private func beginLogin(_ request: LoginRequest) {
        if request.newAccount {
            // 「添加账号」前清一次 WebView 登录态，避免把已有账号再加一遍
            WebSessionCleaner.clear()
        }
        if request.platform.usesWebLogin {
            webLogin = request
        } else if request.platform.isPasswordLogin {
            passwordLogin = request
        } else {
            appState.show("该平台登录方式暂未接入界面")
        }
    }

    private func finishLogin(platform: SharePlatform, newAccount: Bool) {
        let suffix = newAccount ? "已添加为新账号" : "已登录"
        appState.show("\(platform.displayName) \(suffix)")
    }
}

// MARK: - 账号列表弹窗（对应 AccountListSection）

struct AccountListSheet: View {

    let platform: SharePlatform
    /// 发起登录（添加账号 / 重新登录）
    let beginLogin: (DriveView.LoginRequest) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var accounts = AccountStore.shared

    @State private var renaming: AccountRecord?
    @State private var quitting: AccountRecord?

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(accounts.accounts(for: platform)) { account in
                        accountRow(account)
                    }
                } header: {
                    Text("\(platform.displayName) 账号")
                } footer: {
                    Text("主账号用于列目录 / 转存等需要单一身份的操作；开启「多账号下载」后，批量下载会按文件在这些账号之间轮换取链。")
                        .font(.caption2)
                }

                Section {
                    Button {
                        beginLogin(DriveView.LoginRequest(platform: platform, accountId: nil, newAccount: true))
                    } label: {
                        Label("添加账号", systemImage: "plus.circle")
                    }
                    .disabled(!canLogin)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("账号管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(item: $renaming) { target in
                // ★ 备注输入不能用 .alert + TextField：alert 内的文本框是 iOS 16+ 才支持的，
                //   本工程 deploymentTarget 是 iOS 15，必须走独立 sheet。
                RemarkEditorSheet(initialText: target.remark) { text in
                    accounts.setRemark(platform, id: target.id, remark: text)
                    renaming = nil
                } onCancel: {
                    renaming = nil
                }
            }
            .confirmationDialog("退出该账号？", isPresented: Binding(
                get: { quitting != nil },
                set: { if !$0 { quitting = nil } }
            ), titleVisibility: .visible) {
                Button("退出", role: .destructive) {
                    if let target = quitting {
                        accounts.remove(platform, id: target.id)
                        if accounts.accountCount(for: platform) == 0 {
                            // 最后一个账号退出：顺手清 WebView 登录态，防止下次自动登回旧账号
                            WebSessionCleaner.clear()
                        }
                        appState.show("已退出 \(target.displayName)")
                    }
                    quitting = nil
                }
                Button("取消", role: .cancel) { quitting = nil }
            } message: {
                Text("只删除这一个账号，其余账号不受影响。")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var canLogin: Bool {
        platform.usesWebLogin || platform.isPasswordLogin
    }

    @ViewBuilder
    private func accountRow(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(account.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if account.isPrimary {
                    Text("主")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(YunXTheme.brand)
                        .clipShape(Capsule())
                }
                Spacer()
                if !account.loggedIn || account.cookie.isEmpty && account.token.isEmpty {
                    Text("凭证待刷新")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            HStack(spacing: 10) {
                Text(updatedText(account.updatedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()

                if !account.isPrimary {
                    Button("设为主账号") {
                        accounts.setPrimary(platform, id: account.id)
                        appState.show("已将 \(account.displayName) 设为主账号")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }

                Button("备注") {
                    renaming = account
                }
                .font(.caption)
                .buttonStyle(.bordered)

                Button("退出", role: .destructive) {
                    quitting = account
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 3)
    }

    private func updatedText(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "更新于 \(formatter.string(from: Date(timeIntervalSince1970: timestamp)))"
    }
}

/// 备注编辑器（iOS 15 兼容：alert 内不能放可编辑 TextField）
struct RemarkEditorSheet: View {
    let initialText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("账号备注（留空则显示昵称）", text: $text)
                        .disableAutocorrection(true)
                } header: {
                    Text("备注只显示在本机，用于在多个账号间认出它们。")
                }
            }
            .navigationTitle("备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { onSave(text) }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { text = initialText }
        }
        .navigationViewStyle(.stack)
    }
}

/// 账号密码登录弹窗（蓝奏云 / 蓝奏云优享版 / 123 云盘）
struct PasswordLoginSheet: View {

    let platform: SharePlatform
    let accountId: String?
    let newAccount: Bool
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
                platform: platform,
                account: account,
                password: password,
                accountId: accountId,
                newAccount: newAccount
            )
            onSuccess()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
