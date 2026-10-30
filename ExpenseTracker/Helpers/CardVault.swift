//
//  CardVault.swift
//  ExpenseTracker
//

import Foundation
import Security

/// Keeps full card details (number, expiry, CVV) in the iPhone's Keychain instead of the app's database.
///
/// The Keychain is encrypted by the system, kept apart from the app's database and backups, and each item is
/// available only while the phone is unlocked and only on this phone. A card is stored under an id that its
/// `PaymentCard` record holds, so the database never contains the details themselves.
enum CardVault {
    struct Secrets: Codable, Equatable {
        var number = ""
        var expiry = ""
        var cvv = ""

        var isEmpty: Bool { number.isEmpty && expiry.isEmpty && cvv.isEmpty }
    }

    private static let service = (Bundle.main.bundleIdentifier ?? "ExpenseTracker") + ".cards"

    /// Recently read items, so a list of cards doesn't ask the Keychain on every redraw.
    private static var cache: [String: Secrets] = [:]

    private static func query(for id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
    }

    /// The details saved under this id, or `nil` if there are none.
    static func load(_ id: String) -> Secrets? {
        if let cached = cache[id] { return cached }

        var request = query(for: id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let secrets = try? JSONDecoder().decode(Secrets.self, from: data) else { return nil }
        cache[id] = secrets
        return secrets
    }

    /// Saves the details, or removes the item when there is nothing to keep. Returns whether it worked.
    @discardableResult
    static func save(_ secrets: Secrets, for id: String) -> Bool {
        guard !secrets.isEmpty else {
            delete(id)
            return true
        }
        guard let data = try? JSONEncoder().encode(secrets) else { return false }

        let update = SecItemUpdate(query(for: id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        var status = update
        if update == errSecItemNotFound {
            var item = query(for: id)
            item[kSecValueData as String] = data
            // Only while the phone is unlocked, and never copied to another device.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return false }
        cache[id] = secrets
        return true
    }

    static func delete(_ id: String) {
        SecItemDelete(query(for: id) as CFDictionary)
        cache[id] = nil
    }

    /// Removes every item whose id is not in `ids`: details of cards that were deleted.
    static func purge(keeping ids: Set<String>) {
        var request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        request[kSecReturnData as String] = false

        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }
        for item in items {
            if let id = item[kSecAttrAccount as String] as? String, !ids.contains(id) {
                delete(id)
            }
        }
    }
}
