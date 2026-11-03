import SwiftUI
import UIKit

private enum WashPalette {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.84, blue: 0.70, alpha: 1)
            : UIColor(red: 0.13, green: 0.42, blue: 0.33, alpha: 1)
    })
    static let tint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.25, blue: 0.18, alpha: 1)
            : UIColor(red: 0.84, green: 0.93, blue: 0.87, alpha: 1)
    })
    static let button = Color(red: 0.13, green: 0.42, blue: 0.33)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let secondary = Color(uiColor: .secondaryLabel)
}

struct LaundryRootView: View {
    @ObservedObject var model: LaundryViewModel
    @State private var scannerOpen = false
    @State private var pasteOpen = false
    @State private var pasteCode = ""
    @State private var aboutOpen = false
    @State private var logoutOpen = false

    private var messageShown: Binding<Bool> {
        Binding(get: { model.message != nil }, set: { if !$0 { model.dismissMessage() } })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.busy {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView()
                                .tint(WashPalette.accent)
                            Text(model.progress)
                                .font(.footnote)
                                .foregroundStyle(WashPalette.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                    if !model.loggedIn {
                        LoginContent(model: model)
                    } else {
                        switch model.page {
                        case .home:
                            homeContent
                        case .device:
                            deviceContent
                        case .checkout:
                            checkoutContent
                        case .orders:
                            OrdersContent(model: model)
                        }
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(WashPalette.background.ignoresSafeArea())
        .tint(WashPalette.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.loggedIn {
                bottomBar
            }
        }
        .sheet(isPresented: $scannerOpen) {
            QRScannerSheet { raw in
                scannerOpen = false
                model.scan(raw)
            }
        }
        .sheet(isPresented: $pasteOpen) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    TextEditor(text: $pasteCode)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(WashPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("二维码内容")
                        .onChange(of: pasteCode) { pasteCode = String($0.prefix(4096)) }
                    Button("识别设备") {
                        let raw = String(pasteCode.prefix(4096))
                        pasteOpen = false
                        pasteCode = ""
                        model.scan(raw)
                    }
                    .buttonStyle(WashPrimaryButtonStyle())
                    .disabled(pasteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer(minLength: 0)
                }
                .padding(20)
                .background(WashPalette.background.ignoresSafeArea())
                .navigationTitle("粘贴设备码")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("取消") { pasteOpen = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $aboutOpen) {
            AboutView()
        }
        .confirmationDialog("退出登录？", isPresented: $logoutOpen, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { model.logout() }
        } message: {
            Text("未完成订单会保留在这台设备；用同一手机号登录后可继续查看。")
        }
        .alert("简洗", isPresented: messageShown) {
            Button("好") { model.dismissMessage() }
        } message: {
            Text(model.message ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if model.loggedIn && (model.page == .device || model.page == .checkout) {
                Button {
                    model.navigate(model.page == .checkout ? .device : .home)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 36)
                }
                .accessibilityLabel("返回")
                .disabled(model.busy)
            }
            Image(systemName: "drop.fill")
                .foregroundStyle(WashPalette.accent)
            Text("简洗")
                .font(.headline)
            Spacer()
            Button { aboutOpen = true } label: {
                Image(systemName: "info.circle")
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("关于简洗")
            if model.loggedIn {
                Menu {
                    Button("退出登录", role: .destructive) { logoutOpen = true }
                } label: {
                    Image(systemName: "person.crop.circle")
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("账户")
                .disabled(model.busy)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(WashPalette.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            tab("洗衣", symbol: "drop.fill", selected: model.page != .orders) {
                model.navigate(.home)
            }
            tab("订单", symbol: "doc.text", selected: model.page == .orders) {
                model.navigate(.orders)
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func tab(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19))
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(selected ? WashPalette.accent : WashPalette.secondary)
        }
        .disabled(model.busy)
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("开始洗衣")
                    .font(.title2.weight(.semibold))
                Text(model.phoneLabel)
                    .font(.subheadline)
                    .foregroundStyle(WashPalette.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(WashPalette.accent)
                    .frame(width: 64, height: 64)
                    .background(WashPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                Text("扫描洗衣机二维码")
                    .font(.title3.weight(.semibold))
                Button {
                    scannerOpen = true
                } label: {
                    Label("扫一扫", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(WashPrimaryButtonStyle())
                .disabled(model.busy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(WashPalette.tint, in: RoundedRectangle(cornerRadius: 8))
            Button {
                pasteOpen = true
            } label: {
                Label("粘贴设备码", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(WashSecondaryButtonStyle())
            .disabled(model.busy)
            if let order = model.order, !order.phase.finished {
                Button {
                    model.navigate(.orders)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("还有一笔订单待确认")
                                .font(.subheadline.weight(.semibold))
                            Text("查看付款进度")
                                .font(.footnote)
                                .foregroundStyle(WashPalette.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(WashPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var deviceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("选择洗衣模式")
                .font(.title2.weight(.semibold))
            if let device = model.device {
                deviceSummary(device.name, detail: device.remainingMinutes > 0
                    ? "使用中，约剩 \(device.remainingMinutes) 分钟" : "请确认这是你面前的洗衣机")
                if !device.error.isEmpty {
                    Label(device.error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                ForEach(device.modes, id: \.id) { mode in
                    Button {
                        model.selectMode(mode)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: model.mode?.id == mode.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(WashPalette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.name).font(.body.weight(.medium))
                                if !mode.feature.isEmpty {
                                    Text(mode.feature)
                                        .font(.caption)
                                        .foregroundStyle(WashPalette.secondary)
                                        .lineLimit(3)
                                }
                            }
                            Spacer(minLength: 8)
                            Text("¥\(mode.price)")
                                .font(.body.weight(.semibold))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(WashPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(model.mode?.id == mode.id ? WashPalette.accent : Color(uiColor: .separator),
                                    lineWidth: model.mode?.id == mode.id ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                }
                Button("确认模式，查看金额") { model.preview() }
                    .buttonStyle(WashPrimaryButtonStyle())
                    .disabled(model.busy || model.mode == nil || device.remainingMinutes > 0 || !device.error.isEmpty)
            }
        }
    }

    private var checkoutContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确认这一次洗衣")
                .font(.title2.weight(.semibold))
            if let quote = model.quote {
                deviceSummary(quote.device.name, detail: quote.mode.name)
                VStack(alignment: .leading, spacing: 12) {
                    receiptLine("洗衣项目", quote.mode.name)
                    receiptLine("数量", "1 次")
                    Divider()
                    Text("本次实付")
                        .font(.subheadline)
                        .foregroundStyle(WashPalette.secondary)
                    Text("¥\(quote.amount)")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(WashPalette.accent)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WashPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                Text("支付方式")
                    .font(.headline)
                ForEach(model.methods) { route in
                    Button {
                        model.selectPayment(route)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: model.payRoute?.id == route.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(WashPalette.accent)
                            Text(route.title)
                            Spacer()
                            Text("单次付款")
                                .font(.caption)
                                .foregroundStyle(WashPalette.secondary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                    Divider()
                }
                Button {
                    model.pay()
                } label: {
                    Label("确认支付 ¥\(quote.amount)", systemImage: "lock.fill")
                }
                .buttonStyle(WashPrimaryButtonStyle())
                .disabled(model.busy || model.payRoute == nil)
                Text("付款前请确认机器内已放好衣物。")
                    .font(.footnote)
                    .foregroundStyle(WashPalette.secondary)
            }
        }
    }

    private func deviceSummary(_ title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .foregroundStyle(WashPalette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(WashPalette.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WashPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LoginContent: View {
    @ObservedObject var model: LaundryViewModel
    @State private var phone = ""
    @State private var code = ""
    @State private var accepted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "drop.fill")
                .font(.system(size: 42))
                .foregroundStyle(WashPalette.accent)
                .frame(width: 72, height: 72)
                .background(WashPalette.tint, in: RoundedRectangle(cornerRadius: 8))
            Text("简洗")
                .font(.title.weight(.semibold))
            Text("登录洗衣账户")
                .font(.subheadline)
                .foregroundStyle(WashPalette.secondary)
            VStack(alignment: .leading, spacing: 14) {
                Text("手机号").font(.subheadline.weight(.medium))
                HStack {
                    Text("+86").foregroundStyle(WashPalette.secondary)
                    TextField("手机号", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .onChange(of: phone) { phone = String($0.filter(\.isNumber).prefix(11)) }
                }
                .washField()
                Text("短信验证码").font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    SecureField("验证码", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: code) { code = String($0.filter(\.isNumber).prefix(8)) }
                    Button(model.smsCooldown > 0 ? "\(model.smsCooldown)s" : "获取验证码") {
                        model.sendCode(phone)
                    }
                    .font(.subheadline.weight(.medium))
                    .disabled(!accepted || model.busy || phone.count != 11 || model.smsCooldown > 0)
                    .fixedSize()
                }
                .washField()
                Toggle("我同意使用此手机号登录本人已有的胖乖生活账户", isOn: $accepted)
                    .font(.footnote)
                Button("登录") { model.login(phone: phone, code: code) }
                    .buttonStyle(WashPrimaryButtonStyle())
                    .disabled(!accepted || model.busy || phone.count != 11 || !(4...8).contains(code.count))
            }
            .padding(18)
            .background(WashPalette.surface, in: RoundedRectangle(cornerRadius: 8))
            Text("简洗是独立客户端。短信和洗衣服务由原平台提供。")
                .font(.footnote)
                .foregroundStyle(WashPalette.secondary)
        }
    }
}

private struct OrdersContent: View {
    @ObservedObject var model: LaundryViewModel
    @State private var cancelOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("我的订单")
                .font(.title2.weight(.semibold))
            if let order = model.order {
                Image(systemName: order.phase == .paid ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                    .font(.system(size: 44))
                    .foregroundStyle(WashPalette.accent)
                    .padding(.top, 8)
                Text(phaseTitle(order.phase))
                    .font(.title3.weight(.semibold))
                Text(phaseDescription(order))
                    .font(.subheadline)
                    .foregroundStyle(WashPalette.secondary)
                VStack(spacing: 14) {
                    receiptLine("设备", order.deviceName)
                    receiptLine("模式", order.modeName)
                    receiptLine("金额", "¥\(order.amount)")
                    receiptLine("支付方式", order.payMethod.title)
                    receiptLine("下单时间", orderDate(order.createdAt))
                    if !order.orderNo.isEmpty {
                        Divider()
                        Text("订单号 \(order.orderNo)")
                            .font(.footnote)
                            .foregroundStyle(WashPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(18)
                .background(WashPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                if !order.orderNo.isEmpty && order.phase != .cancelled {
                    Button("刷新订单状态") { model.refreshOrder() }
                        .buttonStyle(WashSecondaryButtonStyle())
                        .disabled(model.busy)
                }
                if !order.phase.finished && !order.orderNo.isEmpty &&
                    (order.payMethod == .alipay || order.phase == .created) {
                    Button("继续付款") { model.resumePayment() }
                        .buttonStyle(WashPrimaryButtonStyle())
                        .disabled(model.busy)
                }
                if !order.phase.finished && !order.orderId.isEmpty {
                    Button("取消未付款订单", role: .destructive) { cancelOpen = true }
                        .disabled(model.busy)
                }
                Text("这里保留本机最近一笔订单。")
                    .font(.footnote)
                    .foregroundStyle(WashPalette.secondary)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 44))
                        .foregroundStyle(WashPalette.accent)
                    Text("还没有洗衣订单")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .alert("取消这笔订单？", isPresented: $cancelOpen) {
            Button("保留", role: .cancel) { }
            Button("确认取消", role: .destructive) { model.cancelOrder() }
        } message: {
            Text("会先核对订单详情和付款状态，确认仍可取消后再申请。")
        }
    }

    private func phaseTitle(_ phase: OrderPhase) -> String {
        switch phase {
        case .paid: return "付款已确认"
        case .creating, .unconfirmed: return "下单结果待确认"
        case .created: return "订单待付款"
        case .paymentPending: return "付款结果待确认"
        case .cancelled: return "订单已取消"
        case .rejected: return "下单未成功"
        case .closed: return "订单已关闭"
        case .completed: return "订单已完成"
        case .refunding: return "退款处理中"
        case .refunded: return "订单已退款"
        }
    }

    private func phaseDescription(_ order: LocalOrder) -> String {
        switch order.phase {
        case .paid: return "请查看洗衣机运行状态。"
        case .cancelled, .rejected: return "可以返回洗衣，重新选择模式。"
        case .closed: return "订单已超时或失效，可以重新选择模式。"
        case .completed: return "本次洗衣已结束。"
        case .refunding: return "平台正在处理退款，请在原应用查看进度。"
        case .refunded: return "平台已标记退款完成，请核对到账情况。"
        case .created: return "订单已创建，可以继续付款；若已在原应用付款，请刷新状态。"
        case .creating, .unconfirmed:
            return "请先在原应用核对这笔订单，避免重复下单。"
        case .paymentPending: return "付款结果尚未确认，请先查询订单状态。"
        }
    }

    private func orderDate(_ milliseconds: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000))
    }
}

private func receiptLine(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title)
            .foregroundStyle(WashPalette.secondary)
            .frame(width: 76, alignment: .leading)
        Text(value)
            .fontWeight(.medium)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .multilineTextAlignment(.trailing)
    }
    .font(.subheadline)
}

private struct WashPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(WashPalette.button.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct WashSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(WashPalette.accent)
            .background(WashPalette.surface.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: .separator), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private extension View {
    func washField() -> some View {
        self
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(WashPalette.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: .separator), lineWidth: 1))
    }
}
