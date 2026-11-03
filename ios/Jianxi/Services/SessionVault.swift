import Foundation
import Security

final class SessionVault {
    private let service = "dev.rain.laundry.ios"

    func token() -> String { string("token") ?? "" }
    func owner() -> String { string("owner") ?? "" }
    func phoneLabel() -> String { string("phone_label") ?? "" }

    func login(phone: String, token: String) throws {
        try put("owner", value: WireProtocol.sha256(phone))
        try put("phone_label", value: "\(phone.prefix(3)) **** \(phone.suffix(4))")
        try put("token", value: token)
    }

    func logout() {
        ["token", "owner", "phone_label"].forEach(delete)
    }

    func saveOrder(_ order: LocalOrder) throws {
        let data = try JSONEncoder().encode(order)
        try put("order_" + order.owner, data: data)
    }

    func order() -> LocalOrder? {
        let currentOwner = owner()
        guard !currentOwner.isEmpty,
              let data = data("order_" + currentOwner),
              let order = try? JSONDecoder().decode(LocalOrder.self, from: data),
              order.owner == currentOwner else { return nil }
        return order
    }

    private func string(_ name: String) -> String? {
        data(name).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func put(_ name: String, value: String) throws {
        try put(name, data: Data(value.utf8))
    }

    private func data(_ name: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func put(_ name: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name
        ]
        let changes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw ClientError(message: "无法保存本地会话") }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            throw ClientError(message: "无法保存本地会话")
        }
    }

    private func delete(_ name: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name
        ]
        SecItemDelete(query as CFDictionary)
    }
}
