//
//  JSONValue.swift
//  AstraStyle
//
//  A generic, order-preserving JSON value used for the handful of `jsonb`
//  columns (spec §9) whose shape is intentionally open-ended on the server
//  (e.g. `analysis_metadata`, `prompt_payload`, `availability`,
//  `attributes`, `model_metadata`). Columns whose shape is predictable are
//  typed concretely instead (see WeatherSnapshot, ScheduleSnapshot) —
//  `AstraJSONValue` is reserved for truly free-form payloads so we are not
//  forced to guess a schema the backend hasn't committed to yet.
//

import Foundation

/// Losslessly round-trips arbitrary JSON through `Codable`.
// Hashable, not just Equatable: `KyraMessage` holds an optional
// `AstraJSONValue` (modelMetadata) and declares Hashable conformance, which
// every stored property must support. Every associated value here is already
// Hashable — String, Double, Bool, and Array/Dictionary of Hashable elements —
// so the compiler synthesises it; nothing needs to be written by hand.
public indirect enum AstraJSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AstraJSONValue])
    case object([String: AstraJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AstraJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AstraJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
