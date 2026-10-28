/*
 * YunXiOS - 云析 iOS 版
 *
 * 移植自 YunX (https://github.com/CYQawa/YunX)，遵循 GNU AGPL-3.0 协议开源。
 * 本文件：应用入口。
 */

import SwiftUI

@main
struct YunXiOSApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(nil)
                // 深链接入口（对应 Android MainActivity 收到 intent）：
                // yunx:// 自有协议 / 磁力 / Share Extension 传进来的链接文本，都走这一条路由。
                .onOpenURL { url in
                    let outcome = DeepLinks.route(url: url, settings: appState.settings)
                    switch outcome {
                    case .text(let text), .magnet(let text):
                        appState.handleDeepLink(text)
                    case .disabled(let target):
                        appState.show("「链接唤起」中已关闭：\(target.displayName)")
                    case .ignored:
                        break
                    }
                }
        }
    }
}
