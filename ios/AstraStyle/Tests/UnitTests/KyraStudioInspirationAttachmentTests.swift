import Foundation
import Testing
@testable import AstraStyle

@Suite("Kyra Studio inspiration attachment")
struct KyraStudioInspirationAttachmentTests {
    @Test("Request encodes a generation ID as the distinct studio_inspiration reference")
    func requestContract() throws {
        let generationID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")
        guard let generationID else {
            Issue.record("fixture generation id must be valid")
            return
        }
        let body = KyraRespondBody(
            threadID: nil,
            message: KyraOutgoingMessage(
                text: "Help me refine this generated look.",
                attachments: [.studioInspiration(generationID: generationID)]
            ),
            weatherSnapshot: nil,
            scheduleSnapshot: nil
        )

        let encoded = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: encoded)
        guard let bodyObject = object as? [String: Any],
              let attachments = bodyObject["attachments"] as? [[String: String]],
              let attachment = attachments.first
        else {
            Issue.record("encoded Kyra body should contain an attachment")
            return
        }
        #expect(attachment["type"] == "studio_inspiration")
        #expect(attachment["value"]?.lowercased() == generationID.uuidString.lowercased())
    }
}
