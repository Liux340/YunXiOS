/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：深链接注册项（对应 data/prefs/LinkOpenTarget.kt）。
 *
 * Android 侧每项对应一个 activity-alias，用户关掉某项 = 禁用该组件，系统就不再派那种链接给云析。
 * iOS 没有等价的运行时组件启停（注册在 Info.plist 里，且第三方域名无法做 Universal Link 校验），
 * 因此这里的语义改为：**应用内按项拦截**（见 DeepLinks.route + SettingsStore.linkOpen），
 * displayName/sample/titleKey 三项与 Android 逐字对齐，方便用户跨端理解同一份开关清单。
 */

import Foundation

/// 深链接（网盘分享链接一键唤起）的注册项
enum LinkOpenTarget: String, CaseIterable, Identifiable {
    case quark
    case uc
    case xunlei
    case baidu
    case c139
    case pan123
    case pan115
    case guangya
    case lanzou
    case magnet
    case yunx
    case share
    case processText

    var id: String { rawValue }

    /// 设置页显示的名字（与 Android LinkOpenTarget.label 一致）
    var displayName: String {
        switch self {
        case .quark: return "夸克网盘"
        case .uc: return "UC 网盘"
        case .xunlei: return "迅雷网盘"
        case .baidu: return "百度网盘"
        case .c139: return "139（和彩云）"
        case .pan123: return "123 云盘"
        case .pan115: return "115 网盘"
        case .guangya: return "光鸭云盘"
        case .lanzou: return "蓝奏云 / 优享版"
        case .magnet: return "磁力链接"
        case .yunx: return "yunx:// 自有协议"
        case .share: return "分享菜单"
        case .processText: return "选中文本解析"
        }
    }

    /// 设置页显示的链接样例（与 Android LinkOpenTarget.sample 一致）
    var sample: String {
        switch self {
        case .quark: return "pan.quark.cn/s/…"
        case .uc: return "drive.uc.cn/s/…"
        case .xunlei: return "pan.xunlei.com/s/…"
        case .baidu: return "pan.baidu.com/s/…"
        case .c139: return "yun.139.com/shareweb/…"
        case .pan123: return "www.123pan.com/s/…"
        case .pan115: return "115.com/s/…"
        case .guangya: return "www.guangyapan.com/s/…"
        case .lanzou: return "lanzou*.com/…"
        case .magnet: return "magnet:?xt=…"
        case .yunx: return "yunx://resolve?url=…"
        case .share: return "其它 App「分享 → 云析」"
        case .processText: return "长按选中文字 →「用云析解析」"
        }
    }

    /// iOS 侧实现说明：少数项受平台能力限制，注册项仍保留（保持与 Android 清单同构）
    var availabilityNote: String? {
        switch self {
        case .processText:
            // Android 的 ACTION_PROCESS_TEXT 在 iOS 没有等价系统入口
            return "iOS 无系统级「选中文本→云析」入口，需借助快捷指令"
        case .share:
            return "需要在系统分享面板中勾选「云析」（管理… → 显示更多）"
        default:
            return nil
        }
    }

    /// UserDefaults 键（默认开），与 Android prefKey 同形：`link_open_{name 小写下划线}`
    var prefKey: String {
        "link_open_" + snakeName
    }

    /// 枚举名转 Android 风格小写下划线（camelCase → snake_case），保证与 Kotlin `name.lowercase()` 同键
    private var snakeName: String {
        var result = ""
        for character in rawValue {
            if character.isUppercase {
                if !result.isEmpty { result.append("_") }
                result.append(Character(character.lowercased()))
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// 解析平台 → 注册项（GitHub 等无对应注册项返回 nil，不做拦截）
    init?(platform: SharePlatform) {
        switch platform {
        case .quark: self = .quark
        case .uc: self = .uc
        case .xunlei: self = .xunlei
        case .baidu: self = .baidu
        case .c139: self = .c139
        case .pan123: self = .pan123
        case .pan115: self = .pan115
        case .guangya: self = .guangya
        case .lanzou, .ilanzou: self = .lanzou
        case .github: return nil
        }
    }
}
