import Foundation

// AuthModels only needs this localization surface. The production definition
// lives in Models.swift; keeping the verifier small avoids pulling UI models
// into a security-foundation test executable.
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

private enum ExpectedFailure: Error { case save }

private struct FailingSessionVault: SessionVaulting {
    func load() throws -> AuthSession? { nil }
    func save(_ session: AuthSession) throws { throw ExpectedFailure.save }
    func clear() throws {}
}

@main
enum VerifyAuthFoundation {
    static func main() async throws {
        precondition(E164PhoneNumber("+886 912-345-678")?.value == "+886912345678")
        precondition(E164PhoneNumber("886912345678") == nil)
        precondition(E164PhoneNumber("+012345678") == nil)
        precondition(E164PhoneNumber("+1١٢٣٤٥٦٧") == nil)
        precondition(E164PhoneNumber("+1234567") == nil)
        precondition(E164PhoneNumber("+1234567890123456") == nil)

        let linked = AppAccount(
            provider: .apple,
            providerSubject: "provider-subject",
            displayName: "Moon",
            canonicalAccountID: "backend-account"
        )
        precondition(linked.providerLocalAccountID == "apple:provider-subject")
        precondition(linked.canonicalLocalAccountID == "account:backend-account")

        let session = AuthSession(
            account: linked,
            assurance: .backendVerified,
            expiresAt: Date.now.addingTimeInterval(60),
            accessToken: "access-secret",
            refreshToken: "refresh-secret"
        )
        let memoryVault = MemorySessionVault()
        try memoryVault.save(session)
        let loadedSession = try memoryVault.load()
        precondition(loadedSession == session)
        try memoryVault.clear()
        let clearedSession = try memoryVault.load()
        precondition(clearedSession == nil)

        do {
            try FailingSessionVault().save(session)
            preconditionFailure("Failing vault unexpectedly accepted a session")
        } catch ExpectedFailure.save {
            // Expected: production activation must roll back a prepared relink.
        }

        let phone = E164PhoneNumber("+14155552671")!
        let otpService = DebugPhoneOTPService(resendDelay: 3_600, maxAttempts: 2)
        let challenge = try await otpService.requestCode(for: phone)
        precondition(!challenge.maskedDestination.contains("4155552671"))
        do {
            _ = try await otpService.requestCode(for: phone)
            preconditionFailure("Resend throttle did not run")
        } catch let error as PhoneOTPServiceError {
            guard case let .resendTooSoon(seconds) = error else {
                preconditionFailure("Unexpected resend error: \(error)")
            }
            precondition(seconds > 0)
        }
        do {
            _ = try await otpService.verify(challengeID: challenge.id, code: "000000")
            preconditionFailure("Wrong OTP was accepted")
        } catch PhoneOTPServiceError.invalidCode(remainingAttempts: 1) {
            // Expected.
        }
        do {
            _ = try await otpService.verify(challengeID: challenge.id, code: "000000")
            preconditionFailure("Second wrong OTP was accepted")
        } catch PhoneOTPServiceError.invalidCode(remainingAttempts: 0) {
            // Expected.
        }
        do {
            _ = try await otpService.verify(challengeID: challenge.id, code: DebugPhoneOTPService.testCode)
            preconditionFailure("Exhausted challenge was accepted")
        } catch PhoneOTPServiceError.tooManyAttempts {
            // Expected.
        }

        let successfulService = DebugPhoneOTPService(resendDelay: 0)
        let successfulChallenge = try await successfulService.requestCode(for: phone)
        let phoneSession = try await successfulService.verify(
            challengeID: successfulChallenge.id,
            code: DebugPhoneOTPService.testCode
        )
        precondition(phoneSession.assurance == .localPreview)
        precondition(phoneSession.account.provider == .phone)
        precondition(!phoneSession.account.providerSubject.contains(phone.value))
        precondition(!phoneSession.account.displayName.contains(phone.value))
        precondition(phoneSession.accessToken == nil && phoneSession.refreshToken == nil)

        let firstAppleRequest = try AppleAuthorizationRequestContext.make()
        let secondAppleRequest = try AppleAuthorizationRequestContext.make()
        precondition(firstAppleRequest.rawNonce != firstAppleRequest.hashedNonce)
        precondition(firstAppleRequest.rawNonce != secondAppleRequest.rawNonce)
        precondition(firstAppleRequest.state != secondAppleRequest.state)
        precondition(firstAppleRequest.hashedNonce.count == 64)

        print("Auth provider IDs, E.164 validation, vault failure, OTP limits, hashed phone identity, and Apple nonce/state generation verified")
    }
}
