/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：下载页（对应 ui/screens/DownloadScreen.kt）。
 */

import SwiftUI
import UIKit

struct DownloadView: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var manager = DownloadManager.shared

    var body: some View {
        NavigationView {
            Group {
                if manager.tasks.isEmpty {
                    EmptyHint(icon: "arrow.down.circle", title: "暂无下载任务",
                              subtitle: "在「解析」页粘贴分享链接，取到直链后可加入下载")
                } else {
                    List {
                        ForEach(manager.tasks) { task in
                            DownloadTaskRow(task: task)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            manager.removeAllCompleted()
                            appState.show("已清理已完成任务")
                        } label: {
                            Label("清除已完成", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct DownloadTaskRow: View {

    @EnvironmentObject private var appState: AppState
    let task: DownloadTaskModel

    private var platform: SharePlatform? {
        SharePlatform(rawValue: task.platform)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 8) {
                if let platform = platform {
                    PlatformBadge(platform: platform)
                }
                FileNameText(text: task.filename, font: .subheadline, weight: .medium)
                Spacer()
                Text(task.status.displayName)
                    .font(.caption2)
                    .foregroundColor(statusColor)
            }

            if task.status == .running || task.status == .queued || task.status == .merging || task.status == .paused {
                ProgressView(value: task.progress)
                    .tint(YunXTheme.brand)
                HStack {
                    Text("\(task.downloadedText) / \(task.displaySize)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", task.progress * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if task.status == .completed {
                Text("已完成 · \(task.displaySize)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let error = task.errorMessage, task.status == .failed {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                switch task.status {
                case .running, .queued, .merging:
                    actionButton("暂停", icon: "pause.circle") {
                        DownloadManager.shared.pause(task.id)
                    }
                case .paused, .failed:
                    actionButton("继续", icon: "play.circle") {
                        DownloadManager.shared.resume(task.id)
                    }
                case .completed:
                    actionButton("打开", icon: "folder") {
                        openInFiles(task)
                    }
                }

                actionButton("删除", icon: "trash", role: .destructive) {
                    DownloadManager.shared.remove(task.id)
                    appState.show("已删除任务")
                }

                Spacer()
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch task.status {
        case .completed: return .green
        case .failed: return .red
        case .paused: return .orange
        default: return .secondary
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
        }
        .buttonStyle(.borderless)
    }

    /// 在「文件」App 中打开下载目录
    private func openInFiles(_ task: DownloadTaskModel) {
        let url = DownloadManager.fileURL(for: task)
        let directory = url.deletingLastPathComponent()
        // 使用 shareddocuments scheme 打开文件 App 的对应目录
        let path = directory.path.replacingOccurrences(of: "/private", with: "")
        if let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let sharedURL = URL(string: "shareddocuments://\(encoded)") {
            UIApplication.shared.open(sharedURL, options: [:], completionHandler: nil)
        } else {
            appState.show("文件位于：\(path)")
        }
    }
}
