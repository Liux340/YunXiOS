/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：数据模型（对应 data/network/model/ShareModels.kt）。
 */

import Foundation

/// 分享解析会话（一次解析流程的凭证）
struct ShareSession: Hashable {
    let shareId: String
    let stoken: String
    let title: String
}

/// 分享 Token 响应（4.1 接口）
struct ShareToken {
    let stoken: String
    let title: String
    let firstFid: String
}

/// 分享文件 / 目录项
struct ShareFile: Hashable, Identifiable {
    let fid: String
    let fname: String
    let fsize: Int64
    let isdir: Bool
    let pdirFid: String
    let fidToken: String
    let modifyTime: String

    var id: String { fid.isEmpty ? fname : fid }

    init(
        fid: String,
        fname: String,
        fsize: Int64,
        isdir: Bool,
        pdirFid: String,
        fidToken: String,
        modifyTime: String = ""
    ) {
        self.fid = fid
        self.fname = fname
        self.fsize = fsize
        self.isdir = isdir
        self.pdirFid = pdirFid
        self.fidToken = fidToken
        self.modifyTime = modifyTime
    }
}

/// 分享信息（云盘功能：创建分享后查询得到的链接与提取码）
struct ShareInfo {
    let shareUrl: String
    let passcode: String
    let pwdId: String
    let title: String
    let expiredType: Int
    var warning: String? = nil
}

/// 网盘空间详情（单位字节）
struct QuotaInfo {
    let used: Int64
    let total: Int64
    var usedInTrash: Int64 = 0
}

/// 下载直链
struct DownloadLink {
    let fid: String
    let filename: String
    let downloadUrl: String
    let size: Int64
    /// 下载完成后需删除的临时转存子目录 fid；nil 表示无需清理
    let cleanupDirFid: String?
    /// 是否为 HLS（m3u8）转码流地址
    let isHls: Bool
    /// 游客（未登录）直链携带的游客态 Cookie（如夸克/UC 的 __pugs）
    let guestCookie: String

    init(
        fid: String,
        filename: String,
        downloadUrl: String,
        size: Int64,
        cleanupDirFid: String? = nil,
        isHls: Bool = false,
        guestCookie: String = ""
    ) {
        self.fid = fid
        self.filename = filename
        self.downloadUrl = downloadUrl
        self.size = size
        self.cleanupDirFid = cleanupDirFid
        self.isHls = isHls
        self.guestCookie = guestCookie
    }
}

/// UC 转码播放流
struct PlayLink {
    let url: String
    let resolution: String
    let format: String
    let isHls: Bool
}

/// 解析结果：share_id + 提取码 + 平台
struct ParsedShare {
    let shareId: String
    let pwd: String?
    let platform: SharePlatform
}

/// 网盘平台
enum SharePlatform: String, CaseIterable, Identifiable {
    case quark
    case uc
    case xunlei
    case baidu
    case c139
    case pan123
    case pan115
    case guangya
    case ilanzou
    case lanzou
    case github

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quark: return "夸克网盘"
        case .uc: return "UC 网盘"
        case .xunlei: return "迅雷网盘"
        case .baidu: return "百度网盘"
        case .c139: return "139 网盘"
        case .pan123: return "123 云盘"
        case .pan115: return "115 网盘"
        case .guangya: return "光鸭云盘"
        case .ilanzou: return "蓝奏云优享版"
        case .lanzou: return "蓝奏云"
        case .github: return "GitHub"
        }
    }

    var shortLabel: String {
        switch self {
        case .quark: return "夸克"
        case .uc: return "UC"
        case .xunlei: return "迅雷"
        case .baidu: return "百度"
        case .c139: return "139"
        case .pan123: return "123"
        case .pan115: return "115"
        case .guangya: return "光鸭"
        case .ilanzou: return "蓝优"
        case .lanzou: return "蓝奏"
        case .github: return "GitHub"
        }
    }

    /// 该平台是否使用 WebView Cookie 登录（其余为账号密码 / 验证码登录）
    var usesWebLogin: Bool {
        switch self {
        case .quark, .uc, .baidu, .c139, .pan115: return true
        default: return false
        }
    }

    /// 分享文件列表的默认根目录 fid（对应 Android ResolveViewModel.currentDefaultDirFid）
    var rootFid: String {
        switch self {
        case .uc: return "0"
        case .xunlei: return "0"
        case .baidu: return ""
        case .c139: return "0"
        case .pan123: return "0"
        case .pan115: return "0"
        case .guangya: return ""
        case .ilanzou: return ""
        case .lanzou: return ""
        case .github: return "github:root"
        case .quark: return "0"
        }
    }

    /// WebView 登录页地址
    var loginURL: String {
        switch self {
        case .quark: return "https://pan.quark.cn/?fr=pc&platform=pc"
        case .uc: return "https://drive.uc.cn/"
        case .baidu: return "https://pan.baidu.com/"
        case .c139: return "https://yun.139.com/"
        case .pan115: return "https://115.com/"
        default: return ""
        }
    }

    /// 该平台登录所需 Cookie 的域（用于从 WebView 中筛选）
    var cookieHosts: [String] {
        switch self {
        case .quark: return ["pan.quark.cn", "quark.cn"]
        case .uc: return ["drive.uc.cn", "uc.cn"]
        case .baidu: return ["pan.baidu.com", "baidu.com"]
        case .c139: return ["yun.139.com", "139.com"]
        case .pan115: return ["115.com", "webapi.115.com"]
        default: return []
        }
    }

    /// 是否为「账号密码 / 验证码」登录平台
    var isPasswordLogin: Bool {
        switch self {
        case .lanzou, .ilanzou, .pan123: return true
        default: return false
        }
    }
}
