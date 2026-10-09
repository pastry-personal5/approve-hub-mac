import Foundation
import Security

protocol CredentialKeychain: Sendable {
  func get(_ account: String) throws -> Data?
  func set(_ value: Data, for account: String) throws
  func delete(_ account: String) throws
}

struct SystemCredentialKeychain: CredentialKeychain {
  let service: String

  init(service: String = "com.approvehub.local-identity") {
    self.service = service
  }

  func get(_ account: String) throws -> Data? {
    var query = baseQuery(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw CredentialError.keychainFailure
    }
    return data
  }

  func set(_ value: Data, for account: String) throws {
    let query = baseQuery(account)
    let status = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: value] as CFDictionary
    )
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw CredentialError.keychainFailure }
    var item = query
    item[kSecValueData as String] = value
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
      throw CredentialError.keychainFailure
    }
  }

  func delete(_ account: String) throws {
    let status = SecItemDelete(baseQuery(account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialError.keychainFailure
    }
  }

  private func baseQuery(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
  }
}
