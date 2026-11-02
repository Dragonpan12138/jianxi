package dev.rain.laundry.core

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

interface PurchaseGateway {
    suspend fun quote(device: Device, mode: WashMode): Quote
    suspend fun create(quote: Quote, fix: LocationFix): CreatedOrder
}
class QuoteChanged(val quote: Quote) : Exception("价格已更新，请重新确认")

/** Persist intent before the one non-retryable create request, including cancellation. */
class OrderWorkflow(private val gateway: PurchaseGateway, private val read: () -> LocalOrder?, private val save: (LocalOrder) -> Unit) {
    private val mutex = Mutex()
    suspend fun create(accepted: Quote, method: PayMethod, fix: LocationFix, owner: String, route: PayRoute = PayRoute(method)): LocalOrder = mutex.withLock {
        val current = read()
        if (current != null && !current.phase.finished) throw ClientError("请先处理未完成订单")
        val fresh = gateway.quote(accepted.device, accepted.mode)
        if (fresh.amount != accepted.amount || fresh.itemsJson != accepted.itemsJson || fresh.tradeType != accepted.tradeType) throw QuoteChanged(fresh)
        val attempt = LocalOrder(owner, accepted.device.name, accepted.mode.name, accepted.amount, method, OrderPhase.CREATING,
            thirdChannel = route.thirdChannel, outVoucherId = route.outVoucherId)
        save(attempt)
        try {
            val created = gateway.create(fresh, fix)
            attempt.copy(orderId = created.id, orderNo = created.number, phase = OrderPhase.CREATED).also(save)
        } catch (e: BusinessRejected) {
            save(attempt.copy(phase = OrderPhase.REJECTED))
            throw e
        } catch (e: SessionExpired) {
            save(attempt.copy(phase = OrderPhase.REJECTED))
            throw e
        } catch (e: Exception) {
            save(attempt.copy(phase = OrderPhase.UNCONFIRMED))
            throw e
        }
    }
}
