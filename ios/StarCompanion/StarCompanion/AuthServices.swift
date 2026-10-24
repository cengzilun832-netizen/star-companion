import AuthenticationServices
import CryptoKit
import Foundation
import Security

protocol PhoneOTPServicing {
    func requestCode(for phoneNumber: E164PhoneNumber) async throws -> PhoneOTPChallenge
    func verify(challengeID: String, code: String) async throws -> AuthSession
}

/// The production authentication backend is opt-in. An absent, placeholder,
/// or non-HTTPS Info.plist value deliberately leaves production sign-in in the
/// unconfigured state instead of guessing a server.
struct AuthBackendConfiguration: Equatable, Sendable {
    static let infoPlistKey = "StarCompanionAPIBaseURL"
    static let phoneOTPEnabledInfoPlistKey = "StarCompanionPhoneOTPEnabled"

    let baseURL: URL

    init?(bundle: Bundle = .main) {
        guard let rawValue = bundle.object(forInfoDictionaryKey: Self.infoPlistKey) as? String else {
            return nil
        }
        self.init(baseURLString: rawValue)
    }

    init?(baseURLString: String) {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == baseURLString,
              !trimmed.isEmpty,
              !trimmed.contains("$("),
              !trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            return nil
        }

        components.scheme = "https"
        if components.percentEncodedPath.count > 1 {
            while components.percentEncodedPath.hasSuffix("/") {
                components.percentEncodedPath.removeLast()
            }
        }
        guard let normalizedURL = components.url else { return nil }
        baseURL = normalizedURL
    }

    func endpointURL(path: String) -> URL? {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains(".."),
              !path.contains("?") && !path.contains("#"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let prefix = components.percentEncodedPath == "/"
            ? ""
            : components.percentEncodedPath
        components.percentEncodedPath = prefix + "/" + path
        return components.url
    }

    static func isPhoneOTPEnabled(bundle: Bundle = .main) -> Bool {
        if let value = bundle.object(forInfoDictionaryKey: phoneOTPEnabledInfoPlistKey) as? Bool {
            return value
        }
        guard let value = bundle.object(forInfoDictionaryKey: phoneOTPEnabledInfoPlistKey) as? String else {
            return false
        }
        return ["1", "true", "yes"].contains(value.lowercased())
    }
}

private protocol StrictBackendResponse: Decodable {
    static var allowedJSONKeys: Set<String> { get }
    static var requiredJSONKeys: Set<String> { get }
}

private struct PhoneChallengeRequest: Encodable {
    let phoneNumber: String
}

private struct PhoneChallengeResponse: StrictBackendResponse {
    static let allowedJSONKeys: Set<String> = [
        "challengeID", "maskedDestination", "expiresAt", "resendAvailableAt",
        "maxAttempts", "remainingAttempts"
    ]
    static let requiredJSONKeys = allowedJSONKeys

    let challengeID: String
    let maskedDestination: String
    let expiresAt: Date
    let resendAvailableAt: Date
    let maxAttempts: Int
    let remainingAttempts: Int
}

private struct PhoneVerifyRequest: Encodable {
    let challengeID: String
    let code: String
}

private struct AppleExchangeRequest: Encodable {
    let providerSubject: String
    let displayName: String?
    let identityToken: String
    let authorizationCode: String
    let nonce: String
    let state: String
}

private struct SessionRefreshRequest: Encodable {
    let refreshToken: String
}

/// Both Apple exchange and phone verification return this exact, flat schema.
/// The provider is selected by the endpoint rather than trusted from JSON.
private struct BackendSessionResponse: StrictBackendResponse {
    static let allowedJSONKeys: Set<String> = [
        "assurance", "canonicalAccountID", "providerSubject", "displayName",
        "issuedAt", "expiresAt", "accessToken", "refreshToken"
    ]
    static let requiredJSONKeys: Set<String> = [
        "assurance", "canonicalAccountID", "providerSubject", "displayName",
        "issuedAt", "expiresAt", "accessToken", "refreshToken"
    ]

    let assurance: AuthSessionAssurance
    let canonicalAccountID: String
    let providerSubject: String
    let displayName: String
    let issuedAt: Date
    let expiresAt: Date?
    let accessToken: String
    let refreshToken: String?
}

private struct BackendErrorResponse: StrictBackendResponse {
    static let allowedJSONKeys: Set<String> = [
        "code", "requestID", "remainingAttempts", "retryAfterSeconds"
    ]
    static let requiredJSONKeys: Set<String> = ["code", "requestID"]

    let code: String
    let requestID: String
    let remainingAttempts: Int?
    let retryAfterSeconds: Int?
}

private enum AuthBackendClientError: Error {
    case invalidRequest
    case invalidResponse
    case responseTooLarge
    case httpStatus(Int, BackendErrorResponse?)
}

protocol AuthSessionRefreshing {
    var isConfigured: Bool { get }
    func refresh(_ session: AuthSession) async throws -> AuthSession
}

private final class AuthNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// HTTPS client shared by the production Apple and phone authentication paths.
/// It intentionally has no logging surface so credentials and OTP values cannot
/// end up in console output.
actor ProductionAuthBackendClient: PhoneOTPServicing, AppleCredentialExchanging, AuthSessionRefreshing {
    nonisolated let isConfigured = true

    private static let maximumResponseBytes = 256 * 1_024

    private let configuration: AuthBackendConfiguration
    private let session: URLSession
    private let redirectDelegate: AuthNoRedirectDelegate?
    private let timeout: TimeInterval
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: AuthBackendConfiguration,
        session: URLSession? = nil,
        timeout: TimeInterval = 15
    ) {
        self.configuration = configuration
        self.timeout = min(max(timeout, 5), 30)
        if let session {
            self.session = session
            redirectDelegate = nil
        } else {
            let delegate = AuthNoRedirectDelegate()
            redirectDelegate = delegate
            self.session = URLSession(
                configuration: Self.makeEphemeralSessionConfiguration(timeout: self.timeout),
                delegate: delegate,
                delegateQueue: nil
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = Self.fractionalISO8601.date(from: rawValue)
                ?? Self.standardISO8601.date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date"
            )
        }
        self.decoder = decoder
    }

    static func makeEphemeralSessionConfiguration(timeout: TimeInterval = 15) -> URLSessionConfiguration {
        let safeTimeout = min(max(timeout, 5), 30)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = safeTimeout
        configuration.timeoutIntervalForResource = safeTimeout
        configuration.waitsForConnectivity = false
        return configuration
    }

    func requestCode(for phoneNumber: E164PhoneNumber) async throws -> PhoneOTPChallenge {
        do {
            let response: PhoneChallengeResponse = try await post(
                path: "v1/auth/phone/challenges",
                body: PhoneChallengeRequest(phoneNumber: phoneNumber.value)
            )
            return try validatedChallenge(response, requestedPhone: phoneNumber)
        } catch let error as PhoneOTPServiceError {
            throw error
        } catch let error as AuthBackendClientError {
            if let mapped = mapPhoneError(error) { throw mapped }
            throw error
        }
    }

    func verify(challengeID: String, code: String) async throws -> AuthSession {
        let cleanChallengeID = challengeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = code.filter(\.isNumber)
        guard cleanChallengeID == challengeID,
              (1...256).contains(cleanChallengeID.count),
              !cleanChallengeID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              cleanCode == code,
              cleanCode.count == 6
        else {
            throw PhoneOTPServiceError.challengeNotFound
        }

        do {
            let response: BackendSessionResponse = try await post(
                path: "v1/auth/phone/verify",
                body: PhoneVerifyRequest(challengeID: cleanChallengeID, code: cleanCode)
            )
            return try validatedSession(response, provider: .phone, expectedProviderSubject: nil)
        } catch let error as PhoneOTPServiceError {
            throw error
        } catch let error as AuthBackendClientError {
            if let mapped = mapPhoneError(error) { throw mapped }
            throw error
        }
    }

    func exchange(_ payload: AppleCredentialExchangePayload) async throws -> AuthSession {
        guard !payload.providerSubject.isEmpty,
              !payload.identityToken.isEmpty,
              !payload.authorizationCode.isEmpty,
              !payload.rawNonce.isEmpty,
              !payload.state.isEmpty
        else {
            throw AppleSignInServiceError.missingCredential
        }

        do {
            let response: BackendSessionResponse = try await post(
                path: "v1/auth/apple/exchange",
                body: AppleExchangeRequest(
                    providerSubject: payload.providerSubject,
                    displayName: payload.displayName,
                    identityToken: payload.identityToken.base64EncodedString(),
                    authorizationCode: payload.authorizationCode.base64EncodedString(),
                    nonce: payload.rawNonce,
                    state: payload.state
                )
            )
            return try validatedSession(
                response,
                provider: .apple,
                expectedProviderSubject: payload.providerSubject
            )
        } catch let error as AppleSignInServiceError {
            throw error
        } catch let error as AuthBackendClientError {
            guard case let .httpStatus(_, response) = error,
                  let code = response?.code
            else {
                throw AppleSignInServiceError.authorizationFailed
            }
            switch code {
            case "auth_not_configured":
                throw AppleSignInServiceError.notConfigured
            case "rate_limited":
                throw AppleSignInServiceError.rateLimited
            case "apple_unavailable", "storage_unavailable", "credential_unavailable":
                throw AppleSignInServiceError.temporarilyUnavailable
            default:
                throw AppleSignInServiceError.authorizationFailed
            }
        } catch is URLError {
            throw AppleSignInServiceError.temporarilyUnavailable
        } catch {
            throw AppleSignInServiceError.authorizationFailed
        }
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        guard session.assurance == .backendVerified,
              let refreshToken = session.refreshToken,
              isToken(refreshToken)
        else {
            throw AuthSessionRefreshError.missingRefreshToken
        }

        do {
            let response: BackendSessionResponse = try await post(
                path: "v1/auth/session/refresh",
                body: SessionRefreshRequest(refreshToken: refreshToken)
            )
            let refreshed = try validatedSession(
                response,
                provider: session.account.provider,
                expectedProviderSubject: session.account.providerSubject,
                expectedCanonicalAccountID: session.account.canonicalAccountID
            )
            guard refreshed.accessToken != session.accessToken,
                  refreshed.refreshToken != session.refreshToken,
                  refreshed.issuedAt >= session.issuedAt
            else {
                throw AuthSessionRefreshError.invalidResponse
            }
            return refreshed
        } catch let error as AuthBackendClientError {
            switch error {
            case let .httpStatus(status, _) where status == 401 || status == 403:
                throw AuthSessionRefreshError.rejected
            case .invalidRequest, .invalidResponse, .responseTooLarge:
                throw AuthSessionRefreshError.invalidResponse
            case .httpStatus:
                throw AuthSessionRefreshError.temporarilyUnavailable
            }
        } catch is URLError {
            throw AuthSessionRefreshError.temporarilyUnavailable
        } catch let error as AuthSessionRefreshError {
            throw error
        } catch {
            throw AuthSessionRefreshError.invalidResponse
        }
    }

    private func post<Body: Encodable, Response: StrictBackendResponse>(
        path: String,
        body: Body
    ) async throws -> Response {
        guard let url = configuration.endpointURL(path: path) else {
            throw AuthBackendClientError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw AuthBackendClientError.invalidRequest
        }

        let (data, response) = try await session.data(for: request)
        guard data.count <= Self.maximumResponseBytes else {
            throw AuthBackendClientError.responseTooLarge
        }
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.url == url
        else {
            throw AuthBackendClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let backendError = try? decodeStrict(BackendErrorResponse.self, from: data)
            throw AuthBackendClientError.httpStatus(httpResponse.statusCode, backendError)
        }
        guard httpResponse.mimeType?.lowercased() == "application/json" else {
            throw AuthBackendClientError.invalidResponse
        }
        return try decodeStrict(Response.self, from: data)
    }

    private func decodeStrict<Response: StrictBackendResponse>(
        _ type: Response.Type,
        from data: Data
    ) throws -> Response {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            throw AuthBackendClientError.invalidResponse
        }

        let keys = Set(dictionary.keys)
        guard keys.isSubset(of: Response.allowedJSONKeys),
              Response.requiredJSONKeys.isSubset(of: keys)
        else {
            throw AuthBackendClientError.invalidResponse
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AuthBackendClientError.invalidResponse
        }
    }

    private func validatedChallenge(
        _ response: PhoneChallengeResponse,
        requestedPhone: E164PhoneNumber,
        now: Date = .now
    ) throws -> PhoneOTPChallenge {
        guard isClean(response.challengeID, maximumLength: 256, permitsWhitespace: false),
              isClean(response.maskedDestination, maximumLength: 80, permitsWhitespace: true),
              response.maskedDestination != requestedPhone.value,
              !response.maskedDestination.contains(requestedPhone.value.dropFirst()),
              response.expiresAt > now,
              response.resendAvailableAt <= response.expiresAt,
              (1...10).contains(response.maxAttempts),
              (1...response.maxAttempts).contains(response.remainingAttempts)
        else {
            throw AuthBackendClientError.invalidResponse
        }
        return PhoneOTPChallenge(
            id: response.challengeID,
            maskedDestination: response.maskedDestination,
            expiresAt: response.expiresAt,
            resendAvailableAt: response.resendAvailableAt,
            maxAttempts: response.maxAttempts,
            remainingAttempts: response.remainingAttempts
        )
    }

    private func validatedSession(
        _ response: BackendSessionResponse,
        provider: AuthProvider,
        expectedProviderSubject: String?,
        expectedCanonicalAccountID: String? = nil,
        now: Date = .now
    ) throws -> AuthSession {
        guard response.assurance == .backendVerified,
              isClean(response.canonicalAccountID, maximumLength: 256, permitsWhitespace: false),
              isClean(response.providerSubject, maximumLength: 512, permitsWhitespace: false),
              isClean(response.displayName, maximumLength: 160, permitsWhitespace: true),
              isToken(response.accessToken),
              response.refreshToken.map(isToken) ?? true,
              response.issuedAt <= now.addingTimeInterval(5 * 60),
              response.expiresAt.map({ $0 > now && $0 > response.issuedAt }) ?? true,
              expectedProviderSubject.map({ $0 == response.providerSubject }) ?? true,
              expectedCanonicalAccountID.map({ $0 == response.canonicalAccountID }) ?? true
        else {
            throw AuthBackendClientError.invalidResponse
        }

        return AuthSession(
            account: AppAccount(
                provider: provider,
                providerSubject: response.providerSubject,
                displayName: response.displayName,
                canonicalAccountID: response.canonicalAccountID
            ),
            assurance: .backendVerified,
            issuedAt: response.issuedAt,
            expiresAt: response.expiresAt,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }

    private func isClean(
        _ value: String,
        maximumLength: Int,
        permitsWhitespace: Bool
    ) -> Bool {
        guard !value.isEmpty,
              value.count <= maximumLength,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return false
        }
        return permitsWhitespace
            || !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
    }

    private func isToken(_ token: String) -> Bool {
        isClean(token, maximumLength: 16_384, permitsWhitespace: false)
    }

    private func mapPhoneError(_ error: AuthBackendClientError) -> PhoneOTPServiceError? {
        guard case let .httpStatus(_, response) = error,
              let response
        else {
            return nil
        }
        switch response.code {
        case "invalid_phone_number":
            return .invalidPhoneNumber
        case "challenge_not_found":
            return .challengeNotFound
        case "challenge_expired":
            return .challengeExpired
        case "invalid_code":
            guard let attempts = response.remainingAttempts, (0...10).contains(attempts) else {
                return nil
            }
            return .invalidCode(remainingAttempts: attempts)
        case "too_many_attempts":
            return .tooManyAttempts
        case "resend_too_soon":
            guard let seconds = response.retryAfterSeconds, (1...3_600).contains(seconds) else {
                return nil
            }
            return .resendTooSoon(seconds: seconds)
        default:
            return nil
        }
    }

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

#if DEBUG
actor DebugPhoneOTPService: PhoneOTPServicing {
    static let testCode = "123456"

    private struct Record {
        let phoneNumber: E164PhoneNumber
        let expiresAt: Date
        var remainingAttempts: Int
    }

    private let challengeLifetime: TimeInterval
    private let resendDelay: TimeInterval
    private let maxAttempts: Int
    private var records: [String: Record] = [:]
    private var lastSentAt: [String: Date] = [:]

    init(
        challengeLifetime: TimeInterval = 5 * 60,
        resendDelay: TimeInterval = 60,
        maxAttempts: Int = 5
    ) {
        self.challengeLifetime = challengeLifetime
        self.resendDelay = resendDelay
        self.maxAttempts = maxAttempts
    }

    func requestCode(for phoneNumber: E164PhoneNumber) async throws -> PhoneOTPChallenge {
        let now = Date.now
        if let lastSent = lastSentAt[phoneNumber.value] {
            let remaining = Int(ceil(resendDelay - now.timeIntervalSince(lastSent)))
            if remaining > 0 {
                throw PhoneOTPServiceError.resendTooSoon(seconds: remaining)
            }
        }

        let id = UUID().uuidString
        let expiresAt = now.addingTimeInterval(challengeLifetime)
        let resendAvailableAt = now.addingTimeInterval(resendDelay)
        records[id] = Record(
            phoneNumber: phoneNumber,
            expiresAt: expiresAt,
            remainingAttempts: maxAttempts
        )
        lastSentAt[phoneNumber.value] = now
        return PhoneOTPChallenge(
            id: id,
            maskedDestination: phoneNumber.maskedDescription,
            expiresAt: expiresAt,
            resendAvailableAt: resendAvailableAt,
            maxAttempts: maxAttempts,
            remainingAttempts: maxAttempts
        )
    }

    func verify(challengeID: String, code: String) async throws -> AuthSession {
        guard var record = records[challengeID] else {
            throw PhoneOTPServiceError.challengeNotFound
        }
        guard record.expiresAt > .now else {
            records.removeValue(forKey: challengeID)
            throw PhoneOTPServiceError.challengeExpired
        }
        guard record.remainingAttempts > 0 else {
            throw PhoneOTPServiceError.tooManyAttempts
        }

        let normalizedCode = code.filter(\.isNumber)
        guard normalizedCode == Self.testCode else {
            record.remainingAttempts -= 1
            records[challengeID] = record
            throw PhoneOTPServiceError.invalidCode(remainingAttempts: record.remainingAttempts)
        }

        records.removeValue(forKey: challengeID)
        let digest = SHA256.hash(data: Data(("star-companion-debug-phone:" + record.phoneNumber.value).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let account = AppAccount(
            provider: .phone,
            providerSubject: "debug-" + String(digest.prefix(32)),
            displayName: "Star Friend \(record.phoneNumber.maskedDescription)"
        )
        return AuthSession(account: account, assurance: .localPreview)
    }
}
#endif

struct UnconfiguredPhoneOTPService: PhoneOTPServicing {
    func requestCode(for phoneNumber: E164PhoneNumber) async throws -> PhoneOTPChallenge {
        throw PhoneOTPServiceError.notConfigured
    }

    func verify(challengeID: String, code: String) async throws -> AuthSession {
        throw PhoneOTPServiceError.notConfigured
    }
}

struct AppleAuthorizationRequestContext: Equatable, Sendable {
    let rawNonce: String
    let hashedNonce: String
    let state: String
    let createdAt: Date

    static func make() throws -> AppleAuthorizationRequestContext {
        let nonce = try randomURLSafeString(byteCount: 32)
        let state = try randomURLSafeString(byteCount: 24)
        let hashedNonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return AppleAuthorizationRequestContext(
            rawNonce: nonce,
            hashedNonce: hashedNonce,
            state: state,
            createdAt: .now
        )
    }

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AppleSignInServiceError.authorizationFailed
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct AppleCredentialExchangePayload: Sendable {
    let providerSubject: String
    let displayName: String?
    let identityToken: Data
    let authorizationCode: Data
    let rawNonce: String
    let state: String
}

protocol AppleCredentialExchanging {
    /// Production implementations must validate Apple's signature, audience,
    /// issuer, expiry and nonce on the app backend before returning a session.
    func exchange(_ payload: AppleCredentialExchangePayload) async throws -> AuthSession
}

#if DEBUG
struct DebugAppleCredentialExchange: AppleCredentialExchanging {
    func exchange(_ payload: AppleCredentialExchangePayload) async throws -> AuthSession {
        let displayName = payload.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = AppAccount(
            provider: .apple,
            providerSubject: payload.providerSubject,
            displayName: displayName?.isEmpty == false ? displayName! : "Apple Stargazer"
        )
        // The Apple token is deliberately not retained. This DEBUG-only local
        // session is labelled `localPreview`, never `backendVerified`.
        return AuthSession(account: account, assurance: .localPreview)
    }
}
#endif

struct UnconfiguredAppleCredentialExchange: AppleCredentialExchanging {
    func exchange(_ payload: AppleCredentialExchangePayload) async throws -> AuthSession {
        throw AppleSignInServiceError.notConfigured
    }
}

struct UnconfiguredAuthSessionRefreshService: AuthSessionRefreshing {
    let isConfigured = false

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        throw AuthSessionRefreshError.notConfigured
    }
}

@MainActor
protocol AppleSignInServicing {
    func prepare(_ request: ASAuthorizationAppleIDRequest) throws -> AppleAuthorizationRequestContext
    func complete(
        _ result: Result<ASAuthorization, Error>,
        context: AppleAuthorizationRequestContext
    ) async throws -> AuthSession
}

@MainActor
struct NativeAppleSignInService: AppleSignInServicing {
    private let exchangeService: any AppleCredentialExchanging

    init(exchangeService: any AppleCredentialExchanging) {
        self.exchangeService = exchangeService
    }

    func prepare(_ request: ASAuthorizationAppleIDRequest) throws -> AppleAuthorizationRequestContext {
        let context = try AppleAuthorizationRequestContext.make()
        request.requestedScopes = [.fullName]
        request.nonce = context.hashedNonce
        request.state = context.state
        return context
    }

    func complete(
        _ result: Result<ASAuthorization, Error>,
        context: AppleAuthorizationRequestContext
    ) async throws -> AuthSession {
        let authorization: ASAuthorization
        switch result {
        case let .success(value):
            authorization = value
        case let .failure(error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                throw AppleSignInServiceError.cancelled
            }
            throw AppleSignInServiceError.authorizationFailed
        }

        guard Date.now.timeIntervalSince(context.createdAt) <= 5 * 60 else {
            throw AppleSignInServiceError.requestExpired
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = credential.identityToken,
              let authorizationCode = credential.authorizationCode
        else {
            throw AppleSignInServiceError.missingCredential
        }
        guard credential.state == context.state else {
            throw AppleSignInServiceError.stateMismatch
        }

        let displayName = credential.fullName.flatMap {
            let value = PersonNameComponentsFormatter().string(from: $0)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return try await exchangeService.exchange(AppleCredentialExchangePayload(
            providerSubject: credential.user,
            displayName: displayName,
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            rawNonce: context.rawNonce,
            state: context.state
        ))
    }
}

enum DefaultAuthServices {
    @MainActor
    static func apple() -> any AppleSignInServicing {
        #if DEBUG
        NativeAppleSignInService(exchangeService: DebugAppleCredentialExchange())
        #else
        if let configuration = AuthBackendConfiguration() {
            NativeAppleSignInService(
                exchangeService: ProductionAuthBackendClient(configuration: configuration)
            )
        } else {
            NativeAppleSignInService(exchangeService: UnconfiguredAppleCredentialExchange())
        }
        #endif
    }

    static func phoneOTP() -> any PhoneOTPServicing {
        #if DEBUG
        DebugPhoneOTPService()
        #else
        if AuthBackendConfiguration.isPhoneOTPEnabled(),
           let configuration = AuthBackendConfiguration() {
            ProductionAuthBackendClient(configuration: configuration)
        } else {
            UnconfiguredPhoneOTPService()
        }
        #endif
    }

    static func sessionRefresh() -> any AuthSessionRefreshing {
        if let configuration = AuthBackendConfiguration() {
            ProductionAuthBackendClient(configuration: configuration)
        } else {
            UnconfiguredAuthSessionRefreshService()
        }
    }
}
