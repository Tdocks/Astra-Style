//
//  AstraRequestEnvelope.swift
//  AstraStyle
//
//  Request/response envelope shapes shared by every Edge Function call.
//

import Foundation

/// Wraps every outgoing request body with the fields the Edge Function
/// layer needs for observability (spec §14 "Log request ID and latency")
/// without polluting each individual endpoint's payload type.
public struct AstraRequestEnvelope<Body: Encodable & Sendable>: Encodable, Sendable {
    public let requestID: String
    public let clientVersion: String
    public let body: Body

    public init(requestID: String, clientVersion: String, body: Body) {
        self.requestID = requestID
        self.clientVersion = clientVersion
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case clientVersion = "client_version"
        case body
    }
}

/// Wraps every incoming response body. `error` is populated instead of
/// `data` on failure; the client never needs to guess which one is present
/// from HTTP status alone.
public struct AstraResponseEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    public let data: Payload?
    public let error: AstraServerErrorPayload?
    public let requestID: String?

    enum CodingKeys: String, CodingKey {
        case data
        case error
        case requestID = "request_id"
    }
}

/// The server-side error shape returned in `AstraResponseEnvelope.error`.
public struct AstraServerErrorPayload: Decodable, Sendable {
    public let category: String
    public let message: String

    public func asAstraError(statusCode: Int?, requestID: String?) -> AstraError {
        let mappedCategory: AstraError.Category
        switch category {
        case "network": mappedCategory = .network
        case "auth": mappedCategory = .auth
        case "validation": mappedCategory = .validation
        case "provider": mappedCategory = .provider
        case "rate_limited": mappedCategory = .rateLimited
        default: mappedCategory = .server
        }
        return AstraError(category: mappedCategory, message: message, underlyingStatusCode: statusCode, requestID: requestID)
    }
}

/// An empty, `Encodable`/`Decodable` payload for endpoints that take or
/// return no body (e.g. `GET /studio/status/:id` takes none;
/// `DELETE /account` returns none).
public struct AstraEmptyPayload: Codable, Sendable {
    public init() {}
}
