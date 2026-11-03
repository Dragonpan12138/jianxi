import Foundation
import XCTest
@testable import Jianxi

private final class StubGateway: PurchaseGateway {
    var quoteResult: Quote
    var createResult: Result<CreatedOrder, Error> = .success(CreatedOrder(id: "order-id", number: "trade-no"))
    var quoteCalls = 0
    var createCalls = 0

    init(quote: Quote) { quoteResult = quote }

    func quote(device: Device, mode: WashMode) async throws -> Quote {
        quoteCalls += 1
        return quoteResult
    }

    func create(quote: Quote, fix: LocationFix) async throws -> CreatedOrder {
        createCalls += 1
        return try createResult.get()
    }
}

final class WorkflowTests: XCTestCase {
    private func acceptedQuote() -> Quote {
        let mode = WashMode(id: "sku", name: "标准洗", price: "4.00")
        let device = Device(id: "goods", name: "洗衣机", imei: "imei", category: "00",
                            shopId: "shop", orgId: "123", remainingMinutes: 0, modes: [mode])
        return Quote(device: device, mode: mode, amount: "4.00",
                     itemsJSON: PurchaseRules.items(device: device, mode: mode), tradeType: 0)
    }

    @MainActor func testUnknownCreateResultBlocksSecondOrder() async {
        let accepted = acceptedQuote()
        let gateway = StubGateway(quote: accepted)
        gateway.createResult = .failure(ClientError(message: "网络连接失败"))
        var saved: LocalOrder?
        let workflow = OrderWorkflow(gateway: gateway, read: { saved }, save: { saved = $0 })
        let fix = LocationFix(latitude: 30.2, longitude: 120.1)

        do {
            _ = try await workflow.create(accepted: accepted, method: .balance, fix: fix, owner: "owner")
            XCTFail("A lost create response must remain uncertain")
        } catch is ClientError { }
        catch { XCTFail("Unexpected error: \(error)") }

        XCTAssertEqual(saved?.phase, .unconfirmed)
        XCTAssertEqual(gateway.createCalls, 1)
        do {
            _ = try await workflow.create(accepted: accepted, method: .balance, fix: fix, owner: "owner")
            XCTFail("A second create request must be blocked")
        } catch is ClientError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(gateway.createCalls, 1)
    }

    @MainActor func testQuoteChangeStopsBeforeCreate() async {
        let accepted = acceptedQuote()
        let gateway = StubGateway(quote: Quote(device: accepted.device, mode: accepted.mode,
                                               amount: "5.00", itemsJSON: accepted.itemsJSON,
                                               tradeType: accepted.tradeType))
        var saved: LocalOrder?
        let workflow = OrderWorkflow(gateway: gateway, read: { saved }, save: { saved = $0 })
        do {
            _ = try await workflow.create(accepted: accepted, method: .alipay,
                                          fix: LocationFix(latitude: 30, longitude: 120), owner: "owner")
            XCTFail("Changed price must require a second confirmation")
        } catch let changed as QuoteChanged {
            XCTAssertEqual(changed.quote.amount, "5.00")
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNil(saved)
        XCTAssertEqual(gateway.createCalls, 0)
    }

    @MainActor func testExplicitRejectionDoesNotRemainUnconfirmed() async {
        let accepted = acceptedQuote()
        let gateway = StubGateway(quote: accepted)
        gateway.createResult = .failure(BusinessRejected(code: 4001, message: "设备不可用"))
        var saved: LocalOrder?
        let workflow = OrderWorkflow(gateway: gateway, read: { saved }, save: { saved = $0 })
        do {
            _ = try await workflow.create(accepted: accepted, method: .alipay,
                                          fix: LocationFix(latitude: 30, longitude: 120), owner: "owner")
            XCTFail("Server rejection must surface")
        } catch is BusinessRejected { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(saved?.phase, .rejected)
    }

    @MainActor func testPendingBalancePaymentNeverSubmitsAgain() async throws {
        let order = LocalOrder(owner: "owner", deviceName: "test", modeName: "wash",
                               amount: "4.00", payMethod: .balance, phase: .paymentPending,
                               orderId: "id", orderNo: "trade")
        var queryCount = 0
        var startCount = 0
        var pendingCount = 0
        let workflow = PaymentWorkflow(queryPaid: { _ in queryCount += 1; return false },
                                       onPaid: { _ in XCTFail("Order is not paid") },
                                       startPayment: { _ in startCount += 1 },
                                       onBalancePending: { pendingCount += 1 })
        try await workflow.startOrResume(order)
        XCTAssertEqual(queryCount, 1)
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(pendingCount, 1)
    }

    @MainActor func testRejectedPaymentChecksSameOrderBeforeReportingFailure() async throws {
        let order = LocalOrder(owner: "owner", deviceName: "test", modeName: "wash",
                               amount: "4.00", payMethod: .alipay, phase: .created,
                               orderId: "id", orderNo: "trade")
        var paidCount = 0
        var queryCount = 0
        let workflow = PaymentWorkflow(queryPaid: { candidate in
            XCTAssertEqual(candidate.orderNo, "trade")
            queryCount += 1
            return true
        }, onPaid: { _ in paidCount += 1 }, startPayment: { _ in
            throw BusinessRejected(code: 4001, message: "付款参数错误")
        }, onBalancePending: { XCTFail("This is an Alipay order") })
        try await workflow.startOrResume(order)
        XCTAssertEqual(queryCount, 1)
        XCTAssertEqual(paidCount, 1)
    }
}
