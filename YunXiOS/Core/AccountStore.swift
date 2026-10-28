/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：账号仓库（对应 data/db/{平台}AccountEntity/Dao + repository/{平台}AccountRepository
 * + repository/AccountDirectory.kt + db/MultiAccountEntity.kt）。
 * Cookie / 口令 / JWT 经 CredentialStore 加密后存入 UserDefaults，杜绝明文落盘。
 *
 * ★ 多账号（对齐 Android v1.3.0）：一个平台可存多条账号，其中恰有一条为「主账号」。
 *   - 列目录 / 转存 / 上传等**需要单一身份**的操作走主账号（primary，兜底 updatedAt 最新）；
 *   - 多账号下载（C1 轮询、C2 多源）才会用到非主账号；
 *   - 「多登录一次」不等于「多一个账号」：日常重登覆盖同一行，只有「添加账号」落新行，
 *     见 resolveAccountSlot —— 否则每次重登都会多堆一个失效账号。
 *   - 老数据（v1：每平台一条）迁移时沿用平台常量作主键并设为主账号，升级零感知。
 */

import Foundation

/// 单平台账号记录
struct AccountRecord: Codable, Identifiable, Equatable {
    /// 账号行主键：老数据沿用平台常量（如 `"quark"`），新增账号为 `"<platform>-<时间戳36进制>"`
    var id: String
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
    /// 用户自定义备注，空串 = 界面回退显示昵称
    var remark: String = ""
    /// 该平台的主账号（同平台只应有一条为 true）
    var isPrimary: Bool = false
    var loggedIn: Bool = false
    /// 最后更新时间（秒）。主账号缺失时按它兜底
    var updatedAt: TimeInterval = Date().timeIntervalSince1970

    static func empty(_ platform: String) -> AccountRecord {
        AccountRecord(id: platform, platform: platform)
    }

    /// 界面展示名：备注优先，其次昵称，最后账号/兜底文案
    var displayName: String {
        if !remark.isEmpty { return remark }
        if !nickname.isEmpty { return nickname }
        if !username.isEmpty { return username }
        return "账号"
    }
}

/// 新账号主键：`<平台>-<时间戳36进制>`，与老数据沿用的平台常量主键（如 `"quark"`）并存
func newAccountId(platform: String, now: TimeInterval = Date().timeIntervalSince1970) -> String {
    let milliseconds = Int64(now * 1000)
    return "\(platform)-\(String(milliseconds, radix: 36))"
}

/// resolveAccountSlot 的结果：本次登录要写入的账号行（主键 / 是否主账号 / 备注）
struct AccountSlot: Equatable {
    var id: String
    var isPrimary: Bool
    var remark: String
}

/**
 * 一次登录应该落到哪一行 —— 多账号下「多登录一次」不等于「多一个账号」。
 *
 * - 该平台还没有账号 ⇒ 用平台常量主键（与老数据同形）并设为主账号；
 * - 「添加账号」且已有账号 ⇒ 用新主键、非主账号、备注留空；
 * - 日常重新登录（含会话过期后重登）⇒ 覆盖当前主账号那一行，并继承它的主账号标记与备注。
 */
func resolveAccountSlot(
    platform: String,
    existing: AccountRecord?,
    newAccount: Bool,
    now: TimeInterval = Date().timeIntervalSince1970
) -> AccountSlot {
    if existing == nil {
        return AccountSlot(id: platform, isPrimary: true, remark: "")
    }
    if newAccount {
        return AccountSlot(id: newAccountId(platform: platform, now: now), isPrimary: false, remark: "")
    }
    return AccountSlot(id: existing!.id, isPrimary: existing!.isPrimary, remark: existing!.remark)
}

@MainActor
final class AccountStore: ObservableObject {

    static let shared = AccountStore()

    private let defaults = UserDefaults.standard
    /// v2：按平台存账号列表（多账号）。v1（单条）在 load 时就地迁移。
    private let storageKey = "yunx_accounts_v2"
    private let legacyStorageKey = "yunx_accounts_v1"
    private let encryptionPurpose = "accounts"

    /// platform rawValue → 账号列表（主账号在前）
    @Published private(set) var lists: [String: [AccountRecord]] = [:]

    private init() {
        load()
    }

    // MARK: - 读取（主账号口径：与现有 UI/仓库调用保持兼容）

    /// 该平台的主账号（无主账号标记时兜底 updatedAt 最新；无账号返回 nil）
    func record(for platform: SharePlatform) -> AccountRecord? {
        primaryRecord(for: platform.rawValue)
    }

    private func primaryRecord(for platform: String) -> AccountRecord? {
        let accounts = lists[platform] ?? []
        if let primary = accounts.first(where: { $0.isPrimary }) { return primary }
        return accounts.max { $0.updatedAt < $1.updatedAt }
    }

    func isLoggedIn(_ platform: SharePlatform) -> Bool {
        guard let r = record(for: platform) else { return false }
        if platform.usesWebLogin {
            return r.loggedIn && !r.cookie.isEmpty
        }
        return r.loggedIn
    }

    /// 当前平台（主账号）Cookie，未登录返回空串
    func cookie(for platform: SharePlatform) -> String {
        record(for: platform)?.cookie ?? ""
    }

    /// 当前平台（主账号）可用凭证：Cookie 优先，其次 token（如蓝奏云优享版的 appToken）
    func credential(for platform: SharePlatform) -> String {
        Self.credential(of: record(for: platform))
    }

    func token(for platform: SharePlatform) -> String {
        record(for: platform)?.token ?? ""
    }

    /// 指定账号的凭证（多账号下载按账号取链用）
    func credential(for platform: SharePlatform, accountId: String) -> String {
        Self.credential(of: account(for: platform, id: accountId))
    }

    /**
     * 清理临时转存目录要用的凭证：优先用「当初取链的那个账号」，
     * 该账号已退出 / 凭证为空时回退主账号（避免下载完成后留下一堆删不掉的临时文件）。
     */
    func cleanupCredential(for platform: SharePlatform, accountId: String?) -> String {
        if let accountId = accountId, !accountId.isEmpty {
            let own = credential(for: platform, accountId: accountId)
            if !own.isEmpty { return own }
        }
        return credential(for: platform)
    }

    func account(for platform: SharePlatform, id: String) -> AccountRecord? {
        lists[platform.rawValue]?.first { $0.id == id }
    }

    private static func credential(of record: AccountRecord?) -> String {
        guard let record = record else { return "" }
        if !record.cookie.isEmpty { return record.cookie }
        return record.token
    }

    // MARK: - 账号目录（对应 AccountDirectory：列表 / 设主 / 备注 / 退出）

    /// 该平台全部已登录账号（主账号在前）
    func accounts(for platform: SharePlatform) -> [AccountRecord] {
        lists[platform.rawValue] ?? []
    }

    func accountCount(for platform: SharePlatform) -> Int {
        accounts(for: platform).count
    }

    /// 设为主账号：列目录 / 转存 / 上传等需要单一身份的操作改用它（同平台仅保留一条 true）
    func setPrimary(_ platform: SharePlatform, id: String) {
        guard var accounts = lists[platform.rawValue],
              accounts.contains(where: { $0.id == id }) else { return }
        for index in accounts.indices {
            accounts[index].isPrimary = (accounts[index].id == id)
        }
        lists[platform.rawValue] = sorted(accounts)
        persist()
        objectWillChange.send()
    }

    /// 改账号备注（空串 = 界面回退显示昵称）
    func setRemark(_ platform: SharePlatform, id: String, remark: String) {
        guard var accounts = lists[platform.rawValue],
              let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].remark = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].updatedAt = Date().timeIntervalSince1970
        lists[platform.rawValue] = sorted(accounts)
        persist()
        objectWillChange.send()
    }

    /**
     * 退出某个账号：只删这一行，其余账号不受影响。
     *
     * ★ 删掉的若是主账号，把同平台「最近更新」的那一个补成主账号：否则会留下
     *   「还有账号、但一条都不是主账号」的状态 —— 界面上的主账号徽标消失，
     *   取链时只能靠 updatedAt 兜底，行为变得不可预期。
     */
    func remove(_ platform: SharePlatform, id: String) {
        guard var accounts = lists[platform.rawValue] else { return }
        accounts.removeAll { $0.id == id }
        if !accounts.isEmpty && accounts.allSatisfy({ !$0.isPrimary }) {
            let newest = sorted(accounts).first?.id
            for index in accounts.indices where accounts[index].id == newest {
                accounts[index].isPrimary = true
            }
        }
        if accounts.isEmpty {
            lists.removeValue(forKey: platform.rawValue)
        } else {
            lists[platform.rawValue] = sorted(accounts)
        }
        persist()
        objectWillChange.send()
    }

    // MARK: - 写入

    /// 更新主账号那一行（保持既有调用点语义：迅雷 token 刷新、下载器 Cookie 续期等）
    func update(_ platform: SharePlatform, mutate: (inout AccountRecord) -> Void) {
        updateAccount(platform, id: record(for: platform)?.id, mutate: mutate)
    }

    /// 按账号 id 更新。id 为 nil 时落到主账号；明确给出 id 却找不到那一行时**不会**误写主账号，
    /// 而是在该行上新建（登录目标行被删掉后重登的场景）。
    func updateAccount(
        _ platform: SharePlatform,
        id: String?,
        newAccount: Bool = false,
        mutate: (inout AccountRecord) -> Void
    ) {
        let key = platform.rawValue
        var accounts = lists[key] ?? []

        let slot: AccountSlot
        if let explicit = id, !explicit.isEmpty {
            // 显式行：存在则覆盖该行并继承其主账号标记与备注；不存在则就在该行新建
            if let target = accounts.first(where: { $0.id == explicit }) {
                slot = AccountSlot(id: explicit, isPrimary: target.isPrimary, remark: target.remark)
            } else {
                slot = AccountSlot(id: explicit, isPrimary: accounts.isEmpty, remark: "")
            }
        } else {
            // 首次登录 / 「添加账号」/ 日常重登三种语义统一交给 resolveAccountSlot
            slot = resolveAccountSlot(
                platform: key,
                existing: primary(for: accounts),
                newAccount: newAccount
            )
        }

        if let index = accounts.firstIndex(where: { $0.id == slot.id }) {
            mutate(&accounts[index])
            accounts[index].id = slot.id
            accounts[index].isPrimary = slot.isPrimary
            accounts[index].remark = slot.remark
            accounts[index].updatedAt = Date().timeIntervalSince1970
        } else {
            var record = AccountRecord(id: slot.id, platform: key)
            record.isPrimary = slot.isPrimary
            record.remark = slot.remark
            mutate(&record)
            record.id = slot.id
            record.platform = key
            record.updatedAt = Date().timeIntervalSince1970
            accounts.append(record)
        }

        normalizePrimary(&accounts, winner: slot.isPrimary ? slot.id : nil)
        lists[key] = sorted(accounts)
        persist()
        objectWillChange.send()
    }

    /// 维持「同平台只有一条主账号」不变式：
    /// winner 非空 ⇒ 只有 winner 是主账号；winner 为空 ⇒ 一条都没有时补最新的那条。
    private func normalizePrimary(_ accounts: inout [AccountRecord], winner: String?) {
        if let winner = winner {
            for index in accounts.indices where accounts[index].id != winner {
                accounts[index].isPrimary = false
            }
            return
        }
        guard !accounts.isEmpty, accounts.allSatisfy({ !$0.isPrimary }) else { return }
        let newest = sorted(accounts).first?.id
        if let index = accounts.firstIndex(where: { $0.id == newest }) {
            accounts[index].isPrimary = true
        }
    }

    /// 同平台里应保留的主账号（无标记时兜底 updatedAt 最新）
    private func primary(for accounts: [AccountRecord]) -> AccountRecord? {
        if let primary = accounts.first(where: { $0.isPrimary }) { return primary }
        return accounts.max { $0.updatedAt < $1.updatedAt }
    }

    /// 主账号在前，其次按更新时间倒序（界面与轮询顺序稳定）
    private func sorted(_ accounts: [AccountRecord]) -> [AccountRecord] {
        accounts.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func saveCookie(
        _ cookie: String,
        nickname: String? = nil,
        platform: SharePlatform,
        accountId: String? = nil,
        newAccount: Bool = false
    ) {
        updateAccount(platform, id: accountId, newAccount: newAccount) { record in
            record.cookie = cookie
            if let nickname = nickname, !nickname.isEmpty { record.nickname = nickname }
            record.loggedIn = !cookie.isEmpty
        }
    }

    /// 退出该平台**全部**账号（设置页「清空」口径）
    func logout(_ platform: SharePlatform) {
        lists.removeValue(forKey: platform.rawValue)
        persist()
        objectWillChange.send()
    }

    // MARK: - 多账号下载（C1 轮询 / C2 多源）

    /**
     * 本次批量下载可轮换使用的凭证列表（主账号在前）。
     *
     * ★ 取链与请求头必须用**同一份**凭证，所以这里返回 (账号 id, 凭证) 成对的数据，
     *   上层按文件轮换取一对，不拆开用。少于两个账号时只有一条，等价未开启多账号。
     */
    func credentialsForRotation(for platform: SharePlatform) -> [(accountId: String, credential: String)] {
        guard multiAccountEnabled() else { return [] }
        return sorted(lists[platform.rawValue] ?? [])
            .map { (accountId: $0.id, credential: Self.credential(of: $0)) }
            .filter { !$0.credential.isEmpty }
    }

    /// C1 是否可用：开关开着且该平台有多个账号
    func canRotateAccounts(for platform: SharePlatform) -> Bool {
        credentialsForRotation(for: platform).count >= 2
    }

    private func multiAccountEnabled() -> Bool {
        SettingsStore.shared.multiAccountDownload
    }

    /// 把某账号的 Cookie 回写落库（cookieSink 接线用）。
    /// ★ 只写对应账号行 —— 不能把非主账号的 Cookie 覆盖到主账号上，否则 CDN 会 412/403。
    func writeBackCookie(_ cookie: String, platform: SharePlatform, accountId: String) {
        guard var accounts = lists[platform.rawValue],
              let index = accounts.firstIndex(where: { $0.id == accountId }) else { return }
        if accounts[index].cookie == cookie { return }
        accounts[index].cookie = cookie
        accounts[index].loggedIn = !cookie.isEmpty
        accounts[index].updatedAt = Date().timeIntervalSince1970
        lists[platform.rawValue] = sorted(accounts)
        persist()
        objectWillChange.send()
    }

    /**
     * 按「本次请求所用的 Cookie」反查账号行并回写（对应 Android Quark/UCAccountRepository
     * 里 `dao.getAccounts().firstOrNull { it.cookie == requestCookie }` 那段）。
     *
     * ★ 反查不到就不写：可能那个账号已被退出，写进去等于凭空多一行失效账号。
     */
    func writeBackCookieByRequest(
        merged: String,
        requestCookie: String,
        platform: SharePlatform
    ) {
        guard let matched = lists[platform.rawValue]?.first(where: { $0.cookie == requestCookie }) else { return }
        writeBackCookie(merged, platform: platform, accountId: matched.id)
    }

    // MARK: - 持久化（AES-GCM 加密）

    private func load() {
        let hasV2 = (defaults.string(forKey: storageKey).map { !$0.isEmpty } ?? false)
        if hasV2 {
            // ★ v2 密文存在但解不开时，绝不回落到 v1 迁移：否则会用陈旧账号覆盖、并把 v1 删掉，
            //   表现为「密钥暂时不可用 ⇒ 账号被写坏」。这里只让内存为空，密文原样保留。
            if let decoded = try? decodeV2() { lists = decoded }
            return
        }
        // v1（每平台一条）→ v2 就地迁移：沿用平台常量作主键并设为主账号
        guard let legacy = readV1() else { return }
        var migrated: [String: [AccountRecord]] = [:]
        for (platform, account) in legacy {
            migrated[platform] = [account]      // readV1 已补好 id / isPrimary / updatedAt
        }
        lists = migrated
        persist()   // 立刻写 v2，随后删除 v1，避免二次迁移
        defaults.removeObject(forKey: legacyStorageKey)
    }

    private func decodeV2() throws -> [String: [AccountRecord]] {
        let cipher = defaults.string(forKey: storageKey) ?? ""
        guard let plain = CredentialStore.decrypt(cipher, purpose: encryptionPurpose),
              let data = plain.data(using: .utf8) else {
            throw YunXError.credentialUnreadable
        }
        return try JSONDecoder().decode([String: [AccountRecord]].self, from: data)
    }

    /// v1（每平台一条）→ v2 就地迁移：沿用平台常量作主键并设为主账号
    private func readV1() -> [String: AccountRecord]? {
        guard let cipher = defaults.string(forKey: legacyStorageKey), !cipher.isEmpty else { return nil }
        guard let plain = CredentialStore.decrypt(cipher, purpose: encryptionPurpose),
              let data = plain.data(using: .utf8) else { return nil }
        // ★ v1 的 JSON 没有 id / remark / isPrimary / updatedAt，直接用 AccountRecord 解码会
        //   keyNotFound 失败 ⇒ 老账号全丢。先解成旧结构，再补字段映射过去。
        guard let legacy = try? JSONDecoder().decode([String: LegacyRecord].self, from: data) else { return nil }
        var result: [String: AccountRecord] = [:]
        for (platform, old) in legacy {
            var record = AccountRecord(id: platform, platform: platform)
            record.cookie = old.cookie
            record.username = old.username
            record.password = old.password
            record.token = old.token
            record.refreshToken = old.refreshToken
            record.deviceId = old.deviceId
            record.nickname = old.nickname
            record.loggedIn = old.loggedIn
            record.isPrimary = true
            record.updatedAt = Date().timeIntervalSince1970
            result[platform] = record
        }
        return result
    }

    /// v1 的账号结构（无 id / remark / isPrimary / updatedAt）
    private struct LegacyRecord: Codable {
        var cookie: String = ""
        var username: String = ""
        var password: String = ""
        var token: String = ""
        var refreshToken: String = ""
        var deviceId: String = ""
        var nickname: String = ""
        var loggedIn: Bool = false
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(lists),
              let plain = String(data: data, encoding: .utf8) else { return }
        let cipher = CredentialStore.encrypt(plain, purpose: encryptionPurpose)
        defaults.set(cipher, forKey: storageKey)
    }
}
