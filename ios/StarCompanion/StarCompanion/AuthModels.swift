import Foundation

enum AuthProvider: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case apple
    case phone
    case weChat = "wechat"

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .apple:
            language.text("Apple 帳號", "Apple 계정", "Apple Account")
        case .phone:
            language.text("手機號碼", "휴대폰 번호", "Phone number")
        case .weChat:
            language.text("微信", "WeChat", "WeChat")
        }
    }
}

/// Provider-neutral account metadata. Authentication secrets never belong in
/// this value; they are stored only as part of `AuthSession` in Keychain.
struct AppAccount: Codable, Equatable, Identifiable, Sendable {
    let provider: AuthProvider
    let providerSubject: String
    let displayName: String
    let canonicalAccountID: String?

    init(
        provider: AuthProvider,
        providerSubject: String,
        displayName: String,
        canonicalAccountID: String? = nil
    ) {
        self.provider = provider
        self.providerSubject = providerSubject
        self.displayName = displayName
        self.canonicalAccountID = canonicalAccountID
    }

    var id: String { canonicalLocalAccountID }

    var providerLocalAccountID: String {
        "\(provider.rawValue):\(providerSubject)"
    }

    /// A backend-issued account ID takes precedence once providers are linked.
    /// Until then, the provider namespace prevents local account collisions.
    var canonicalLocalAccountID: String {
        if let canonical = canonicalAccountID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !canonical.isEmpty {
            return "account:\(canonical)"
        }
        return providerLocalAccountID
    }
}

enum AuthSessionAssurance: String, Codable, Equatable, Sendable {
    /// The app backend verified the provider response and issued the session.
    case backendVerified
    /// A clearly labelled local-only DEBUG session. It is never a production token.
    case localPreview
    /// An existing on-device WeChat preview migrated from the former data model.
    case legacyLocal
}

/// Stored only by `SessionVault`. Tokens are optional because preview and
/// migrated local sessions intentionally do not pretend to be server sessions.
struct AuthSession: Codable, Equatable, Sendable {
    let account: AppAccount
    let assurance: AuthSessionAssurance
    let issuedAt: Date
    let expiresAt: Date?
    let accessToken: String?
    let refreshToken: String?

    init(
        account: AppAccount,
        assurance: AuthSessionAssurance,
        issuedAt: Date = .now,
        expiresAt: Date? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil
    ) {
        self.account = account
        self.assurance = assurance
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func isExpired(at date: Date = .now) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }

    func needsRefresh(at date: Date = .now, leeway: TimeInterval = 2 * 60) -> Bool {
        guard assurance == .backendVerified,
              refreshToken?.isEmpty == false,
              let expiresAt
        else { return false }
        return expiresAt <= date.addingTimeInterval(max(0, leeway))
    }
}

struct E164PhoneNumber: Equatable, Sendable {
    let value: String

    init?(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "+" else { return nil }

        let separators = CharacterSet(charactersIn: " -().")
        let body = trimmed.dropFirst()
        let isASCIIDigit: (Unicode.Scalar) -> Bool = { (48...57).contains($0.value) }
        guard body.unicodeScalars.allSatisfy({
            isASCIIDigit($0) || separators.contains($0)
        }) else { return nil }

        let digits = body.unicodeScalars
            .filter(isASCIIDigit)
            .map(String.init)
            .joined()
        guard (8...15).contains(digits.count), digits.first != "0" else { return nil }
        value = "+" + digits
    }

    var maskedDescription: String {
        let suffix = value.suffix(4)
        return "+•• •••• \(suffix)"
    }
}

struct PhoneOTPChallenge: Equatable, Sendable {
    let id: String
    let maskedDestination: String
    let expiresAt: Date
    let resendAvailableAt: Date
    let maxAttempts: Int
    var remainingAttempts: Int

    func isExpired(at date: Date = .now) -> Bool {
        expiresAt <= date
    }

    func secondsUntilResend(at date: Date = .now) -> Int {
        max(0, Int(ceil(resendAvailableAt.timeIntervalSince(date))))
    }

    func secondsUntilExpiry(at date: Date = .now) -> Int {
        max(0, Int(ceil(expiresAt.timeIntervalSince(date))))
    }
}

enum PhoneOTPServiceError: Error, Equatable, Sendable {
    case invalidPhoneNumber
    case notConfigured
    case challengeNotFound
    case challengeExpired
    case invalidCode(remainingAttempts: Int)
    case tooManyAttempts
    case resendTooSoon(seconds: Int)
}

enum AppleSignInServiceError: Error, Equatable, Sendable {
    case cancelled
    case missingCredential
    case requestExpired
    case stateMismatch
    case notConfigured
    case rateLimited
    case temporarilyUnavailable
    case authorizationFailed
}

enum AuthSessionRefreshError: Error, Equatable, Sendable {
    case notConfigured
    case missingRefreshToken
    case rejected
    case temporarilyUnavailable
    case invalidResponse
}

enum WeChatSignInServiceError: Error, Equatable, Sendable {
    case notConfigured
}
