import Foundation
import Testing
@testable import AstraStyle

@Suite("ScannerReviewSaveIdentity")
struct ScannerReviewSaveIdentityTests {
    @Test("A capture keeps the same owner-scoped save IDs after relaunch")
    func saveIdentitySurvivesViewModelRecreation() {
        let draftID = UUID()
        let ownerID = UUID()
        let first = scannerSaveIdentity(owner: ownerID, draftID: draftID)
        let relaunched = scannerSaveIdentity(owner: ownerID, draftID: draftID)
        let peer = scannerSaveIdentity(owner: UUID(), draftID: draftID)

        #expect(first.item == relaunched.item)
        #expect(first.image == relaunched.image)
        #expect(first.item != peer.item)
    }

}
