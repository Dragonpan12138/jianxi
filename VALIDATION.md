# 验证记录

## 0.1.4 · 首次付款与失败阶段

日期：2026-11-02

- 编译：通过，versionName `0.1.4`，versionCode `5`。
- 单元测试：38 项通过，0 失败、0 错误。新增首次付款不提前查询、恢复支付宝付款、已付款不重复发起、余额结果未知不重复扣款、查询失败停止、创建未知停止付款，以及参数错误分阶段显示的回归检查。
- Android Lint：通过，0 错误、4 条现有依赖版本提示。
- APK ZIP CRC：通过；APK 内 MIT 全文与根目录 `LICENSE` 字节一致。
- APK 签名：验证通过；证书与此前测试版相同，可覆盖安装。
- 签名证书 SHA-256：`e381d632fcaca580539bad72a5193f1766129cc4a49e0ca7775e91b243417733`。
- APK SHA-256：`d44b92c1185b68a00761dff108185727b9ae8c0359787db0c6a504be28e1dcf3`。
- APK 字节数：17685685。

照片二维码使用本机解码器离线读取；原版 APK 仅进行静态核对。网络测试使用本机 MockWebServer。本轮未连接用户账户，没有向用户设备发送识别、报价、订单、取消或付款请求。实际“参数不正确”的根因尚待具体失败阶段与服务端错误码确认，修复效果需要设备空闲后复测。

## 0.1.3 · 关于页面与开源

日期：2026-11-02

环境：Windows、JDK 21.0.7、Gradle 8.9、Android SDK 35、Build Tools 35.0.0。

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

- 编译：通过，versionName `0.1.3`，versionCode `4`，包名 `dev.rain.laundry`。
- 单元测试：31 项通过，0 失败、0 错误；全部网络测试使用本机 MockWebServer。
- Android Lint：通过，0 错误、4 条 `GradleDependency` 警告，均为现有 AndroidX 依赖有新版本可用的提示。
- APK ZIP CRC：通过。
- APK 内的 `res/raw/mit_license.txt` 与仓库根目录 `LICENSE` 字节一致。
- APK v2 签名验证：通过；开发测试签名与 0.1.2 一致，可覆盖安装。
- 签名证书 SHA-256：`e381d632fcaca580539bad72a5193f1766129cc4a49e0ca7775e91b243417733`。
- APK SHA-256：`b93065fe6c43af7eb0c25522b64ebaec50d680b4249146d1ca1610fa4dd69cc0`。
- APK 字节数：17802090。

本轮加入登录前后均可访问的“关于简洗”页面、GitHub 项目入口、离线 MIT 协议全文及第三方组件说明。版本信息读取生成的 `BuildConfig`。原有 MockWebServer 测试明确绑定和使用 `127.0.0.1`，避免 Windows 将回环地址表示为电脑主机名而被测试接口的本机地址检查拒绝。

未连接 Android 真机，关于页的实机视觉效果、系统返回和外部浏览器跳转仍待手机验证。本轮没有提交真实短信、订单或付款。

## 0.1.2 · 历史验证记录

日期：2026-11-02

- 编译：通过，versionName 0.1.2，versionCode 3。
- Android Lint：通过，0 问题。
- APK ZIP CRC：通过。
- APK v2 签名验证：通过，与前版测试签名相同，可覆盖安装。
- 签名证书 SHA-256：`e381d632fcaca580539bad72a5193f1766129cc4a49e0ca7775e91b243417733`。
- APK SHA-256：`8fffff152aed55d5e46a994d48be4d20dc768849e1da6fed7c87cb6afbbe4f92`。
- APK 字节数：17668472。

### 着色器渲染检查

直接读取工程 `GLASS_LENS_SHADER`，在 Skia RuntimeEffect 中编译成功。静止、左侧按压、中间拖动和右侧按压四种场景均生成有效像素，按压场景的图像有实际取样变化。该检查用于确认着色器程序，不是 Android 实机截图，不代表手机帧率或手感测试。

本轮调整为底栏尺寸与交互绘制。登录/支付逻辑的上一轮结果为 0.1.1 的 31 项测试通过；本轮没有重跑这些业务测试，也没有提交真实短信、订单或付款。

### 实机待确认

按压与拖动的跟手程度、松手回弹、不同系统上的折射支持、深浅色下的视觉效果。Android 13+ 使用 AGSL 折射与色散；较早版本使用兼容回退，外观会有区别。参见 `GLASS_UI_NOTES.md`。
