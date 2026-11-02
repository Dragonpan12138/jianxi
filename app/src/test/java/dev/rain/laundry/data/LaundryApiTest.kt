package dev.rain.laundry.data

import dev.rain.laundry.core.*
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.net.InetAddress

class LaundryApiTest {
    private lateinit var server: MockWebServer
    private lateinit var api: LaundryApi
    @Before fun setup() {
        server = MockWebServer().apply { start(InetAddress.getByName("127.0.0.1"), 0) }
        val testUrl = server.url("/").newBuilder().host("127.0.0.1").build()
        api = LaundryApi({ "example-token" }, "Test", baseUrl = testUrl, now = { 1700000000000 })
    }
    @After fun stop() { server.shutdown() }
    @Test fun registrationSmsUsesPublicTemplateAndNoSession() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":0,"data":"短信已发送"}"""))
        api.sendCode("13800000000")
        val request = server.takeRequest()
        assertEquals("/common/sms/sendCode", request.path)
        assertEquals("POST", request.method)
        assertEquals("", request.getHeader("Authorization"))
        assertEquals(WireProtocol.sign("/common/sms/sendCode", "", "1700000000000"), request.getHeader("sign"))
        val body = request.body.readUtf8()
        assertEquals(setOf("phone=13800000000", "template=reg"), body.split('&').toSet())
    }
    @Test fun loginUsesRealContractAndSignsRequest() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":0,"data":{"token":"new-token"}}"""))
        assertEquals("new-token", api.login("13800000000", "123456"))
        val request = server.takeRequest()
        assertEquals("/user/reg", request.path); assertEquals("POST", request.method)
        assertEquals("", request.getHeader("Authorization"))
        assertEquals(WireProtocol.sign("/user/reg", "", "1700000000000"), request.getHeader("sign"))
        val body = request.body.readUtf8()
        assertTrue(body.contains("verify=123456")); assertFalse(body.contains("token="))
    }
    @Test fun serverRejectionIsNotTreatedAsSuccess() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":1001,"msg":"验证码错误","data":null}"""))
        val error = runCatching { api.login("13800000000", "123456") }.exceptionOrNull()
        assertTrue(error is ClientError); assertEquals("验证码错误", error?.message)
    }
    @Test fun membershipEndpointsAreNotCallable() = runTest {
        assertTrue(runCatching { api.post("alipay/periodicDeductSignUrl", emptyMap()) }.isFailure)
        assertEquals(0, server.requestCount)
    }
    @Test fun orderCreationDoesNotAppendUpsellParameters() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":0,"data":{"orderId":"id","tradeNo":"trade"}}"""))
        val device = Device("g1", "test", "1234", "WASH", "shop", "org", 0, emptyList())
        api.create(Quote(device, WashMode("s1", "wash", "4.00"), "4.00", "[]", 1), LocationFix(30.2, 120.1))
        val request = server.takeRequest(); val body = request.body.readUtf8()
        assertTrue(body.contains("promotions=%5B%5D"))
        assertFalse(body.contains("valueCouponPackChecked")); assertFalse(body.contains("suishoubuItems"))
        assertEquals("30.2", request.getHeader("lat")); assertNotNull(request.getHeader("orderRiskSign"))
    }
    @Test fun previewExplicitlyDisablesAutoSelection() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":0,"data":true}"""))
        server.enqueue(MockResponse().setBody("""{"code":0,"data":{"realPrice":"4","items":[{"goodsId":"g","skuId":"s","amount":"1"}],"promotions":[]}}"""))
        api.quote(Device("g", "test", "1234", "WASH", "shop", "org", 0, emptyList()), WashMode("s", "wash", "4"))
        val availability = server.takeRequest()
        assertEquals("/appoint/checkMachineCanUse", availability.path)
        assertTrue(availability.body.readUtf8().contains("skuId=s"))
        assertTrue(server.takeRequest().body.readUtf8().contains("isAutoSelectPromotion=false"))
    }
    @Test fun onlyBooleanBackendPaidStateIsAccepted() = runTest {
        val order = LocalOrder("owner", "test", "wash", "4.00", PayMethod.ALIPAY, OrderPhase.PAYMENT_PENDING, orderNo = "t1")
        server.enqueue(MockResponse().setBody("""{"code":0,"data":false}""")); assertFalse(api.paid(order))
        server.enqueue(MockResponse().setBody("""{"code":0,"data":true}""")); assertTrue(api.paid(order))
        server.enqueue(MockResponse().setBody("""{"code":0,"data":"9000"}""")); assertTrue(runCatching { api.paid(order) }.isFailure)
    }
    @Test fun cancellationUsesOrderIdAndStringAcknowledgement() = runTest {
        val order = LocalOrder("owner", "test", "wash", "4.00", PayMethod.ALIPAY, OrderPhase.CREATED, orderId = "id1", orderNo = "t1")
        server.enqueue(MockResponse().setBody("""{"code":0,"data":"取消成功"}"""))
        api.cancel(order)
        val request = server.takeRequest()
        assertEquals("/order/cancel", request.path); assertTrue(request.body.readUtf8().contains("orderId=id1"))
    }
    @Test fun obsoleteAuthenticatedSmsEndpointCannotBeCalled() = runTest {
        assertTrue(runCatching { api.post("user/smsCode", mapOf("phone" to "13800000000")) }.exceptionOrNull() is IllegalArgumentException)
        assertEquals(0, server.requestCount)
    }
    @Test fun anUnavailableModeNeverReachesPreviewOrCreate() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":0,"data":false}"""))
        val error = runCatching { api.quote(Device("g", "test", "1234", "00", "shop", "org", 0, emptyList()), WashMode("s", "wash", "4")) }.exceptionOrNull()
        assertTrue(error is ClientError)
        assertEquals(1, server.requestCount)
        assertEquals("/appoint/checkMachineCanUse", server.takeRequest().path)
    }
    @Test fun canonicalDeviceIdAndMachineImeiComeFromDetails() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":0,"data":{"id":"scan-id","categoryCode":"00"}}"""))
        server.enqueue(MockResponse().setBody("""{"code":0,"data":{"goodsId":"canonical-id","name":"洗衣机","imei":"machine-imei","categoryCode":"00","isBluetooth":0,"payment":"before","shopId":"shop","orgId":"org"}}"""))
        server.enqueue(MockResponse().setBody("""{"code":0,"data":[{"skuId":"s1","name":"标准洗","price":"4.00","scanAvailable":true}]}"""))
        val device = api.device(DeviceCode("SN", "serial-number"))
        assertEquals("canonical-id", device.id); assertEquals("machine-imei", device.imei)
        assertEquals("/goods/scan/v2", server.takeRequest().path)
        assertTrue(server.takeRequest().body.readUtf8().contains("goodsId=scan-id"))
        assertTrue(server.takeRequest().body.readUtf8().contains("goodsId=canonical-id"))
    }
    @Test fun unsupportedApplianceStopsBeforeFetchingWashModes() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":0,"data":{"id":"g1"}}"""))
        server.enqueue(MockResponse().setBody("""{"code":0,"data":{"goodsId":"g1","categoryCode":"04","imei":"12345678"}}"""))
        assertTrue(runCatching { api.device(DeviceCode("IMEI", "12345678")) }.exceptionOrNull() is ClientError)
        assertEquals(2, server.requestCount)
    }
    @Test fun skuUnpaidOrderResponseIsAnActionableBusinessRejection() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":2128,"msg":"有未支付订单","data":{"incompleteOrderId":"old-order"}}"""))
        val error = runCatching { api.post("goods/normal/skus", mapOf("goodsId" to "g1")) }.exceptionOrNull()
        assertTrue(error is BusinessRejected); assertEquals(2128, (error as BusinessRejected).code)
        assertTrue(error.message.orEmpty().contains("原应用"))
    }
    @Test fun publicLoginFailureAndProtectedSessionExpiryAreDifferent() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":401,"msg":"未登录"}"""))
        assertTrue(runCatching { api.sendCode("13800000000") }.exceptionOrNull() is BusinessRejected)
        server.enqueue(MockResponse().setBody("""{"code":401,"msg":"未登录"}"""))
        assertTrue(runCatching { api.post("goods/normal/details", mapOf("goodsId" to "g1")) }.exceptionOrNull() is SessionExpired)
    }
    @Test fun forbiddenRequestDoesNotDiscardTheSession() = runTest {
        server.enqueue(MockResponse().setResponseCode(403))
        val error = runCatching { api.post("goods/normal/details", mapOf("goodsId" to "g1")) }.exceptionOrNull()
        assertTrue(error is BusinessRejected); assertFalse(error is SessionExpired)
    }
    @Test fun routedPaymentKeepsItsChannelAndVoucherParameters() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":0,"data":[{"method":13,"autoPayState":0,"thirdChannel":"route-1","outVoucherId":"voucher-1"},{"method":2,"autoPayState":0},{"method":13,"autoPayState":1}]}"""))
        val quote = Quote(Device("g", "test", "1234", "00", "shop", "org", 0, emptyList()), WashMode("s", "wash", "4"), "4.00", "[]", 1)
        val routes = api.channels(quote)
        val route = routes.single { it.method == PayMethod.ALIPAY }
        assertEquals("route-1", route.thirdChannel)
        server.enqueue(MockResponse().setBody("""{"code":0,"data":{"prepayParam":"payload"}}"""))
        api.prepay(LocalOrder("owner", "test", "wash", "4.00", route.method, OrderPhase.CREATED, orderNo = "t1", thirdChannel = route.thirdChannel, outVoucherId = route.outVoucherId))
        server.takeRequest()
        val request = server.takeRequest()
        assertEquals("/pay/unify/prePay", request.path)
        val body = request.body.readUtf8()
        assertTrue(body.contains("thirdChannel=route-1")); assertTrue(body.contains("outVoucherId=voucher-1"))
        assertTrue(body.contains("againFlag=0"))
    }
    @Test fun explicitCreateRejectionRemainsDistinguishableFromLostResponses() = runTest {
        val quote = Quote(Device("g", "test", "1234", "00", "shop", "org", 0, emptyList()), WashMode("s", "wash", "4"), "4.00", "[]", 1)
        server.enqueue(MockResponse().setBody("""{"code":4001,"msg":"设备不可用"}"""))
        assertTrue(runCatching { api.create(quote, LocationFix(30.2, 120.1)) }.exceptionOrNull() is BusinessRejected)
        server.enqueue(MockResponse().setResponseCode(503))
        val uncertain = runCatching { api.create(quote, LocationFix(30.2, 120.1)) }.exceptionOrNull()
        assertTrue(uncertain is ClientError); assertFalse(uncertain is BusinessRejected)
    }
}
