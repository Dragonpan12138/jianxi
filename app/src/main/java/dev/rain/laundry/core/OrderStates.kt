package dev.rain.laundry.core

/** Status meanings from the supplied APK's OrderDetailsAct.loadDetails. */
enum class RemoteOrderStatus(val wire: Int) {
    UNPAID(0), CLOSED(1), IN_USE(2), COMPLETED(3), REFUNDING(4), REFUNDED(5)
}

object OrderStates {
    fun apply(order: LocalOrder, status: RemoteOrderStatus): LocalOrder = when (status) {
        // An unpaid snapshot does not prove that a previously submitted balance payment failed.
        RemoteOrderStatus.UNPAID -> order
        RemoteOrderStatus.CLOSED -> order.copy(phase = OrderPhase.CLOSED)
        // These backend states already reflect use/settlement; do not start or sync the machine again.
        RemoteOrderStatus.IN_USE -> order.copy(phase = OrderPhase.PAID, syncRequested = true)
        RemoteOrderStatus.COMPLETED -> order.copy(phase = OrderPhase.COMPLETED, syncRequested = true)
        RemoteOrderStatus.REFUNDING -> order.copy(phase = OrderPhase.REFUNDING, syncRequested = true)
        RemoteOrderStatus.REFUNDED -> order.copy(phase = OrderPhase.REFUNDED, syncRequested = true)
    }
}
