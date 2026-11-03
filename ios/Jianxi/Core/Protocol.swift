import CoreFoundation
import CryptoKit
import Foundation

private func decodedFormComponent(_ raw: Substring) throws -> String {
    let bytes = Array(raw.utf8)
    for index in bytes.indices where bytes[index] == 37 {
        guard index + 2 < bytes.count,
              (bytes[index + 1] >= 48 && bytes[index + 1] <= 57 || bytes[index + 1] >= 65 && bytes[index + 1] <= 70 || bytes[index + 1] >= 97 && bytes[index + 1] <= 102),
              (bytes[index + 2] >= 48 && bytes[index + 2] <= 57 || bytes[index + 2] >= 65 && bytes[index + 2] <= 70 || bytes[index + 2] >= 97 && bytes[index + 2] <= 102) else {
            throw ClientError(message: "二维码编码无效")
        }
    }
    guard let result = String(raw).replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
        throw ClientError(message: "二维码编码无效")
    }
    return result
}

private func formPairs(_ raw: String) throws -> [(String, String)] {
    try raw.split(separator: "&", omittingEmptySubsequences: false).compactMap { entry in
        guard let separator = entry.firstIndex(of: "=") else { return nil }
        let key = try decodedFormComponent(entry[..<separator])
        let value = try decodedFormComponent(entry[entry.index(after: separator)...])
        return (key, value)
    }
}

enum DeviceCodes {
    static func parse(_ raw: String) throws -> DeviceCode {
        guard raw.utf16.count <= 4_096 else { throw ClientError(message: "二维码内容过长") }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).last?
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let matches = try formPairs(String(query)).filter { ["IMEI", "NQT", "SN"].contains($0.0) }
        guard matches.count == 1 else {
            throw ClientError(message: "请使用包含 IMEI、SN 或 NQT 的洗衣机二维码")
        }
        let (key, value) = matches[0]
        let fullRange = value.startIndex..<value.endIndex
        guard value.range(of: #"^[A-Za-z0-9_.-]{4,96}$"#, options: .regularExpression) == fullRange else {
            throw ClientError(message: "设备编号格式异常")
        }
        return DeviceCode(key: key, value: value)
    }
}

enum WireProtocol {
    static let version = "1.144.0"
    static let channel = "android_app"
    // Public constant from the supplied APK; it is not an account credential.
    private static let clientConstant = "nFU9pbG8YQoAe1kFh+E7eyrdlSLglwEJeA0wwHB1j5o="

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func sign(path: String, token: String, timestamp: String) -> String {
        precondition(path.hasPrefix("/") && !path.contains("?"))
        return sha256("appSecret=\(clientConstant)&channel=\(channel)&timestamp=\(timestamp)&token=\(token)&version=\(version)&\(path)")
    }

    static func riskSign(path: String, token: String, timestamp: String,
                         imei: String, category: String, fix: LocationFix) -> String {
        precondition(path.hasPrefix("/") && !path.contains("?"))
        return sha256("appSecret=\(clientConstant)&categoryCode=\(category)&channel=\(channel)&imei=\(imei)&lat=\(fix.latitude)&lng=\(fix.longitude)&timestamp=\(timestamp)&token=\(token)&version=\(version)&\(path)")
    }
}

func jsonText(_ object: [String: Any], _ key: String, fallback: String = "") -> String {
    guard let value = object[key], !(value is NSNull) else { return fallback }
    if let string = value as? String { return string }
    if let number = value as? NSNumber {
        return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
    }
    return fallback
}

func jsonBoolean(_ value: Any) -> Bool? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

private func jsonString(_ object: Any) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

enum PurchaseRules {
    static func items(device: Device, mode: WashMode) -> String {
        jsonString([["goodsId": device.id, "skuId": mode.id, "amount": "1",
                     "soldType": "1", "num": "1", "price": ""]])
    }

    static func goldExclusion(orgId: String) -> String {
        jsonString([["promotionId": "0", "promotionType": "4", "assetId": "0",
                     "oldPromotionId": "3482", "orgId": orgId]])
    }

    static func verifyQuote(_ data: [String: Any], device: Device, mode: WashMode) throws -> Quote {
        guard let items = data["items"] as? [Any] else {
            throw ClientError(message: "报价缺少洗衣项目")
        }
        guard items.count == 1 else { throw ClientError(message: "报价包含额外商品，请先在原应用核对") }
        guard let item = items[0] as? [String: Any],
              jsonText(item, "goodsId") == device.id,
              jsonText(item, "skuId") == mode.id,
              jsonText(item, "amount", fallback: "1") == "1" else {
            throw ClientError(message: "报价项目与所选洗衣模式不一致")
        }
        try verifyPromotions(data, orgId: device.orgId)
        let tradeType: Int
        if data["tradeType"] == nil || data["tradeType"] is NSNull {
            tradeType = 0
        } else {
            guard let parsed = Int(jsonText(data, "tradeType")) else {
                throw ClientError(message: "报价订单类型格式尚未适配")
            }
            tradeType = parsed
        }
        return Quote(device: device, mode: mode, amount: try money(jsonText(data, "realPrice")),
                     itemsJSON: PurchaseRules.items(device: device, mode: mode), tradeType: tradeType)
    }

    private static func verifyPromotions(_ data: [String: Any], orgId: String) throws {
        guard let raw = data["promotions"], !(raw is NSNull) else { return }
        guard let promotions = raw as? [Any] else {
            throw ClientError(message: "报价优惠数据格式尚未适配")
        }
        for entry in promotions {
            guard let promotion = entry as? [String: Any] else {
                throw ClientError(message: "报价优惠数据格式尚未适配")
            }
            let promotionType: Int
            if promotion["promotionType"] == nil || promotion["promotionType"] is NSNull {
                promotionType = 0
            } else {
                guard let parsed = Int(jsonText(promotion, "promotionType")) else {
                    throw ClientError(message: "报价优惠类型尚未适配")
                }
                promotionType = parsed
            }
            var excludesGold = false
            for key in ["options", "participateList"] {
                guard let value = promotion[key], !(value is NSNull) else { continue }
                guard let options = value as? [Any] else {
                    throw ClientError(message: "报价优惠选项格式尚未适配（\(key)：\(shape(value))）")
                }
                for option in options {
                    guard let item = option as? [String: Any] else {
                        throw ClientError(message: "报价优惠选项格式尚未适配（\(key)[]：\(shape(option))）")
                    }
                    if try used(item) {
                        guard goldExcluded(item, orgId: orgId) else {
                            throw ClientError(message: "报价附加了未选择的优惠，请先核对")
                        }
                        excludesGold = true
                    }
                }
            }
            if try used(promotion), !(promotionType == 4 && excludesGold) {
                throw ClientError(message: "报价附加了未选择的优惠，请先核对")
            }
        }
    }

    private static func used(_ object: [String: Any]) throws -> Bool {
        guard let flag = object["isUsed"], !(flag is NSNull) else { return false }
        guard let value = jsonBoolean(flag) else {
            throw ClientError(message: "报价优惠选中状态格式尚未适配")
        }
        return value
    }

    private static func goldExcluded(_ item: [String: Any], orgId: String) -> Bool {
        jsonText(item, "promotionType") == "4" && jsonText(item, "promotionId") == "0" &&
        jsonText(item, "assetId") == "0" && jsonText(item, "oldPromotionId") == "3482" &&
        jsonText(item, "orgId") == orgId
    }

    private static func shape(_ value: Any) -> String {
        if value is NSNull { return "空值" }
        if value is [Any] { return "数组" }
        if value is [String: Any] { return "对象" }
        if value is String { return "文本" }
        if jsonBoolean(value) != nil { return "布尔值" }
        return "数值"
    }

    static func verifyAlipay(_ raw: String, expectedAmount: String) throws {
        let args: [String: String]
        do {
            args = Dictionary(try formPairs(raw), uniquingKeysWith: { _, latest in latest })
        } catch {
            throw ClientError(message: "支付宝支付参数无效")
        }
        guard args["method"] == "alipay.trade.app.pay" else {
            throw ClientError(message: "当前返回的不是单次支付宝付款")
        }
        guard let content = args["biz_content"], let data = content.data(using: .utf8),
              let business = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError(message: "支付宝订单内容无法确认")
        }
        let forbidden: Set<String> = ["agreement_sign_params", "agreement_no", "period_rule_params",
                                      "sign_scene", "personal_product_code"]
        guard !args.keys.contains(where: forbidden.contains), !containsContract(business, forbidden: forbidden) else {
            throw ClientError(message: "付款包含签约内容，已停止")
        }
        let rawProduct = business["product_code"]
        if let rawProduct, !(rawProduct is NSNull), !(rawProduct is String) {
            throw ClientError(message: "支付宝支付产品码格式尚未适配")
        }
        let product = rawProduct as? String ?? ""
        if !product.isEmpty && product != "QUICK_MSECURITY_PAY" {
            let safe = product.range(of: #"^[A-Za-z0-9_]{1,64}$"#, options: .regularExpression)
                == product.startIndex..<product.endIndex
            throw ClientError(message: "暂不支持此支付宝支付产品（产品码：\(safe ? product : "未知格式")）")
        }
        let actualAmount = try money(jsonText(business, "total_amount"))
        let confirmedAmount = try money(expectedAmount)
        guard actualAmount == confirmedAmount else {
            throw ClientError(message: "支付金额与确认金额不一致")
        }
    }

    private static func containsContract(_ value: Any, forbidden: Set<String>) -> Bool {
        if let object = value as? [String: Any] {
            return object.contains { forbidden.contains($0.key) || containsContract($0.value, forbidden: forbidden) }
        }
        if let array = value as? [Any] {
            return array.contains { containsContract($0, forbidden: forbidden) }
        }
        return false
    }
}
