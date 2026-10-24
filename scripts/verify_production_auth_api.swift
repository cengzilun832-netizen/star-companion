import Foundation

// AuthModels only needs this localization surface. The production definition
// lives in Models.swift; the verifier stays independent of UI models.
enum AppLanguage {
    case traditionalChinese
    case korean
    case english

    func text(_ traditionalChinese: String, _ korean: String, _ english: String) -> String {
        switch self {
        case .traditionalChinese: traditionalChinese
        case .korean: korean
        case .english: english
        }
    }
}

private enum VerificationFailure: Error, LocalizedError {
    case unexpectedRequest(String)

    var errorDescription: String? {
        switch self {
        case let .unexpectedRequest(message): message
        }
    }
}

private final class AuthMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?

    static func install(_ newHandler: @escaping Handler) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    private static func currentHandler() -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.currentHandler() else {
            client?.urlProtocol(self, didFailWithError: VerificationFailure.unexpectedRequest("missing handler"))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthMockURLProtocol.self]
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    return URLSession(configuration: configuration)
}

private func response(
    for request: URLRequest,
    status: Int = 200,
    contentType: String = "application/json",
    responseURL: URL? = nil
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: responseURL ?? request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType]
    )!
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func sessionObject(
    assurance: String = "backendVerified",
    providerSubject: String,
    canonicalAccountID: String = "canonical-account-42",
    accessToken: String = "access.token.value",
    extra: [String: Any] = [:]
) -> [String: Any] {
    let formatter = ISO8601DateFormatter()
    var object: [String: Any] = [
        "assurance": assurance,
        "canonicalAccountID": canonicalAccountID,
        "providerSubject": providerSubject,
        "displayName": "Moon Friend",
        "issuedAt": formatter.string(from: .now),
        "expiresAt": formatter.string(from: Date.now.addingTimeInterval(3_600)),
        "accessToken": accessToken,
        "refreshToken": "refresh.token.value"
    ]
    extra.forEach { object[$0.key] = $0.value }
    return object
}

private func requireJSONBody(_ request: URLRequest) throws -> [String: Any] {
    let body: Data?
    if let directBody = request.httpBody {
        body = directBody
    } else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { break }
            if count == 0 { break }
            collected.append(buffer, count: count)
        }
        body = collected
    } else {
        body = nil
    }

    guard request.httpMethod == "POST",
          request.value(forHTTPHeaderField: "Accept") == "application/json",
          request.value(forHTTPHeaderField: "Content-Type") == "application/json",
          request.value(forHTTPHeaderField: "Cache-Control") == "no-store",
          let body,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    else {
        throw VerificationFailure.unexpectedRequest("request was not strict JSON POST")
    }
    return object
}

@main
enum VerifyProductionAuthAPI {
    @MainActor
    static func main() async throws {
        precondition(AuthBackendConfiguration(baseURLString: "http://api.example.test") == nil)
        precondition(AuthBackendConfiguration(baseURLString: "https://user:secret@api.example.test") == nil)
        precondition(AuthBackendConfiguration(baseURLString: "https://api.example.test?debug=1") == nil)
        precondition(AuthBackendConfiguration(baseURLString: "$(STAR_COMPANION_API_BASE_URL)") == nil)
        let backendConfiguration = AuthBackendConfiguration(
            baseURLString: "https://api.example.test/mobile/"
        )!
        precondition(
            backendConfiguration.endpointURL(path: "v1/auth/phone/verify")?.absoluteString
                == "https://api.example.test/mobile/v1/auth/phone/verify"
        )

        let ephemeral = ProductionAuthBackendClient.makeEphemeralSessionConfiguration(timeout: 1)
        precondition(ephemeral.urlCache == nil)
        precondition(ephemeral.httpCookieStorage == nil)
        precondition(!ephemeral.httpShouldSetCookies)
        precondition(ephemeral.requestCachePolicy == .reloadIgnoringLocalCacheData)
        precondition(ephemeral.timeoutIntervalForRequest == 5)
        precondition(ephemeral.timeoutIntervalForResource == 5)

        let client = ProductionAuthBackendClient(
            configuration: backendConfiguration,
            session: makeMockSession(),
            timeout: 8
        )

        let phone = E164PhoneNumber("+14155552671")!
        AuthMockURLProtocol.install { request in
            guard request.url?.path == "/mobile/v1/auth/phone/challenges" else {
                throw VerificationFailure.unexpectedRequest(request.url?.path ?? "nil URL")
            }
            let body = try requireJSONBody(request)
            guard body["phoneNumber"] as? String == phone.value,
                  Set(body.keys) == ["phoneNumber"]
            else {
                throw VerificationFailure.unexpectedRequest("phone request schema")
            }
            let formatter = ISO8601DateFormatter()
            return (
                response(for: request),
                try jsonData([
                    "challengeID": "challenge_123",
                    "maskedDestination": "+•• •••• 2671",
                    "expiresAt": formatter.string(from: Date.now.addingTimeInterval(300)),
                    "resendAvailableAt": formatter.string(from: Date.now.addingTimeInterval(60)),
                    "maxAttempts": 5,
                    "remainingAttempts": 5
                ])
            )
        }
        let challenge = try await client.requestCode(for: phone)
        precondition(challenge.id == "challenge_123")
        precondition(challenge.remainingAttempts == 5)
        precondition(!challenge.maskedDestination.contains(phone.value.dropFirst()))

        AuthMockURLProtocol.install { request in
            guard request.url?.path == "/mobile/v1/auth/phone/verify" else {
                throw VerificationFailure.unexpectedRequest(request.url?.path ?? "nil URL")
            }
            let body = try requireJSONBody(request)
            guard body["challengeID"] as? String == challenge.id,
                  body["code"] as? String == "654321",
                  Set(body.keys) == ["challengeID", "code"]
            else {
                throw VerificationFailure.unexpectedRequest("phone verification schema")
            }
            return (
                response(for: request),
                try jsonData(sessionObject(providerSubject: "phone-provider-subject"))
            )
        }
        let phoneSession = try await client.verify(challengeID: challenge.id, code: "654321")
        precondition(phoneSession.assurance == .backendVerified)
        precondition(phoneSession.account.provider == .phone)
        precondition(phoneSession.account.canonicalAccountID == "canonical-account-42")
        precondition(phoneSession.accessToken == "access.token.value")

        let applePayload = AppleCredentialExchangePayload(
            providerSubject: "apple-provider-subject",
            displayName: "Moon Friend",
            identityToken: Data("identity-token".utf8),
            authorizationCode: Data("authorization-code".utf8),
            rawNonce: "nonce-value",
            state: "state-value"
        )
        AuthMockURLProtocol.install { request in
            guard request.url?.path == "/mobile/v1/auth/apple/exchange" else {
                throw VerificationFailure.unexpectedRequest(request.url?.path ?? "nil URL")
            }
            let body = try requireJSONBody(request)
            guard body["providerSubject"] as? String == applePayload.providerSubject,
                  body["identityToken"] as? String == applePayload.identityToken.base64EncodedString(),
                  body["authorizationCode"] as? String == applePayload.authorizationCode.base64EncodedString(),
                  body["nonce"] as? String == applePayload.rawNonce,
                  body["state"] as? String == applePayload.state
            else {
                throw VerificationFailure.unexpectedRequest("Apple exchange schema")
            }
            return (
                response(for: request),
                try jsonData(sessionObject(
                    providerSubject: applePayload.providerSubject,
                    extra: [
                        "issuedAt": ISO8601DateFormatter.fractional.string(from: .now),
                        "expiresAt": ISO8601DateFormatter.fractional.string(
                            from: Date.now.addingTimeInterval(3_600)
                        )
                    ]
                ))
            )
        }
        let appleSession = try await client.exchange(applePayload)
        precondition(appleSession.assurance == .backendVerified)
        precondition(appleSession.account.provider == .apple)
        precondition(appleSession.account.providerSubject == applePayload.providerSubject)
        precondition(appleSession.account.canonicalAccountID == "canonical-account-42")

        AuthMockURLProtocol.install { request in
            guard request.url?.path == "/mobile/v1/auth/session/refresh" else {
                throw VerificationFailure.unexpectedRequest(request.url?.path ?? "nil URL")
            }
            let body = try requireJSONBody(request)
            guard body["refreshToken"] as? String == appleSession.refreshToken,
                  Set(body.keys) == ["refreshToken"]
            else {
                throw VerificationFailure.unexpectedRequest("session refresh schema")
            }
            return (
                response(for: request),
                try jsonData(sessionObject(
                    providerSubject: applePayload.providerSubject,
                    accessToken: "rotated.access.token",
                    extra: [
                        "refreshToken": "rotated.refresh.token",
                        "issuedAt": ISO8601DateFormatter.fractional.string(
                            from: Date.now.addingTimeInterval(1)
                        ),
                        "expiresAt": ISO8601DateFormatter.fractional.string(
                            from: Date.now.addingTimeInterval(7_200)
                        )
                    ]
                ))
            )
        }
        let refreshedAppleSession = try await client.refresh(appleSession)
        precondition(refreshedAppleSession.account == appleSession.account)
        precondition(refreshedAppleSession.accessToken == "rotated.access.token")
        precondition(refreshedAppleSession.refreshToken == "rotated.refresh.token")

        // A typed response is still rejected when it is not explicitly backend verified.
        AuthMockURLProtocol.install { request in
            (
                response(for: request),
                try jsonData(sessionObject(
                    assurance: "localPreview",
                    providerSubject: applePayload.providerSubject
                ))
            )
        }
        do {
            _ = try await client.exchange(applePayload)
            preconditionFailure("localPreview Apple response was accepted")
        } catch AppleSignInServiceError.authorizationFailed {
            // Expected.
        }

        // Unknown response keys fail closed rather than being ignored by Codable.
        AuthMockURLProtocol.install { request in
            (
                response(for: request),
                try jsonData(sessionObject(
                    providerSubject: applePayload.providerSubject,
                    extra: ["unexpectedPrivilege": "admin"]
                ))
            )
        }
        do {
            _ = try await client.exchange(applePayload)
            preconditionFailure("response with unknown key was accepted")
        } catch AppleSignInServiceError.authorizationFailed {
            // Expected.
        }

        // Missing canonical identity or access token can never create a session.
        for invalidObject in [
            sessionObject(providerSubject: applePayload.providerSubject, canonicalAccountID: ""),
            sessionObject(providerSubject: applePayload.providerSubject, accessToken: "")
        ] {
            AuthMockURLProtocol.install { request in
                (response(for: request), try jsonData(invalidObject))
            }
            do {
                _ = try await client.exchange(applePayload)
                preconditionFailure("incomplete backend session was accepted")
            } catch AppleSignInServiceError.authorizationFailed {
                // Expected.
            }
        }

        AuthMockURLProtocol.install { request in
            (
                response(for: request, status: 401),
                try jsonData([
                    "code": "invalid_code",
                    "requestID": "request-phone-denied",
                    "remainingAttempts": 2
                ])
            )
        }
        do {
            _ = try await client.verify(challengeID: challenge.id, code: "000000")
            preconditionFailure("non-2xx OTP response was accepted")
        } catch PhoneOTPServiceError.invalidCode(remainingAttempts: 2) {
            // A known backend denial is mapped, never treated as a session.
        }

        AuthMockURLProtocol.install { request in
            (
                response(for: request, status: 503),
                try jsonData(["code": "auth_not_configured", "requestID": "request-config"])
            )
        }
        do {
            _ = try await client.exchange(applePayload)
            preconditionFailure("unconfigured Apple backend was not surfaced")
        } catch AppleSignInServiceError.notConfigured {
            // Expected: release UI can explain configuration instead of a vague retry.
        }

        AuthMockURLProtocol.install { request in
            (
                response(for: request, status: 429),
                try jsonData([
                    "code": "rate_limited",
                    "requestID": "request-rate-limit",
                    "retryAfterSeconds": 30
                ])
            )
        }
        do {
            _ = try await client.exchange(applePayload)
            preconditionFailure("Apple rate limit was not surfaced")
        } catch AppleSignInServiceError.rateLimited {
            // Expected.
        }

        AuthMockURLProtocol.install { request in
            (
                response(for: request, status: 401),
                try jsonData(["code": "unauthorized", "requestID": "request-refresh-replay"])
            )
        }
        do {
            _ = try await client.refresh(refreshedAppleSession)
            preconditionFailure("replayed refresh credential was accepted")
        } catch AuthSessionRefreshError.rejected {
            // Expected.
        }

        AuthMockURLProtocol.install { request in
            let redirectedURL = URL(string: "https://different.example.test/v1/auth/phone/challenges")!
            let formatter = ISO8601DateFormatter()
            return (
                response(for: request, responseURL: redirectedURL),
                try jsonData([
                    "challengeID": "redirected",
                    "maskedDestination": "+•• •••• 2671",
                    "expiresAt": formatter.string(from: Date.now.addingTimeInterval(300)),
                    "resendAvailableAt": formatter.string(from: Date.now.addingTimeInterval(60)),
                    "maxAttempts": 5,
                    "remainingAttempts": 5
                ])
            )
        }
        do {
            _ = try await client.requestCode(for: phone)
            preconditionFailure("redirected authentication response was accepted")
        } catch {
            // Expected: final URL must be the exact configured HTTPS endpoint.
        }

        // This command-line verifier has no Info.plist API URL, so Release
        // defaults must retain the explicit fail-closed service.
        precondition(DefaultAuthServices.phoneOTP() is UnconfiguredPhoneOTPService)
        precondition(DefaultAuthServices.sessionRefresh() is UnconfiguredAuthSessionRefreshService)

        print("Production Apple exchange, fractional dates, token refresh rotation, precise errors, strict schemas, and fail-closed defaults verified")
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
