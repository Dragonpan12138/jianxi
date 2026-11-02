# 0.1.1 接口与流程复查

复查日期：2026-11-02。依据用户提供的原版 APK 1.144.0 的 Retrofit 注解、调用页面、ViewModel、数据模型及 DEX 指令，逐项核对本客户端。以下不是生产服务器流量记录。

| 环节 | 原版证据 | 复查与修正 |
|---|---|---|
| 登录短信 | `PhoneLoginActivity.onClick$lambda$5` → `LoginViewModel.sendCode(phone,"reg")` → `ApiService.sendCode` | 修正为 `common/sms/sendCode`，包含 `template=reg`。0.1.0 的 `user/smsCode` 是另一个短信接口，不是此登录页面的入口 |
| 验证码登录 | `LoginViewModel.login` → `user/reg` | 核对 `channel=android_app`、`phone`、`verify`。登录前不带残留会话 |
| 扫码 | `HomeScanCodeAct.scanCodeResult`、`ScanCodeVm.scanV2` | `goods/scan/v2`；保留原始参数名 IMEI/SN/NQT，不把 SN 当成机器 IMEI |
| 设备详情 | `LockingAct.createObserver$lambda$3` | 以详情中的 `goodsId` 为正式编号，`imei` 为机器标识；依据 `GoodsTypeEnum` 支持 `00` 洗衣机和 `01` 洗鞋机；蓝牙、先用后付及其他品类直接停止此版本的下单流程 |
| 模式列表 | `LockingAct.createObserver$lambda$7$lambda$6` | 正常 `code=0` 的 `data` 是 SKU 数组；`code=2128` 表示存在未支付订单，提示先处理，不按普通数组解析 |
| 模式可用性 | `WashViewModel$checkMachineCanUse$1`、`WashSkuAct` | 增加 `appoint/checkMachineCanUse`，表单 `skuId`；返回布尔值，false 时不报价、不创建订单 |
| 订单预览 | `OrderPayPreviewVm.orderPreview`、`tradePreviewV2` | 核对真实路径为 `trade/preview/v4`，表单 `items`、`promotions`、`isAutoSelectPromotion`。仅接受明确选择的洗衣项目 |
| 创建订单 | `OrderPayPreviewVm.createOrder` 及其协程 | 核对 `trade/create` 和 `imei/categoryCode/lat/lng` 请求头，以及 `items/promotions` 表单和风控签名 |
| 支付路由 | `PayModeVm.getPrePayChannel`、`PayModeFragment.appPay` | `payChannelRoute/prePay` 的字段已核对。保留选定路由的 `thirdChannel`、`outVoucherId`，并随本地订单保存，预支付时传回；不是只保留支付类型 |
| 预支付 | `PayModeVm.prePay`、`prePay$default` | `pay/unify/prePay`；首次 `againFlag=0`，恢复时复用订单；只接受与已确认金额一致的支付宝单次付款参数 |
| 余额 | `PayModeVm.walletPay` | `pay/unify/pay`，字段 `orderNo`、`payType=2`。结果未知后不重复扣款 |
| 支付查询 | `PayStateVm$queryPayStatus$1` | `order/pay_status`，字段 `orderNo/payType`，数据类型布尔；SDK 的 `9000` 不直接当作后端付款确认 |
| 设备同步 | `PayStateVm$orderSync$1` | `order/sync`，字段 `orderNo/payType`；仅在确认付款后请求一次，不把请求完成当作设备已经启动 |
| 取消 | `OrderDetailsViewModel$orderCancel$1`、`ApiService.orderCancel` | `order/cancel`，字段 `orderId`；原版返回 `ApiResponse<String>`，不能误写成 Boolean |
| 失败状态 | 客户端工作流与上述响应契约 | 区分服务端非零业务码的明确拒绝与超时/无效响应的未知结果。前者可以重新确认，后者保留记录并阻止自动重试；HTTP 403 不等同于需要清除登录会话 |

本次增加的测试先复现了 0.1.0 的短信路径错误，然后覆盖匿名短信模板、空会话签名、正式设备编号、非洗衣设备拒绝、模式不可用、未支付订单状态、支付路由参数保存和明确拒单恢复。

未进行的验证：真实短信接收、实际学校二维码响应、原平台账号风控、设备风控、新包名与支付签名兼容性、真实余额扣款和洗衣机启动。短信和付款都没有用真实账号自动试发。签约、银行专用 SDK、先用后付、蓝牙控制仍不在当前实现范围内。普通业务接口存在不代表所有设备类型都可用。
