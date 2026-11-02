package dev.rain.laundry.data

import com.google.gson.*
import dev.rain.laundry.core.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.io.IOException
import java.util.concurrent.TimeUnit

class LaundryApi(
    private val token: () -> String,
    private val brand: String,
    private val client: OkHttpClient = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS).callTimeout(30, TimeUnit.SECONDS).retryOnConnectionFailure(false)
        .followRedirects(false).followSslRedirects(false).build(),
    private val baseUrl: HttpUrl = "https://userapi.qiekj.com/".toHttpUrl(),
    private val now: () -> Long = System::currentTimeMillis
) : PurchaseGateway {
    companion object {
        private val ANONYMOUS_PATHS = setOf("common/sms/sendCode", "user/reg")
        val ALLOWED_PATHS = setOf("common/sms/sendCode", "user/reg", "goods/scan/v2", "goods/normal/details",
            "goods/normal/skus", "trade/preview/v4", "trade/create", "payChannelRoute/prePay",
            "pay/unify/prePay", "pay/unify/pay", "order/pay_status", "order/sync", "order/cancel", "appoint/checkMachineCanUse")
        private val PAYMENT_OPERATIONS = mapOf(
            "appoint/checkMachineCanUse" to "核对设备状态失败",
            "trade/preview/v4" to "核对洗衣金额失败",
            "trade/create" to "创建订单失败",
            "payChannelRoute/prePay" to "获取支付方式失败",
            "pay/unify/prePay" to "获取支付信息失败",
            "pay/unify/pay" to "余额付款未完成",
            "order/pay_status" to "查询付款状态失败",
            "order/cancel" to "取消订单失败"
        )
    }

    suspend fun post(path: String, fields: Map<String, String>, risk: Pair<Device, LocationFix>? = null): JsonElement = withContext(Dispatchers.IO) {
        require(path in ALLOWED_PATHS) { "Unsupported business endpoint" }
        require(baseUrl.isHttps || baseUrl.host in setOf("localhost", "127.0.0.1"))
        val anonymous = path in ANONYMOUS_PATHS
        val authorization = if (anonymous) "" else token()
        val timestamp = now().toString()
        val form = FormBody.Builder().apply {
            fields.forEach { (key, value) -> add(key, value) }
            if (authorization.isNotEmpty()) add("token", authorization)
        }.build()
        val request = Request.Builder().url(baseUrl.newBuilder().addPathSegments(path).build())
            .header("Authorization", authorization).header("Version", WireProtocol.VERSION)
            .header("channel", WireProtocol.CHANNEL).header("phoneBrand", brand.filter { it.code in 32..126 })
            .header("deviceId", "").header("timestamp", timestamp)
            .header("sign", WireProtocol.sign("/$path", authorization, timestamp))
            .header("User-Agent", "QEUser/${WireProtocol.VERSION} (com.qiekj.user; build:294; Android; userChannel:android_app) OkHttp/4.12.0")
            .post(form)
        risk?.let { (device, fix) ->
            request.header("imei", device.imei).header("categoryCode", device.category)
                .header("lat", fix.latitude.toString()).header("lng", fix.longitude.toString())
                .header("orderRiskTimestamp", timestamp)
                .header("orderRiskSign", WireProtocol.riskSign("/$path", authorization, timestamp, device.imei, device.category, fix))
        }
        try {
            client.newCall(request.build()).execute().use { response ->
                if (response.code == 401 && !anonymous) throw SessionExpired()
                if (response.code == 403) throw BusinessRejected(403, "本次请求被平台拒绝，请稍后重试（403）", PAYMENT_OPERATIONS[path])
                if (!response.isSuccessful) throw ClientError("服务暂时不可用（${response.code}）")
                val body = response.body ?: throw ClientError("服务器没有返回内容")
                if (body.contentLength() > 2_000_000) throw ClientError("服务器返回内容过大")
                val source = body.source()
                if (source.request(2_000_001)) throw ClientError("服务器返回内容过大")
                val root = try { JsonParser.parseString(source.readUtf8()).asJsonObject }
                catch (_: Exception) { throw ClientError("服务器返回格式变化，暂时无法处理") }
                val code = root.text("code").toIntOrNull() ?: throw ClientError("服务器响应缺少有效状态码")
                if (code != 0) {
                    val message = root.text("msg", "请求失败（$code）").take(180)
                    if (!anonymous && (code == 401 || message in setOf("未登录", "登录已过期", "登录失效", "请重新登录"))) throw SessionExpired()
                    if (code == 2128 && path == "goods/normal/skus") throw BusinessRejected(code, "此设备存在未支付订单，请先在原应用处理")
                    throw BusinessRejected(code, message, PAYMENT_OPERATIONS[path])
                }
                root.get("data") ?: JsonNull.INSTANCE
            }
        } catch (_: IOException) { throw ClientError("网络连接失败，请检查网络后重试") }
    }

    suspend fun sendCode(phone: String) { post("common/sms/sendCode", mapOf("phone" to phone, "template" to "reg")) }
    suspend fun login(phone: String, code: String): String {
        val result = post("user/reg", mapOf("channel" to WireProtocol.CHANNEL, "phone" to phone, "verify" to code)).asJsonObject
        return result.text("token").takeIf { it.isNotBlank() } ?: throw ClientError("登录响应缺少会话信息")
    }
    suspend fun device(code: DeviceCode): Device {
        val scan = post("goods/scan/v2", mapOf(code.key to code.value)).asJsonObject
        if (scan.text("jumpToAlipayFlag2") == "true") throw ClientError("此二维码需要通过支付宝扫码，请使用支付宝扫描原二维码")
        val scanId = scan.text("id").ifBlank { throw ClientError("设备识别响应缺少编号") }
        val detail = post("goods/normal/details", mapOf("goodsId" to scanId)).asJsonObject
        val id = detail.text("goodsId", scanId).ifBlank { throw ClientError("设备详情缺少编号") }
        val category = detail.text("categoryCode", scan.text("categoryCode"))
        if (category !in setOf("00", "01")) throw ClientError("当前版本仅支持洗衣机和洗鞋机")
        if (detail.text("isBluetooth", "0") == "1") throw ClientError("此设备需要蓝牙启动，当前版本暂不支持")
        if (detail.text("payment") == "after") throw ClientError("此设备使用先用后付，当前版本暂不支持")
        val imei = detail.text("imei").ifBlank { throw ClientError("设备详情缺少标识，请先在原应用核对设备") }
        val skuResponse = post("goods/normal/skus", mapOf("goodsId" to id))
        val modes = parseModes(skuResponse)
        if (modes.isEmpty()) throw ClientError("当前设备没有可用的洗衣模式，请确认设备类型")
        return Device(id, detail.text("name", "洗衣机"), imei,
            category, detail.text("shopId"), detail.text("orgId"),
            detail.text("remainTime", "0").toIntOrNull() ?: 0, modes, detail.text("deviceErrorMsg"))
    }
    fun parseModes(response: JsonElement): List<WashMode> {
        // Variants must be explicitly recognized. Unknown schemas fail closed.
        val data = if (response.isJsonObject && response.asJsonObject.has("code")) response.asJsonObject.get("data") else response
        val array = when {
            data == null || data.isJsonNull -> null
            data.isJsonArray -> data.asJsonArray
            data.isJsonObject -> listOf("skus", "skuList", "list").firstNotNullOfOrNull { key ->
                data.asJsonObject.get(key)?.takeIf { it.isJsonArray }?.asJsonArray
            }
            else -> null
        } ?: throw ClientError("洗衣模式数据格式尚未适配，请保留二维码供后续验证")
        return array.mapNotNull { element ->
            if (!element.isJsonObject) return@mapNotNull null
            val item = element.asJsonObject
            if (item.text("scanAvailable", "true") == "false") return@mapNotNull null
            val id = item.text("skuId")
            if (id.isBlank()) null else WashMode(id, item.text("name", "洗衣模式"), money(item.text("price")), item.text("feature"))
        }
    }
    override suspend fun quote(device: Device, mode: WashMode): Quote {
        val available = post("appoint/checkMachineCanUse", mapOf("skuId" to mode.id))
        if (!available.isJsonPrimitive || !available.asJsonPrimitive.isBoolean) throw ClientError("设备可用状态格式尚未适配")
        if (!available.asBoolean) throw ClientError("此洗衣模式暂不可用，请刷新设备后重试")
        // APK 1.144.0 sends numeric string flags: "0" disables automatic promotion selection.
        val fields = mutableMapOf("items" to PurchaseRules.items(device, mode),
            "promotions" to "[]", "isAutoSelectPromotion" to "0")
        if (device.orgId.isNotBlank()) {
            fields["forbiddenPromotions"] = PurchaseRules.goldExclusion(device.orgId)
        }
        val data = post("trade/preview/v4", fields).asJsonObject
        return PurchaseRules.verifyQuote(data, device, mode)
    }
    suspend fun channels(quote: Quote): List<PayRoute> {
        val device = quote.device
        // APK 1.144.0: OrderPayPreviewAct -> PayModeFragment passes orgId, despite the wire name shopId.
        val channelShopId = device.orgId
        if (channelShopId.toLongOrNull() == null)
            throw ClientError("设备机构编号无效，请重新扫码识别设备")
        val result = post("payChannelRoute/prePay", mapOf("imei" to device.imei, "goodsId" to device.id,
            "hitAd" to "0", "payPrice" to quote.amount, "useTicket" to "0", "shopId" to channelShopId,
            "combineOrderStatus" to "false", "confirmSelectedStatus" to "false"))
        if (!result.isJsonArray) throw ClientError("支付渠道响应格式尚未适配")
        val supported = result.asJsonArray.mapNotNull {
            if (!it.isJsonObject) return@mapNotNull null
            val channel = it.asJsonObject
            if (channel.text("autoPayState", "0") == "1") return@mapNotNull null
            val method = PayMethod.entries.firstOrNull { method -> method.wire == channel.text("method") } ?: return@mapNotNull null
            PayRoute(method, channel.text("thirdChannel"), channel.text("outVoucherId"))
        }.groupBy { it.method }.values.map { routes ->
            routes.firstOrNull { it.thirdChannel.isBlank() && it.outVoucherId.isBlank() } ?: routes.first()
        }
        if (supported.isEmpty()) throw ClientError("此设备暂未提供可用的单次支付渠道")
        return supported
    }
    override suspend fun create(quote: Quote, fix: LocationFix): CreatedOrder {
        val data = post("trade/create", mapOf("items" to quote.itemsJson,
            "promotions" to PurchaseRules.goldExclusion(quote.device.orgId)), quote.device to fix).asJsonObject
        val id = data.text("orderId"); val no = data.text("tradeNo")
        if (id.isBlank() || no.isBlank()) throw ClientError("订单返回内容不完整，请核对订单后再继续")
        return CreatedOrder(id, no)
    }
    suspend fun prepay(order: LocalOrder): String {
        val fields = mutableMapOf("orderNo" to order.orderNo, "payType" to order.payMethod.wire, "againFlag" to if (order.phase == OrderPhase.PAYMENT_PENDING) "1" else "0")
        order.thirdChannel?.takeIf { it.isNotBlank() }?.let { fields["thirdChannel"] = it }
        order.outVoucherId?.takeIf { it.isNotBlank() }?.let { fields["outVoucherId"] = it }
        val data = post("pay/unify/prePay", fields).asJsonObject
        return data.text("prepayParam").ifBlank { throw ClientError("未取得支付参数，请查询订单状态") }
    }
    suspend fun balancePay(order: LocalOrder) { post("pay/unify/pay", mapOf("orderNo" to order.orderNo, "payType" to "2")) }
    suspend fun paid(order: LocalOrder): Boolean {
        val data = post("order/pay_status", mapOf("orderNo" to order.orderNo, "payType" to order.payMethod.wire))
        if (!data.isJsonPrimitive || !data.asJsonPrimitive.isBoolean) throw ClientError("支付状态格式尚未适配")
        return data.asBoolean
    }
    suspend fun sync(order: LocalOrder) { post("order/sync", mapOf("orderNo" to order.orderNo, "payType" to order.payMethod.wire)) }
    suspend fun cancel(order: LocalOrder) {
        val result = post("order/cancel", mapOf("orderId" to order.orderId))
        // The supplied APK declares ApiResponse<String>; code=0 plus string data is acknowledgement.
        if (!result.isJsonPrimitive || !result.asJsonPrimitive.isString) throw ClientError("取消结果尚未确认，请刷新订单")
    }
}
