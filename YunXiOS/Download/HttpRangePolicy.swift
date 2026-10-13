/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：Content-Range 解析与校验（对应 data/download/HttpRangePolicy.kt）。
 */

import Foundation

enum HttpRangePolicy {

    struct ContentRange {
        let start: Int64
        let end: Int64
        let total: Int64?
    }

    /// 解析 `bytes 0-1023/4096` 形式的 Content-Range
    static func parse(_ value: String?) -> ContentRange? {
        guard let text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let pattern = "^bytes\\s+(\\d+)-(\\d+)/(\\d+|\\*)$"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range) else { return nil }
        func group(_ i: Int) -> String? {
            guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: text) else { return nil }
            return String(text[r])
        }
        guard let startStr = group(1), let endStr = group(2), let totalStr = group(3),
              let start = Int64(startStr), let end = Int64(endStr) else { return nil }
        let total: Int64? = totalStr == "*" ? nil : Int64(totalStr)
        if start < 0 || end < start { return nil }
        if let total = total, end >= total { return nil }
        return ContentRange(start: start, end: end, total: total)
    }

    /// 校验响应头与请求区间是否一致
    static func matches(_ value: String?, requestedStart: Int64, requestedEnd: Int64?) -> Bool {
        guard let range = parse(value) else { return false }
        if range.start != requestedStart { return false }
        if let requestedEnd = requestedEnd { return range.end == requestedEnd }
        return true
    }
}
