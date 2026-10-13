/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：平台仓库注册表（对应 Android 侧 MainScreen 手工组装各仓库的逻辑）。
 */

import Foundation

@MainActor
final class PlatformRegistry {

    static let shared = PlatformRegistry()

    private var repositories: [SharePlatform: ShareResolveRepository] = [:]

    private init() {
        repositories[.quark] = QuarkResolveRepository()
        repositories[.uc] = UCResolveRepository()
        repositories[.baidu] = BaiduResolveRepository()
        repositories[.pan123] = Pan123ResolveRepository()
        repositories[.pan115] = Pan115ResolveRepository()
        repositories[.c139] = C139ResolveRepository()
        repositories[.xunlei] = XunleiResolveRepository()
        repositories[.guangya] = GuangYaResolveRepository()
        repositories[.lanzou] = LanzouResolveRepository()
        repositories[.ilanzou] = ILanzouResolveRepository()
    }

    func repository(for platform: SharePlatform) -> ShareResolveRepository? {
        repositories[platform]
    }
}
