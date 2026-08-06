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

/// Supabase's own gateway error shape, which is **not**
/// `AstraResponseEnvelope`.
///
/// When a function slug has never been deployed the request never reaches
/// any Astra code, so nothing writes the envelope: the platform answers
/// on its own. Decoding that as `AstraResponseEnvelope` silently
/// *succeeds* — every field of the envelope is optional — leaving
/// `error == nil` and discarding the only sentence that said what went
/// wrong. This type exists so the gateway's message can be logged rather
/// than lost; see
/// `AstraAPIClient.notFoundError(endpoint:data:requestID:envelope:)`.
///
/// **Only `message` is declared, deliberately.** The bodies observed
/// against `anutsdzbxycaavmmkewo` on 2026-08-06 were
/// `{"code":"NOT_FOUND","message":"Requested function was not found"}` for
/// an undeployed slug and
/// `{"code":"UNAUTHORIZED_NO_AUTH_HEADER","message":"Missing authorization
/// header"}` with no bearer token — so `code` is a string there, while
/// Supabase's docs and older responses show an integer. Declaring it at
/// either type makes the whole decode fail on the other, throwing away the
/// message for the sake of a field nothing reads.
public struct AstraGatewayErrorPayload: Decodable, Sendable {
    public let message: String
}

/// An empty, `Encodable`/`Decodable` payload for endpoints that take or
/// return no body (e.g. `GET /studio/status/:id` takes none;
/// `DELETE /account` returns none).
public struct AstraEmptyPayload: Codable, Sendable {
    public init() {}
}
