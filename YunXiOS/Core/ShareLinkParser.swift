/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：统一分享链接识别入口（对应 data/network/ShareLinkParser.kt）。
 */

import Foundation

/// 正则辅助：基于 NSRegularExpression，保证 iOS 15 兼容。
enum RegexUtil {
    static func firstGroup(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range) else { return nil }
        guard group < match.numberOfRanges else { return nil }
        guard let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    static func hasMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.firstMatch(in: text, options: [], range: range) != nil
    }
}

/// 从分享链接或整段分享文案中提取 share_id 与提取码。
enum ShareLinkParser {

    private static let urlRegex = "https?://[^\\s]+"
    private static let quarkShareIdRegex = "pan\\.quark\\.cn/s/([A-Za-z0-9]+)"
    private static let ucShareIdRegex = "drive\\.uc\\.cn/s/([A-Za-z0-9]+)"
    private static let xunleiShareIdRegex = "pan\\.xunlei\\.com/s/([A-Za-z0-9_-]+)"
    private static let baiduShareIdRegex = "pan\\.baidu\\.com/s/(1[A-Za-z0-9_-]+)"
    private static let c139ShareIdRegex = "yun\\.139\\.com/shareweb/.*?/w/i/([A-Za-z0-9_-]+)"

    private static let pan123ShareIdRegex = "123(?:865|pan)\\.(?:com|cn)/s/([A-Za-z0-9]+-[A-Za-z0-9]+)"
    private static let pan123ShareSubRegex = "share\\.123pan\\.cn/123pan/([A-Za-z0-9-]+)"
    private static let pan123SrrRegex = "api/srr\\?sk=([A-Za-z0-9-]+)"

    private static let pan115ShareIdRegex = "115(?:cdn|rc)?\\.com/s/(sw[A-Za-z0-9]+)"
    private static let pan115CommandRegex = "115(?:cdn|rc)?\\.com/(sw[A-Za-z0-9]{8,})-([A-Za-z0-9]{4,8})"
    private static let pwdIn115UrlRegex = "[?&]password=([A-Za-z0-9]+)"

    private static let guangyaShareIdRegex = "guangyapan\\.com/s/([A-Za-z0-9_-]+)"

    private static let ilanzouShareIdRegex = "(?:^|[/.])ilanzou\\.(?:com|net|org|cn)/s/([A-Za-z0-9_-]+)"
    private static let lanzouShareIdRegex =
        "(?:^|[/.])(?:lanzou[a-z0-9-]*|lan[zs]o[ux])\\.(?:com|net|org|cn)/([A-Za-z0-9]+)"

    private static let pwdInLanzouUrlRegex = "[?&](?:pwd|pass|passcode|password)=([A-Za-z0-9]+)"
    private static let pwdInUrlRegex = "[?&]pwd=([A-Za-z0-9]+)"
    private static let pwdInTextRegex = "(?:提取码|访问码|密码)[：:]\\s*([A-Za-z0-9]{4,8})"

    static func parse(_ text: String) -> ParsedShare? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = RegexUtil.firstGroup(urlRegex, in: trimmed, group: 0) else { return nil }
        url = url.trimmingCharacters(in: CharacterSet(charactersIn: "。，,；;)]}\"'"))

        func urlPwd() -> String? { RegexUtil.firstGroup(pwdInUrlRegex, in: url) }
        func textPwd() -> String? { RegexUtil.firstGroup(pwdInTextRegex, in: text) }
        func lanzouPwd() -> String? {
            RegexUtil.firstGroup(pwdInLanzouUrlRegex, in: url) ?? textPwd()
        }

        if let sid = RegexUtil.firstGroup(quarkShareIdRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: urlPwd() ?? textPwd(), platform: .quark)
        }
        if let sid = RegexUtil.firstGroup(ucShareIdRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: urlPwd() ?? textPwd(), platform: .uc)
        }
        if let sid = RegexUtil.firstGroup(xunleiShareIdRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: urlPwd() ?? textPwd(), platform: .xunlei)
        }
        if let sid = RegexUtil.firstGroup(baiduShareIdRegex, in: url) {
            // 百度 surl 不包含开头的 "1"
            let surl = String(sid.dropFirst())
            return ParsedShare(shareId: surl, pwd: urlPwd() ?? textPwd(), platform: .baidu)
        }
        if let sid = RegexUtil.firstGroup(c139ShareIdRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: urlPwd() ?? textPwd(), platform: .c139)
        }
        if let sid = RegexUtil.firstGroup(pan123ShareIdRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: urlPwd() ?? textPwd(), platform: .pan123)
        }
        if let sid = RegexUtil.firstGroup(pan123ShareSubRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: urlPwd() ?? textPwd(), platform: .pan123)
        }
        if let sid = RegexUtil.firstGroup(pan123SrrRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: urlPwd() ?? textPwd(), platform: .pan123)
        }
        if let sid = RegexUtil.firstGroup(pan115ShareIdRegex, in: url) {
            let pwd = RegexUtil.firstGroup(pwdIn115UrlRegex, in: url) ?? textPwd()
            return ParsedShare(shareId: sid, pwd: pwd, platform: .pan115)
        }
        if let re = try? NSRegularExpression(pattern: pan115CommandRegex, options: [.caseInsensitive]) {
            let range = NSRange(url.startIndex..<url.endIndex, in: url)
            if let m = re.firstMatch(in: url, options: [], range: range),
               let codeRange = Range(m.range(at: 1), in: url),
               let pwdRange = Range(m.range(at: 2), in: url) {
                return ParsedShare(shareId: String(url[codeRange]), pwd: String(url[pwdRange]), platform: .pan115)
            }
        }
        if let sid = RegexUtil.firstGroup(guangyaShareIdRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: urlPwd() ?? textPwd(), platform: .guangya)
        }
        // 蓝奏云优享版先于蓝奏云判断，避免 ilanzou.com 被误判
        if let sid = RegexUtil.firstGroup(ilanzouShareIdRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: lanzouPwd(), platform: .ilanzou)
        }
        if let sid = RegexUtil.firstGroup(lanzouShareIdRegex, in: url) {
            return ParsedShare(shareId: sid, pwd: lanzouPwd(), platform: .lanzou)
        }
        return nil
    }
}
