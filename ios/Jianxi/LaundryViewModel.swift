import Combine
import Foundation

enum Page {
    case home, device, checkout, orders
}

@MainActor
final class LaundryViewModel: ObservableObject {
    @Published private(set) var loggedIn: Bool
    @Published private(set) var phoneLabel: String
    @Published private(set) var page: Page = .home
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    @Published private(set) var message: String?
    @Published private(set) var smsCooldown = 0
    @Published private(set) var device: Device?
    @Published private(set) var mode: WashMode?
    @Published private(set) var quote: Quote?
    @Published private(set) var methods: [PayRoute] = []
    @Published private(set) var payRoute: PayRoute?
    @Published private(set) var order: LocalOrder?

    private let vault: SessionVault
    private let api: LaundryAPI
    private let location = LocationProvider()
    private var cooldownTask: Task<Void, Never>?
    private lazy var orderWorkflow = OrderWorkflow(
        gateway: api,
        read: { [unowned self] in self.order },
        save: { [unowned self] value in try self.saveOrder(value) }
    )
    private lazy var paymentWorkflow = PaymentWorkflow(
        queryPaid: { [unowned self] order in
            self.progress = "正在查询付款状态"
            return try await self.api.paid(order)
        },
        onPaid: { [unowned self] order in try await self.confirmPaid(order) },
        startPayment: { [unowned self] order in try await self.payExisting(order) },
        onBalancePending: { [unowned self] in
            self.message = "余额付款结果尚未确认，请稍后刷新订单"
        }
    )

    init() {
        let vault = SessionVault()
        self.vault = vault
        self.api = LaundryAPI(token: { vault.token() }, brand: "Apple")
        let sessionReady = !vault.token().isEmpty && !vault.owner().isEmpty
        if !sessionReady { vault.logout() }
        loggedIn = sessionReady
        phoneLabel = vault.phoneLabel()
        if var saved = vault.order() {
            if saved.phase == .creating {
                saved.phase = .unconfirmed
                try? vault.saveOrder(saved)
            }
            order = saved
        }
        AlipayPayment.shared.setRecoveryHandler { [weak self] status in
            guard let self, let order = self.order, order.phase == .paymentPending,
                  order.payMethod == .alipay else { return }
            self.sdkReturned(orderNo: order.orderNo, status: status)
        }
    }

    func dismissMessage() { message = nil }
    func navigate(_ destination: Page) { if !busy { page = destination } }
    func selectMode(_ value: WashMode) { if !busy { mode = value; quote = nil } }
    func selectPayment(_ route: PayRoute) {
        if !busy && methods.contains(route) { payRoute = route }
    }

    func sendCode(_ phone: String) {
        guard validPhone(phone) else { message = "请输入正确的手机号"; return }
        guard smsCooldown == 0 else { return }
        work("正在发送验证码") {
            try await self.api.sendCode(phone)
            self.smsCooldown = 60
            self.message = "验证码已发送"
            self.cooldownTask?.cancel()
            self.cooldownTask = Task { @MainActor in
                while self.smsCooldown > 0 && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled { self.smsCooldown -= 1 }
                }
            }
        }
    }

    func login(phone: String, code: String) {
        guard validPhone(phone), code.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil else {
            message = "请填写手机号和短信验证码"
            return
        }
        work("正在登录") {
            let token = try await self.api.login(phone: phone, code: code)
            try self.vault.login(phone: phone, token: token)
            self.cooldownTask?.cancel()
            self.smsCooldown = 0
            self.loggedIn = true
            self.phoneLabel = self.vault.phoneLabel()
            self.order = self.vault.order()
            self.device = nil
            self.mode = nil
            self.quote = nil
            self.methods = []
            self.payRoute = nil
            self.page = .home
        }
    }

    func logout() {
        guard !busy else { return }
        cooldownTask?.cancel()
        vault.logout()
        loggedIn = false
        phoneLabel = ""
        page = .home
        message = nil
        smsCooldown = 0
        device = nil
        mode = nil
        quote = nil
        methods = []
        payRoute = nil
        order = nil
    }

    func scan(_ raw: String) {
        work("正在识别洗衣机") {
            let code = try DeviceCodes.parse(raw)
            let found = try await self.api.device(code)
            self.device = found
            self.mode = found.modes.first
            self.quote = nil
            self.page = .device
        }
    }

    func preview() {
        guard let device, let mode else { return }
        work("正在确认价格") {
            let quote = try await self.api.quote(device: device, mode: mode)
            let routes = try await self.api.channels(quote)
            self.quote = quote
            self.methods = routes
            self.payRoute = routes.first
            self.page = .checkout
        }
    }

    func pay() {
        guard let quote, let payRoute else { return }
        if let order, !order.phase.finished {
            page = .orders
            message = "请先处理未完成订单"
            return
        }
        work("正在核对订单") {
            let fix = try await self.location.current()
            let created: LocalOrder
            do {
                created = try await self.orderWorkflow.create(
                    accepted: quote, method: payRoute.method, fix: fix,
                    owner: self.vault.owner(), route: payRoute
                )
            } catch let changed as QuoteChanged {
                self.quote = changed.quote
                self.methods = []
                self.payRoute = nil
                self.page = .checkout
                let routes = try await self.api.channels(changed.quote)
                self.methods = routes
                self.payRoute = routes.first
                throw ClientError(message: "价格已更新，请重新确认")
            } catch {
                if self.order?.phase == .unconfirmed { self.page = .orders }
                throw error
            }
            self.page = .orders
            try await self.paymentWorkflow.startOrResume(created)
        }
    }

    func resumePayment() {
        guard let order, !order.orderNo.isEmpty, !order.phase.finished else { return }
        work("正在核对付款状态") {
            let current = try await self.synchronizeOrderState(order)
            if current.phase.finished { self.noticeOrderState(current) }
            else { try await self.paymentWorkflow.startOrResume(current) }
        }
    }

    func refreshOrder() {
        guard let order else { return }
        guard !order.orderId.isEmpty || !order.orderNo.isEmpty else {
            message = "上一次下单结果未确认，请先在原应用核对订单"
            return
        }
        work("正在查询订单") {
            let current = try await self.synchronizeOrderState(order)
            self.noticeOrderState(current)
        }
    }

    func cancelOrder() {
        guard let order, !order.orderId.isEmpty, !order.phase.finished else { return }
        work("正在取消订单") {
            let current = try await self.synchronizeOrderState(order)
            if current.phase.finished { self.noticeOrderState(current); return }
            if try await self.api.paid(current) { try await self.confirmPaid(current); return }
            do {
                try await self.api.cancel(current)
            } catch let error as BusinessRejected where error.code == 3122 {
                let latest = try await self.synchronizeOrderState(current)
                if latest.phase.finished { self.noticeOrderState(latest); return }
                throw error
            }
            var cancelled = current
            cancelled.phase = .cancelled
            try self.saveOrder(cancelled)
            self.message = "订单已取消"
        }
    }

    private func payExisting(_ order: LocalOrder) async throws {
        if order.payMethod == .balance {
            progress = "正在提交余额付款"
            var pending = order
            pending.phase = .paymentPending
            try saveOrder(pending)
            try await api.balancePay(pending)
            try await poll(pending)
        } else {
            progress = "正在获取支付信息"
            let payload = try await api.prepay(order)
            try PurchaseRules.verifyAlipay(payload, expectedAmount: order.amount)
            var pending = order
            pending.phase = .paymentPending
            try saveOrder(pending)
            AlipayPayment.shared.start(payload: payload) { [weak self] status in
                self?.sdkReturned(orderNo: order.orderNo, status: status)
            }
        }
    }

    private func sdkReturned(orderNo: String, status: String?) {
        Task { @MainActor in
            while busy { try? await Task.sleep(nanoseconds: 200_000_000) }
            guard let order, order.orderNo == orderNo, !order.phase.finished else { return }
            work("正在查询付款结果") {
                if status == "6001" { self.message = "付款已取消，可在订单中继续付款" }
                try await self.poll(order)
            }
        }
    }

    private func poll(_ order: LocalOrder) async throws {
        for attempt in 0..<5 {
            if try await api.paid(order) { try await confirmPaid(order); return }
            if attempt < 4 { try await Task.sleep(nanoseconds: 2_000_000_000) }
        }
        let current = try await synchronizeOrderState(order)
        if current.phase.finished { noticeOrderState(current) }
        else { message = "付款结果仍在确认，请稍后刷新订单" }
    }

    private func synchronizeOrderState(_ order: LocalOrder) async throws -> LocalOrder {
        let status = try await api.orderStatus(order)
        let current = OrderStates.apply(order, status)
        if current != order { try saveOrder(current) }
        return current
    }

    private func confirmPaid(_ order: LocalOrder) async throws {
        var paid = order
        paid.phase = .paid
        try saveOrder(paid)
        if !paid.syncRequested {
            paid.syncRequested = true
            try saveOrder(paid)
            do {
                try await api.sync(paid)
                message = "付款已确认，已请求同步设备，请查看机器是否启动"
            } catch {
                message = "付款已确认；设备同步结果待核实，请查看洗衣机"
            }
        } else {
            message = "付款已确认，请查看洗衣机运行状态"
        }
    }

    private func saveOrder(_ value: LocalOrder) throws {
        try vault.saveOrder(value)
        order = value
    }

    private func noticeOrderState(_ order: LocalOrder) {
        switch order.phase {
        case .closed: message = "订单已关闭，可以返回洗衣重新选择模式"
        case .completed: message = "订单已完成"
        case .refunding: message = "订单正在退款，请在原应用查看进度"
        case .refunded: message = "订单已退款，请核对到账情况"
        case .paid: message = "付款已确认，请查看洗衣机运行状态"
        case .cancelled: message = "订单已取消"
        default: message = "尚未确认付款，可稍后再次查询"
        }
    }

    private func work(_ label: String, _ action: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        progress = label
        Task { @MainActor in
            do { try await action() }
            catch is CancellationError { }
            catch is SessionExpired {
                vault.logout()
                loggedIn = false
                phoneLabel = ""
                order = nil
                page = .home
                message = "登录已过期，请重新登录"
            }
            catch let error as BusinessRejected { message = error.displayMessage }
            catch let error as ClientError { message = error.message }
            catch { message = "暂时无法处理这份数据，请稍后重试" }
            busy = false
            progress = ""
        }
    }

    private func validPhone(_ phone: String) -> Bool {
        phone.range(of: #"^1[3-9]\d{9}$"#, options: .regularExpression) != nil
    }
}
