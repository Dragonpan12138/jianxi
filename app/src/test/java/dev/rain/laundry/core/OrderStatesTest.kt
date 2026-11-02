package dev.rain.laundry.core

import org.junit.Assert.*
import org.junit.Test

class OrderStatesTest {
    private val pending = LocalOrder("owner", "test", "wash", "1.00", PayMethod.BALANCE,
        OrderPhase.PAYMENT_PENDING, orderId = "local-order-id", orderNo = "local-order-no")

    @Test fun closedOrderEndsThePendingAttemptWithoutLosingItsIdentity() {
        val closed = OrderStates.apply(pending, RemoteOrderStatus.CLOSED)
        assertEquals(pending.copy(phase = OrderPhase.CLOSED), closed)
        assertTrue(closed.phase.finished)
        assertFalse(closed.phase == OrderPhase.PAID)
    }
    @Test fun unpaidSnapshotDoesNotResetAnUncertainBalancePayment() {
        assertSame(pending, OrderStates.apply(pending, RemoteOrderStatus.UNPAID))
        assertFalse(pending.phase.finished)
    }
    @Test fun settledBackendOrdersNeverNeedAnotherPaymentOrMachineSync() {
        for ((remote, phase) in listOf(RemoteOrderStatus.IN_USE to OrderPhase.PAID,
            RemoteOrderStatus.COMPLETED to OrderPhase.COMPLETED, RemoteOrderStatus.REFUNDING to OrderPhase.REFUNDING,
            RemoteOrderStatus.REFUNDED to OrderPhase.REFUNDED)) {
            val current = OrderStates.apply(pending, remote)
            assertEquals(phase, current.phase)
            assertTrue(current.phase.finished)
            assertTrue(current.syncRequested)
        }
    }
}
