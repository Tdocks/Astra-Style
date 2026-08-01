//
//  AstraAPIClient.swift
//  AstraStyle
//
//  The single HTTP boundary between the app and the backend. Per spec §8,
//  the iOS client talks ONLY to Supabase Edge Functions — never directly to
//  Postgres, Storage, or any AI/vision/image provider. Every repository's
//  "Live" implementation is built on top of this client; nothing else in
//  the app is allowed to import `Foundation.URLSession` directly for
//  first-party API calls.
//
//  Responsibilities:
//   - Typed endpoint routing (`AstraEndpoint`, spec §14's 16 endpoints).
//   - Envelope encode/decode (`AstraRequestEnvelope` / `AstraResponseEnvelope`).
//   - Bearer token attachment via an injected token provider (breaks the
//     circular dependency with `SessionStore`, which itself is built on
//     top of this client).
//   - Structured `AstraError` mapping.
//   - Exponential backoff retry for retryable failure categories.
//   - `X-Request-Id` propagation for server-side log correlation
//     (spec §14 "Log request ID and latency").
//

import Foundation

/// Supplies the current Supabase access token, if any. Implemented by
/// `SessionStore`; injected post-construction to avoid a circular
/// initializer dependency (`SessionStore` itself depends on
/// `AstraAPIClient`).
public protocol AstraAuthTokenProviding: Sendable {
    func currentAccessToken() async -> String?
}

/// `@unchecked Sendable`: every stored property except `tokenProviderBox` is
/// set once in `init` and never mutated again; `tokenProviderBox` guards
/// its own mutable state with an `NSLock`. `JSONEncoder`/`JSONDecoder` are
/// documented by Apple as safe for concurrent use from multiple threads
/// even where the SDK's own `Sendable` audit lags behind.
public final class AstraAPIClient: @unchecked Sendable {
    private let environment: AstraEnvironment
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let retryPolicy: AstraRetryPolicy
    private let tokenProviderBox: TokenProviderBox

    public init(
        environment: AstraEnvironment,
        session: URLSession = .shared,
        retryPolicy: AstraRetryPolicy = .default
    ) {
        self.environment = environment
        self.session = session
        self.retryPolicy = retryPolicy
        self.tokenProviderBox = TokenProviderBox()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .useDefaultKeys
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// A client safe to construct in SwiftUI previews / tests. It is never
    /// actually invoked in preview builds because `AppContainer.preview()`
    /// wires repositories to in-memory mocks instead.
    public static let previewClient = AstraAPIClient(environment: .preview)

    public func setAuthTokenProvider(_ provider: AstraAuthTokenProviding) {
        tokenProviderBox.provider = provider
    }

    /// Performs a request against an Edge Function with no request body
    /// (e.g. `GET /studio/status/:id`).
    public func send<Payload: Decodable & Sendable>(
        _ endpoint: AstraEndpoint,
        as payloadType: Payload.Type
    ) async throws -> Payload {
        try await send(endpoint, body: AstraEmptyPayload(), as: payloadType)
    }

    /// Performs a request against an Edge Function with a typed request
    /// body, applying retry-with-backoff for retryable failures.
    ///
    /// When `endpoint.requiresIdempotencyKey` is true, one key is minted for
    /// the logical call and reused on every retry attempt — that is what
    /// makes a 5xx retry of `closet/analyze-item` safe against double
    /// vision billing (HANDOFF §9.2).
    public func send<Body: Encodable & Sendable, Payload: Decodable & Sendable>(
        _ endpoint: AstraEndpoint,
        body: Body,
        as payloadType: Payload.Type
    ) async throws -> Payload {
        let requestID = UUID().uuidString
        let idempotencyKey = endpoint.requiresIdempotencyKey ? UUID().uuidString : nil
        let policy = endpoint.retryPolicy == .default ? retryPolicy : endpoint.retryPolicy

        var attempt = 0
        while true {
            do {
                return try await performOnce(
                    endpoint,
                    body: body,
                    requestID: requestID,
                    idempotencyKey: idempotencyKey,
                    as: payloadType
                )
            } catch let error as AstraError {
                attempt += 1
                guard error.isRetryable, attempt <= policy.maxAttempts else {
                    throw error
                }
                let delay = policy.delay(forAttempt: attempt)
                try await Task.sleep(for: .seconds(delay))
                continue
            }
        }
    }

    private func performOnce<Body: Encodable & Sendable, Payload: Decodable & Sendable>(
        _ endpoint: AstraEndpoint,
        body: Body,
        requestID: String,
        idempotencyKey: String?,
        as payloadType: Payload.Type
    ) async throws -> Payload {
        let request = try await makeRequest(
            endpoint,
            body: body,
            requestID: requestID,
            idempotencyKey: idempotencyKey
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw AstraError.cancelled
        } catch {
            throw AstraError.network(error.localizedDescription, requestID: requestID)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AstraError.network("No HTTP response received.", requestID: requestID)
        }
        try throwIfUnsuccessful(httpResponse, data: data, requestID: requestID)

        return try decodePayload(Payload.self, from: data, statusCode: httpResponse.statusCode, requestID: requestID)
    }

    /// Builds the signed, enveloped `URLRequest` for an endpoint.
    ///
    /// Split out of `performOnce` so that "how a request is addressed and
    /// authorised" and "what the server said back" are two things you can read
    /// (and get wrong) independently.
    private func makeRequest<Body: Encodable & Sendable>(
        _ endpoint: AstraEndpoint,
        body: Body,
        requestID: String,
        idempotencyKey: String?
    ) async throws -> URLRequest {
        let url = environment.edgeFunctionsBaseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-Id")
        request.setValue(environment.supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        if endpoint.requiresAuthentication {
            guard let token = await tokenProviderBox.provider?.currentAccessToken() else {
                throw AstraError.auth("You've been signed out. Please sign in again.", requestID: requestID)
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(environment.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        if endpoint.method != .get {
            let envelope = AstraRequestEnvelope(requestID: requestID, clientVersion: Self.clientVersion, body: body)
            do {
                request.httpBody = try encoder.encode(envelope)
            } catch {
                throw AstraError.validation("Failed to encode request.", requestID: requestID)
            }
        }
        return request
    }

    /// Maps a non-2xx status onto the `AstraError` case the UI knows how to
    /// present, preferring the server's own error envelope when it sent one.
    private func throwIfUnsuccessful(
        _ response: HTTPURLResponse,
        data: Data,
        requestID: String
    ) throws {
        let statusCode = response.statusCode
        func serverEnvelopeError() -> AstraError? {
            try? decoder.decode(AstraResponseEnvelope<AstraEmptyPayload>.self, from: data)
                .error?.asAstraError(statusCode: statusCode, requestID: requestID)
        }

        switch statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw AstraError.auth("Your session has expired.", requestID: requestID)
        case 422, 400:
            throw serverEnvelopeError()
                ?? AstraError.validation("The request was invalid.", requestID: requestID)
        case 429:
            throw AstraError.rateLimited(requestID: requestID)
        case 500..<600:
            throw serverEnvelopeError()
                ?? AstraError.server(
                    "The server encountered an error.",
                    statusCode: statusCode,
                    requestID: requestID
                )
        default:
            // Prefer the server's envelope when present — a mis-routed slug
            // often returns 404 with a careful message (ADR 0013). Swallowing
            // it as "Unexpected response (404)." hides the only clue.
            throw serverEnvelopeError()
                ?? AstraError.server(
                    "Unexpected response (\(statusCode)).",
                    statusCode: statusCode,
                    requestID: requestID
                )
        }
    }

    /// Unwraps the success envelope. A 2xx that carries an `error` or no `data`
    /// is still a failure, and is reported as one rather than as an empty model.
    private func decodePayload<Payload: Decodable & Sendable>(
        _ payloadType: Payload.Type,
        from data: Data,
        statusCode: Int,
        requestID: String
    ) throws -> Payload {
        do {
            let envelope = try decoder.decode(AstraResponseEnvelope<Payload>.self, from: data)
            if let error = envelope.error {
                throw error.asAstraError(statusCode: statusCode, requestID: requestID)
            }
            guard let payload = envelope.data else {
                throw AstraError.server("The server returned an empty payload.", requestID: requestID)
            }
            return payload
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.server("Failed to parse the server's response.", requestID: requestID)
        }
    }

    private static let clientVersion: String = {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return "ios/\(shortVersion)"
    }()
}

/// A small reference box so `AstraAPIClient` (a `final class` conforming to
/// `Sendable` by being effectively immutable) can still have its token
/// provider set once, post-construction, without becoming a mutable
/// `class` itself. The box's mutable state is only ever touched from
/// `@MainActor` call sites (`SessionStore`), and reads happen inside an
/// actor-hopping `await`, so we mark it `@unchecked Sendable` with the
/// invariant documented here rather than adding actor overhead to every
/// network call.
private final class TokenProviderBox: @unchecked Sendable {
    // `NSLock.withLock(_:)` is a Foundation-provided `NSLocking` extension
    // (available well within our iOS 18 minimum) — intentionally not
    // reimplemented here to avoid shadowing/ambiguity with the SDK's own
    // method of the same name.
    private let lock = NSLock()
    private var _provider: AstraAuthTokenProviding?

    var provider: AstraAuthTokenProviding? {
        get { lock.withLock { _provider } }
        set { lock.withLock { _provider = newValue } }
    }
}

/// Exponential backoff with jitter, per spec §14 implied resilience
/// requirements around unreliable mobile networks.
public struct AstraRetryPolicy: Sendable, Equatable {
    public let maxAttempts: Int
    public let baseDelay: Double
    public let maxDelay: Double

    public init(maxAttempts: Int, baseDelay: Double, maxDelay: Double) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let `default` = AstraRetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 8.0)
    public static let none = AstraRetryPolicy(maxAttempts: 0, baseDelay: 0, maxDelay: 0)
    /// Paid provider calls that are server-idempotent under `Idempotency-Key`.
    public static let paidProvider = AstraRetryPolicy(maxAttempts: 3, baseDelay: 0.75, maxDelay: 8.0)
    /// Batch enqueue + status poll — fewer, slower retries to avoid poll stampedes.
    public static let batchJob = AstraRetryPolicy(maxAttempts: 2, baseDelay: 0.5, maxDelay: 4.0)

    func delay(forAttempt attempt: Int) -> Double {
        let exponential = baseDelay * pow(2.0, Double(attempt - 1))
        let capped = min(exponential, maxDelay)
        let jitter = Double.random(in: 0...(capped * 0.2))
        return capped + jitter
    }
}
