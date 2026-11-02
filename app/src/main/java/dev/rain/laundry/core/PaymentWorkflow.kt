package dev.rain.laundry.core

/** A CREATED order has not started payment yet; payment status is queried after initiation. */
class PaymentWorkflow(
    private val queryPaid: suspend (LocalOrder) -> Boolean,
    private val onPaid: suspend (LocalOrder) -> Unit,
    private val startPayment: suspend (LocalOrder) -> Unit,
    private val onBalancePending: () -> Unit
) {
    suspend fun startOrResume(order: LocalOrder) {
        if (order.phase == OrderPhase.CREATED) {
            startPayment(order)
            return
        }
        if (order.phase != OrderPhase.PAYMENT_PENDING) {
            throw ClientError("订单状态尚未确认，请先核对订单")
        }
        if (queryPaid(order)) {
            onPaid(order)
            return
        }
        if (order.payMethod == PayMethod.BALANCE) {
            onBalancePending()
            return
        }
        startPayment(order)
    }
}
