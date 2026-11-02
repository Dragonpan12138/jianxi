# 简洗 Jianxi

简洗是一个使用 Kotlin、Jetpack Compose 和 Material 3 构建的独立 Android 洗衣客户端，提供短信登录、扫码识别设备、模式选择、单次支付和本机订单查询，配有液态玻璃悬浮底栏和系统深色模式。

[GitHub 源码](https://github.com/xiyuchengxu/jianxi) · [问题反馈](https://github.com/xiyuchengxu/jianxi/issues) · [MIT 开源协议](LICENSE)

当前版本 **0.1.9**，支持 Android 8.0（API 26）及以上系统。包名 `dev.rain.laundry`，可与原版并存，并可覆盖安装此前测试版。本项目与原服务平台无隶属关系。

## 0.1.9 支付渠道机构编号

修正“确认模式，查看金额”后获取支付方式的字段映射：`payChannelRoute/prePay` 中名为 `shopId` 的参数，按原版调用链传入设备的 `orgId`。此前误传设备详情中的 `shopId`，会触发后端将字符串转换为 Long 的错误。

机构编号不符合 64 位整数格式时会提示重新扫码；支付渠道返回错误时会标明“获取支付方式失败”。回归测试使用不同的店铺与机构编号，覆盖完整识别、报价、支付渠道请求链及大整数精度。51 项 JVM 单元测试和 3 项 Android 运行测试通过，真实设备返回仍需覆盖安装后重新扫码验证。

## 0.1.8 关于页打赏

关于页新增“打赏支持”按钮，展示作者提供的支付宝收款码，并可保存图片后使用支付宝识别。收款码原图随应用内置，可离线查看。关于页标语改为“把洗衣，变简单”，去掉末尾句号。

Android 10 及以上保存到相册，较早系统使用系统文件保存窗口；保存图片不新增存储权限。实现参考 [Android 共享媒体说明](https://developer.android.com/training/data-storage/shared/media)。Android 15 模拟器已验证弹窗、保存后图片字节一致、系统返回及既有报价界面，3 项运行测试通过。

## 0.1.7 模拟器验证与底栏避让

在 Android 官方模拟器 Android 15 / API 35 上运行实际 APK，验证登录界面、关于页、离线 MIT 协议、粘贴设备码、模式选择、报价、支付方式展示及底栏按压切换。修正付款页按钮被悬浮底栏遮挡的问题：在滚动区域外预留底栏空间，滚动到底部后可完整看到确认支付按钮。

3 项 Android 运行测试及 49 项 JVM 单元测试通过。运行测试以本地响应覆盖空优惠列表、已选未知优惠和异常结构，未使用真实账户、未发送短信、未创建订单或付款；真实服务端兼容性仍需设备空闲后复测。

## 0.1.6 报价空值兼容

按原版 JSON 转换器的默认值规则兼容空优惠列表、空选中标记和空类型字段。`options:null`、`participateList:null` 作为空列表处理，避免误报“报价优惠选项格式尚未适配”。已选优惠及非空的异常结构仍会停止确认；格式提示补充字段名和数据类型，不输出字段内容。

## 0.1.5 报价参数修正

修正“确认模式，查看金额”请求：关闭自动优惠使用原版的数值字符串 `0`，补齐所属机构的 `forbiddenPromotions`。普通支付宝、余额下单携带原版明确“不使用金币”的记录，不购买金币、会员或附加商品。

报价返回的优惠列表会区分可选项和已使用项。未选中的优惠目录可以正常展示报价；出现未选择的实际优惠、额外商品或未知选中状态时仍停止确认。回归测试已按原版 APK 的字段约定验证，实际设备需安装后复测。

## 0.1.4 付款顺序与错误提示

新创建、尚未发起付款的订单直接获取支付信息，避免在支付初始化前查询付款状态。继续已发起的支付宝付款时先查询状态，再复用原订单；余额付款结果未知时继续保留订单并等待查询结果。

如果同一订单已在原应用付款，可以刷新状态核对；支付初始化被拒绝时也会查询是否已付款，查询失败会保留原来的错误提示。

付款报错会显示“创建订单失败”“获取支付信息失败”或“查询付款状态失败”等具体步骤，以及服务端错误码。本次修正基于原版 APK 的离线流程核对，真实设备效果仍待空闲时复测。

## 0.1.3 关于与开源

顶部信息按钮可打开“关于简洗”，登录前后均可访问。页面展示应用版本、可直接打开的 GitHub 仓库地址、MIT 开源协议和第三方组件说明。MIT 全文随 APK 打包，可离线阅读和选择复制。

项目源码使用 [MIT License](LICENSE)，第三方组件使用各自许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 0.1.2 底栏与录屏动效

底栏可见轨道缩为最多 252dp 宽、60dp 高，图标缩为 20dp。参考用户提供的录屏，按住时弹出鼓起的玻璃透镜，拖动时随手指移动并拉伸，松手后落到选中的标签并回弹。拖出底栏较远会取消本次切换。后台请求忙碌时禁用切换，并保留无障碍点击。

透镜单独采样页面和底栏场景，能放大下方的图标及文字，边缘使用折射位移、RGB 色散和高光。Android 13 及以上使用 AGSL；Android 12 使用背景模糊及拖动放大回退；更早版本保留半透明和拖动放大。轨道外预留了透镜鼓起所需的空间。细节见 `GLASS_UI_NOTES.md`。

## 0.1.1 修正

登录验证码入口已按原版登录页面改为 `common/sms/sendCode`，表单为 `phone`、`template=reg`。0.1.0 错用了 `user/smsCode`，会出现未登录提示。登录前请求使用空会话签名，不夹带残留 token。

同时核对了洗衣流程：模式进入报价前增加 `appoint/checkMachineCanUse` 检查；使用详情接口的正式设备编号及 IMEI；只进入支持的洗衣/洗鞋设备流程；保留支付路由的 `thirdChannel`、`outVoucherId`；区分明确拒单、会话过期、访问受限和结果未知。明确拒单可以重新确认下单，网络导致的未知结果仍阻止自动重试。具体证据与未验证部分见 `PROTOCOL_AUDIT.md`。

使用 Kotlin、Jetpack Compose、Material 3。界面采用浅绿色和系统深色模式；底栏为悬浮液态玻璃风格，静止时标签保持清晰，按压时由独立透镜对底栏内容做局部放大和光学效果。

## 当前功能

- 本人已有账户的手机号、短信验证码登录，发送验证码的 60 秒冷却。
- 本机相机扫描二维码，或粘贴二维码内容；识别 `IMEI`、`SN`、`NQT`。
- 查询设备、选择模式、向后端查询报价、展示本次洗衣项目及金额。
- 使用后端提供的支付宝单次付款或账户余额渠道；不支持微信支付、会员和周期扣款。
- 本机最近一笔订单的保存、继续付款、查询结果、取消未付款订单，以及已付款后的设备同步请求。
- token 和本机订单通过 Android Keystore 的 AES-GCM 加密保存；登出后同一手机号可找回本机保留的订单。

这是根据提供的胖乖生活 1.144.0 APK 静态协议实现的**待实机联调版本**。尚无学校真实二维码与本人账户联调结果，不能把编译成功或单元测试通过当作真实洗衣、支付成功的证明。服务端风控、二维码类型、模式响应结构、新包名与支付签名兼容性仍待确认。

## 使用

安装测试 APK，使用本人手机号登录，再扫描洗衣机二维码或粘贴完整内容。在付款页核对设备、模式和金额，明确点击“确认支付”后才会创建订单。定位权限只在付款前申请，用于原协议下单所需的位置参数；相机权限由本机扫码功能申请。

如果二维码或响应结构尚未适配，客户端会停止该步骤并显示错误，不会使用演示数据替代真实设备。请保留二维码原始内容供后续联调，不要分享短信验证码和登录 token。

## 订单处理

- 报价只接受一个已选择的洗衣项目；出现额外商品或已使用但未选择的优惠时停止下单。可选优惠目录不当作已购买商品。
- 在创建前再次向后端核对报价。金额或项目变动时需要重新确认。
- 创建订单前先保存本地尝试记录。创建请求不自动重试；网络中断导致结果不明时保留“下单结果待确认”，阻止继续创建第二笔订单。服务端明确拒绝下单时显示“下单未成功”，允许重新选择和确认。
- 已知订单的支付宝继续付款复用原订单号。余额扣款请求发出后若结果不明，只查询状态，不重复扣款。
- SDK 返回 `9000` 不直接当作已付款，最终状态以 `order/pay_status` 的布尔结果为准。
- 设备同步请求和“机器已经启动”是不同状态，界面不会把请求发送成功当作已经启动。
- 取消订单先查询是否付款；仅在后端成功确认取消后解除本地未完成订单限制。
- 如果创建请求结果不明且没有拿到订单号，当前版本需要先在原应用核对订单。此版本没有猜测订单号或自行解除这项限制的入口。

## 构建

需要 JDK 17 或 21、Android SDK 35、Build Tools 35.0.0。通过 Android Studio 打开本目录即可；首次构建需要访问 Google Maven 和 Maven Central。

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

Windows 使用 `gradlew.bat`。测试 APK 位于 `app/build/outputs/apk/debug/app-debug.apk`。源码包不含 Android SDK、构建缓存、账号数据或个人发布密钥。`development-debug.p12` 是随本项目公开提供的开发测试签名，密码为 `android`，用于后续测试版本覆盖升级；它不是正式发布签名，正式发布签名尚未配置。

### 本地 Android 运行测试

测试代码位于 `app/src/androidTest/java/dev/rain/laundry/LocalRuntimeTest.kt`。请使用未登录任何账户的独立官方模拟器，Android 15 / API 35、x86_64 默认系统镜像。本次使用的模拟器序列号为 `emulator-5558`；自行运行时替换为自己的模拟器序列号。

```sh
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest
adb -s emulator-5558 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5558 install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s emulator-5558 shell am instrument -w -r -e class dev.rain.laundry.LocalRuntimeTest dev.rain.laundry.test/androidx.test.runner.AndroidJUnitRunner
```

业务测试只在测试 APK 中替换网络客户端，通过 OkHttp 拦截器直接返回合成响应，不调用 `chain.proceed`。正式 APK 不含模拟账户和假响应。测试不会点击确认支付；截图保存在模拟器的 `/sdcard/Android/data/dev.rain.laundry/files/runtime-checks/`。

## 协议来源与实现范围

`core/WireProtocol` 实现样本的请求头签名及下单风控签名。协议版本固定为样本的 `1.144.0`，独立客户端版本由 `app/build.gradle.kts` 中的 `versionName` 定义，两者不应混用。签名中的常量来自样本的公开客户端代码，不是账户密码或服务端私钥。

`data/LaundryApi` 仅允许明确列出的必要业务路径，正式主机固定为 `https://userapi.qiekj.com/`。没有关闭 TLS 校验，也不自动跟随业务接口重定向。只有单元测试可向本机 MockWebServer 发请求。

模式数据尚待真实设备验证，目前显式支持返回数组，以及 `skus`、`skuList`、`list` 包装的数组。未知结构直接提示尚未适配。普通洗衣以外的先享后付、免密签约、蓝牙设备、自动续费、会员优惠组合及附加商品不在本版本范围内。已存在的支付平台扣款授权不会因安装本客户端而自动解除。

## 验证记录

见随源码提供的 `VALIDATION.md`，记录本次实际运行的编译与检查结果。本轮开发没有使用真实手机号、验证码、学校设备或订单，也没有向原业务服务器发送联调请求。网络自动化测试使用本机假响应。

## 主要文件

| 文件 | 用途 |
|---|---|
| `MainActivity.kt` | 扫码、定位授权、支付宝 SDK 拉起 |
| `LaundryViewModel.kt` | 页面状态与登录、下单、订单恢复 |
| `ui/LaundryApp.kt` | Material 3 页面 |
| `ui/AboutScreen.kt` | 关于页面、GitHub 入口及离线 MIT 全文 |
| `ui/DonationDialog.kt` | 打赏收款码展示与图片保存 |
| `ui/GlassNavigationBar.kt` | 小尺寸底栏、拖动手势、放大透镜及回弹 |
| `ui/GlassLensEffect.kt` | AGSL 边缘折射及 RGB 色散 |
| `core/Protocol.kt` | 二维码、签名、报价和支付参数核对 |
| `core/OrderWorkflow.kt` | 防重复下单及未知结果持久化 |
| `core/PaymentWorkflow.kt` | 首次付款与继续付款的顺序、余额结果未知时的等待 |
| `data/SessionVault.kt` | Android Keystore 加密会话及订单 |
| `data/LaundryApi.kt` | 限定业务范围的网络接口 |

## 依赖与文档

Material 3/Compose、AndroidX、OkHttp、Gson、ZXing Embedded 和支付宝 Android SDK 为第三方组件，使用其各自的许可。此工程不包含原版应用的图标、广告组件或整包反编译源码。

- [Compose 官方配置说明](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler)
- [Compose GraphicsLayer 官方说明](https://developer.android.com/develop/ui/compose/graphics/draw/modifiers)
- [ZXing Android Embedded](https://github.com/journeyapps/zxing-android-embedded)
- [支付宝 SDK Maven 坐标](https://central.sonatype.com/artifact/com.alipay.sdk/alipaysdk-android)
