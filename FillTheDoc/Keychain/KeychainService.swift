import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData
    case stringEncoding
    
    public var errorDescription: String? {
        switch self {
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            case .invalidData:
                return "Keychain returned invalid data"
            case .stringEncoding:
                return "Keychain string encoding error"
        }
    }
}

/// Низкоуровневый сервис Keychain: хранение/чтение/удаление значений по account.
public actor KeychainService {
    private let service: String
    
    public init(service: String = Bundle.main.bundleIdentifier ?? "FillTheDoc") {
        self.service = service
    }
    
    public func saveString(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.stringEncoding }
        
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        // Попробуем update (если item уже есть)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        
        if updateStatus == errSecSuccess {
            return
        }
        
        if updateStatus != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
        
        // Если не найден — добавим
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }
    
    public func loadString(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data else { throw KeychainError.invalidData }
        
        return String(data: data, encoding: .utf8)
    }
    
    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
