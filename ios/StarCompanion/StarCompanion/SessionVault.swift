import Foundation
import Security

protocol SessionVaulting {
    func load() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear() throws
}

enum SessionVaultError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidStoredSession
    case encodingFailed
}

/// Stores the complete authentication session in the system Keychain. Neither
/// provider tokens nor provider contact details are mirrored into UserDefaults.
struct KeychainSessionVault: SessionVaulting {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        service: String = (Bundle.main.bundleIdentifier ?? "com.starcompanion.local") + ".authentication",
        account: String = "current-session.v1"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SessionVaultError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let session = try? decoder.decode(AuthSession.self, from: data)
        else {
            throw SessionVaultError.invalidStoredSession
        }
        return session
    }

    func save(_ session: AuthSession) throws {
        guard let data = try? encoder.encode(session) else {
            throw SessionVaultError.encodingFailed
        }

        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let updates = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updates as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SessionVaultError.unexpectedStatus(updateStatus)
            }
        case errSecItemNotFound:
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SessionVaultError.unexpectedStatus(addStatus)
            }
        default:
            throw SessionVaultError.unexpectedStatus(status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionVaultError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Deterministic test double for AppStore and verifier scripts.
final class MemorySessionVault: SessionVaulting {
    private var session: AuthSession?

    init(session: AuthSession? = nil) {
        self.session = session
    }

    func load() throws -> AuthSession? { session }

    func save(_ session: AuthSession) throws {
        self.session = session
    }

    func clear() throws {
        session = nil
    }
}
