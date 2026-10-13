/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：JSON 取值辅助（对应 Kotlin 侧 JSONObject 的 optString/optInt/optLong/optBoolean/optJSONArray）。
 * 各平台 API 移植时统一使用这套访问器，保持与 Android 原实现一一对应。
 */

import Foundation

/// 只读 JSON 包装，提供容错取值（取值失败返回默认值，不抛异常）。
struct JSONValue {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw }

    static let null = JSONValue(nil)

    /// 从 Data 解析（失败返回 nil）
    static func parse(_ data: Data) -> JSONValue? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return JSONValue(obj)
    }

    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return parse(data)
    }

    var isNull: Bool {
        guard let v = raw else { return true }
        return v is NSNull
    }

    func has(_ key: String) -> Bool {
        (raw as? [String: Any])?[key] != nil
    }

    func object(_ key: String) -> JSONValue {
        guard let dict = raw as? [String: Any], let v = dict[key], !(v is NSNull) else { return .null }
        return JSONValue(v)
    }

    func array(_ key: String) -> [JSONValue] {
        guard let dict = raw as? [String: Any], let arr = dict[key] as? [Any] else { return [] }
        return arr.map { JSONValue($0) }
    }

    /// 顶层数组
    var arrayValue: [JSONValue] {
        guard let arr = raw as? [Any] else { return [] }
        return arr.map { JSONValue($0) }
    }

    func string(_ key: String) -> String {
        guard let dict = raw as? [String: Any], let v = dict[key] else { return "" }
        return JSONValue.stringValue(v)
    }

    func int(_ key: String) -> Int {
        guard let dict = raw as? [String: Any], let v = dict[key] else { return 0 }
        return JSONValue.intValue(v)
    }

    func long(_ key: String) -> Int64 {
        guard let dict = raw as? [String: Any], let v = dict[key] else { return 0 }
        return JSONValue.longValue(v)
    }

    func bool(_ key: String) -> Bool {
        guard let dict = raw as? [String: Any], let v = dict[key] else { return false }
        return JSONValue.boolValue(v)
    }

    /// 当前节点自身作为字符串
    var stringValue: String { JSONValue.stringValue(raw) }
    var intValue: Int { JSONValue.intValue(raw) }
    var longValue: Int64 { JSONValue.longValue(raw) }
    var boolValue: Bool { JSONValue.boolValue(raw) }

    static func stringValue(_ v: Any?) -> String {
        guard let v = v else { return "" }
        if v is NSNull { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func intValue(_ v: Any?) -> Int {
        guard let v = v else { return 0 }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) ?? 0 }
        return 0
    }

    static func longValue(_ v: Any?) -> Int64 {
        guard let v = v else { return 0 }
        if let n = v as? NSNumber { return n.int64Value }
        if let s = v as? String { return Int64(s) ?? 0 }
        return 0
    }

    static func boolValue(_ v: Any?) -> Bool {
        guard let v = v else { return false }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return s == "true" || s == "1" }
        return false
    }
}
