/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：主题与可复用组件（对应 ui/theme + ui/components）。
 */

import SwiftUI
import UIKit

enum YunXTheme {
    /// 主题主色（与 Android 侧 4C8BF5 保持一致）
    static let brand = Color(red: 0.30, green: 0.55, blue: 0.96)

    static func platformColor(_ platform: SharePlatform) -> Color {
        switch platform {
        case .quark: return Color(red: 0.29, green: 0.44, blue: 0.95)
        case .uc: return Color(red: 0.98, green: 0.55, blue: 0.15)
        case .xunlei: return Color(red: 0.11, green: 0.39, blue: 0.98)
        case .baidu: return Color(red: 0.24, green: 0.48, blue: 0.94)
        case .c139: return Color(red: 0.05, green: 0.62, blue: 0.55)
        case .pan123: return Color(red: 0.95, green: 0.35, blue: 0.35)
        case .pan115: return Color(red: 0.20, green: 0.62, blue: 0.94)
        case .guangya: return Color(red: 0.85, green: 0.42, blue: 0.30)
        case .ilanzou: return Color(red: 0.35, green: 0.70, blue: 0.98)
        case .lanzou: return Color(red: 0.25, green: 0.75, blue: 0.55)
        case .github: return Color(red: 0.30, green: 0.30, blue: 0.34)
        }
    }
}

/// 文件名展示（对应 FileNameText）
struct FileNameText: View {
    let text: String
    var font: Font = .body
    var weight: Font.Weight = .regular

    @AppStorage("file_name_multi_line") private var multiLine = false

    var body: some View {
        Text(text)
            .font(font)
            .fontWeight(weight)
            .lineLimit(multiLine ? 3 : 1)
            .truncationMode(.middle)
            .multilineTextAlignment(.leading)
    }
}

/// 文件大小格式化
func formatSize(_ bytes: Int64) -> String {
    if bytes <= 0 { return "—" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// 空态提示
struct EmptyHint: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// 全局 Toast
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.82))
            .clipShape(Capsule())
            .shadow(radius: 6)
            .padding(.bottom, 24)
    }
}

/// 平台徽标
struct PlatformBadge: View {
    let platform: SharePlatform

    var body: some View {
        Text(platform.shortLabel)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(YunXTheme.platformColor(platform))
            .clipShape(Capsule())
    }
}
