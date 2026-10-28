/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：登录服务（对应各平台 {X}LoginScreen + {X}AccountRepository 的登录流程）。
 * - Cookie 平台（夸克 / UC / 百度 / 139 / 115）：走 WKWebView 登录后提取 Cookie；
 * - 账号密码平台（蓝奏云 / 蓝奏云优享版 / 123）：直接调用各平台 Api 的登录方法。
 *
 * ★ 多账号：所有写入都带 accountId / newAccount，落到哪一行由 resolveAccountSlot 决定
 *   （首次登录用平台常量主键、日常重登覆盖同一行、「添加账号」落新行）。
 */

import Foundation

@MainActor
enum AccountLoginService {

    /**
     * 账号密码登录（蓝奏云 / 蓝奏云优享版 / 123 云盘）
     *
     * @param accountId 「添加账号」时可指定要覆盖的行；nil = 主账号那行（日常重登）
     * @param newAccount true = 落新行（非主账号、备注留空）
     */
    static func loginWithPassword(
        platform: SharePlatform,
        account: String,
        password: String,
        accountId: String? = nil,
        newAccount: Bool = false
    ) async throws {
        let store = AccountStore.shared
        switch platform {
        case .lanzou:
            let api = LanzouApi()
            let cookie = try await api.login(account: account, password: password)
            guard !cookie.isEmpty else { throw ApiError("蓝奏云登录失败：未获取到凭证") }
            store.updateAccount(platform, id: accountId, newAccount: newAccount) { record in
                record.cookie = cookie
                record.username = account
                record.loggedIn = true
            }

        case .ilanzou:
            let api = ILanzouApi()
            let uuid = try await api.getUuid()
            let token = try await api.login(loginName: account, loginPwd: password, uuid: uuid)
            guard !token.isEmpty else { throw ApiError("蓝奏云优享版登录失败：未获取到 appToken") }
            store.updateAccount(platform, id: accountId, newAccount: newAccount) { record in
                record.token = token
                record.deviceId = uuid
                record.username = account
                record.loggedIn = true
            }

        case .pan123:
            let api = Pan123Api()
            switch await api.passwordLogin(account: account, password: password) {
            case .success(let token):
                store.updateAccount(platform, id: accountId, newAccount: newAccount) { record in
                    record.token = token
                    record.username = account
                    record.loggedIn = true
                }
            case .failure(let message):
                throw ApiError(message)
            }

        default:
            throw ApiError("该平台不支持账号密码登录")
        }
    }

    /// 保存 WebView 提取到的 Cookie
    static func saveWebCookie(
        _ cookie: String,
        platform: SharePlatform,
        accountId: String? = nil,
        newAccount: Bool = false
    ) {
        guard !cookie.isEmpty else { return }
        AccountStore.shared.saveCookie(
            cookie,
            platform: platform,
            accountId: accountId,
            newAccount: newAccount
        )
    }
}
