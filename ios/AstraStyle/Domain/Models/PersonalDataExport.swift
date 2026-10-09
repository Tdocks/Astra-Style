//
//  PersonalDataExport.swift
//  AstraStyle
//
//  Versioned JSON document returned by GET /profile/export-data.
//

import Foundation

public struct PersonalDataExport: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let exportedAt: String
    public let ownerUserID: String
    public let tableCounts: [String: Int]
    public let tables: [String: [PersonalDataJSONValue]]
    public let referencedStorageObjects: [PersonalDataExportStorageReference]?
    public let storageManifestScope: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case ownerUserID = "owner_user_id"
        case tableCounts = "table_counts"
        case tables
        case referencedStorageObjects = "referenced_storage_objects"
        case storageManifestScope = "storage_manifest_scope"
    }
}

public struct PersonalDataExportStorageReference: Codable, Sendable, Equatable {
    public let bucket: String
    public let path: String
}

public indirect enum PersonalDataJSONValue: Codable, Sendable, Equatable {
    case object([String: PersonalDataJSONValue])
    case array([PersonalDataJSONValue])
    case string(String)
    case integer(Int64)
    case number(Double)
    case boolean(Bool)
    case null

    public subscript(key: String) -> PersonalDataJSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let boolean = try? value.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let integer = try? value.decode(Int64.self) {
            self = .integer(integer)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let array = try? value.decode([PersonalDataJSONValue].self) {
            self = .array(array)
        } else if let object = try? value.decode([String: PersonalDataJSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: value,
                debugDescription: "The export contains a value that is not valid JSON."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object):
            try value.encode(object)
        case .array(let array):
            try value.encode(array)
        case .string(let string):
            try value.encode(string)
        case .integer(let integer):
            try value.encode(integer)
        case .number(let number):
            try value.encode(number)
        case .boolean(let boolean):
            try value.encode(boolean)
        case .null:
            try value.encodeNil()
        }
    }
}
