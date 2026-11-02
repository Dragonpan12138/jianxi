# 接口与流程复查

## 0.1.6 空值与原版默认值规则

用户反馈报价返回后提示“报价优惠选项格式尚未适配”。原实现对显式 JSON `null` 与字段缺失采用了不同处理，前者会触发格式异常。

- `NetworkApi.setRetrofitBuilder$lambda$2` 明确启用 `coerceInputValues=true`。
- `Promotions` 的 `options`、`participateList` 默认空列表，`isUsed` 默认 false，`promotionType` 默认 0。
- `PromotionsItem.isUsed` 默认 false；`OrderPayPreview.tradeType` 默认 0。
- 对上述字段的显式 null 恢复这些默认值。空列表不会跳过顶层已选状态检查，子选项的已选状态也继续检查。
- 非空的对象、文本或异常列表成员不猜测转换；提示中附字段名及类型，保留字段内容隐私。

先用 `options:null` 与 `participateList:null` 的本机 JSON 用例复现相同提示，修正后通过。另覆盖可选字段为 null、空列表不能隐藏已选优惠、未知结构仍拒绝等情形。未取得用户手机的完整响应，此次确认的是空值兼容缺口，实际设备仍需复测。

## 0.1.5 报价字段值与优惠目录

用户确认错误发生于“确认模式，查看金额”，服务端提示 `code=1`、`参数不正确`。依据已保存的 1.144.0 APK，再次核对实际调用点及 DTO 序列化字段：

| 原版证据 | 确认与修正 |
|---|---|
| `OrderPayPreviewAct$orderPre$1.invokeSuspend` | 自动优惠分支传 `"1"`，手动选择分支传 `"0"`；修正旧实现的 `isAutoSelectPromotion=false` 为 `0` |
| `OrderPayPreviewVm.orderPreview` | `orgId` 非空时，`forbiddenPromotions` 包含 `promotionId=0`、`promotionType=4`、`assetId=0`、`oldPromotionId=3482` 及该 `orgId`；补齐此字段 |
| `OrderPayPreviewAct.createOrder` | 支付宝或钱包付款时补入同一条“不使用金币”的记录；创建请求与此约定保持一致，不复制优惠目录中其他资产 |
| `Promotions`、`PromotionsItem` 及其 serializer | 优惠目录通过布尔字段 `isUsed` 标识是否使用，缺省为 false；区分未使用的可选目录与实际已选资产。仅允许精确匹配的无金币记录作为排除项，其他已使用优惠继续拒绝 |
| `GoodsItem`、`WashSkuAct.toOrder` | 再次核对设备、SKU、数量及默认项目字段，保留单个洗衣项目检查 |

新增本机契约测试：旧请求被模拟服务按原版字段约定拒绝并返回 `code=1`；修正后报价通过。另覆盖无 `orgId` 时不发送机构排除项、可选优惠目录、已使用或格式异常优惠的拒绝。这些是本地模拟验证，没有向用户设备提交报价、订单或付款。

## 0.1.4 付款阶段复查

复查日期：2026-11-02。离线核对用户本次提供的胖乖生活 1.144.0（versionCode 294）APK。用户照片中的二维码可解码为 NQT 参数，现有解析器支持该类型；未将真实设备标识写入公开测试或文档。

| 环节 | 原版证据 | 本轮处理 |
|---|---|---|
| 创建后的首次付款 | `OrderPayPreviewAct.createObserver$lambda$39` 调用 `PayModeFragment.appPay`；后者直接进入余额付款或 `PayModeVm.prePay` | 修正原先在新订单后先请求 `order/pay_status` 的顺序。`CREATED` 状态直接初始化付款；`PAYMENT_PENDING` 才按恢复付款规则先查状态 |
| 预支付与查询 | `PayModeVm.prePay`、`PayStateVm.queryPayStatus` | 再次核对 `orderNo/payType/againFlag` 及路由字段。保留原订单号，余额未知结果只查询、不重复提交扣款 |
| 创建表单与请求头 | `OrderPayPreviewVm.createOrder`、`ApiService.orderCreate`、`HeadInterceptor` | 核对 `items/promotions`、设备与定位请求头、风控时间戳及 SHA-256 签名。只根据离线证据核对，没有向真实设备提交订单 |
| 项目参数 | `WashSkuAct.toOrder`、`OrderPreviewQuest` 默认构造器 | 核对默认数量与商品字段；普通洗衣的空 `price` 与 `soldType=1` 为原版默认值，未据报错猜改这些字段 |
| 报错定位 | 当前客户端错误处理 | 为付款相关业务拒绝补充操作阶段与服务端错误码，区分创建、获取支付信息和查询状态失败 |

保留人工刷新付款状态和取消前查付款状态的入口。支付初始化被明确拒绝后，查询同一订单是否已在其他客户端付款；确认已付款则恢复状态，查询失败则保留初始化错误，不重新创建或重复提交付款。

此次没有真实接口错误响应或抓包，因此“支付初始化前查询状态”是已确认的流程差异，不等于已经证明它就是本次“参数不正确”的服务器原因。设备正在使用，本轮仅执行本机模拟测试；需待设备空闲后验证实际结果。

## 0.1.1 接口与流程复查

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
