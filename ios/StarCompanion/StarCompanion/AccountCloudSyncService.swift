import Foundation

struct AccountDeletionIntent: Codable, Equatable {
    let accountID: String
    let providerAccountID: String
    let requestID: String
    var serverDeleted: Bool
}

struct PlanetMembership: Codable, Equatable, Sendable {
    struct Member: Codable, Equatable, Identifiable, Sendable {
        let accountID: String
        let name: String
        let personaID: String?
        var id: String { accountID }
    }
    let id: String
    let relationship: StarRelationship
    let members: [Member]
}

struct PlanetInvitation: Codable, Equatable, Sendable {
    let code: String
    let expiresAt: Date
    let shareURL: URL
    var url: URL { shareURL }
}

struct PlanetInviteCreation: Decodable, Sendable {
    let invite: PlanetInvitation
    let planet: PlanetMembership
}

struct AccountActionError: Error, Sendable {
    let code: String
}

/// Only a code explicitly pasted or opened by the user is read. No clipboard polling.
enum PlanetInviteCode {
    static func parse(_ input: String, allowedHost: String?) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValid(text.uppercased()) { return text.uppercased() }
        guard let parts = URLComponents(string: text) else { return nil }
        if parts.scheme?.lowercased() == "starcompanion", parts.host?.lowercased() == "invite",
           parts.path.isEmpty, parts.user == nil, parts.password == nil {
            let codes = parts.queryItems?.filter { $0.name == "code" } ?? []
            if codes.count == 1, let code = codes.first?.value?.uppercased(), isValid(code) { return code }
        }
        if parts.scheme?.lowercased() == "https", parts.host?.lowercased() == allowedHost?.lowercased(), allowedHost != nil,
           parts.path == "/invite", parts.user == nil, parts.password == nil,
           parts.query == nil, let fragment = parts.fragment, fragment.hasPrefix("code=") {
            let code = String(fragment.dropFirst(5)).uppercased()
            if isValid(code) { return code }
        }
        return nil
    }

    static func isValid(_ code: String) -> Bool {
        code.range(of: "^SC-(?:[0-9A-HJKMNP-TV-Z]{4}-){6}[0-9A-HJKMNP-TV-Z]{2}$", options: .regularExpression) != nil
    }
}

enum AccountCloudSyncStatus: Equatable, Sendable {
    case localOnly
    case waitingToSync
    case syncing
    case synced
    case pendingOffline
    case conflict
    case signInRequired
    case paused
}

enum AccountCloudSyncServiceError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    case forbidden
    case payloadTooLarge
    case rateLimited
    case conflict(currentRevision: String?)
    case unsupportedSchema(Int)
    case invalidResponse
    case server(Int)
    case transport
}

protocol AccountCloudSyncing: Sendable {
    var isConfigured: Bool { get }

    func fetchSnapshot(accessToken: String) async throws -> AccountCloudSnapshot?

    func uploadSnapshot(
        _ snapshot: AccountLocalData,
        baseRevision: String?,
        mutationID: String,
        accessToken: String
    ) async throws -> AccountCloudSnapshot

    func deleteSnapshot(
        baseRevision: String,
        mutationID: String,
        accessToken: String
    ) async throws

    func deleteAccount(requestID: String, accessToken: String) async throws
    func fetchPlanet(accessToken: String) async throws -> PlanetMembership?
    func createPlanetInvite(relationship: StarRelationship, accessToken: String) async throws -> PlanetInviteCreation
    func acceptPlanetInvite(code: String, accessToken: String) async throws -> PlanetMembership
    func leavePlanet(accessToken: String) async throws
    func revokePlanetInvite(code: String, accessToken: String) async throws
}

extension AccountCloudSyncing {
    func deleteAccount(requestID: String, accessToken: String) async throws { throw AccountCloudSyncServiceError.notConfigured }
    func fetchPlanet(accessToken: String) async throws -> PlanetMembership? { throw AccountCloudSyncServiceError.notConfigured }
    func createPlanetInvite(relationship: StarRelationship, accessToken: String) async throws -> PlanetInviteCreation { throw AccountCloudSyncServiceError.notConfigured }
    func acceptPlanetInvite(code: String, accessToken: String) async throws -> PlanetMembership { throw AccountCloudSyncServiceError.notConfigured }
    func leavePlanet(accessToken: String) async throws { throw AccountCloudSyncServiceError.notConfigured }
    func revokePlanetInvite(code: String, accessToken: String) async throws { throw AccountCloudSyncServiceError.notConfigured }
}

struct UnconfiguredAccountCloudSyncService: AccountCloudSyncing {
    let isConfigured = false

    func fetchSnapshot(accessToken: String) async throws -> AccountCloudSnapshot? {
        throw AccountCloudSyncServiceError.notConfigured
    }

    func uploadSnapshot(
        _ snapshot: AccountLocalData,
        baseRevision: String?,
        mutationID: String,
        accessToken: String
    ) async throws -> AccountCloudSnapshot {
        throw AccountCloudSyncServiceError.notConfigured
    }

    func deleteSnapshot(
        baseRevision: String,
        mutationID: String,
        accessToken: String
    ) async throws {
        throw AccountCloudSyncServiceError.notConfigured
    }
}

enum DefaultAccountCloudSyncService {
    static func make(bundle: Bundle = .main) -> any AccountCloudSyncing {
        guard let configuration = AccountCloudBackendConfiguration(bundle: bundle)?.configuration else {
            return UnconfiguredAccountCloudSyncService()
        }
        return ProductionAccountCloudSyncService(configuration: configuration)
    }
}

/// Account snapshots may live on a dedicated host even when Apple/phone token
/// issuance is handled by another service. Falling back to the auth base keeps
/// a single-origin deployment possible without coupling the two deployments.
struct AccountCloudBackendConfiguration: Equatable, Sendable {
    static let infoPlistKey = "StarCompanionAccountAPIBaseURL"

    let configuration: AuthBackendConfiguration

    init?(bundle: Bundle = .main) {
        if let value = bundle.object(forInfoDictionaryKey: Self.infoPlistKey) as? String,
           let configuration = AuthBackendConfiguration(baseURLString: value) {
            self.configuration = configuration
            return
        }
        guard let fallback = AuthBackendConfiguration(bundle: bundle) else { return nil }
        configuration = fallback
    }
}

private struct AccountCloudUploadRequest: Encodable {
    let schemaVersion: Int
    let baseRevision: Int64?
    let snapshot: AccountLocalData

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case baseRevision
        case snapshot
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        if let baseRevision {
            try container.encode(baseRevision, forKey: .baseRevision)
        } else {
            // The Worker uses an exact request schema and distinguishes a
            // first create (`null`) from a malformed omitted field.
            try container.encodeNil(forKey: .baseRevision)
        }
        try container.encode(snapshot, forKey: .snapshot)
    }
}

private struct AccountCloudErrorResponse: Decodable {
    let code: String
    let requestID: String
    let currentRevision: Int64?
    let updatedAt: Date?
}

private struct AccountCloudWireSnapshot: Decodable {
    let schemaVersion: Int
    let revision: Int64
    let updatedAt: Date
    let snapshot: AccountLocalData
}

private struct AccountCloudWriteResponse: Decodable {
    let schemaVersion: Int
    let revision: Int64
    let updatedAt: Date
}

private struct AccountCloudDeleteResponse: Decodable {
    let deleted: Bool
    let revision: Int64
    let updatedAt: Date
}

private final class AccountCloudNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
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

/// Account data is stored behind the same verified account backend as sign-in.
/// The server derives the canonical account from the bearer token; this client
/// deliberately never sends an account identifier in a URL, header, or body.
actor ProductionAccountCloudSyncService: AccountCloudSyncing {
    nonisolated let isConfigured = true

    private static let maximumPayloadBytes = 1_048_576
    private static let maximumResponseBytes = 1_114_112
    private static let snapshotKeys: Set<String> = [
        "schemaVersion", "revision", "updatedAt", "snapshot",
    ]
    private static let writeKeys: Set<String> = ["schemaVersion", "revision", "updatedAt"]
    private static let deleteKeys: Set<String> = ["deleted", "revision", "updatedAt"]
    private static let errorKeys: Set<String> = [
        "code", "requestID", "currentRevision", "updatedAt",
    ]

    private let configuration: AuthBackendConfiguration
    private let session: URLSession
    private let redirectDelegate: AccountCloudNoRedirectDelegate?
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
            let delegate = AccountCloudNoRedirectDelegate()
            redirectDelegate = delegate
            self.session = URLSession(
                configuration: Self.makeSessionConfiguration(timeout: self.timeout),
                delegate: delegate,
                delegateQueue: nil
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
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

    func fetchSnapshot(accessToken: String) async throws -> AccountCloudSnapshot? {
        let request = try makeRequest(
            method: "GET",
            accessToken: accessToken,
            body: nil,
            idempotencyKey: nil
        )
        let (data, response) = try await perform(request)

        switch response.statusCode {
        case 200:
            return try decodeAndValidateSnapshot(data)
        case 404:
            let error = try decodeError(data)
            guard error.code == "snapshot_not_found" else {
                throw AccountCloudSyncServiceError.invalidResponse
            }
            return nil
        default:
            throw try mappedError(statusCode: response.statusCode, data: data)
        }
    }

    func uploadSnapshot(
        _ snapshot: AccountLocalData,
        baseRevision: String?,
        mutationID: String,
        accessToken: String
    ) async throws -> AccountCloudSnapshot {
        let wireBaseRevision = try baseRevision.map(parseRevision)
        let body = try encoder.encode(
            AccountCloudUploadRequest(
                schemaVersion: AccountLocalData.currentSchemaVersion,
                baseRevision: wireBaseRevision,
                snapshot: snapshot
            )
        )
        guard body.count <= Self.maximumPayloadBytes else {
            throw AccountCloudSyncServiceError.payloadTooLarge
        }
        let request = try makeRequest(
            method: "PUT",
            accessToken: accessToken,
            body: body,
            idempotencyKey: mutationID
        )
        let (data, response) = try await perform(request)

        switch response.statusCode {
        case 200, 201:
            let response = try decodeWriteResponse(data)
            return AccountCloudSnapshot(
                revision: String(response.revision),
                updatedAt: response.updatedAt,
                snapshot: snapshot
            )
        case 409:
            let error = try decodeError(data)
            guard error.code == "snapshot_conflict" else {
                throw AccountCloudSyncServiceError.invalidResponse
            }
            throw AccountCloudSyncServiceError.conflict(
                currentRevision: error.currentRevision.map(String.init)
            )
        default:
            throw try mappedError(statusCode: response.statusCode, data: data)
        }
    }

    func deleteSnapshot(
        baseRevision: String,
        mutationID: String,
        accessToken: String
    ) async throws {
        let wireBaseRevision = try parseRevision(baseRevision)
        let request = try makeRequest(
            method: "DELETE",
            accessToken: accessToken,
            body: nil,
            idempotencyKey: mutationID,
            ifMatchRevision: wireBaseRevision
        )
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            throw try mappedError(statusCode: response.statusCode, data: data)
        }
        try requireExactKeys(Self.deleteKeys, in: data)
        guard let value = try? decoder.decode(AccountCloudDeleteResponse.self, from: data),
              value.deleted,
              value.revision == wireBaseRevision + 1,
              value.updatedAt <= Date.now.addingTimeInterval(5 * 60)
        else {
            throw AccountCloudSyncServiceError.invalidResponse
        }
    }

    private static func makeSessionConfiguration(timeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        return configuration
    }

    private func makeRequest(
        method: String,
        accessToken: String,
        body: Data?,
        idempotencyKey: String?,
        ifMatchRevision: Int64? = nil,
        path: String = "v1/account/snapshot"
    ) throws -> URLRequest {
        guard isValidToken(accessToken),
              let url = configuration.endpointURL(path: path)
        else {
            throw AccountCloudSyncServiceError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey {
            guard isValidIdempotencyKey(idempotencyKey) else {
                throw AccountCloudSyncServiceError.invalidResponse
            }
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let ifMatchRevision {
            request.setValue("\"\(ifMatchRevision)\"", forHTTPHeaderField: "If-Match")
        }
        return request
    }

    func deleteAccount(requestID: String, accessToken: String) async throws {
        let data = try await accountAction(path: "v1/account", method: "DELETE", body: ["confirmation": "DELETE"], accessToken: accessToken, requestID: requestID)
        struct Result: Decodable { let deleted: Bool }
        guard try decoder.decode(Result.self, from: data).deleted else { throw AccountCloudSyncServiceError.invalidResponse }
    }

    func fetchPlanet(accessToken: String) async throws -> PlanetMembership? {
        let data = try await accountAction(path: "v1/planet", method: "GET", accessToken: accessToken)
        try requireExactKeys(["planet"], in: data)
        struct Result: Decodable { let planet: PlanetMembership? }
        let planet = try decoder.decode(Result.self, from: data).planet
        if let planet { try validateMembership(planet) }
        return planet
    }

    func createPlanetInvite(relationship: StarRelationship, accessToken: String) async throws -> PlanetInviteCreation {
        let data = try await accountAction(path: "v1/planet/invites", method: "POST", body: ["relationship": relationship.rawValue], accessToken: accessToken)
        let result = try decoder.decode(PlanetInviteCreation.self, from: data)
        let invitation = result.invite
        guard PlanetInviteCode.isValid(invitation.code), invitation.expiresAt > .now,
              invitation.url.scheme == "https",
              invitation.url.host == configuration.endpointURL(path: "invite")?.host,
              PlanetInviteCode.parse(invitation.url.absoluteString, allowedHost: invitation.url.host) == invitation.code
        else { throw AccountCloudSyncServiceError.invalidResponse }
        try validateMembership(result.planet)
        return result
    }

    func acceptPlanetInvite(code: String, accessToken: String) async throws -> PlanetMembership {
        guard PlanetInviteCode.isValid(code) else { throw AccountActionError(code: "invalid_invite") }
        let data = try await accountAction(path: "v1/planet/invites/accept", method: "POST", body: ["code": code], accessToken: accessToken)
        struct Result: Decodable { let accepted: Bool; let planet: PlanetMembership }
        let result = try decoder.decode(Result.self, from: data)
        guard result.accepted else { throw AccountCloudSyncServiceError.invalidResponse }
        try validateMembership(result.planet)
        return result.planet
    }

    func leavePlanet(accessToken: String) async throws {
        let data = try await accountAction(path: "v1/planet/membership", method: "DELETE", accessToken: accessToken)
        struct Result: Decodable { let left: Bool }
        guard try decoder.decode(Result.self, from: data).left else { throw AccountCloudSyncServiceError.invalidResponse }
    }

    func revokePlanetInvite(code: String, accessToken: String) async throws {
        guard PlanetInviteCode.isValid(code) else { throw AccountActionError(code: "invalid_invite") }
        let data = try await accountAction(path: "v1/planet/invites", method: "DELETE", body: ["code": code], accessToken: accessToken)
        struct Result: Decodable { let revoked: Bool }
        guard try decoder.decode(Result.self, from: data).revoked else { throw AccountCloudSyncServiceError.invalidResponse }
    }

    private func validateMembership(_ planet: PlanetMembership) throws {
        guard !planet.id.isEmpty, planet.id.count <= 256,
              (1...2).contains(planet.members.count),
              Set(planet.members.map(\.accountID)).count == planet.members.count,
              planet.members.allSatisfy({ !$0.accountID.isEmpty && $0.accountID.count <= 256 && $0.name.count <= 128 })
        else { throw AccountCloudSyncServiceError.invalidResponse }
    }

    private func accountAction(path: String, method: String, body: [String: String]? = nil, accessToken: String, requestID: String? = nil) async throws -> Data {
        let request = try makeRequest(method: method, accessToken: accessToken, body: try body.map { try encoder.encode($0) }, idempotencyKey: requestID, path: path)
        let (data, response) = try await perform(request)
        guard (200...299).contains(response.statusCode) else {
            if let value = try? decoder.decode(AccountCloudErrorResponse.self, from: data) {
                throw AccountActionError(code: value.code)
            }
            throw try mappedError(statusCode: response.statusCode, data: data)
        }
        return data
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard data.count <= Self.maximumResponseBytes,
                  let response = response as? HTTPURLResponse,
                  response.url == request.url
            else {
                throw AccountCloudSyncServiceError.invalidResponse
            }
            if response.statusCode != 204 {
                guard response.mimeType?.lowercased() == "application/json" else {
                    throw AccountCloudSyncServiceError.invalidResponse
                }
            }
            return (data, response)
        } catch let error as AccountCloudSyncServiceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AccountCloudSyncServiceError.transport
        }
    }

    private func decodeAndValidateSnapshot(_ data: Data) throws -> AccountCloudSnapshot {
        try requireExactKeys(Self.snapshotKeys, in: data)
        let value: AccountCloudWireSnapshot
        do {
            value = try decoder.decode(AccountCloudWireSnapshot.self, from: data)
        } catch {
            throw AccountCloudSyncServiceError.invalidResponse
        }
        return try validated(value)
    }

    private func decodeWriteResponse(_ data: Data) throws -> AccountCloudWriteResponse {
        try requireExactKeys(Self.writeKeys, in: data)
        guard let value = try? decoder.decode(AccountCloudWriteResponse.self, from: data),
              value.schemaVersion == AccountCloudSnapshot.currentSchemaVersion,
              value.revision >= 1,
              value.updatedAt <= Date.now.addingTimeInterval(5 * 60)
        else {
            throw AccountCloudSyncServiceError.invalidResponse
        }
        return value
    }

    private func validated(_ value: AccountCloudWireSnapshot) throws -> AccountCloudSnapshot {
        guard value.schemaVersion == value.snapshot.schemaVersion,
              value.schemaVersion <= AccountLocalData.currentSchemaVersion,
              value.revision >= 1,
              value.updatedAt <= Date.now.addingTimeInterval(5 * 60)
        else {
            if value.schemaVersion > AccountLocalData.currentSchemaVersion {
                throw AccountCloudSyncServiceError.unsupportedSchema(value.schemaVersion)
            }
            throw AccountCloudSyncServiceError.invalidResponse
        }
        return AccountCloudSnapshot(
            schemaVersion: value.schemaVersion,
            revision: String(value.revision),
            updatedAt: value.updatedAt,
            snapshot: value.snapshot
        )
    }

    private func decodeError(_ data: Data) throws -> AccountCloudErrorResponse {
        try requireKeys(required: ["code", "requestID"], allowed: Self.errorKeys, in: data)
        guard let value = try? decoder.decode(AccountCloudErrorResponse.self, from: data),
              !value.code.isEmpty,
              value.code.count <= 80,
              !value.code.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              (1...128).contains(value.requestID.count),
              !value.requestID.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              value.currentRevision.map({ $0 >= 1 }) ?? true,
              value.updatedAt.map({ $0 <= Date.now.addingTimeInterval(5 * 60) }) ?? true
        else {
            throw AccountCloudSyncServiceError.invalidResponse
        }
        return value
    }

    private func requireExactKeys(_ expected: Set<String>, in data: Data) throws {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys) == expected
        else {
            throw AccountCloudSyncServiceError.invalidResponse
        }
    }

    private func requireKeys(
        required: Set<String>,
        allowed: Set<String>,
        in data: Data
    ) throws {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            throw AccountCloudSyncServiceError.invalidResponse
        }
        let keys = Set(dictionary.keys)
        guard required.isSubset(of: keys), keys.isSubset(of: allowed) else {
            throw AccountCloudSyncServiceError.invalidResponse
        }
    }

    private func mappedError(statusCode: Int, data: Data) throws -> AccountCloudSyncServiceError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 413: return .payloadTooLarge
        case 429: return .rateLimited
        case 500...599: return .server(statusCode)
        default:
            _ = try decodeError(data)
            return .server(statusCode)
        }
    }

    private func isValidToken(_ token: String) -> Bool {
        (1...16_384).contains(token.count)
            && token == token.trimmingCharacters(in: .whitespacesAndNewlines)
            && !token.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
            && !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private func isValidIdempotencyKey(_ value: String) -> Bool {
        guard (1...128).contains(value.count) else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private func parseRevision(_ value: String) throws -> Int64 {
        guard !value.isEmpty,
              value.first != "0",
              value.allSatisfy(\.isNumber),
              let revision = Int64(value),
              revision >= 1
        else {
            throw AccountCloudSyncServiceError.invalidResponse
        }
        return revision
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
