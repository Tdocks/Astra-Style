//
//  AstraError.swift
//  AstraStyle
//
//  A structured error type distinguishing failure categories so every layer
//  above networking (repositories, view models, views) can react
//  appropriately — e.g. show a "sign in again" prompt for `.auth`, an
//  inline field error for `.validation`, a retry affordance for
//  `.network`/`.server`, or a provider-specific message for `.provider`.
//

import Foundation

public struct AstraError: Error, Sendable, Equatable, LocalizedError {
    public enum Category: Sendable, Equatable {
        /// No connectivity, timeout, DNS failure, TLS failure, etc.
        case network
        /// Missing/expired session, refresh failure, 401 from an Edge Function.
        case auth
        /// 4xx response indicating the request itself was malformed
        /// (missing field, bad enum value, failed server-side schema check).
        case validation
        /// 5xx response, or a well-formed response the client couldn't
        /// parse.
        case server
        /// The Edge Function ran, but the underlying AI/vision/image
        /// provider it called failed or timed out (spec §8's provider
        /// abstraction — StylistReasoningProvider, VisionAnalysisProvider,
        /// ImageGenerationProvider, EmbeddingProvider,
        /// ProductExtractionProvider).
        case provider
        /// Client-side rate limiting or a 429 from the server (spec §14
        /// "Rate limit").
        case rateLimited
        /// Request was cancelled (e.g. view disappeared mid-flight).
        case cancelled
        /// The feature exists as a protocol requirement but its backing
        /// schema, table or Edge Function has not been built yet.
        ///
        /// Distinct from `.server` on purpose. A `.server` failure is a runtime
        /// problem that might not happen next time; this one is a fact about
        /// the build — retrying will never help, and the UI should degrade
        /// (hide the module, disable the control) rather than offer a retry
        /// button that cannot succeed. Making it its own category is what stops
        /// a not-yet-built feature from being indistinguishable, at the call
        /// site, from a backend outage.
        case unimplemented
        case unknown
    }

    public let category: Category
    public let message: String
    public let underlyingStatusCode: Int?
    /// Correlates this failure with server-side logs (spec §14 "Log
    /// request ID and latency").
    public let requestID: String?

    public init(category: Category, message: String, underlyingStatusCode: Int? = nil, requestID: String? = nil) {
        self.category = category
        self.message = message
        self.underlyingStatusCode = underlyingStatusCode
        self.requestID = requestID
    }

    public var errorDescription: String? { message }

    /// Whether a transient-failure retry (exponential backoff) is
    /// worthwhile for this category.
    public var isRetryable: Bool {
        switch category {
        case .network, .server, .provider, .rateLimited: true
        case .auth, .validation, .cancelled, .unimplemented, .unknown: false
        }
    }

    public static func == (lhs: AstraError, rhs: AstraError) -> Bool {
        lhs.category == rhs.category
            && lhs.message == rhs.message
            && lhs.underlyingStatusCode == rhs.underlyingStatusCode
            && lhs.requestID == rhs.requestID
    }
}

extension AstraError {
    public static func network(_ message: String, requestID: String? = nil) -> AstraError {
        AstraError(category: .network, message: message, requestID: requestID)
    }

    public static func auth(_ message: String, requestID: String? = nil) -> AstraError {
        AstraError(category: .auth, message: message, requestID: requestID)
    }

    public static func validation(_ message: String, requestID: String? = nil) -> AstraError {
        AstraError(category: .validation, message: message, requestID: requestID)
    }

    public static func server(_ message: String, statusCode: Int? = nil, requestID: String? = nil) -> AstraError {
        AstraError(category: .server, message: message, underlyingStatusCode: statusCode, requestID: requestID)
    }

    public static func provider(_ message: String, requestID: String? = nil) -> AstraError {
        AstraError(category: .provider, message: message, requestID: requestID)
    }

    public static func rateLimited(_ message: String = "Too many requests. Please try again shortly.", requestID: String? = nil) -> AstraError {
        AstraError(category: .rateLimited, message: message, requestID: requestID)
    }

    public static let cancelled = AstraError(category: .cancelled, message: "Request cancelled.")

    /// A feature whose backing schema/endpoint does not exist yet.
    ///
    /// `message` is user-facing like every other case, so it says what the user
    /// can expect rather than naming a missing table. The developer-facing
    /// detail belongs in a comment at the throw site.
    public static func unimplemented(_ message: String) -> AstraError {
        AstraError(category: .unimplemented, message: message)
    }
}
