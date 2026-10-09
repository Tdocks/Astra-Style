import Foundation
import Testing
@testable import AstraStyle

@Suite("Personal data export document")
struct PersonalDataExportTests {
    @Test("Decodes nested user rows and round-trips them as JSON")
    func decodesAndEncodesTableRows() throws {
        let json = Data(
            """
            {
              "schema_version": 1,
              "exported_at": "2026-09-29T14:00:00.000Z",
              "owner_user_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
              "table_counts": { "closet_items": 1 },
              "tables": {
                "closet_items": [{
                  "name": "Oxford shirt",
                  "is_favorite": true,
                  "wear_count": 3,
                  "price_paid": 89.5,
                  "details": null,
                  "colors": ["blue", "white"]
                }]
              }
            }
            """.utf8
        )
        let export = try JSONDecoder().decode(PersonalDataExport.self, from: json)
        let row = try #require(export.tables["closet_items"]?.first)

        #expect(export.tableCounts["closet_items"] == 1)
        #expect(row["name"] == .string("Oxford shirt"))
        #expect(row["is_favorite"] == .boolean(true))
        #expect(row["wear_count"] == .integer(3))
        #expect(row["price_paid"] == .number(89.5))
        #expect(row["details"] == .null)
        #expect(row["colors"] == .array([.string("blue"), .string("white")]))

        let encoded = try JSONEncoder().encode(export)
        let roundTrip = try JSONDecoder().decode(PersonalDataExport.self, from: encoded)
        #expect(roundTrip == export)
    }

    @Test("Preserves optional Storage references when sharing an export")
    func preservesStorageManifestOnRoundTrip() throws {
        let json = Data(
            """
            {
              "schema_version": 1,
              "exported_at": "2026-10-08T14:00:00.000Z",
              "owner_user_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
              "table_counts": { "profiles": 1 },
              "tables": { "profiles": [] },
              "referenced_storage_objects": [
                { "bucket": "user-content", "path": "users/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/avatars/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg" }
              ],
              "storage_manifest_scope": "Referenced paths only; no image files included."
            }
            """.utf8
        )

        let export = try JSONDecoder().decode(PersonalDataExport.self, from: json)
        #expect(export.referencedStorageObjects == [
            PersonalDataExportStorageReference(
                bucket: "user-content",
                path: "users/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/avatars/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg"
            ),
        ])
        #expect(export.storageManifestScope == "Referenced paths only; no image files included.")

        let encoded = try JSONEncoder().encode(export)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["referenced_storage_objects"] != nil)
        #expect(object["storage_manifest_scope"] as? String == "Referenced paths only; no image files included.")
    }

    @Test("The preview repository produces a shareable local file")
    @MainActor
    func mockExportIsAFile() async throws {
        let url = try await MockProfileRepository().exportPersonalData()
        #expect(url.isFileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
