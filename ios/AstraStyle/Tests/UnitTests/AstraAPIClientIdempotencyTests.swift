//
//  AstraAPIClientIdempotencyTests.swift
//  AstraStyleTests
//
//  Pins HANDOFF §9.2: a retry of a paid vision call must reuse one
//  Idempotency-Key so the server can collapse duplicate attempts.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("AstraAPIClient Idempotency-Key reuse across retries", .serialized)
struct AstraAPIClientIdempotencyTests {

    @Test("Default retry policy makes four requests with three exponential backoffs")
    func defaultRetryCountAndBackoff() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 10
        let delays = RetryDelayRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
            session: URLSession(configuration: configuration),
            retrySleep: { await delays.record($0) })
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))
        do {
            _ = try await client.send(.exportPersonalData, as: AstraEmptyPayload.self)
            Issue.record("Exhausted server retries must surface an error")
        } catch let error as AstraError {
            #expect(error.underlyingStatusCode == 503)
        }
        #expect(IdempotencyStubURLProtocol.capturedRequests.count == 4)
        let recorded = await delays.values
        #expect(recorded.count == 3)
        for (delay, base) in zip(recorded, [0.5, 1.0, 2.0]) {
            #expect(delay >= base && delay <= base * 1.2)
        }
    }

    @Test("Transient responses honor Retry-After", arguments: [429, 503])
    func honorsRetryAfter(status: Int) async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 1
        IdempotencyStubURLProtocol.failureStatus = status
        IdempotencyStubURLProtocol.failureHeaders = ["Retry-After": "3"]
        IdempotencyStubURLProtocol.successBody = Data(#"{"data":{},"error":null}"#.utf8)
        let delays = RetryDelayRecorder()
        let client = retryClient(delays: delays)
        _ = try await client.send(.exportPersonalData, as: AstraEmptyPayload.self)
        #expect(await delays.values == [3])
        #expect(IdempotencyStubURLProtocol.capturedRequests.count == 2)
    }

    @Test("Invalid retry hints fall back to backoff; long hints surface without another request",
           arguments: ["invalid", "-1", "NaN", "3600"])
    func boundsRetryAfter(header: String) async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 1
        IdempotencyStubURLProtocol.failureHeaders = ["Retry-After": header]
        IdempotencyStubURLProtocol.successBody = Data(#"{"data":{},"error":null}"#.utf8)
        let delays = RetryDelayRecorder()
        let client = retryClient(delays: delays)
        do {
            _ = try await client.send(.exportPersonalData, as: AstraEmptyPayload.self)
            #expect(header != "3600")
        } catch let error as AstraError {
            #expect(header == "3600")
            #expect(error.retryAfter == 3600)
        }
        let recorded = await delays.values
        if header == "3600" {
            #expect(recorded.isEmpty)
            #expect(IdempotencyStubURLProtocol.capturedRequests.count == 1)
        } else {
            #expect(recorded.count == 1)
            #expect(recorded.first.map { $0 >= 0.5 && $0 <= 0.6 } == true)
        }
    }

    @Test("HTTP-date retry hint delays a recovered request")
    func honorsHTTPDate() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 1
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        IdempotencyStubURLProtocol.failureHeaders = [
            "Retry-After": formatter.string(from: .now.addingTimeInterval(10))
        ]
        IdempotencyStubURLProtocol.successBody = Data(#"{"data":{},"error":null}"#.utf8)
        let delays = RetryDelayRecorder()
        let client = retryClient(delays: delays)
        _ = try await client.send(.exportPersonalData, as: AstraEmptyPayload.self)
        let delay = try #require(await delays.values.first)
        #expect(delay > 5 && delay <= 10)
    }

    @Test("Cancellation during backoff stops retries even when the sleeper returns normally")
    func cancellationStopsRetry() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 10
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
            session: URLSession(configuration: configuration), retrySleep: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))
        let task = Task {
            try await client.send(.exportPersonalData, as: AstraEmptyPayload.self)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled retry must stop")
        } catch is CancellationError {
            #expect(IdempotencyStubURLProtocol.capturedRequests.count == 1)
        }
    }

    private func retryClient(delays: RetryDelayRecorder) -> AstraAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
            session: URLSession(configuration: configuration),
            retrySleep: { await delays.record($0) })
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))
        return client
    }

    @Test("Exhausted wear retries enqueue the same identity sent to the server")
    func wearIdentitySurvivesOfflineFallback() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 10
        let client = retryClient(delays: RetryDelayRecorder())
        let ownerID = UUID()
        let queue = InMemoryOfflineMutationQueue()
        let repository = LiveOutfitRepository(apiClient: client, offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: SupabaseOutfitWriter(supabase: AstraSupabaseClientFactory.previewClient),
            cache: InMemoryOutfitCache(), currentUserID: { ownerID })
        let wear = try await repository.recordWear(outfitID: UUID(), wornAt: .now,
                                                  occasion: nil, rating: nil, feedback: nil)
        let requests = IdempotencyStubURLProtocol.capturedRequests
        #expect(requests.count == 4)
        for request in requests {
            let data = try #require(request.httpBody)
            let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let body = try #require(envelope["body"] as? [String: Any])
            #expect((body["wear_id"] as? String)?.lowercased() == wear.id.uuidString.lowercased())
        }
        let mutation = try #require(await queue.pendingMutations().first)
        let queued = try JSONDecoder.astraDefault.decode(OutfitWear.self, from: mutation.payloadData)
        #expect(queued.id == wear.id)
    }

    @Test("Postgres empty weather defaults decode as an absent wear observation")
    func emptyWearWeatherDecodes() throws {
        let original = OutfitWear(id: UUID(), outfitID: UUID(), userID: UUID(), wornAt: .now)
        let data = try JSONEncoder.astraDefault.encode(original)
        var stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        stored["weather_snapshot"] = [String: String]()
        let decoded = try JSONDecoder.astraDefault.decode(OutfitWear.self,
            from: JSONSerialization.data(withJSONObject: stored))
        #expect(decoded.id == original.id)
        #expect(decoded.weatherSnapshot == nil)
    }

    @Test("Retry stops immediately after recovery without an extra sleep or request")
    func retryStopsAfterRecovery() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 2
        IdempotencyStubURLProtocol.successBody = Data(#"{"data":{},"error":null,"request_id":"recovered"}"#.utf8)
        let delays = RetryDelayRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
            session: URLSession(configuration: configuration),
            retrySleep: { await delays.record($0) })
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))
        _ = try await client.send(.exportPersonalData, as: AstraEmptyPayload.self)
        #expect(IdempotencyStubURLProtocol.capturedRequests.count == 3)
        #expect(await delays.values.count == 2)
    }

    @Test("An unauthenticated request never reaches transport or retry sleep")
    func missingSessionDoesNotSendOrRetry() async throws {
        IdempotencyStubURLProtocol.reset()
        let delays = RetryDelayRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
            session: URLSession(configuration: configuration),
            retrySleep: { await delays.record($0) })
        do {
            _ = try await client.send(.exportPersonalData, as: AstraEmptyPayload.self)
            Issue.record("Missing credentials must fail before transport")
        } catch let error as AstraError {
            #expect(error.category == .auth)
        }
        #expect(IdempotencyStubURLProtocol.capturedRequests.isEmpty)
        #expect(await delays.values.isEmpty)
    }

    @Test("analyzeClosetItem sends the same Idempotency-Key on every retry attempt of one logical call")
    func analyzeItemReusesIdempotencyKeyAcrossRetries() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 2
        IdempotencyStubURLProtocol.successBody = Data(
            #"""
            {"data":{"category":{"value":"top","confidence":0.9},"secondary_colors":[],"material":[],"seasonality":[],"fields_below_confidence_threshold":[]},"error":null,"request_id":"r1"}
            """#.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AstraAPIClient(environment: .preview, session: session, retryPolicy: .none)
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))

        let result = try await client.send(
            .analyzeClosetItem,
            body: AstraEmptyPayload(),
            as: ClosetItemAnalysisResult.self
        )
        #expect(result.category.value == .top)

        let keys = IdempotencyStubURLProtocol.capturedIdempotencyKeys
        #expect(keys.count == 3)
        #expect(Set(keys).count == 1)
        #expect(keys[0]?.isEmpty == false)
    }

    @Test("A batch resume reuses its caller-owned key across retries")
    func batchResumeReusesSuppliedKeyAcrossRetries() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 2
        IdempotencyStubURLProtocol.successBody = Data(
            #"{"data":{"job_id":"11111111-1111-4111-8111-111111111111","status":"queued"},"error":null,"request_id":"batch"}"#.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
                                    session: URLSession(configuration: configuration), retryPolicy: .none)
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))

        _ = try await client.send(
            .batchAnalyzeCloset,
            body: AstraEmptyPayload(),
            idempotencyKey: "stable-scanner-batch-key",
            as: ClosetItemAnalysisBatchJob.self
        )

        #expect(IdempotencyStubURLProtocol.capturedIdempotencyKeys == [
            "stable-scanner-batch-key",
            "stable-scanner-batch-key",
            "stable-scanner-batch-key"
        ])
    }

    @Test("High-resolution export sends a nonempty idempotency key")
    func hiResExportRequiresIdempotencyKey() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.successBody = Data(
            #"{"data":[],"error":null,"request_id":"hires"}"#.utf8
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
                                    session: URLSession(configuration: configuration), retryPolicy: .none)
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))
        _ = try await client.send(.exportStudioHiRes, body: AstraEmptyPayload(), as: [AstraEmptyPayload].self)
        let keys = IdempotencyStubURLProtocol.capturedIdempotencyKeys
        #expect(keys.count == 1)
        #expect(keys.first.flatMap { $0 }?.isEmpty == false)
        #expect(IdempotencyStubURLProtocol.capturedAuthorization == ["Bearer test-token"])
    }

    @Test("Live high-resolution repository encodes the source and fresh consent")
    func hiResRepositoryRequestContract() async throws {
        IdempotencyStubURLProtocol.reset()
        let child = StudioGeneration(id: UUID(), userID: UUID(), referenceImagePath: "", status: .queued)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let response: [String: AstraJSONValue] = [
            "data": try JSONDecoder().decode(AstraJSONValue.self, from: encoder.encode(child)),
            "request_id": .string("hires"), "error": .null
        ]
        IdempotencyStubURLProtocol.successBody = try encoder.encode(response)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
                                    session: URLSession(configuration: configuration), retryPolicy: .none)
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))
        let repository = LiveStudioRepository(apiClient: client, supabase: AstraSupabaseClientFactory.previewClient)
        let sourceID = UUID()
        let result = try await repository.exportHiRes(sourceID: sourceID,
            consent: StudioConsentAttestation(acknowledged: true))
        #expect(result.id == child.id)
        let request = try #require(IdempotencyStubURLProtocol.capturedRequests.first)
        #expect(request.url?.path.hasSuffix("/studio/export-hi-res") == true)
        #expect(request.httpMethod == "POST")
        let data = try #require(request.httpBody)
        let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try #require(envelope["body"] as? [String: Any])
        #expect((body["source_generation_id"] as? String)?.lowercased() == sourceID.uuidString.lowercased())
        let consent = try #require(body["consent"] as? [String: Any])
        #expect(consent["acknowledged"] as? Bool == true)
        #expect(consent["terms_version"] as? String == StudioConsentTerms.currentVersion)
    }

    @MainActor
    @Test("The request attaches renewed credentials instead of an expired token")
    func requestUsesRenewedSession() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.successBody = Data(
            #"{"data":[],"error":null,"request_id":"renewal"}"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
                                    session: URLSession(configuration: configuration), retryPolicy: .none)
        let userID = UUID()
        let keychain = KeychainTokenStore(service: "astra.test.request-renewal.\(UUID().uuidString)")
        defer { try? keychain.clear() }
        let store = SessionStore(apiClient: client, supabase: AstraSupabaseClientFactory.previewClient,
                                 keychain: keychain, sessionRefresher: RequestSessionRefresher(userID: userID))
        store.adoptInMemory(AuthSession(userID: userID, accessToken: "expired-token",
                                       refreshToken: "old-refresh", expiresAt: .now.addingTimeInterval(-1)))
        _ = try await client.send(.generateOutfits, body: AstraEmptyPayload(), as: [AstraEmptyPayload].self)
        #expect(IdempotencyStubURLProtocol.capturedAuthorization == ["Bearer renewed-token"])
    }

    @Test("generateOutfits does not send an Idempotency-Key")
    func outfitsDoesNotRequireIdempotencyKey() async throws {
        IdempotencyStubURLProtocol.reset()
        IdempotencyStubURLProtocol.failTimes = 0
        IdempotencyStubURLProtocol.successBody = Data(
            #"{"data":[],"error":null,"request_id":"r2"}"#.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AstraAPIClient(environment: .preview, session: session, retryPolicy: .none)
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))

        _ = try await client.send(
            .generateOutfits,
            body: AstraEmptyPayload(),
            as: [AstraEmptyPayload].self
        )
        #expect(IdempotencyStubURLProtocol.capturedIdempotencyKeys == [nil])
    }
    @Test("Live Studio deletion uses the authenticated shared generation deletion route")
    func studioDeletionUsesCanonicalRoute() async throws {
        IdempotencyStubURLProtocol.reset()
        let generationID = UUID()
        IdempotencyStubURLProtocol.successBody = Data(
            "{\"data\":{\"id\":\"\(generationID)\",\"status\":\"deleted\"},\"error\":null,\"request_id\":\"delete-test\"}".utf8
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyStubURLProtocol.self]
        let client = AstraAPIClient(environment: .preview,
            session: URLSession(configuration: configuration), retryPolicy: .none)
        client.setAuthTokenProvider(FixedIdempotencyTokenProvider(token: "test-token"))
        let repository = LiveStudioRepository(apiClient: client, supabase: AstraSupabaseClientFactory.previewClient)

        try await repository.deleteGeneration(id: generationID)

        let request = try #require(IdempotencyStubURLProtocol.capturedRequests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/functions/v1/studio/generations/\(generationID.uuidString.lowercased())")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(IdempotencyStubURLProtocol.capturedRequests.count == 1)
    }
}

private struct FixedIdempotencyTokenProvider: AstraAuthTokenProviding {
    let token: String
    func currentAccessToken() async -> String? { token }
}

final class IdempotencyStubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _failTimes = 0
    nonisolated(unsafe) private static var _failureStatus = 503
    nonisolated(unsafe) private static var _failureHeaders: [String: String] = [:]

    static var failureStatus: Int {
        get { lock.withLock { _failureStatus } }
        set { lock.withLock { _failureStatus = newValue } }
    }
    static var failureHeaders: [String: String] {
        get { lock.withLock { _failureHeaders } }
        set { lock.withLock { _failureHeaders = newValue } }
    }
    nonisolated(unsafe) private static var _successBody = Data()
    nonisolated(unsafe) private static var _keys: [String?] = []
    nonisolated(unsafe) private static var _requests: [URLRequest] = []
    static var capturedRequests: [URLRequest] { lock.withLock { _requests } }
    nonisolated(unsafe) private static var _authorization: [String?] = []

    static var capturedAuthorization: [String?] { lock.withLock { _authorization } }

    static var failTimes: Int {
        get { lock.withLock { _failTimes } }
        set { lock.withLock { _failTimes = newValue } }
    }

    static var successBody: Data {
        get { lock.withLock { _successBody } }
        set { lock.withLock { _successBody = newValue } }
    }

    static var capturedIdempotencyKeys: [String?] {
        lock.withLock { _keys }
    }

    static func reset() {
        lock.withLock {
            _failTimes = 0
            _failureStatus = 503
            _failureHeaders = [:]
            _successBody = Data()
            _keys = []
            _authorization = []
            _requests = []
        }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var capturedRequest = request
        if capturedRequest.httpBody == nil, let stream = capturedRequest.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            capturedRequest.httpBody = body
        }
        let key = request.value(forHTTPHeaderField: "Idempotency-Key")
        let (shouldFail, body): (Bool, Data) = Self.lock.withLock {
            Self._requests.append(capturedRequest)
            Self._keys.append(key)
            Self._authorization.append(request.value(forHTTPHeaderField: "Authorization"))
            if Self._failTimes > 0 {
                Self._failTimes -= 1
                return (true, Data(#"{"error":{"category":"server","message":"blip"},"data":null,"request_id":"r"}"#.utf8))
            }
            return (false, Self._successBody)
        }
        let status = shouldFail ? Self.failureStatus : 200
        var headers = ["Content-Type": "application/json"]
        if shouldFail { headers.merge(Self.failureHeaders) { _, new in new } }
        guard
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct RequestSessionRefresher: SessionRefreshing {
    let userID: UUID
    func refreshSession(refreshToken: String) async throws -> RefreshedSession {
        RefreshedSession(userID: userID, accessToken: "renewed-token", refreshToken: "rotated",
                         expiresAt: .now.addingTimeInterval(3600))
    }
}

private actor RetryDelayRecorder {
    private(set) var values: [Double] = []
    func record(_ delay: Double) { values.append(delay) }
}
