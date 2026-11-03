import AlipaySDK
import Foundation

@MainActor
final class AlipayPayment {
    static let shared = AlipayPayment()
    private static let callbackScheme = "jianxi-alipay"
    private var completion: ((String?) -> Void)?
    private var recovery: ((String?) -> Void)?

    private init() {}

    func setRecoveryHandler(_ handler: @escaping (String?) -> Void) {
        recovery = handler
    }

    func start(payload: String, completion: @escaping (String?) -> Void) {
        self.completion = completion
        AlipaySDK.defaultService().payOrder(payload, fromScheme: Self.callbackScheme) { [weak self] result in
            Task { @MainActor in self?.complete(result) }
        }
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == Self.callbackScheme else { return false }
        AlipaySDK.defaultService().processOrder(withPaymentResult: url) { [weak self] result in
            Task { @MainActor in self?.complete(result) }
        }
        return true
    }

    private func complete(_ result: [AnyHashable: Any]?) {
        let callback = completion ?? recovery
        self.completion = nil
        callback?(result?["resultStatus"] as? String)
    }
}
