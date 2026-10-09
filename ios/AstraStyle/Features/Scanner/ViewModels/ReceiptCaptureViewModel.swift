import Foundation
import ImageIO
import Observation

@MainActor
@Observable
final class ReceiptCaptureViewModel {
    private(set) var isRecognizing = false
    private(set) var suggestions: ReceiptSuggestions?
    private(set) var error: String?
    private(set) var savedItem: ClosetItem?
    private(set) var form: ClosetItemFormViewModel?
    private let recognizer: any LabelTextRecognizing
    private let repository: any ClosetRepository
    private let currentUserID: @Sendable () async -> UUID?

    init(recognizer: any LabelTextRecognizing, repository: any ClosetRepository, currentUserID: @escaping @Sendable () async -> UUID?) {
        self.recognizer = recognizer
        self.repository = repository
        self.currentUserID = currentUserID
    }

    func recognize(_ data: Data) async {
        guard !isRecognizing else { return }
        isRecognizing = true
        error = nil
        suggestions = nil
        form = nil
        savedItem = nil
        defer { isRecognizing = false }
        let recognizer = recognizer
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2048
                      ] as CFDictionary) else {
                    throw AstraError.validation("That photo couldn't be read. Choose another image.")
                }
                return ReceiptSuggestions.parse(try recognizer.recognizeText(in: image))
            }.value
            suggestions = result
            let model = ClosetItemFormViewModel.adding(closetRepository: repository, currentUserID: currentUserID)
            model.retailer = result.retailer ?? ""
            model.pricePaid = result.total
            model.purchaseDate = result.date
            if let currency = result.currency { model.currency = currency }
            model.showsMoreDetails = true
            model.onSaved = { [weak self] item in self?.savedItem = item }
            form = model
            if result.text.isEmpty { error = "No readable text found. Try a clearer photo or fill in the item below." }
        } catch {
            self.error = (error as? AstraError)?.message ?? "Couldn't read that photo. Try again."
        }
    }
}
