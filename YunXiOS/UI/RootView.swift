/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：主容器（对应 ui/MainScreen.kt：底部导航 + 全局 Snackbar + 引导页）。
 */

import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case resolve
    case download
    case drive
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resolve: return "解析"
        case .download: return "下载"
        case .drive: return "网盘"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .resolve: return "link"
        case .download: return "arrow.down.circle"
        case .drive: return "externaldrive.connected.to.line.below"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {

    @EnvironmentObject private var appState: AppState
    @State private var tab: MainTab = .resolve
    @AppStorage("onboarding_done") private var onboardingDone = false
    @State private var showOnboarding = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                ResolveView()
                    .tabItem { Label(MainTab.resolve.title, systemImage: MainTab.resolve.icon) }
                    .tag(MainTab.resolve)

                DownloadView()
                    .tabItem { Label(MainTab.download.title, systemImage: MainTab.download.icon) }
                    .tag(MainTab.download)

                DriveView()
                    .tabItem { Label(MainTab.drive.title, systemImage: MainTab.drive.icon) }
                    .tag(MainTab.drive)

                SettingsView()
                    .tabItem { Label(MainTab.settings.title, systemImage: MainTab.settings.icon) }
                    .tag(MainTab.settings)
            }
            .accentColor(YunXTheme.brand)

            if let toast = appState.toast {
                ToastView(text: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.toast)
        .onAppear {
            if !onboardingDone { showOnboarding = true }
            appState.settings.applyProxy()
        }
        // 深链接到达时切到解析页（对应 Android 收到 intent 后打开解析页并填入）
        .onChange(of: appState.pendingDeepLink?.token) { _ in
            if appState.pendingDeepLink != nil { tab = .resolve }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                onboardingDone = true
                showOnboarding = false
            }
        }
    }
}
