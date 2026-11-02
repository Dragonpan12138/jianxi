package dev.rain.laundry

import android.content.ContentUris
import android.graphics.Bitmap
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.provider.MediaStore
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.rain.laundry.data.LaundryApi
import kotlinx.coroutines.flow.MutableStateFlow
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okhttp3.MediaType.Companion.toMediaType
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

/** Runs on a fresh local emulator. All LaundryApi requests are intercepted before networking. */
@RunWith(AndroidJUnit4::class)
class LocalRuntimeTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val automation get() = instrumentation.uiAutomation
    private val screenshots get() = File(instrumentation.targetContext.getExternalFilesDir(null), "runtime-checks").apply { mkdirs() }

    @Test fun loginAboutAndOfflineLicenseRenderAndReturn() {
        ActivityScenario.launch(MainActivity::class.java).use {
            awaitText("手机号登录")
            capture("01-login")
            click("关于简洗")
            awaitText("GitHub · 项目源码")
            awaitText("版本 ${BuildConfig.VERSION_NAME}")
            capture("02-about")
            click("打赏支持")
            awaitText("支付宝打赏收款码")
            capture("11-donation")
            val previousImages = savedDonationImages()
            click("保存收款码")
            awaitText("已保存到相册")
            val createdImages = savedDonationImages() - previousImages
            try {
                assertEquals(1, createdImages.size)
                val context = instrumentation.targetContext
                val original = context.resources.openRawResource(R.raw.donation_alipay).use { it.readBytes() }
                val saved = context.contentResolver.openInputStream(createdImages.single())!!.use { it.readBytes() }
                assertArrayEquals("Saved QR image must preserve the supplied bytes", original, saved)
                capture("12-donation-saved")
            } finally {
                createdImages.forEach { instrumentation.targetContext.contentResolver.delete(it, null, null) }
            }
            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            awaitText("GitHub · 项目源码")
            scrollToText("阅读完整协议")
            click("阅读完整协议")
            awaitText("Permission is hereby granted")
            capture("03-license")
            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            awaitText("阅读完整协议")
            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            awaitText("手机号登录")
        }
    }

    @Test fun pastedDeviceReachesCheckoutWithNullPromotionLists() = withLocalSession { vm, calls ->
        awaitText("开始洗衣")
        capture("04-home")
        click("粘贴设备码")
        val editor = awaitNode { it.isEditable }
        assertTrue(editor.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                "https://example.invalid/skip?NQT=00000000-0000-4000-8000-000000000001")
        }))
        click("识别设备")
        awaitText("选择洗衣模式")
        awaitText("本地测试洗衣机")
        capture("05-device")
        click("确认模式，查看金额")
        awaitText("确认这一次洗衣")
        await { !vm.state.value.busy }
        assertEquals(Page.CHECKOUT, vm.state.value.page)
        assertEquals("4.00", vm.state.value.quote?.amount)
        assertEquals(2, vm.state.value.methods.size)
        assertNull(vm.state.value.order)
        capture("06-checkout")
        assertEquals(listOf("/goods/scan/v2", "/goods/normal/details", "/goods/normal/skus",
            "/appoint/checkMachineCanUse", "/trade/preview/v4", "/payChannelRoute/prePay"), calls.toList())

        val viewport = awaitNode { it.isScrollable }
        val viewportBounds = Rect().also(viewport::getBoundsInScreen)
        val navigationBounds = Rect().also(awaitText("订单")::getBoundsInScreen)
        assertTrue("The scroll viewport must end above the floating navigation bar",
            viewportBounds.bottom <= navigationBounds.top)
        // Reveal the final payment action without invoking it or requesting location.
        viewport.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
        instrumentation.waitForIdleSync()
        awaitText("确认支付 ¥4.00")
        val paymentBounds = Rect().also(awaitText("确认支付 ¥4.00")::getBoundsInScreen)
        assertTrue("Payment label must remain fully above the navigation bar",
            paymentBounds.height() > 0 && paymentBounds.bottom <= navigationBounds.top)
        capture("06-checkout")

        // Exercise the real pointer path, including Android RuntimeShader glass rendering.
        val tab = awaitText("订单")
        val rect = Rect().also(tab::getBoundsInScreen)
        val downTime = SystemClock.uptimeMillis()
        injectTouch(downTime, MotionEvent.ACTION_DOWN, rect.exactCenterX(), rect.exactCenterY())
        SystemClock.sleep(180)
        capture("07-glass-pressed")
        injectTouch(downTime, MotionEvent.ACTION_UP, rect.exactCenterX(), rect.exactCenterY())
        awaitText("我的订单")
        capture("08-orders")
        assertNull(vm.state.value.order)
    }

    @Test fun selectedAndMalformedPromotionsStopBeforeOrderCreation() {
        for ((promotions, expected, name) in listOf(
            Triple("""[{"promotionType":1,"isUsed":true,"options":null,"participateList":null}]""",
                "报价附加了未选择的优惠", "09-selected-promotion-blocked"),
            Triple("""[{"promotionType":7,"isUsed":false,"options":{},"participateList":null}]""",
                "options：对象", "10-malformed-promotion-blocked")
        )) withLocalSession(promotions) { vm, calls ->
            instrumentation.runOnMainSync { vm.scan("SN=LOCAL-TEST-DEVICE") }
            await { !vm.state.value.busy && vm.state.value.page == Page.DEVICE }
            instrumentation.runOnMainSync { vm.preview() }
            await { !vm.state.value.busy && vm.state.value.message?.contains(expected) == true }
            awaitText(expected)
            assertEquals(Page.DEVICE, vm.state.value.page)
            assertNull(vm.state.value.quote)
            assertNull(vm.state.value.order)
            assertFalse(calls.any { it == "/trade/create" || it.startsWith("/pay/") })
            capture(name)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun withLocalSession(
        promotions: String = """[{"promotionType":7,"isUsed":null,"options":null,"participateList":null}]""",
        test: (LaundryViewModel, CopyOnWriteArrayList<String>) -> Unit
    ) {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var vm: LaundryViewModel
            lateinit var state: MutableStateFlow<UiState>
            lateinit var api: LaundryApi
            lateinit var oldClient: OkHttpClient
            lateinit var initial: UiState
            val calls = CopyOnWriteArrayList<String>()
            val clientField = LaundryApi::class.java.getDeclaredField("client").apply { isAccessible = true }
            scenario.onActivity { activity ->
                vm = MainActivity::class.java.getDeclaredMethod("getVm").apply { isAccessible = true }.invoke(activity) as LaundryViewModel
                state = LaundryViewModel::class.java.getDeclaredField("_state").apply { isAccessible = true }.get(vm) as MutableStateFlow<UiState>
                api = LaundryViewModel::class.java.getDeclaredField("api").apply { isAccessible = true }.get(vm) as LaundryApi
                oldClient = clientField.get(api) as OkHttpClient
                initial = state.value
                val localClient = OkHttpClient.Builder().addInterceptor { chain ->
                    val request = chain.request()
                    val path = request.url.encodedPath
                    calls.add(path)
                    val body = request.body as? FormBody
                    val fields = body?.let { form -> (0 until form.size).associate { form.name(it) to form.value(it) } }.orEmpty()
                    val response = when (path) {
                        "/goods/scan/v2" -> """{"code":0,"data":{"id":"local-device","categoryCode":"00"}}"""
                        "/goods/normal/details" -> """{"code":0,"data":{"goodsId":"local-device","name":"本地测试洗衣机","imei":"LOCAL-TEST-IMEI","categoryCode":"00","shopId":"b6da19d1-118b-4f68-967a-000000000001","orgId":3100001,"payment":"before","isBluetooth":0,"remainTime":0}}"""
                        "/goods/normal/skus" -> """{"code":0,"data":[{"skuId":"local-sku","name":"标准洗","price":"4.00","scanAvailable":true}]}"""
                        "/appoint/checkMachineCanUse" -> """{"code":0,"data":true}"""
                        "/trade/preview/v4" -> if (fields["isAutoSelectPromotion"] == "0" && fields["forbiddenPromotions"]?.contains("3100001") == true)
                            """{"code":0,"data":{"realPrice":"4.00","tradeType":null,"items":[{"goodsId":"local-device","skuId":"local-sku","amount":1}],"promotions":$promotions}}"""
                        else """{"code":1,"msg":"本地测试：报价参数不正确"}"""
                        "/payChannelRoute/prePay" -> if (fields["shopId"] == "3100001" && fields["goodsId"] == "local-device" && fields["imei"] == "LOCAL-TEST-IMEI")
                            """{"code":0,"data":[{"method":13,"autoPayState":0},{"method":2,"autoPayState":0}]}"""
                        else """{"code":1,"msg":"Failed to convert property 'shopId' to java.lang.Long"}"""
                        else -> """{"code":1,"msg":"本地测试已阻止非预期接口"}"""
                    }
                    // Never call chain.proceed: no request reaches a socket or the production service.
                    Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("Local fixture")
                        .body(response.toResponseBody("application/json; charset=utf-8".toMediaType())).build()
                }.build()
                clientField.set(api, localClient)
                state.value = initial.copy(loggedIn = true, phoneLabel = "本地模拟账户", page = Page.HOME)
            }
            try { test(vm, calls) }
            finally {
                instrumentation.runOnMainSync {
                    state.value = initial
                    clientField.set(api, oldClient)
                }
            }
        }
    }

    private fun await(condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 12_000
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return
            SystemClock.sleep(100)
        }
        fail("Timed out waiting for Android state")
    }

    private fun find(node: AccessibilityNodeInfo?, predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        if (node == null) return null
        if (predicate(node)) return node
        for (i in 0 until node.childCount) find(node.getChild(i), predicate)?.let { return it }
        return null
    }

    private fun awaitNode(predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo {
        var found: AccessibilityNodeInfo? = null
        await { found = find(automation.rootInActiveWindow, predicate); found != null }
        return requireNotNull(found)
    }

    private fun awaitText(text: String) = awaitNode {
        it.text?.contains(text) == true || it.contentDescription?.contains(text) == true
    }

    private fun scrollToText(text: String) {
        repeat(8) {
            if (find(automation.rootInActiveWindow) { it.text?.contains(text) == true } != null) return
            awaitNode { it.isScrollable }.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            SystemClock.sleep(250)
        }
        awaitText(text)
    }

    private fun savedDonationImages(): Set<Uri> {
        val images = mutableSetOf<Uri>()
        instrumentation.targetContext.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Images.Media._ID),
            "${MediaStore.Images.Media.DISPLAY_NAME} LIKE ? AND ${MediaStore.Images.Media.OWNER_PACKAGE_NAME} = ?",
            arrayOf("简洗-支付宝收款码%", instrumentation.targetContext.packageName), null
        )?.use { cursor ->
            while (cursor.moveToNext()) images.add(ContentUris.withAppendedId(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cursor.getLong(0)))
        }
        return images
    }

    private fun click(text: String) {
        await {
            var node = find(automation.rootInActiveWindow) {
                it.text?.contains(text) == true || it.contentDescription?.contains(text) == true
            }
            while (node != null && !node.isClickable) node = node.parent
            node != null && node.isEnabled && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        }
        instrumentation.waitForIdleSync()
    }

    private fun injectTouch(downTime: Long, action: Int, x: Float, y: Float) {
        val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
        try { assertTrue(automation.injectInputEvent(event, true)) } finally { event.recycle() }
    }

    private fun capture(name: String) {
        instrumentation.waitForIdleSync()
        SystemClock.sleep(180)
        val bitmap = requireNotNull(automation.takeScreenshot()) { "Android screenshot unavailable" }
        try { File(screenshots, "$name.png").outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) } }
        finally { bitmap.recycle() }
    }
}
