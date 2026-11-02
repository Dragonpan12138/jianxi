package dev.rain.laundry.core

import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class PaymentWorkflowTest {
    private fun order(method: PayMethod = PayMethod.ALIPAY, phase: OrderPhase = OrderPhase.CREATED) =
        LocalOrder("owner", "test", "wash", "4.00", method, phase, orderId = "id1", orderNo = "trade1")

    @Test fun freshOrderObtainsPaymentParametersBeforeAnyStatusQuery() = runTest {
        val calls = mutableListOf<String>()
        val flow = PaymentWorkflow(
            queryPaid = { throw BusinessRejected(1001, "参数不正确") },
            onPaid = { fail("A fresh order has not been paid") },
            startPayment = { calls.add("prepay:${it.orderNo}") },
            onBalancePending = { fail("A fresh order is not pending") }
        )
        flow.startOrResume(order())
        assertEquals(listOf("prepay:trade1"), calls)
    }

    @Test fun resumingAlipayQueriesBeforeReusingTheSameOrder() = runTest {
        val calls = mutableListOf<String>()
        val flow = PaymentWorkflow(
            queryPaid = { calls.add("status:${it.orderNo}"); false },
            onPaid = { fail("Still unpaid") },
            startPayment = { calls.add("prepay:${it.orderNo}") },
            onBalancePending = { fail("Not a balance payment") }
        )
        flow.startOrResume(order(phase = OrderPhase.PAYMENT_PENDING))
        assertEquals(listOf("status:trade1", "prepay:trade1"), calls)
    }

    @Test fun confirmedPaymentIsNeverStartedAgain() = runTest {
        var confirmed: LocalOrder? = null
        val pending = order(phase = OrderPhase.PAYMENT_PENDING)
        val flow = PaymentWorkflow(
            queryPaid = { true }, onPaid = { confirmed = it },
            startPayment = { fail("Already paid") }, onBalancePending = { fail("Already paid") }
        )
        flow.startOrResume(pending)
        assertEquals(pending, confirmed)
    }

    @Test fun unknownBalanceResultDoesNotTriggerAnotherDeduction() = runTest {
        var waiting = false
        val flow = PaymentWorkflow(
            queryPaid = { false }, onPaid = { fail("Not confirmed") },
            startPayment = { fail("Must not repeat the balance deduction") },
            onBalancePending = { waiting = true }
        )
        flow.startOrResume(order(PayMethod.BALANCE, OrderPhase.PAYMENT_PENDING))
        assertTrue(waiting)
    }

    @Test fun failedStatusQueryNeverFallsThroughToAnotherPayment() = runTest {
        val error = BusinessRejected(1001, "参数不正确", "查询付款状态失败")
        val flow = PaymentWorkflow(
            queryPaid = { throw error }, onPaid = { fail("Not confirmed") },
            startPayment = { fail("Must wait for payment status") },
            onBalancePending = { fail("Status query failed") }
        )
        assertSame(error, runCatching { flow.startOrResume(order(phase = OrderPhase.PAYMENT_PENDING)) }.exceptionOrNull())
    }

    @Test fun unconfirmedOrderCreationCannotStartPayment() = runTest {
        val flow = PaymentWorkflow(
            queryPaid = { fail("Creation is unknown"); false },
            onPaid = { fail("Creation is unknown") },
            startPayment = { fail("Creation is unknown") },
            onBalancePending = { fail("Creation is unknown") }
        )
        assertTrue(runCatching { flow.startOrResume(order(phase = OrderPhase.UNCONFIRMED)) }.exceptionOrNull() is ClientError)
    }
}
