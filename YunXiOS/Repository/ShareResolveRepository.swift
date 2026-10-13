/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：分享解析仓库公共协议（对应 data/repository/ShareResolveRepository.kt）。
 * 各平台 Resolve 仓库统一实现本协议，UI 侧只依赖协议，不依赖具体平台。
 */

import Foundation

protocol ShareResolveRepository {

    /// 创建分享会话：解析链接 → 获取 stoken
    func createSession(link: String, pwd: String?, cookie: String) async throws -> ShareSession

    /// 列出指定目录下的文件
    func listFiles(session: ShareSession, dirFid: String, cookie: String) async throws -> [ShareFile]

    /// 确保临时转存目录存在，返回其 fid
    func ensureTempDir(cookie: String) async throws -> String

    /// 转存分享文件到指定目录，返回转存后的新 fid
    func transferFile(session: ShareSession, file: ShareFile, toDirFid: String, cookie: String) async throws -> String

    /// 获取文件下载直链（转存后调用）
    func getDownloadLink(fid: String, cookie: String) async throws -> DownloadLink

    /// 获取分享文件下载直链（平台差异在此收敛）
    func getShareDownloadLink(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink

    /// 免转存取链（登录态）。默认回退到 getShareDownloadLink。
    func getShareDownloadLinkWithoutSave(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink

    /// 未登录（游客）取分享直链。默认失败。
    func getGuestShareDownloadLink(session: ShareSession, file: ShareFile) async throws -> DownloadLink

    /// 下载完成后清理临时转存目录。默认空实现。
    func cleanupTempDir(dirFid: String, cookie: String) async
}

extension ShareResolveRepository {
    func getShareDownloadLinkWithoutSave(session: ShareSession, file: ShareFile, cookie: String) async throws -> DownloadLink {
        try await getShareDownloadLink(session: session, file: file, cookie: cookie)
    }

    func getGuestShareDownloadLink(session: ShareSession, file: ShareFile) async throws -> DownloadLink {
        throw YunXError.notLoggedIn
    }

    func cleanupTempDir(dirFid: String, cookie: String) async {}

    /// 通用：解析链接得到 ParsedShare，并校验平台
    func parse(_ link: String, expected: SharePlatform) throws -> ParsedShare {
        guard let parsed = ShareLinkParser.parse(link) else {
            throw YunXError.unrecognizedLink
        }
        return parsed
    }
}
