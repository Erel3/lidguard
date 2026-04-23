import Foundation
import Security

enum KeychainService {
  private static let serviceName = "com.akim.lidguard"

  @discardableResult
  static func save(key: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }

    // Try update first — avoids the old delete-then-add race that could
    // leave the keychain empty if add failed after delete succeeded.
    let locator: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]
    let updateAttrs: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let updateStatus = SecItemUpdate(locator as CFDictionary, updateAttrs as CFDictionary)
    if updateStatus == errSecSuccess {
      return true
    }
    if updateStatus != errSecItemNotFound {
      return false
    }

    var addQuery = locator
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
  }

  static func load(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  @discardableResult
  static func delete(key: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]

    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  static func deleteAll() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
