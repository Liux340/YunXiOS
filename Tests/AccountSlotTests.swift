/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：多账号槽位规则单测（对应 Android AccountSlotTest + SecureAccountDaosTest 里
 * 「解密失败不删凭证」那组不变式的可测部分）。
 */

import XCTest
@testable import YunXiOS

final class AccountSlotTests: XCTestCase {

    /// 固定时间戳，保证 newAccountId 可断言
    private let now: TimeInterval = 1_700_000_000

    func test首次登录用平台常量主键并设为主账号() {
        let slot = resolveAccountSlot(platform: "quark", existing: nil, newAccount: false, now: now)
        XCTAssertEqual(slot.id, "quark")
        XCTAssertTrue(slot.isPrimary)
        XCTAssertEqual(slot.remark, "")
    }

    func test添加账号落新行且非主账号() {
        let existing = AccountRecord(id: "quark", platform: "quark", remark: "主力", isPrimary: true)
        let slot = resolveAccountSlot(platform: "quark", existing: existing, newAccount: true, now: now)
        XCTAssertNotEqual(slot.id, "quark")
        XCTAssertTrue(slot.id.hasPrefix("quark-"))
        XCTAssertFalse(slot.isPrimary)
        XCTAssertEqual(slot.remark, "")   // 新账号备注留空，不把主账号的备注抄过来
    }

    func test日常重登覆盖主账号行并继承标记与备注() {
        let existing = AccountRecord(id: "quark", platform: "quark", remark: "主力", isPrimary: true)
        let slot = resolveAccountSlot(platform: "quark", existing: existing, newAccount: false, now: now)
        XCTAssertEqual(slot.id, "quark")
        XCTAssertTrue(slot.isPrimary)
        XCTAssertEqual(slot.remark, "主力")   // 重登不该把用户写的备注清掉
    }

    func test新账号主键形如平台加时间戳36进制() {
        let generated = newAccountId(platform: "uc", now: now)
        XCTAssertTrue(generated.hasPrefix("uc-"))
        let suffix = String(generated.dropFirst("uc-".count))
        XCTAssertEqual(Int64(suffix, radix: 36) != nil, true)
    }

    // MARK: - AccountRecord 展示与凭证口径

    func test展示名优先备注其次昵称最后账号() {
        var record = AccountRecord(id: "x", platform: "uc")
        XCTAssertEqual(record.displayName, "账号")
        record.nickname = "小明"
        XCTAssertEqual(record.displayName, "小明")
        record.remark = "备用号"
        XCTAssertEqual(record.displayName, "备用号")
        record.remark = ""
        record.username = "mail@example.com"
        record.nickname = ""
        XCTAssertEqual(record.displayName, "mail@example.com")
    }

    /// 「LinkOpenTarget 的 prefKey」要与 Android `link_open_{NAME 小写下划线}` 同形
    func test链接唤起键名与上游同形() {
        XCTAssertEqual(LinkOpenTarget.quark.prefKey, "link_open_quark")
        XCTAssertEqual(LinkOpenTarget.processText.prefKey, "link_open_process_text")
        XCTAssertEqual(LinkOpenTarget.c139.prefKey, "link_open_c139")
    }

    /// 注册项清单要与上游 13 项一一对应（少一项就会漏管一类链接）
    func test注册项数量与上游一致() {
        XCTAssertEqual(LinkOpenTarget.allCases.count, 13)
    }

    func test平台到注册项的映射() {
        XCTAssertEqual(LinkOpenTarget(platform: .quark), .quark)
        XCTAssertEqual(LinkOpenTarget(platform: .ilanzou), .lanzou)   // 蓝奏优享与蓝奏共用一项
        XCTAssertEqual(LinkOpenTarget(platform: .lanzou), .lanzou)
        XCTAssertNil(LinkOpenTarget(platform: .github))               // GitHub 无对应注册项
    }
}
