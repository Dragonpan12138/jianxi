import Foundation

protocol PurchaseGateway {
    func quote(device: Device, mode: WashMode) async throws -> Quote
    func create(quote: Quote, fix: LocationFix) async throws -> CreatedOrder
}

struct QuoteChanged: LocalizedError {
    let quote: Quote
    var errorDescription: String? { "价格已更新，请重新确认" }
}

@MainActor
final class OrderWorkflow {
    private let gateway: PurchaseGateway
    private let read: () -> LocalOrder?
    private let save: (LocalOrder) throws -> Void
    private var creating = false

    init(gateway: PurchaseGateway, read: @escaping () -> LocalOrder?,
         save: @escaping (LocalOrder) throws -> Void) {
        self.gateway = gateway
        self.read = read
        self.save = save
    }

    func create(accepted: Quote, method: PayMethod, fix: LocationFix,
                owner: String, route: PayRoute? = nil) async throws -> LocalOrder {
        guard !creating else { throw ClientError(message: "正在创建订单，请稍后") }
        creating = true
        defer { creating = false }

        if let current = read(), !current.phase.finished {
            throw ClientError(message: "请先处理未完成订单")
        }
        let fresh = try await gateway.quote(device: accepted.device, mode: accepted.mode)
        guard fresh.amount == accepted.amount,
              fresh.itemsJSON == accepted.itemsJSON,
              fresh.tradeType == accepted.tradeType else {
            throw QuoteChanged(quote: fresh)
        }
        let selected = route ?? PayRoute(method: method)
        guard selected.method == method else {
            throw ClientError(message: "支付方式与订单不一致，请重新选择")
        }
        let attempt = LocalOrder(owner: owner, deviceName: fresh.device.name,
                                 modeName: fresh.mode.name, amount: fresh.amount,
                                 payMethod: method, phase: .creating,
                                 thirdChannel: selected.thirdChannel,
                                 outVoucherId: selected.outVoucherId)
        try save(attempt)
        do {
            let result = try await gateway.create(quote: fresh, fix: fix)
            var created = attempt
            created.orderId = result.id
            created.orderNo = result.number
            created.phase = .created
            try save(created)
            return created
        } catch let error as BusinessRejected {
            var rejected = attempt
            rejected.phase = .rejected
            try? save(rejected)
            throw error
        } catch let error as SessionExpired {
            var rejected = attempt
            rejected.phase = .rejected
            try? save(rejected)
            throw error
        } catch {
            var unknown = attempt
            unknown.phase = .unconfirmed
            try? save(unknown)
            throw error
        }
    }
}

@MainActor
final class PaymentWorkflow {
    private let queryPaid: (LocalOrder) async throws -> Bool
    private let onPaid: (LocalOrder) async throws -> Void
    private let startPayment: (LocalOrder) async throws -> Void
    private let onBalancePending: () -> Void

    init(queryPaid: @escaping (LocalOrder) async throws -> Bool,
         onPaid: @escaping (LocalOrder) async throws -> Void,
         startPayment: @escaping (LocalOrder) async throws -> Void,
         onBalancePending: @escaping () -> Void) {
        self.queryPaid = queryPaid
        self.onPaid = onPaid
        self.startPayment = startPayment
        self.onBalancePending = onBalancePending
    }

    func startOrResume(_ order: LocalOrder) async throws {
        if order.phase == .created {
            do {
                try await startPayment(order)
            } catch let error as BusinessRejected {
                let paid: Bool
                do {
                    paid = try await queryPaid(order)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    paid = false
                }
                if paid { try await onPaid(order) } else { throw error }
            }
            return
        }
        guard order.phase == .paymentPending else {
            throw ClientError(message: "订单状态尚未确认，请先核对订单")
        }
        if try await queryPaid(order) {
            try await onPaid(order)
        } else if order.payMethod == .balance {
            onBalancePending()
        } else {
            try await startPayment(order)
        }
    }
}
