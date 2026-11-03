# 简洗 iOS

这是基于仓库中 Android 客户端移植的 SwiftUI 客户端，目标系统为 iOS/iPadOS 16 及以上。原项目采用 [MIT 许可证](../LICENSE)，图标沿用并重新绘制了原项目的洗衣机标识。

## 工程与编译

项目用 `project.yml` 生成 Xcode 工程，用 CocoaPods 安装 `AlipaySDK-iOS`。在 macOS 上运行：

```sh
cd ios
brew install xcodegen cocoapods
xcodegen generate --spec project.yml
pod install
open Jianxi.xcworkspace
```

在 Xcode 中选择 `Jianxi` scheme，使用自己的签名团队运行。不要打开生成的 `.xcodeproj`，支付宝 SDK 通过 `.xcworkspace` 链接。

## 没有 Mac 时

原 Android 仓库是 MIT 开源项目，可以在 GitHub 页面点击 **Fork** 建立自己的副本，再把本地的 `ios/`、`.github/workflows/ios-build.yml` 和 `.gitignore` 改动推送到这个副本。Actions 的 **iOS build** 工作流会在云端 macOS 运行器上编译模拟器版本、运行核心契约测试，并生成 `Jianxi-Unsigned-IPA` artifact。它是设备版应用的标准 `Payload/Jianxi.app` 包结构，但**未签名，不能直接安装**。下载并解压 Actions artifact 后，在 Windows 上使用 Sideloadly 或 AltStore/AltServer，以自己的 Apple ID 为其中的 IPA 签名并安装到 iPhone/iPad；免费签名通常每 7 天需要续签。侧载工具可能需要安装 Apple 设备驱动并在设备上信任这台电脑。

要在 CI 中直接生成已签名、可安装到登记过的 iPhone/iPad 的 IPA，需加入 Apple Developer Program，并准备：

1. 显式 App ID：`dev.rain.laundry.ios`。
2. Apple Distribution 证书及其带私钥的 `.p12` 文件。
3. 包含目标 iPhone/iPad UDID 的 **Ad Hoc** 描述文件，且 App ID 与上述 bundle ID 一致。
4. 在 GitHub 仓库的 Actions Secrets 中设置 `IOS_TEAM_ID`、`IOS_P12_BASE64`、`IOS_P12_PASSWORD`、`IOS_ADHOC_PROFILE_BASE64`。两个 `*_BASE64` 值分别是完整 `.p12` 和 `.mobileprovision` 文件的 Base64 内容。证书、私钥、描述文件和真实账号信息不要提交到仓库。

然后在 Actions 中手动运行 **iOS build**，勾选 `build_signed_ipa`。成功后下载 `Jianxi-AdHoc-IPA` artifact；该 IPA 只允许安装到描述文件列出的设备。可用 Windows 上的签名安装工具将其安装到手机，或使用受信任的企业内部安装渠道。首次打开可能需要在设备的“VPN 与设备管理”中信任开发者。描述文件或证书过期后需要重新构建。

免费 Apple ID 不适用于自动 Ad Hoc 导出流程，但可用于侧载工具给未签名 IPA 签名。这个工作流不执行真实短信、下单或付款请求。

## 验证范围

移植遵循 Android 版的单次洗衣流程、订单持久化和付款状态确认原则。第三方服务是否接受 iOS 设备、支付宝 SDK 是否能完成回跳、真实机器是否启动，都必须在设备空闲时由本人逐步验证。支付 SDK 返回成功不等于平台订单已付款，应用应以服务端状态为准。
