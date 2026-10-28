/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：WKWebView 登录页（对应各平台 {X}LoginScreen 的 WebView Cookie 提取流程）。
 */

import SwiftUI
import WebKit

/// 网页登录态清理（对应 Android MultiAccountViewModel.clearWebSession）
enum WebSessionCleaner {

    /**
     * 清空 WKWebView 的 Cookie 与网站数据。
     *
     * ★ 「添加账号」前必须清一次：网页登录型平台（夸克 / UC / 百度 / 139 / 115）的登录页会把
     *   WebView 里**已有的**登录态自动检测出来并保存 —— 于是「添加账号」加进来的还是同一个账号，
     *   只会多出一行重复记录。清 WebView 只影响网页登录态，已落库的账号不受影响
     *   （各平台 API 用的是库里的 Cookie，不是 WebView）。
     * ★ 该平台最后一个账号被退出时也清一次：残留 Cookie 会在下次打开登录页时把用户自动登回旧账号，
     *   让「退出」形同虚设。
     */
    static func clear() {
        let store = WKWebsiteDataStore.default()
        // 全量清理已包含 Cookie；不传 completion 里的等待逻辑，登录页随后会重新加载
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }
}

/// WKWebView 封装
struct WebViewContainer: UIViewRepresentable {
    let urlString: String
    let hosts: [String]
    var onCookieChanged: ([String: String]) -> Void
    var onLoadingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = nil
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: WebViewContainer

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadingChanged(false)
            collectCookies()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingChanged(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingChanged(false)
        }

        /// 读取站点 Cookie，按域筛选后交由上层保存
        private func collectCookies() {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self else { return }
                let hosts = self.parent.hosts
                var values: [String: String] = [:]
                for cookie in cookies {
                    let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                    guard hosts.contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) else { continue }
                    values[cookie.name] = cookie.value
                }
                if !values.isEmpty {
                    self.parent.onCookieChanged(values)
                }
            }
        }
    }
}

/// 登录弹窗（WebView Cookie 平台）
struct WebLoginSheet: View {
    let platform: SharePlatform
    let onCancel: () -> Void
    let onSuccess: (String) -> Void

    @State private var isLoading = true
    @State private var cookies: [String: String] = [:]

    private var cookieString: String {
        cookies
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack {
                    WebViewContainer(
                        urlString: platform.loginURL,
                        hosts: platform.cookieHosts,
                        onCookieChanged: { cookies = $0 },
                        onLoadingChanged: { isLoading = $0 }
                    )
                    if isLoading {
                        ProgressView()
                    }
                }

                VStack(spacing: 10) {
                    Text("在网页中完成登录后，点击「完成」保存登录凭证（Cookie 将加密存储在本机）")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button("取消") { onCancel() }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.bordered)

                        Button("完成") {
                            onSuccess(cookieString)
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        .disabled(cookies.isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            .navigationTitle("\(platform.displayName) 登录")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
