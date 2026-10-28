/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：解析页（对应 ui/screens/ResolveScreen.kt + ui/resolve/ShareDetailScreen.kt + DownloadLinkDialog.kt）。
 */

import SwiftUI
import UIKit

struct ResolveView: View {

    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ResolveViewModel()
    @State private var pastedFromClipboard = false
    /// 已消费过的深链接令牌（避免同一次唤起重复触发解析）
    @State private var handledLinkToken = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                inputSection

                if !viewModel.files.isEmpty || viewModel.isWorking {
                    Divider()
                    contentSection
                } else {
                    EmptyHint(
                        icon: "link.badge.plus",
                        title: "粘贴分享链接开始解析",
                        subtitle: "支持夸克 / UC / 迅雷 / 百度 / 139 / 123 / 115 / 光鸭 / 蓝奏云 / 蓝奏云优享版"
                    )
                }
            }
            .navigationTitle("云析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        if !viewModel.files.isEmpty {
                            Button {
                                viewModel.toggleSelectionMode()
                            } label: {
                                Image(systemName: viewModel.selectionMode
                                    ? "checkmark.rectangle"
                                    : "checklist")
                            }
                        }
                        Button {
                            appState.resolveInput = ""
                            viewModel.input = ""
                            viewModel.linkDialog = nil
                            viewModel.clearSelection()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .opacity(viewModel.input.isEmpty ? 0 : 1)
                    }
                }
            }
            .sheet(item: $viewModel.linkDialog) { dialog in
                DownloadLinkSheet(
                    dialog: dialog,
                    onCopy: { viewModel.copyLink(dialog) },
                    onDownload: { viewModel.enqueue(dialog) },
                    onClose: { viewModel.linkDialog = nil }
                )
            }
            // 真机反馈修复：TextEditor 弹起键盘后没有任何收起入口，键盘盖住「开始解析」按钮。
            // 双保险：键盘上方「完成」工具条 + 点击内容区空白处收起。
            .keyboardDoneToolbar()
            .contentShape(Rectangle())
            .onTapGesture { KeyboardHelper.dismiss() }
            .onAppear {
                // 顺序要紧：先收深链接，收到就不再做剪贴板自动识别（否则输入框会被覆盖）
                if !consumePendingDeepLink() {
                    syncClipboardIfNeeded()
                }
            }
            // 深链接消费：填入输入框并自动解析（对应 Android LinkOpenScreen 的一键直达）
            .onChange(of: appState.pendingDeepLink?.token) { _ in
                consumePendingDeepLink()
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 输入区

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {

            TextEditor(text: $viewModel.input)
                .frame(minHeight: 72, maxHeight: 110)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    Group {
                        if viewModel.input.isEmpty {
                            Text("粘贴分享链接或分享文案（可含提取码）")
                                .foregroundColor(.secondary)
                                .padding(.leading, 13)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                )
                .onChange(of: viewModel.input) { newValue in
                    appState.resolveInput = newValue
                }

            HStack(spacing: 10) {
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await viewModel.parseAndOpen() }
                } label: {
                    if viewModel.isWorking {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text(viewModel.statusText.isEmpty ? "处理中…" : viewModel.statusText)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("开始解析").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)
            }

            if let error = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 结果区

    private var contentSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if viewModel.canGoBack {
                    Button {
                        Task { await viewModel.goBack() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                }

                if let platform = viewModel.platform {
                    PlatformBadge(platform: platform)
                }

                Text(viewModel.breadcrumb)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                Text("\(viewModel.files.count) 项")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(viewModel.files) { file in
                    FileRow(
                        file: file,
                        busy: viewModel.busyFileId == file.id,
                        selectionMode: viewModel.selectionMode,
                        selected: viewModel.selectedFileIds.contains(file.id),
                        onTap: {
                            Task {
                                if viewModel.selectionMode {
                                    viewModel.toggleSelection(file)
                                } else if file.isdir {
                                    await viewModel.open(file)
                                } else {
                                    await viewModel.requestDownload(file)
                                }
                            }
                        }
                    )
                }
            }
            .listStyle(.plain)

            if viewModel.selectionMode {
                selectionBar
            }
        }
    }

    /// 多选底栏：全选 / 下载 N 个 / 取消
    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(viewModel.selectedFileIds.isEmpty ? "全选" : "清空") {
                    if viewModel.selectedFileIds.isEmpty {
                        viewModel.selectAllDownloadable()
                    } else {
                        viewModel.clearSelection()
                    }
                }
                .font(.subheadline)
                .disabled(viewModel.downloadableFiles.isEmpty)

                if !viewModel.batchStatus.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text(viewModel.batchStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    Task { await viewModel.downloadSelected() }
                } label: {
                    Text("下载 \(viewModel.selectedFileIds.count) 个")
                        .frame(maxWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedFileIds.isEmpty || viewModel.isWorking)

                Button("取消") {
                    viewModel.toggleSelectionMode()
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
        }
    }

    // MARK: - 深链接消费

    /// 收取待处理的深链接：填入输入框并自动解析。
    /// 返回 true 表示本次挂载确有深链接被消费（剪贴板自动识别应让位，不要覆盖输入框）。
    @discardableResult
    private func consumePendingDeepLink() -> Bool {
        guard let request = appState.pendingDeepLink, request.token != handledLinkToken else {
            return false
        }
        handledLinkToken = request.token
        appState.consumeDeepLink(token: request.token)
        viewModel.input = request.text
        appState.resolveInput = request.text
        // 视同「已粘贴」，避免剪贴板自动识别把这条链接又覆盖成剪贴板里的旧内容
        pastedFromClipboard = true
        Task { await viewModel.parseAndOpen() }
        return true
    }

    // MARK: - 剪贴板

    private func syncClipboardIfNeeded() {
        guard appState.settings.clipboardDetect, !pastedFromClipboard else { return }
        pasteFromClipboard(silent: true)
    }

    private func pasteFromClipboard(silent: Bool = false) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            if !silent { appState.show("剪贴板为空") }
            return
        }
        guard ShareLinkParser.parse(text) != nil else {
            if !silent { appState.show("剪贴板中没有可识别的分享链接") }
            return
        }
        viewModel.input = text
        appState.resolveInput = text
        pastedFromClipboard = true
    }
}

/// 文件行
private struct FileRow: View {
    let file: ShareFile
    let busy: Bool
    let selectionMode: Bool
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if selectionMode {
                    Image(systemName: file.isdir
                        ? "square.dimming"
                        : (selected ? "checkmark.circle.fill" : "circle"))
                        .font(.title3)
                        .foregroundColor(file.isdir ? Color(.systemGray3) : (selected ? YunXTheme.brand : .secondary))
                        .frame(width: 24)
                }

                Image(systemName: file.isdir ? "folder.fill" : iconForFile(file.fname))
                    .font(.title3)
                    .foregroundColor(file.isdir ? .yellow : .secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    FileNameText(text: file.fname, font: .subheadline, weight: .medium)
                    if !file.isdir {
                        Text(formatSize(file.fsize))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !selectionMode {
                    if busy {
                        ProgressView()
                    } else {
                        Image(systemName: file.isdir ? "chevron.right" : "arrow.down.circle")
                            .foregroundColor(file.isdir ? .secondary : YunXTheme.brand)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy && !selectionMode)
    }

    private func iconForFile(_ name: String) -> String {
        let ext = name.split(separator: ".").last?.lowercased() ?? ""
        switch ext {
        case "mp4", "mkv", "mov", "avi", "webm", "flv", "ts", "m3u8", "wmv", "rmvb": return "film"
        case "mp3", "flac", "wav", "aac", "m4a": return "music.note"
        case "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic": return "photo"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "pdf": return "doc.richtext"
        case "apk", "ipa", "exe", "dmg": return "shippingbox"
        default: return "doc"
        }
    }
}

/// 下载直链弹窗（对应 DownloadLinkDialog）
private struct DownloadLinkSheet: View {
    let dialog: ResolveViewModel.LinkDialog
    let onCopy: () -> Void
    let onDownload: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    FileNameText(text: dialog.fileName, font: .headline, weight: .semibold)
                    HStack(spacing: 8) {
                        PlatformBadge(platform: dialog.platform)
                        Text(formatSize(dialog.size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if dialog.link.isHls {
                            Text("HLS 转码流")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }

                ScrollView {
                    Text(dialog.link.downloadUrl)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    Button {
                        onCopy()
                    } label: {
                        Label("复制直链", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onDownload()
                    } label: {
                        Label("加入下载", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("下载直链")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭", action: onClose)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
