import Foundation

enum RemoteOrderStatus: Int, CaseIterable {
    case unpaid = 0
    case closed = 1
    case inUse = 2
    case completed = 3
    case refunding = 4
    case refunded = 5
}

enum OrderStates {
    static func apply(_ order: LocalOrder, _ status: RemoteOrderStatus) -> LocalOrder {
        var current = order
        switch status {
        case .unpaid:
            // An unpaid snapshot does not prove a submitted balance payment failed.
            return current
        case .closed:
            current.phase = .closed
        case .inUse:
            current.phase = .paid
            current.syncRequested = true
        case .completed:
            current.phase = .completed
            current.syncRequested = true
        case .refunding:
            current.phase = .refunding
            current.syncRequested = true
        case .refunded:
            current.phase = .refunded
            current.syncRequested = true
        }
        return current
    }
}
