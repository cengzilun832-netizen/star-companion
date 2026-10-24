import Foundation

private enum CloudAPIVerificationFailure: Error, LocalizedError {
    case unexpectedRequest(String)

    var errorDescription: String? {
        switch self {
        case let .unexpectedRequest(message): message
        }
    }
}

private final class AccountCloudMockURLProtocol: URLProtocol, @unchecked Sendable {
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
            client?.urlProtocol(
                self,
                didFailWithError: CloudAPIVerificationFailure.unexpectedRequest("missing handler")
            )
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
    configuration.protocolClasses = [AccountCloudMockURLProtocol.self]
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    return URLSession(configuration: configuration)
}

private func response(
    for request: URLRequest,
    status: Int,
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

private func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonObject<Value: Encodable>(_ value: Value) throws -> Any {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try JSONSerialization.jsonObject(with: encoder.encode(value))
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else {
        throw CloudAPIVerificationFailure.unexpectedRequest("missing request body")
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else {
            throw CloudAPIVerificationFailure.unexpectedRequest("unreadable request body")
        }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private func requireIdentitySafeRequest(
    _ request: URLRequest,
    method: String,
    accessToken: String,
    forbiddenAccountID: String
) throws {
    guard request.httpMethod == method,
          request.url?.absoluteString == "https://sync.example.test/mobile/v1/account/snapshot",
          request.url?.query == nil,
          request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accessToken)",
          request.value(forHTTPHeaderField: "Accept") == "application/json",
          request.value(forHTTPHeaderField: "Cache-Control") == "no-store"
    else {
        throw CloudAPIVerificationFailure.unexpectedRequest("incorrect cloud request envelope")
    }

    let headers = request.allHTTPHeaderFields ?? [:]
    let identitySurface = ([request.url?.absoluteString ?? ""]
        + headers.map { "\($0.key):\($0.value)" })
        .joined(separator: "\n")
        .lowercased()
    guard !identitySurface.contains(forbiddenAccountID.lowercased()),
          !headers.keys.contains(where: {
              $0.lowercased().contains("account") || $0.lowercased().contains("user-id")
          })
    else {
        throw CloudAPIVerificationFailure.unexpectedRequest(
            "client account identifier leaked outside the bearer credential"
        )
    }
}

private func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

@main
enum VerifyAccountCloudAPI {
    static func main() async throws {
        let backend = AuthBackendConfiguration(
            baseURLString: "https://sync.example.test/mobile/"
        )!
        let client = ProductionAccountCloudSyncService(
            configuration: backend,
            session: makeMockSession(),
            timeout: 8
        )
        let accessToken = "verified-access-token-for-wire-tests"
        let forbiddenAccountID = "canonical-account-must-not-be-sent"
        var snapshot = AccountLocalData.seeded(for: "wire-contract-fixture")
        snapshot.visitStreak = 9
        let updatedAt = Date(timeIntervalSince1970: 1_788_235_200)
        let snapshotJSON = try jsonObject(snapshot)

        // GET authenticates only with the bearer token. The backend's numeric
        // revision is converted to the app's opaque String representation.
        AccountCloudMockURLProtocol.install { request in
            try requireIdentitySafeRequest(
                request,
                method: "GET",
                accessToken: accessToken,
                forbiddenAccountID: forbiddenAccountID
            )
            guard request.httpBody == nil, request.httpBodyStream == nil else {
                throw CloudAPIVerificationFailure.unexpectedRequest("GET unexpectedly had a body")
            }
            return (
                response(for: request, status: 200),
                try jsonData([
                    "schemaVersion": AccountLocalData.currentSchemaVersion,
                    "revision": 42,
                    "updatedAt": iso8601(updatedAt),
                    "snapshot": snapshotJSON,
                ])
            )
        }
        let fetched = try await client.fetchSnapshot(accessToken: accessToken)
        precondition(fetched?.revision == "42")
        precondition(fetched?.updatedAt == updatedAt)
        precondition(fetched?.snapshot == snapshot)

        // PUT carries compare-and-swap and idempotency metadata, but never a
        // client-selected account ID. A first successful create sends an
        // explicit JSON null baseRevision and accepts HTTP 201.
        let createMutationID = "2cb90b72-a59d-4c6e-b2bc-f631cb5650c8"
        AccountCloudMockURLProtocol.install { request in
            try requireIdentitySafeRequest(
                request,
                method: "PUT",
                accessToken: accessToken,
                forbiddenAccountID: forbiddenAccountID
            )
            guard request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  request.value(forHTTPHeaderField: "Idempotency-Key") == createMutationID,
                  let body = try JSONSerialization.jsonObject(with: requestBody(request))
                    as? [String: Any],
                  Set(body.keys) == ["schemaVersion", "baseRevision", "snapshot"],
                  (body["schemaVersion"] as? NSNumber)?.intValue
                    == AccountLocalData.currentSchemaVersion,
                  body["baseRevision"] is NSNull,
                  body["accountID"] == nil,
                  body["canonicalAccountID"] == nil
            else {
                throw CloudAPIVerificationFailure.unexpectedRequest("incorrect PUT wire contract")
            }
            return (
                response(for: request, status: 201),
                try jsonData([
                    "schemaVersion": AccountLocalData.currentSchemaVersion,
                    "revision": 1,
                    "updatedAt": iso8601(updatedAt),
                ])
            )
        }
        let created = try await client.uploadSnapshot(
            snapshot,
            baseRevision: nil,
            mutationID: createMutationID,
            accessToken: accessToken
        )
        precondition(created.revision == "1")
        precondition(created.snapshot == snapshot)

        // Subsequent writes serialize the opaque local base revision back to
        // the backend's numeric compare-and-swap field.
        let updateMutationID = "b8782993-6352-4228-9fc6-f53c6c966b18"
        AccountCloudMockURLProtocol.install { request in
            try requireIdentitySafeRequest(
                request,
                method: "PUT",
                accessToken: accessToken,
                forbiddenAccountID: forbiddenAccountID
            )
            guard request.value(forHTTPHeaderField: "Idempotency-Key") == updateMutationID,
                  let body = try JSONSerialization.jsonObject(with: requestBody(request))
                    as? [String: Any],
                  Set(body.keys) == ["schemaVersion", "baseRevision", "snapshot"],
                  (body["baseRevision"] as? NSNumber)?.int64Value == 41
            else {
                throw CloudAPIVerificationFailure.unexpectedRequest("incorrect update revision")
            }
            return (
                response(for: request, status: 200),
                try jsonData([
                    "schemaVersion": AccountLocalData.currentSchemaVersion,
                    "revision": 42,
                    "updatedAt": iso8601(updatedAt),
                ])
            )
        }
        let updated = try await client.uploadSnapshot(
            snapshot,
            baseRevision: "41",
            mutationID: updateMutationID,
            accessToken: accessToken
        )
        precondition(updated.revision == "42")

        // Conflict metadata is retained, including conversion of the server's
        // numeric current revision into the same opaque local representation.
        AccountCloudMockURLProtocol.install { request in
            (
                response(for: request, status: 409),
                try jsonData([
                    "code": "snapshot_conflict",
                    "requestID": "request-conflict-1",
                    "currentRevision": 77,
                    "updatedAt": iso8601(updatedAt),
                ])
            )
        }
        do {
            _ = try await client.uploadSnapshot(
                snapshot,
                baseRevision: "41",
                mutationID: updateMutationID,
                accessToken: accessToken
            )
            preconditionFailure("409 response was accepted as a successful upload")
        } catch AccountCloudSyncServiceError.conflict(currentRevision: "77") {
            // Expected.
        }

        // Codable does not make the wire schema permissive: unknown fields,
        // wrong media types, and unrecognized error bodies all fail closed.
        AccountCloudMockURLProtocol.install { request in
            (
                response(for: request, status: 200),
                try jsonData([
                    "schemaVersion": AccountLocalData.currentSchemaVersion,
                    "revision": 42,
                    "updatedAt": iso8601(updatedAt),
                    "snapshot": snapshotJSON,
                    "unexpectedPrivilege": "admin",
                ])
            )
        }
        try await requireError(.invalidResponse) {
            _ = try await client.fetchSnapshot(accessToken: accessToken)
        }

        AccountCloudMockURLProtocol.install { request in
            (
                response(for: request, status: 200, contentType: "text/plain"),
                Data("not json".utf8)
            )
        }
        try await requireError(.invalidResponse) {
            _ = try await client.fetchSnapshot(accessToken: accessToken)
        }

        AccountCloudMockURLProtocol.install { request in
            (
                response(for: request, status: 404),
                try jsonData(["code": "different_error", "requestID": "request-404-1"])
            )
        }
        try await requireError(.invalidResponse) {
            _ = try await client.fetchSnapshot(accessToken: accessToken)
        }

        AccountCloudMockURLProtocol.install { request in
            (
                response(for: request, status: 401),
                try jsonData(["code": "unauthorized", "requestID": "request-401-1"])
            )
        }
        try await requireError(.unauthorized) {
            _ = try await client.fetchSnapshot(accessToken: accessToken)
        }

        // Destructive account actions identify the account only by the bearer.
        let deletionID = UUID().uuidString
        AccountCloudMockURLProtocol.install { request in
            precondition(request.httpMethod == "DELETE")
            precondition(request.url?.path == "/mobile/v1/account")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accessToken)")
            precondition(request.value(forHTTPHeaderField: "Idempotency-Key") == deletionID)
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: String]
            precondition(body == ["confirmation": "DELETE"])
            return (response(for: request, status: 200), try jsonData(["deleted": true]))
        }
        try await client.deleteAccount(requestID: deletionID, accessToken: accessToken)

        AccountCloudMockURLProtocol.install { request in
            (response(for: request, status: 503), try jsonData([
                "code": "apple_revoke_failed", "retryable": true, "requestID": "request-delete-retry"
            ]))
        }
        do {
            try await client.deleteAccount(requestID: deletionID, accessToken: accessToken)
            preconditionFailure("revocation failure must remain retryable, not report deletion")
        } catch let error as AccountActionError {
            precondition(error.code == "apple_revoke_failed")
        }

        let inviteCode = "SC-0123-4567-89AB-CDEF-GHJK-MNPQ-RS"
        let planetJSON: [String: Any] = [
            "id": "planet-server-id", "relationship": "friend",
            "members": [["accountID": "acc-one", "name": "Ollie", "personaID": "moonveil"]],
            "createdAt": "2026-09-07T00:00:00.000Z", "updatedAt": "2026-09-07T00:00:00.000Z"
        ]
        AccountCloudMockURLProtocol.install { request in
            precondition(request.httpMethod == "POST" && request.url?.path == "/mobile/v1/planet/invites")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accessToken)")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: String]
            precondition(body == ["relationship": "friend"])
            return (response(for: request, status: 201), try jsonData([
                "invite": ["code": inviteCode, "expiresAt": iso8601(Date().addingTimeInterval(3600)),
                           "relationship": "friend", "shareURL": "https://sync.example.test/invite#code=\(inviteCode)",
                           "deepLink": "starcompanion://invite?code=\(inviteCode)"],
                "planet": planetJSON
            ]))
        }
        let invitation = try await client.createPlanetInvite(relationship: .friend, accessToken: accessToken)
        precondition(invitation.invite.code == inviteCode && invitation.planet.members.count == 1)

        AccountCloudMockURLProtocol.install { request in
            precondition(request.httpMethod == "POST" && request.url?.path == "/mobile/v1/planet/invites/accept")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: String]
            precondition(body == ["code": inviteCode])
            return (response(for: request, status: 200), try jsonData(["accepted": true, "planet": planetJSON]))
        }
        let accepted = try await client.acceptPlanetInvite(code: inviteCode, accessToken: accessToken)
        precondition(accepted.id == "planet-server-id")

        AccountCloudMockURLProtocol.install { request in
            precondition(request.httpMethod == "DELETE" && request.url?.path == "/mobile/v1/planet/invites")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: String]
            precondition(body == ["code": inviteCode])
            return (response(for: request, status: 200), try jsonData(["revoked": true]))
        }
        try await client.revokePlanetInvite(code: inviteCode, accessToken: accessToken)
        AccountCloudMockURLProtocol.install { request in
            precondition(request.httpMethod == "DELETE" && request.url?.path == "/mobile/v1/planet/membership")
            return (response(for: request, status: 200), try jsonData(["left": true, "planetDeleted": false]))
        }
        try await client.leavePlanet(accessToken: accessToken)

        print("Account deletion, revocation failure, and planet invite/accept/revoke/leave wire contracts verified")
        print(
            "Account cloud API bearer-only identity, numeric-to-opaque revisions, "
                + "201/idempotent CAS writes, conflict metadata, and strict errors verified"
        )
    }

    private static func requireError(
        _ expected: AccountCloudSyncServiceError,
        operation: () async throws -> Void
    ) async throws {
        do {
            try await operation()
            preconditionFailure("expected \(expected), but operation succeeded")
        } catch let error as AccountCloudSyncServiceError {
            precondition(error == expected, "expected \(expected), received \(error)")
        }
    }
}
