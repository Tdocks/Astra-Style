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

@Suite("AstraAPIClient Idempotency-Key reuse across retries")
struct AstraAPIClientIdempotencyTests {

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
}

private struct FixedIdempotencyTokenProvider: AstraAuthTokenProviding {
    let token: String
    func currentAccessToken() async -> String? { token }
}

final class IdempotencyStubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _failTimes = 0
    nonisolated(unsafe) private static var _successBody = Data()
    nonisolated(unsafe) private static var _keys: [String?] = []

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
            _successBody = Data()
            _keys = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "Idempotency-Key")
        let (shouldFail, body): (Bool, Data) = Self.lock.withLock {
            Self._keys.append(key)
            if Self._failTimes > 0 {
                Self._failTimes -= 1
                return (true, Data(#"{"error":{"category":"server","message":"blip"},"data":null,"request_id":"r"}"#.utf8))
            }
            return (false, Self._successBody)
        }
        let status = shouldFail ? 503 : 200
        guard
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
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
