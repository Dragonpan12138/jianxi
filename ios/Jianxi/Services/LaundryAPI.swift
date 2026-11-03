import Foundation

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class LaundryAPI: PurchaseGateway {
    static let allowedPaths: Set<String> = [
        "common/sms/sendCode", "user/reg", "goods/scan/v2", "goods/normal/details",
        "goods/normal/skus", "trade/preview/v4", "trade/create", "payChannelRoute/prePay",
        "pay/unify/prePay", "pay/unify/pay", "order/pay_status", "order/detail",
        "order/sync", "order/cancel", "appoint/checkMachineCanUse"
    ]

    private static let anonymousPaths: Set<String> = ["common/sms/sendCode", "user/reg"]
    private static let paymentOperations: [String: String] = [
        "appoint/checkMachineCanUse": "核对设备状态失败",
        "trade/preview/v4": "核对洗衣金额失败",
        "trade/create": "创建订单失败",
        "payChannelRoute/prePay": "获取支付方式失败",
        "pay/unify/prePay": "获取支付信息失败",
        "pay/unify/pay": "余额付款未完成",
        "order/pay_status": "查询付款状态失败",
        "order/detail": "查询订单详情失败",
        "order/cancel": "取消订单失败"
    ]

    private let token: () -> String
    private let brand: String
    private let session: URLSession
    private let baseURL: URL
    private let now: () -> Int64
    private let redirectDelegate: NoRedirectDelegate?

    init(token: @escaping () -> String, brand: String, session: URLSession? = nil,
         baseURL: URL = URL(string: "https://userapi.qiekj.com/")!,
         now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }) {
        self.token = token
        self.brand = String(decoding: brand.utf8.filter { $0 >= 32 && $0 <= 126 }, as: UTF8.self)
        self.baseURL = baseURL
        self.now = now
        if let session {
            self.session = session
            redirectDelegate = nil
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let delegate = NoRedirectDelegate()
            self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            redirectDelegate = delegate
        }
    }

    func post(path: String, fields: [String: String], risk: (Device, LocationFix)? = nil) async throws -> Any {
        guard Self.allowedPaths.contains(path),
              baseURL.scheme == "https" ||
              (baseURL.scheme == "http" && ["localhost", "127.0.0.1"].contains(baseURL.host ?? "")) else {
            throw ClientError(message: "不支持此接口请求")
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ClientError(message: "接口地址无效")
        }
        let anonymous = Self.anonymousPaths.contains(path)
        let authorization = anonymous ? "" : token()
        let timestamp = String(now())
        var bodyFields = fields
        if !authorization.isEmpty { bodyFields["token"] = authorization }
        var components = URLComponents()
        components.queryItems = bodyFields.keys.sorted().map { URLQueryItem(name: $0, value: bodyFields[$0]!) }
        guard let encoded = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "%20", with: "+") else {
            throw ClientError(message: "请求参数无法编码")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(encoded.utf8)
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(WireProtocol.version, forHTTPHeaderField: "Version")
        request.setValue(WireProtocol.channel, forHTTPHeaderField: "channel")
        request.setValue(brand, forHTTPHeaderField: "phoneBrand")
        request.setValue("", forHTTPHeaderField: "deviceId")
        request.setValue(timestamp, forHTTPHeaderField: "timestamp")
        request.setValue(WireProtocol.sign(path: "/\(path)", token: authorization, timestamp: timestamp),
                         forHTTPHeaderField: "sign")
        request.setValue("QEUser/\(WireProtocol.version) (com.qiekj.user; build:294; Android; userChannel:android_app) OkHttp/4.12.0",
                         forHTTPHeaderField: "User-Agent")
        if let (device, fix) = risk {
            request.setValue(device.imei, forHTTPHeaderField: "imei")
            request.setValue(device.category, forHTTPHeaderField: "categoryCode")
            request.setValue(String(fix.latitude), forHTTPHeaderField: "lat")
            request.setValue(String(fix.longitude), forHTTPHeaderField: "lng")
            request.setValue(timestamp, forHTTPHeaderField: "orderRiskTimestamp")
            request.setValue(WireProtocol.riskSign(path: "/\(path)", token: authorization,
                                                   timestamp: timestamp, imei: device.imei,
                                                   category: device.category, fix: fix),
                             forHTTPHeaderField: "orderRiskSign")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ClientError(message: "网络连接失败，请检查网络后重试")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: "服务器响应无效")
        }
        if http.statusCode == 401 && !anonymous { throw SessionExpired() }
        if http.statusCode == 403 {
            throw BusinessRejected(code: 403, message: "本次请求被平台拒绝，请稍后重试（403）",
                                   operation: Self.paymentOperations[path])
        }
        guard (200...299).contains(http.statusCode) else {
            throw ClientError(message: "服务暂时不可用（\(http.statusCode)）")
        }
        guard !data.isEmpty else { throw ClientError(message: "服务器没有返回内容") }
        guard data.count <= 2_000_000 else { throw ClientError(message: "服务器返回内容过大") }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError(message: "服务器返回格式变化，暂时无法处理")
        }
        guard let code = Int(jsonText(root, "code")) else {
            throw ClientError(message: "服务器响应缺少有效状态码")
        }
        if code != 0 {
            let message = String(jsonText(root, "msg", fallback: "请求失败（\(code)）").prefix(180))
            if !anonymous && (code == 401 || ["未登录", "登录已过期", "登录失效", "请重新登录"].contains(message)) {
                throw SessionExpired()
            }
            if code == 2128 && path == "goods/normal/skus" {
                throw BusinessRejected(code: code, message: "此设备存在未支付订单，请先在原应用处理")
            }
            throw BusinessRejected(code: code, message: message, operation: Self.paymentOperations[path])
        }
        return root["data"] ?? NSNull()
    }

    func sendCode(_ phone: String) async throws {
        _ = try await post(path: "common/sms/sendCode", fields: ["phone": phone, "template": "reg"])
    }

    func login(phone: String, code: String) async throws -> String {
        let data = try await object(path: "user/reg", fields: [
            "channel": WireProtocol.channel, "phone": phone, "verify": code
        ])
        let value = jsonText(data, "token")
        guard !value.isEmpty else { throw ClientError(message: "登录响应缺少会话信息") }
        return value
    }

    func device(_ code: DeviceCode) async throws -> Device {
        let scan = try await object(path: "goods/scan/v2", fields: [code.key: code.value])
        if jsonText(scan, "jumpToAlipayFlag2") == "true" {
            throw ClientError(message: "此二维码需要通过支付宝扫码，请使用支付宝扫描原二维码")
        }
        let scanId = jsonText(scan, "id")
        guard !scanId.isEmpty else { throw ClientError(message: "设备识别响应缺少编号") }
        let detail = try await object(path: "goods/normal/details", fields: ["goodsId": scanId])
        let id = jsonText(detail, "goodsId", fallback: scanId)
        guard !id.isEmpty else { throw ClientError(message: "设备详情缺少编号") }
        let category = jsonText(detail, "categoryCode", fallback: jsonText(scan, "categoryCode"))
        guard ["00", "01"].contains(category) else {
            throw ClientError(message: "当前版本仅支持洗衣机和洗鞋机")
        }
        if jsonText(detail, "isBluetooth", fallback: "0") == "1" {
            throw ClientError(message: "此设备需要蓝牙启动，当前版本暂不支持")
        }
        if jsonText(detail, "payment") == "after" {
            throw ClientError(message: "此设备使用先用后付，当前版本暂不支持")
        }
        let imei = jsonText(detail, "imei")
        guard !imei.isEmpty else {
            throw ClientError(message: "设备详情缺少标识，请先在原应用核对设备")
        }
        let skuResponse = try await post(path: "goods/normal/skus", fields: ["goodsId": id])
        let modes = try parseModes(skuResponse)
        guard !modes.isEmpty else { throw ClientError(message: "当前设备没有可用的洗衣模式，请确认设备类型") }
        return Device(id: id, name: jsonText(detail, "name", fallback: "洗衣机"), imei: imei,
                      category: category, shopId: jsonText(detail, "shopId"),
                      orgId: jsonText(detail, "orgId"),
                      remainingMinutes: Int(jsonText(detail, "remainTime", fallback: "0")) ?? 0,
                      modes: modes, error: jsonText(detail, "deviceErrorMsg"))
    }

    func parseModes(_ response: Any) throws -> [WashMode] {
        let data: Any
        if let envelope = response as? [String: Any], envelope["code"] != nil {
            data = envelope["data"] ?? NSNull()
        } else {
            data = response
        }
        let array: [Any]?
        if let direct = data as? [Any] {
            array = direct
        } else if let object = data as? [String: Any] {
            array = ["skus", "skuList", "list"].compactMap { object[$0] as? [Any] }.first
        } else {
            array = nil
        }
        guard let array else {
            throw ClientError(message: "洗衣模式数据格式尚未适配，请保留二维码供后续验证")
        }
        return try array.compactMap { entry in
            guard let item = entry as? [String: Any] else { return nil }
            if jsonText(item, "scanAvailable", fallback: "true") == "false" { return nil }
            let id = jsonText(item, "skuId")
            guard !id.isEmpty else { return nil }
            return WashMode(id: id, name: jsonText(item, "name", fallback: "洗衣模式"),
                            price: try money(jsonText(item, "price")), feature: jsonText(item, "feature"))
        }
    }

    func quote(device: Device, mode: WashMode) async throws -> Quote {
        let available = try await post(path: "appoint/checkMachineCanUse", fields: ["skuId": mode.id])
        guard let isAvailable = jsonBoolean(available) else {
            throw ClientError(message: "设备可用状态格式尚未适配")
        }
        guard isAvailable else { throw ClientError(message: "此洗衣模式暂不可用，请刷新设备后重试") }
        var fields = ["items": PurchaseRules.items(device: device, mode: mode),
                      "promotions": "[]", "isAutoSelectPromotion": "0"]
        if !device.orgId.isEmpty {
            fields["forbiddenPromotions"] = PurchaseRules.goldExclusion(orgId: device.orgId)
        }
        let data = try await object(path: "trade/preview/v4", fields: fields)
        return try PurchaseRules.verifyQuote(data, device: device, mode: mode)
    }

    func channels(_ quote: Quote) async throws -> [PayRoute] {
        let device = quote.device
        // The original client passes orgId in the wire field named shopId.
        let channelShopId = device.orgId
        guard Int64(channelShopId) != nil else {
            throw ClientError(message: "设备机构编号无效，请重新扫码识别设备")
        }
        let response = try await post(path: "payChannelRoute/prePay", fields: [
            "imei": device.imei, "goodsId": device.id, "hitAd": "0", "payPrice": quote.amount,
            "useTicket": "0", "shopId": channelShopId, "combineOrderStatus": "false",
            "confirmSelectedStatus": "false"
        ])
        guard let array = response as? [Any] else {
            throw ClientError(message: "支付渠道响应格式尚未适配")
        }
        var methods: [PayMethod] = []
        var routes: [PayMethod: [PayRoute]] = [:]
        for entry in array {
            guard let channel = entry as? [String: Any],
                  jsonText(channel, "autoPayState", fallback: "0") != "1",
                  let method = PayMethod.allCases.first(where: { $0.wire == jsonText(channel, "method") }) else { continue }
            if routes[method] == nil { methods.append(method) }
            routes[method, default: []].append(PayRoute(method: method,
                                                        thirdChannel: jsonText(channel, "thirdChannel"),
                                                        outVoucherId: jsonText(channel, "outVoucherId")))
        }
        let supported = methods.compactMap { method -> PayRoute? in
            guard let options = routes[method] else { return nil }
            return options.first(where: { $0.thirdChannel.isEmpty && $0.outVoucherId.isEmpty }) ?? options.first
        }
        guard !supported.isEmpty else { throw ClientError(message: "此设备暂未提供可用的单次支付渠道") }
        return supported
    }

    func create(quote: Quote, fix: LocationFix) async throws -> CreatedOrder {
        let data = try await object(path: "trade/create", fields: [
            "items": quote.itemsJSON,
            "promotions": PurchaseRules.goldExclusion(orgId: quote.device.orgId)
        ], risk: (quote.device, fix))
        let id = jsonText(data, "orderId")
        let number = jsonText(data, "tradeNo")
        guard !id.isEmpty && !number.isEmpty else {
            throw ClientError(message: "订单返回内容不完整，请核对订单后再继续")
        }
        return CreatedOrder(id: id, number: number)
    }

    func prepay(_ order: LocalOrder) async throws -> String {
        var fields = ["orderNo": order.orderNo, "payType": order.payMethod.wire,
                      "againFlag": order.phase == .paymentPending ? "1" : "0"]
        if let channel = order.thirdChannel, !channel.isEmpty { fields["thirdChannel"] = channel }
        if let voucher = order.outVoucherId, !voucher.isEmpty { fields["outVoucherId"] = voucher }
        let data = try await object(path: "pay/unify/prePay", fields: fields)
        let value = jsonText(data, "prepayParam")
        guard !value.isEmpty else { throw ClientError(message: "未取得支付参数，请查询订单状态") }
        return value
    }

    func balancePay(_ order: LocalOrder) async throws {
        _ = try await post(path: "pay/unify/pay", fields: ["orderNo": order.orderNo, "payType": "2"])
    }

    func paid(_ order: LocalOrder) async throws -> Bool {
        let data = try await post(path: "order/pay_status", fields: [
            "orderNo": order.orderNo, "payType": order.payMethod.wire
        ])
        guard let paid = jsonBoolean(data) else { throw ClientError(message: "支付状态格式尚未适配") }
        return paid
    }

    func orderStatus(_ order: LocalOrder) async throws -> RemoteOrderStatus {
        let fields: [String: String]
        if !order.orderId.isEmpty {
            fields = ["orderId": order.orderId]
        } else if !order.orderNo.isEmpty {
            fields = ["orderNo": order.orderNo]
        } else {
            throw ClientError(message: "订单编号不完整，请先在原应用核对")
        }
        let data = try await object(path: "order/detail", fields: fields)
        let matches = !order.orderId.isEmpty
            ? jsonText(data, "id") == order.orderId
            : jsonText(data, "orderNo") == order.orderNo
        guard matches else { throw ClientError(message: "订单详情编号不一致，请先在原应用核对") }
        guard let status = Int(jsonText(data, "orderStatus")),
              let result = RemoteOrderStatus(rawValue: status) else {
            throw ClientError(message: "订单状态格式尚未适配，请先在原应用核对")
        }
        return result
    }

    func sync(_ order: LocalOrder) async throws {
        _ = try await post(path: "order/sync", fields: ["orderNo": order.orderNo, "payType": order.payMethod.wire])
    }

    func cancel(_ order: LocalOrder) async throws {
        let data = try await post(path: "order/cancel", fields: ["orderId": order.orderId])
        guard data is String else { throw ClientError(message: "取消结果尚未确认，请刷新订单") }
    }

    private func object(path: String, fields: [String: String],
                        risk: (Device, LocationFix)? = nil) async throws -> [String: Any] {
        let response = try await post(path: path, fields: fields, risk: risk)
        guard let value = response as? [String: Any] else {
            throw ClientError(message: "服务器返回格式变化，暂时无法处理")
        }
        return value
    }
}
