import Foundation
import Testing
import UIKit
@testable import AstraStyle

@MainActor
@Suite("Receipt capture workflow")
struct ReceiptCaptureViewModelTests {
    private func imageData() throws -> Data {
        let image = try #require(ScannerImageFixtures.solid(width: 32, height: 32, red: 200, green: 200, blue: 200))
        return try #require(ScannerImageFixtures.jpegData(from: image, includeMetadata: false))
    }

    @Test("Live Vision OCR reads a synthetic receipt into editable fields")
    func liveVisionSyntheticReceipt() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600))
        let data = renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.black]
            for (index, line) in ["EXAMPLE SHOP", "2026-10-08", "Total USD 50.00"].enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 60 + index * 100), withAttributes: attributes)
            }
        }
        let model = ReceiptCaptureViewModel(recognizer: LiveVisionLabelTextRecognizer(), repository: MockClosetRepository(), currentUserID: { SampleData.userID })
        await model.recognize(data)
        let form = try #require(model.form)
        #expect(form.pricePaid == Decimal(50))
        #expect(form.currency == "USD")
        #expect(form.purchaseDate != nil)
        #expect(model.suggestions?.text.contains("EXAMPLE") == true)
    }

    @Test("Edited purchase suggestions persist through the existing item form")
    func editedMetadataSaved() async throws {
        let repository = MockClosetRepository()
        let model = ReceiptCaptureViewModel(
            recognizer: MockLabelTextRecognizer(lines: ["Example Shop", "Total USD 50.00", "2026-10-08"]),
            repository: repository,
            currentUserID: { SampleData.userID }
        )
        await model.recognize(try imageData())
        let form = try #require(model.form)
        #expect(form.pricePaid == Decimal(50))
        #expect(form.retailer == "Example Shop")
        #expect(form.purchaseDate != nil)
        form.name = "Receipt shirt"
        form.category = .top
        form.pricePaid = Decimal(25)
        form.retailer = "Corrected merchant"
        await form.submit()
        let saved = try #require(model.savedItem)
        let fetched = try await repository.fetchItem(id: saved.id)
        #expect(fetched.pricePaid == Decimal(25))
        #expect(fetched.retailer == "Corrected merchant")
        #expect(fetched.currency == "USD")
        #expect(await repository.uploadedPaths.isEmpty)
    }

    @Test("An ambiguous dollar currency never inherits the device currency")
    func ambiguousCurrency() async throws {
        let model = ReceiptCaptureViewModel(recognizer: MockLabelTextRecognizer(lines: ["Example Shop", "Total $50.00"]), repository: MockClosetRepository(), currentUserID: { SampleData.userID })
        await model.recognize(try imageData())
        let form = try #require(model.form)
        #expect(form.pricePaid == Decimal(50))
        #expect(form.currency.isEmpty)
        form.currency = "CAD"
        #expect(form.currency == "CAD")
    }

    @Test("Unreadable text keeps the manual form available")
    func emptyTextCanBeEdited() async throws {
        let model = ReceiptCaptureViewModel(recognizer: MockLabelTextRecognizer(), repository: MockClosetRepository(), currentUserID: { SampleData.userID })
        await model.recognize(try imageData())
        #expect(model.form != nil)
        #expect(model.error?.contains("No readable text") == true)
        #expect(!model.isRecognizing)
    }

    @Test("Corrupt photo errors can recover on a later valid photo")
    func corruptPhotoRecovery() async throws {
        let model = ReceiptCaptureViewModel(recognizer: MockLabelTextRecognizer(lines: ["Example Shop"]), repository: MockClosetRepository(), currentUserID: { SampleData.userID })
        await model.recognize(Data([1, 2, 3]))
        #expect(model.form == nil)
        #expect(model.error != nil)
        await model.recognize(try imageData())
        #expect(model.form != nil)
        #expect(model.error == nil)
    }
}
