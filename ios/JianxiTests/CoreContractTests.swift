import Foundation
import XCTest
@testable import Jianxi

final class CoreContractTests: XCTestCase {
    private let device = Device(id: "g1", name: "测试洗衣机", imei: "123456789",
                                category: "WASH", shopId: "s1", orgId: "org",
                                remainingMinutes: 0, modes: [])
    private let mode = WashMode(id: "sku1", name: "标准洗", price: "4.00")

    func testQRCodeAcceptsOnlyOneRecognizedIdentifier() throws {
        XCTAssertEqual(try DeviceCodes.parse("https://example.invalid/?IMEI=123456789"),
                       DeviceCode(key: "IMEI", value: "123456789"))
        XCTAssertEqual(try DeviceCodes.parse("NQT=ABCD%31%32%33%34"),
                       DeviceCode(key: "NQT", value: "ABCD1234"))
        for raw in ["https://example.invalid/", "IMEI=abcd&SN=efgh", "SN=abcd%26token%3Dsecret", "SN=%xx"] {
            XCTAssertThrowsError(try DeviceCodes.parse(raw), raw)
        }
    }

    func testSigningMatchesAndroidVectors() {
        XCTAssertEqual(WireProtocol.sign(path: "/goods/normal/details", token: "test-token", timestamp: "1700000000000"),
                       "a1114633c7431c9dd85b46077bff831dffe57a798bff9e0e8b95803d98cb76d1")
        XCTAssertEqual(WireProtocol.riskSign(path: "/trade/create", token: "test-token",
                                             timestamp: "1700000000000", imei: device.imei,
                                             category: device.category, fix: LocationFix(latitude: 30.2, longitude: 120.1)),
                       "304612052b2b8b47831abf7cda1d1e6e4d2ec550a05f1bfcb6dd8879ce312d84")
    }

    func testAmountsRequireExactCents() throws {
        XCTAssertEqual(try money("4"), "4.00")
        XCTAssertEqual(try money("4.000"), "4.00")
        XCTAssertThrowsError(try money("4.001"))
        XCTAssertThrowsError(try money("-1"))
        XCTAssertThrowsError(try money("NaN"))
    }

    func testQuoteRejectsExtraItemsAndSelectedPromotions() throws {
        let base: [String: Any] = [
            "realPrice": "4.00", "tradeType": 1,
            "items": [["goodsId": "g1", "skuId": "sku1", "amount": "1"]],
            "promotions": [["promotionType": 7, "isUsed": false,
                             "options": NSNull(), "participateList": NSNull()]]
        ]
        XCTAssertEqual(try PurchaseRules.verifyQuote(base, device: device, mode: mode).amount, "4.00")
        var extra = base
        extra["items"] = [["goodsId": "g1", "skuId": "sku1"], ["goodsId": "vip"]]
        XCTAssertThrowsError(try PurchaseRules.verifyQuote(extra, device: device, mode: mode))
        var selected = base
        selected["promotions"] = [["promotionType": 7, "isUsed": true, "options": NSNull()]]
        XCTAssertThrowsError(try PurchaseRules.verifyQuote(selected, device: device, mode: mode))
        var malformed = base
        malformed["promotions"] = [["promotionType": 7, "options": ["private-value": 1]]]
        XCTAssertThrowsError(try PurchaseRules.verifyQuote(malformed, device: device, mode: mode))
    }

    func testAlipayAllowsOnlySinglePaymentAtConfirmedAmount() throws {
        func payload(_ business: String, method: String = "alipay.trade.app.pay") -> String {
            let encoded = business.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            return "method=\(method)&biz_content=\(encoded)&sign=local-test-only"
        }
        try PurchaseRules.verifyAlipay(payload(#"{"total_amount":"4.00","product_code":"QUICK_MSECURITY_PAY"}"#),
                                       expectedAmount: "4.00")
        XCTAssertThrowsError(try PurchaseRules.verifyAlipay(payload(#"{"total_amount":"8.00"}"#),
                                                             expectedAmount: "4.00"))
        XCTAssertThrowsError(try PurchaseRules.verifyAlipay(payload(#"{"total_amount":"4.00","nested":{"agreement_sign_params":{}}}"#),
                                                             expectedAmount: "4.00"))
        XCTAssertThrowsError(try PurchaseRules.verifyAlipay(payload(#"{"total_amount":"4.00"}"#,
                                                             method: "alipay.user.agreement.page.sign"),
                                                             expectedAmount: "4.00"))
    }

    func testOrderStatesDoNotRetryUncertainBalancePayment() {
        let pending = LocalOrder(owner: "owner", deviceName: "test", modeName: "wash", amount: "1.00",
                                 payMethod: .balance, phase: .paymentPending,
                                 orderId: "local-order-id", orderNo: "local-order-no")
        XCTAssertEqual(OrderStates.apply(pending, .unpaid), pending)
        XCTAssertFalse(OrderStates.apply(pending, .unpaid).phase.finished)
        let closed = OrderStates.apply(pending, .closed)
        XCTAssertEqual(closed.phase, .closed)
        XCTAssertTrue(closed.phase.finished)
        let terminalStates: [(RemoteOrderStatus, OrderPhase)] = [
            (.inUse, .paid), (.completed, .completed), (.refunding, .refunding), (.refunded, .refunded)
        ]
        for (status, phase) in terminalStates {
            let order = OrderStates.apply(pending, status)
            XCTAssertEqual(order.phase, phase)
            XCTAssertTrue(order.syncRequested)
        }
    }
}
