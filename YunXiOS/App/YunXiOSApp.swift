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
        }
    }
}
