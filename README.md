# 云析 iOS 版（YunXiOS）

参照开源 Android 项目 [YunX（云析）](https://github.com/CYQawa/YunX) 的代码与接口实现，移植出的 **iOS（SwiftUI）版本**，并提供 **GitHub Actions 自动构建未签名 IPA** 的工作流。

> 上游项目基于 **GNU AGPL-3.0** 开源，本项目作为其衍生移植作品，同样以 **AGPL-3.0** 发布。

---

## 一、这是什么

和 Android 版功能对齐：**粘贴网盘分享链接 → 浏览分享内容 → 取下载直链 → Range 分片并发 + 断点续传下载**。

支持平台（10 个）：

| 平台 | 登录方式 | 取链方式 |
|---|---|---|
| 夸克网盘 | 网页 Cookie | 免转存取链（失败回退「转存 → 取链」）；支持游客取链（约 50MB 内） |
| UC 网盘 | 网页 Cookie | 直接用分享凭证取链（不转存）；视频优先取原画直链；支持游客取链 |
| 百度网盘 | 网页 Cookie | 转存到临时目录后取链 |
| 139 网盘（和彩云） | 网页 Cookie | 转存后取链（请求体 AES-CBC 加解密） |
| 115 网盘 | 网页 Cookie | 转存后取链（RSA 裸运算 + XOR 会话解密） |
| 123 云盘 | 账号密码 → JWT | 分享直链（含签名与重定向跟随） |
| 迅雷网盘 | 验证码 / 密码（接口已移植） | 游客可列目录；登录后转存取链 |
| 光鸭云盘 | 账号 / 短信（接口已移植） | 受限分享走转存后取链 |
| 蓝奏云 | 账号密码 | HTML 页面解析取直链 |
| 蓝奏云优享版 | 账号密码 → appToken | 目录/文件直链（AES-128-ECB 请求加密） |

---

## 二、目录结构

```
YunXiOS/
├── project.yml                        # XcodeGen 工程描述（生成 .xcodeproj）
├── .github/workflows/build-ipa.yml    # GitHub Actions：构建未签名 IPA
└── YunXiOS/
    ├── App/
    │   ├── YunXiOSApp.swift           # 应用入口
    │   └── AppState.swift             # 全局状态容器
    ├── Core/                          # 对应 Android data/ 基础设施层
    │   ├── Models.swift               # ShareSession / ShareFile / DownloadLink / SharePlatform …
    │   ├── ShareLinkParser.swift      # 统一分享链接识别（10 平台正则）
    │   ├── JSONValue.swift            # JSON 容错取值（对应 optString/optInt/optLong/optBoolean）
    │   ├── HTTPClient.swift           # URLSession 客户端（api / download 双实例 + 代理）
    │   ├── ApiError.swift             # 统一错误类型
    │   ├── CredentialStore.swift      # Keychain + AES-GCM 凭证加密
    │   ├── AccountStore.swift         # 账号仓库（加密落盘）
    │   ├── SettingsStore.swift        # 设置项唯一入口
    │   └── DownloadPlatform.swift     # 下载来源平台标识
    ├── Download/                      # 下载引擎
    │   ├── HttpRangePolicy.swift      # Content-Range 解析与校验
    │   ├── DownloadPathPolicy.swift   # 路径安全策略
    │   ├── DownloadTaskModel.swift    # 任务模型 + 持久化
    │   ├── ChunkDownloader.swift      # 委托式流式分片下载器（206 校验 / 200 识别 / 严格写满）
    │   ├── HlsDownloader.swift        # m3u8 分片下载 + AES-128 解密 + HLS 续传
    │   ├── DownloadRunner.swift       # 单任务分片规划 / 并发 / 续传 / 回退单流
    │   ├── DownloadManager.swift      # 任务级调度 + 持久化 + 完成后清理临时转存
    │   └── SpeedLimiter.swift         # 全局限速令牌桶
    ├── Repository/                    # 各平台接口层（与 Android 一一对应）
    │   ├── ShareResolveRepository.swift  # 解析仓库协议（对应 Kotlin 接口）
    │   ├── PlatformRegistry.swift        # 平台仓库注册表
    │   └── {平台}ResolveRepository.swift  # 10 个平台：Constants + Api + Resolve 仓库
    └── UI/                            # SwiftUI 界面
        ├── RootView.swift             # 底部 4 Tab 容器
        ├── ResolveView.swift          # 解析页 + 文件列表 + 直链弹窗
        ├── ResolveViewModel.swift     # 解析流程状态机 + 下载请求头组装
        ├── DownloadView.swift         # 下载任务列表
        ├── DriveView.swift            # 网盘账号与登录
        ├── LoginWebView.swift         # WKWebView 登录 + Cookie 提取
        ├── AccountLoginService.swift  # 账号密码登录服务
        ├── SettingsView.swift         # 设置 / 关于
        ├── OnboardingView.swift       # 首次启动引导 + 免责声明
        └── Components.swift           # 主题与通用组件
```

---

## 三、获取未签名 IPA

仓库已包含工作流 `.github/workflows/build-ipa.yml`：

1. 把本目录推送到 GitHub 仓库（`main` / `master` 分支）；
2. 进入 **Actions → Build Unsigned IPA → Run workflow**（或在 push 时自动触发）；
3. 构建完成后在 **Artifacts** 下载 `YunXiOS-unsigned-ipa`，解压得到 `YunXiOS-unsigned.ipa`。

工作流做了什么：

```
xcodegen generate
xcodebuild archive -scheme YunXiOS -configuration Release -sdk iphoneos \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
mkdir Payload && cp -R *.app Payload/ && zip -r YunXiOS-unsigned.ipa Payload
```

关键点：**全程不签名**（`CODE_SIGNING_ALLOWED=NO`），因此不需要任何证书或 Apple 开发者账号，Runner 也不会去连签名服务。

> ⚠️ 未签名 IPA 无法直接安装到 iPhone。需要用 **Sideloadly / AltStore / TrollStore / 爱思助手** 等工具用你自己的证书（免费 Apple ID 亦可）二次签名后再安装。
> 免费开发者账号签名的应用有效期为 7 天，到期需重新签名。

### 本地构建

```bash
brew install xcodegen
xcodegen generate
open YunXiOS.xcodeproj      # 用 Xcode 打开，选择自己的 Team 即可真机运行
```

---

## 四、相对 Android 版的差异与已知限制

移植过程中做了这些取舍，请知悉：

1. **界面为重新实现**：Android 侧的 Material 3 Expressive 动效、Container Transform 共享元素动画等未一一复刻，iOS 侧使用原生 SwiftUI 交互。
2. **Gopeed 引擎与磁力链接未移植**：Android 版通过进程内 Gopeed（含 `.so` 与打补丁的 `gopeed-classes.jar`）支持磁力/BT。iOS 无法复用该二进制，**磁力下载暂不支持**；HTTP/HTTPS 分片下载与 HLS 已完整实现。
3. **GitHub 仓库解析未移植**：Android 版的 GitHub 收藏/Release 下载链路未纳入本次移植。
4. **迅雷 / 光鸭的登录界面未接入**：两者的验证码 / 短信登录接口已移植到 `XunleiApi`、`GuangYaApi` 中，但 UI 尚未串联（迅雷的游客列目录仍可用）。其余 8 个平台可在「网盘」页完成登录。
5. **速度限制的作用范围**：限速在「分片开始前」按分片字节数消费令牌，因此对分片下载精确生效；当服务器忽略 Range 回退为单流整文件时不受限速约束。
6. **115 加密为纯 Swift 实现**：iOS 无法直接做 RSA 裸模幂，已用纯 Swift 大整数（1024 位 `modPow`）还原客户端协议。
7. **139 的 gzip 兜底**：使用 Compression 框架流式解码，解码失败时保留原始数据（不影响正常响应）。

---

## 五、免责声明

本项目仅供个人学习与技术交流，请勿用于商业用途。下载内容版权归原作者所有，请在下载后 24 小时内删除。使用本项目产生的任何后果由使用者自行承担。

上游项目作者已声明：**云析永远免费开源**。任何收费版本均为二次打包的诈骗版本，与本项目无关。

---

## 六、开源协议

GNU Affero General Public License v3.0（AGPL-3.0）。

```
YunX（云析）Android 版  Copyright (C) 2026 CYQawa
YunXiOS（云析 iOS 版）  基于上述项目移植
```
