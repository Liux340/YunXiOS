/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：深链接纯逻辑单测（移植 Android util/DeepLinksTest.kt 的 9 条用例，
 * 并补 iOS 侧的开关过滤与 Share Extension 文本路径）。
 *
 * ★ 与 Android 一样：只用字符串，不构造需要系统环境的对象，保证纯逻辑可测。
 */

import XCTest
@testable import YunXiOS

final class DeepLinksTests: XCTestCase {

    private func url(_ string: String) -> URL { URL(string: string)! }

    // MARK: - 上游 9 条用例

    func test点网盘分享链接原样返回() {
        let link = "https://pan.quark.cn/s/abc123"
        XCTAssertEqual(DeepLinks.text(fromURL: url(link)), link)
    }

    func test磁力链接原样返回整串含参数() {
        let magnet = "magnet:?xt=urn:btih:abcdef0123&dn=%E6%B5%8B%E8%AF%95"
        XCTAssertEqual(DeepLinks.text(fromURL: url(magnet)), magnet)
        XCTAssertTrue(DeepLinks.isMagnet(magnet))
    }

    func test自有协议拆出url参数并把pwd拼回链接() {
        // https://pan.quark.cn/s/abc123 的表单编码（+ 表示空格）
        let data = "yunx://resolve?url=https%3A%2F%2Fpan.quark.cn%2Fs%2Fabc123&pwd=1234"
        XCTAssertEqual(
            DeepLinks.text(fromURL: url(data)),
            "https://pan.quark.cn/s/abc123?pwd=1234"
        )
    }

    func test自有协议链接里已带pwd时不再重复拼接() {
        let data = "yunx://resolve?url=https%3A%2F%2Fpan.quark.cn%2Fs%2Fabc%3Fpwd%3D9999&pwd=1234"
        XCTAssertEqual(
            DeepLinks.text(fromURL: url(data)),
            "https://pan.quark.cn/s/abc?pwd=9999"
        )
    }

    func test自有协议只有url参数也认() {
        let data = "yunx://resolve?url=https%3A%2F%2Fdrive.uc.cn%2Fs%2Fxyz"
        XCTAssertEqual(DeepLinks.text(fromURL: url(data)), "https://drive.uc.cn/s/xyz")
    }

    func test自有协议缺少url参数返回nil() {
        XCTAssertNil(DeepLinks.text(fromURL: url("yunx://resolve?pwd=1234")))
        XCTAssertNil(DeepLinks.text(fromURL: url("yunx://resolve")))
    }

    func test分享过来的文本去掉首尾空白后原样返回() {
        XCTAssertEqual(
            DeepLinks.text(fromSharedText: "  看这个 https://pan.quark.cn/s/abc 提取码: 1234  "),
            "看这个 https://pan.quark.cn/s/abc 提取码: 1234"
        )
    }

    func test分享文本全空白返回nil() {
        XCTAssertNil(DeepLinks.text(fromSharedText: "   "))
        XCTAssertNil(DeepLinks.text(fromSharedText: ""))
    }

    func test空URL不处理() {
        XCTAssertNil(DeepLinks.text(fromRaw: "   "))
        XCTAssertNil(DeepLinks.text(fromRaw: ""))
    }

    // MARK: - iOS 侧补充：yunx:// 大小写不敏感 + 链接尾巴字符清理

    func test自有协议scheme大小写不敏感() {
        let data = "YUNX://resolve?url=https%3A%2F%2F115.com%2Fs%2FswABC123"
        XCTAssertEqual(DeepLinks.text(fromURL: url(data)), "https://115.com/s/swABC123")
    }

    func testpwd参数为空时不拼接空提取码() {
        let data = "yunx://resolve?url=https%3A%2F%2Fpan.quark.cn%2Fs%2Fabc&pwd="
        XCTAssertEqual(DeepLinks.text(fromURL: url(data)), "https://pan.quark.cn/s/abc")
    }
}
