/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：HTTP 客户端（对应 data/network/HttpClients.kt）。
 * - .api      ：平台 API（登录/解析/直链）、HLS、更新检查共用，超时宽松；
 * - .download ：分片下载专用，长超时、高并发额度。
 * 全局代理通过 URLSessionConfiguration.connectionProxyDictionary 注入，切换即时生效（重建会话）。
 */

import Foundation

/// HTTP 响应封装
struct HTTPResponse {
    let statusCode: Int
    let body: Data
    /// 头字段（key 统一小写）
    let headers: [String: [String]]

    var text: String { String(data: body, encoding: .utf8) ?? "" }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]?.first
    }

    /// Set-Cookie 列表
    var setCookies: [String] {
        headers["set-cookie"] ?? []
    }

    var isSuccessful: Bool { (200...299).contains(statusCode) }
}

/// 代理配置
struct ProxyConfig {
    var host: String?
    var port: Int

    var isActive: Bool {
        guard let host = host, !host.isEmpty else { return false }
        return (1...65535).contains(port)
    }
}

/// 通用 HTTP 客户端（基于 URLSession）
final class HTTPClient {

    private let baseConfig: URLSessionConfiguration
    private var cachedSession: URLSession?
    private var cachedProxySignature: String = ""
    private let lock = NSLock()

    private init(config: URLSessionConfiguration) {
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        self.baseConfig = config
    }

    /// 平台 API 客户端
    static let api = HTTPClient(config: {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 16
        return config
    }())

    /// 下载客户端：分片请求各自建立连接，交给 TCP 背压
    static let download = HTTPClient(config: {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 3600
        config.httpMaximumConnectionsPerHost = 64
        return config
    }())

    // MARK: - 全局代理（对应 HttpClients.setProxy）

    private static var _proxy = ProxyConfig(host: nil, port: 0)
    private static let proxyLock = NSLock()

    static var proxy: ProxyConfig {
        get { proxyLock.lock(); defer { proxyLock.unlock() }; return _proxy }
        set { proxyLock.lock(); _proxy = newValue; proxyLock.unlock() }
    }

    /// 当前会话（代理变化时重建，保证「改设置即时生效」）
    private func session() -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        let proxy = Self.proxy
        let signature = proxy.isActive ? "\(proxy.host ?? ""):\(proxy.port)" : "direct"
        if let cached = cachedSession, signature == cachedProxySignature {
            return cached
        }
        let config = baseConfig.copy() as! URLSessionConfiguration
        if proxy.isActive, let host = proxy.host {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: proxy.port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": proxy.port,
            ]
        }
        let newSession = URLSession(configuration: config)
        cachedSession = newSession
        cachedProxySignature = signature
        return newSession
    }

    // MARK: - 请求

    @discardableResult
    func get(
        _ url: String,
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> HTTPResponse {
        var request = try makeRequest(url, method: "GET", headers: headers)
        if let timeout = timeout { request.timeoutInterval = timeout }
        return try await perform(request)
    }

    /// POST JSON（body 为字典，序列化为 JSON）
    @discardableResult
    func postJSON(
        _ url: String,
        headers: [String: String] = [:],
        body: [String: Any],
        timeout: TimeInterval? = nil
    ) async throws -> HTTPResponse {
        var headers = headers
        if headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        var request = try makeRequest(url, method: "POST", headers: headers)
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        if let timeout = timeout { request.timeoutInterval = timeout }
        return try await perform(request)
    }

    /// POST 表单（application/x-www-form-urlencoded）
    @discardableResult
    func postForm(
        _ url: String,
        headers: [String: String] = [:],
        form: [String: String],
        timeout: TimeInterval? = nil
    ) async throws -> HTTPResponse {
        var headers = headers
        if headers["Content-Type"] == nil { headers["Content-Type"] = "application/x-www-form-urlencoded" }
        var request = try makeRequest(url, method: "POST", headers: headers)
        request.httpBody = form
            .map { "\(HTTPClient.formEncode($0.key))=\(HTTPClient.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        if let timeout = timeout { request.timeoutInterval = timeout }
        return try await perform(request)
    }

    /// 原始请求（分片下载使用，直接取字节流）
    func data(for request: URLRequest) async throws -> (data: Data, response: URLResponse) {
        return try await session().data(for: request)
    }

    /// 构造自定义 URLRequest（带 Range 头 / POST body 等）
    func makeRequest(
        _ url: String,
        method: String = "GET",
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        guard let u = URL(string: url) else {
            throw ApiError("非法 URL：\(url)")
        }
        var request = URLRequest(url: u)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session().data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiError("响应异常")
        }
        return HTTPResponse(statusCode: http.statusCode, body: data, headers: Self.normalize(http))
    }

    private static func normalize(_ response: HTTPURLResponse) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (key, value) in response.allHeaderFields {
            let k = "\(key)".lowercased()
            result[k, default: []].append("\(value)")
        }
        return result
    }

    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// URL 编码辅助（对应 Kotlin URLEncoder.encode）
func urlEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
