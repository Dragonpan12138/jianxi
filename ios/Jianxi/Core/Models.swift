import Foundation

struct DeviceCode: Equatable {
    let key: String
    let value: String
}

struct WashMode: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let price: String
    let feature: String

    init(id: String, name: String, price: String, feature: String = "") {
        self.id = id
        self.name = name
        self.price = price
        self.feature = feature
    }
}

struct Device: Codable, Equatable {
    let id: String
    let name: String
    let imei: String
    let category: String
    let shopId: String
    let orgId: String
    let remainingMinutes: Int
    let modes: [WashMode]
    let error: String

    init(id: String, name: String, imei: String, category: String, shopId: String,
         orgId: String, remainingMinutes: Int, modes: [WashMode], error: String = "") {
        self.id = id
        self.name = name
        self.imei = imei
        self.category = category
        self.shopId = shopId
        self.orgId = orgId
        self.remainingMinutes = remainingMinutes
        self.modes = modes
        self.error = error
    }
}

struct Quote: Equatable {
    let device: Device
    let mode: WashMode
    let amount: String
    let itemsJSON: String
    let tradeType: Int
}

enum PayMethod: String, Codable, CaseIterable {
    case alipay
    case balance

    var wire: String {
        switch self {
        case .alipay: return "13"
        case .balance: return "2"
        }
    }

    var title: String {
        switch self {
        case .alipay: return "支付宝"
        case .balance: return "账户余额"
        }
    }
}

struct PayRoute: Codable, Equatable, Identifiable {
    let method: PayMethod
    let thirdChannel: String
    let outVoucherId: String

    init(method: PayMethod, thirdChannel: String = "", outVoucherId: String = "") {
        self.method = method
        self.thirdChannel = thirdChannel
        self.outVoucherId = outVoucherId
    }

    var id: String { "\(method.rawValue):\(thirdChannel):\(outVoucherId)" }
    var title: String { method.title }
}

struct CreatedOrder: Equatable {
    let id: String
    let number: String
}

struct LocationFix: Equatable {
    let latitude: Double
    let longitude: Double
}

enum OrderPhase: String, Codable, CaseIterable {
    case creating
    case unconfirmed
    case created
    case paymentPending
    case paid
    case cancelled
    case rejected
    case closed
    case completed
    case refunding
    case refunded

    var finished: Bool {
        switch self {
        case .paid, .cancelled, .rejected, .closed, .completed, .refunding, .refunded: return true
        case .creating, .unconfirmed, .created, .paymentPending: return false
        }
    }
}

struct LocalOrder: Codable, Equatable {
    let owner: String
    let deviceName: String
    let modeName: String
    let amount: String
    let payMethod: PayMethod
    var phase: OrderPhase
    let createdAt: Int64
    var orderId: String
    var orderNo: String
    var syncRequested: Bool
    let thirdChannel: String?
    let outVoucherId: String?

    init(owner: String, deviceName: String, modeName: String, amount: String,
         payMethod: PayMethod, phase: OrderPhase,
         createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
         orderId: String = "", orderNo: String = "", syncRequested: Bool = false,
         thirdChannel: String? = nil, outVoucherId: String? = nil) {
        self.owner = owner
        self.deviceName = deviceName
        self.modeName = modeName
        self.amount = amount
        self.payMethod = payMethod
        self.phase = phase
        self.createdAt = createdAt
        self.orderId = orderId
        self.orderNo = orderNo
        self.syncRequested = syncRequested
        self.thirdChannel = thirdChannel
        self.outVoucherId = outVoucherId
    }
}

struct ClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct BusinessRejected: LocalizedError {
    let code: Int
    let message: String
    let operation: String?

    init(code: Int, message: String, operation: String? = nil) {
        self.code = code
        self.message = message
        self.operation = operation
    }

    var displayMessage: String {
        operation.map { "\($0)：\(message)（错误码 \(code)）" } ?? message
    }

    var errorDescription: String? { displayMessage }
}

struct SessionExpired: LocalizedError {
    var errorDescription: String? { "登录已过期，请重新登录" }
}

func money(_ raw: String) throws -> String {
    let expression = try NSRegularExpression(pattern: #"^[+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"#)
    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
    guard expression.firstMatch(in: raw, range: range)?.range == range,
          let decimal = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else {
        throw ClientError(message: "金额格式异常，请刷新后重试")
    }
    let value = NSDecimalNumber(decimal: decimal)
    guard value != NSDecimalNumber.notANumber else {
        throw ClientError(message: "金额格式异常，请刷新后重试")
    }
    guard value.compare(NSDecimalNumber(value: 0)) != .orderedAscending else {
        throw ClientError(message: "金额异常，请刷新后重试")
    }
    let cents = value.multiplying(by: NSDecimalNumber(value: 100))
    let integerCents = cents.rounding(accordingToBehavior: NSDecimalNumberHandler(
        roundingMode: .down, scale: 0, raiseOnExactness: false,
        raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false))
    guard cents == integerCents else { throw ClientError(message: "金额精度异常，请刷新后重试") }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    guard let result = formatter.string(from: value) else {
        throw ClientError(message: "金额格式异常，请刷新后重试")
    }
    return result
}
