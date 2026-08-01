//
//  AstraAPIClientErrorMappingTests.swift
//  AstraStyleTests
//
//  Pins the client's preference for the server's error envelope on status
//  codes that are not 4xx-validation / 5xx — especially 404, where a
//  mis-routed Edge Function slug is the usual cause and the generic
//  "Unexpected response (404)." string hides the only useful clue.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("AstraAPIClient error envelope mapping")
struct AstraAPIClientErrorMappingTests {

    @Test("A 404 with a server envelope surfaces the server's message")
    func notFoundPreservesServerEnvelope() async throws {
        EnvelopeStubURLProtocol.reset()
        EnvelopeStubURLProtocol.statusCode = 404
        EnvelopeStubURLProtocol.responseBody = Data(
            #"""
            {"error":{"category":"validation","message":"No route for POST /closet/analyze-item."},"request_id":"req_404"}
            """#.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnvelopeStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AstraAPIClient(environment: .preview, session: session, retryPolicy: .none)
        client.setAuthTokenProvider(FixedTokenProvider(token: "test-token"))

        do {
            _ = try await client.send(.analyzeClosetItem, body: AstraEmptyPayload(), as: AstraEmptyPayload.self)
            Issue.record("Expected send to throw on 404")
        } catch let error as AstraError {
            #expect(error.category == .validation)
            #expect(error.message == "No route for POST /closet/analyze-item.")
            #expect(error.underlyingStatusCode == 404)
        }
    }

    @Test("A 404 without an envelope still falls back to the generic message")
    func notFoundWithoutEnvelopeUsesGenericMessage() async throws {
        EnvelopeStubURLProtocol.reset()
        EnvelopeStubURLProtocol.statusCode = 404
        EnvelopeStubURLProtocol.responseBody = Data("not json".utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnvelopeStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AstraAPIClient(environment: .preview, session: session, retryPolicy: .none)
        client.setAuthTokenProvider(FixedTokenProvider(token: "test-token"))

        do {
            _ = try await client.send(.analyzeClosetItem, body: AstraEmptyPayload(), as: AstraEmptyPayload.self)
            Issue.record("Expected send to throw on 404")
        } catch let error as AstraError {
            #expect(error.category == .server)
            #expect(error.message == "Unexpected response (404).")
            #expect(error.underlyingStatusCode == 404)
        }
    }
}

private struct FixedTokenProvider: AstraAuthTokenProviding {
    let token: String
    func currentAccessToken() async -> String? { token }
}

/// Returns a fixed status + body for every request. Scoped to an ephemeral
/// `URLSessionConfiguration` per test — never registered process-wide.
final class EnvelopeStubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _statusCode: Int = 500
    nonisolated(unsafe) private static var _responseBody = Data()

    static var statusCode: Int {
        get { lock.withLock { _statusCode } }
        set { lock.withLock { _statusCode = newValue } }
    }

    static var responseBody: Data {
        get { lock.withLock { _responseBody } }
        set { lock.withLock { _responseBody = newValue } }
    }

    static func reset() {
        lock.withLock {
            _statusCode = 500
            _responseBody = Data()
        }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let code = Self.statusCode
        let body = Self.responseBody
        guard
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: code,
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
