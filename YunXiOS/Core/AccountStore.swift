/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：账号仓库（对应 data/db/{平台}AccountEntity/Dao + repository/{平台}AccountRepository）。
 * Cookie / 口令 / JWT 经 CredentialStore 加密后存入 UserDefaults，杜绝明文落盘。
 */

import Foundation

/// 单平台账号记录
struct AccountRecord: Codable {
    var platform: String
    /// WebView 登录获得的 Cookie（夸克/UC/百度/139/115）
    var cookie: String = ""
    /// 账号密码登录（迅雷/光鸭/123/蓝奏云/蓝奏云优享版）
    var username: String = ""
    var password: String = ""
    /// JWT / access_token 等
    var token: String = ""
    /// refresh_token
    var refreshToken: String = ""
    /// 设备指纹 / deviceId 等平台附加字段
    var deviceId: String = ""
    /// 展示用昵称
    var nickname: String = ""
    var loggedIn: Bool = false

    static func empty(_ platform: String) -> AccountRecord {
        AccountRecord(platform: platform)
    }
}

@MainActor
final class AccountStore: ObservableObject {

    static let shared = AccountStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "yunx_accounts_v1"
    private let encryptionPurpose = "accounts"

    @Published private(set) var records: [String: AccountRecord] = [:]

    private init() {
        load()
    }

    // MARK: - 读取

    func record(for platform: SharePlatform) -> AccountRecord? {
        records[platform.rawValue]
    }

    func isLoggedIn(_ platform: SharePlatform) -> Bool {
        guard let r = records[platform.rawValue] else { return false }
        if platform.usesWebLogin {
            return r.loggedIn && !r.cookie.isEmpty
        }
        return r.loggedIn
    }

    /// 当前平台 Cookie（未登录返回空串）
    func cookie(for platform: SharePlatform) -> String {
        records[platform.rawValue]?.cookie ?? ""
    }

    /// 当前平台可用凭证：Cookie 优先，其次 token（如蓝奏云优享版的 appToken）
    func credential(for platform: SharePlatform) -> String {
        guard let record = records[platform.rawValue] else { return "" }
        if !record.cookie.isEmpty { return record.cookie }
        return record.token
    }

    func token(for platform: SharePlatform) -> String {
        records[platform.rawValue]?.token ?? ""
    }

    // MARK: - 写入

    func update(_ platform: SharePlatform, mutate: (inout AccountRecord) -> Void) {
        var record = records[platform.rawValue] ?? AccountRecord.empty(platform.rawValue)
        mutate(&record)
        records[platform.rawValue] = record
        persist()
        objectWillChange.send()
    }

    func saveCookie(_ cookie: String, nickname: String? = nil, platform: SharePlatform) {
        update(platform) { record in
            record.cookie = cookie
            if let nickname = nickname, !nickname.isEmpty { record.nickname = nickname }
            record.loggedIn = !cookie.isEmpty
        }
    }

    func logout(_ platform: SharePlatform) {
        records.removeValue(forKey: platform.rawValue)
        persist()
        objectWillChange.send()
    }

    // MARK: - 持久化（AES-GCM 加密）

    private func load() {
        guard let cipher = defaults.string(forKey: storageKey), !cipher.isEmpty else { return }
        guard let plain = CredentialStore.decrypt(cipher, purpose: encryptionPurpose) else { return }
        guard let data = plain.data(using: .utf8) else { return }
        if let decoded = try? JSONDecoder().decode([String: AccountRecord].self, from: data) {
            records = decoded
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records),
              let plain = String(data: data, encoding: .utf8) else { return }
        let cipher = CredentialStore.encrypt(plain, purpose: encryptionPurpose)
        defaults.set(cipher, forKey: storageKey)
    }
}
