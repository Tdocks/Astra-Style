//
//  AstraAPIClientErrorMappingTests.swift
//  AstraStyleTests
//
//  Pins the client's preference for the server's error envelope on status
//  codes that are not 4xx-validation / 5xx — and pins 404 specifically,
//  which is its own case.
//
//  A 404 has exactly two causes here and neither is transient: the slug
//  was never deployed (Supabase's gateway answers, in its own non-envelope
//  shape), or a deployed function's router has no such sub-path (ADR
//  0013's envelope). Both are facts about the build, so both map to
//  `.unimplemented`, which is not retryable — which is in turn what stops
//  the UI offering a "Try Again" button that cannot work (§22).
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("AstraAPIClient error envelope mapping")
struct AstraAPIClientErrorMappingTests {

    /// The undeployed-slug case, and the one the owner actually hit in
    /// TestFlight. Supabase's gateway body decodes *successfully* as
    /// `AstraResponseEnvelope` — every field of it is optional — leaving
    /// `error == nil`, which is how the real message came to be replaced
    /// by "Unexpected response (404)." for weeks.
    @Test("A Supabase gateway 404 for an undeployed slug is unimplemented, not a server error")
    func gatewayNotFoundIsUnimplemented() async throws {
        // Body captured verbatim from the live project on 2026-08-06 by
        // POSTing to a slug that does not exist. `code` is a *string* there,
        // which is why `AstraGatewayErrorPayload` declares only `message`.
        let error = try await errorFromNotFound(
            body: #"{"code":"NOT_FOUND","message":"Requested function was not found"}"#
        )
        #expect(error.category == .unimplemented)
        #expect(error.underlyingStatusCode == 404)
        #expect(error.requestID != nil)
        #expect(error.isRetryable == false)
    }

    @Test("A router 404 from a deployed function is also unimplemented")
    func routerNotFoundIsUnimplemented() async throws {
        let error = try await errorFromNotFound(
            body: #"{"error":{"category":"validation","message":"No route for POST /closet/analyze-item."},"request_id":"req_404"}"#
        )
        #expect(error.category == .unimplemented)
        #expect(error.underlyingStatusCode == 404)
    }

    @Test("A 404 with an unparseable body is still unimplemented")
    func unparseableNotFoundIsUnimplemented() async throws {
        let error = try await errorFromNotFound(body: "not json")
        #expect(error.category == .unimplemented)
        #expect(error.underlyingStatusCode == 404)
    }

    /// The reason `.unimplemented` matters more than the copy: a 404 is
    /// permanent, so retrying it burns four seconds of the user's time and
    /// then shows him the same screen. `.none` is passed as the *client's*
    /// policy here, so this asserts the error's own verdict rather than
    /// the configuration.
    @Test("A 404 is never retried")
    func notFoundIsNotRetryable() async throws {
        let error = try await errorFromNotFound(
            body: #"{"code":"NOT_FOUND","message":"Requested function was not found"}"#
        )
        #expect(error.isRetryable == false)
    }

    /// The gateway's *shape* is what broke this once already, so pin the
    /// decode rather than only the mapping around it.
    @Test("The gateway body decodes even though its code field is a string")
    func gatewayPayloadDecodes() throws {
        let body = Data(#"{"code":"NOT_FOUND","message":"Requested function was not found"}"#.utf8)
        let payload = try JSONDecoder().decode(AstraGatewayErrorPayload.self, from: body)
        #expect(payload.message == "Requested function was not found")

        // And the integer form Supabase's docs show, which is why `code`
        // is not declared at all.
        let numeric = Data(#"{"code":404,"message":"Requested function was not found"}"#.utf8)
        #expect(try JSONDecoder().decode(AstraGatewayErrorPayload.self, from: numeric).message == payload.message)
    }

    // MARK: - Helper

    private func errorFromNotFound(body: String) async throws -> AstraError {
        EnvelopeStubURLProtocol.reset()
        EnvelopeStubURLProtocol.statusCode = 404
        EnvelopeStubURLProtocol.responseBody = Data(body.utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnvelopeStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AstraAPIClient(environment: .preview, session: session, retryPolicy: .none)
        client.setAuthTokenProvider(FixedTokenProvider(token: "test-token"))

        do {
            _ = try await client.send(.analyzeClosetItem, body: AstraEmptyPayload(), as: AstraEmptyPayload.self)
            Issue.record("Expected send to throw on 404")
            throw AstraError.validation("unreachable")
        } catch let error as AstraError {
            return error
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
