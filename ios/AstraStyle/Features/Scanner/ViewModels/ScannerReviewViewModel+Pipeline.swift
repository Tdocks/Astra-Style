import CoreGraphics
import Foundation
import ImageIO

extension ScannerReviewViewModel {
    func upload(data: Data) async {
        phase = .uploading
        do {
            let path = try await closetRepository.uploadCapturedImage(data)
            storagePath = path
            var draft = draftStore.draft(id: draftID)
            draft?.storagePath = path
            if let draft { draftStore.update(draft) }

            // P3-SCAN-05: prove the path is readable via a user-scoped signed URL.
            if let url = try? await imageURLResolver.resolve(storagePath: path) {
                signedPreviewURL = url
                if var updated = draftStore.draft(id: draftID) {
                    updated.signedPreviewURL = url
                    draftStore.update(updated)
                }
            }
            phase = .analyzing
        } catch {
            let astra = (error as? AstraError) ?? AstraError.network(
                String(localized: "Couldn't upload that photo. Check your connection and try again.",
                       comment: "Scanner upload failure")
            )
            phase = .uploadFailed(astra)
        }
    }

    func analyze(imageData: Data) async {
        do {
            var request = ClosetItemAnalysisRequest(
                id: draftID,
                imageData: imageData,
                storagePath: storagePath,
                imageType: .front,
                deviceHints: deviceHints(from: imageData)
            )
            // Prefer empty imageData on the wire path once uploaded — the
            // repository skips upload when storagePath is set; keep bytes
            // locally for preview only.
            if storagePath != nil {
                request.imageData = Data()
            }
            let result = try await closetRepository.analyzeItem(request)
            applyAnalysis(result)
            if var draft = draftStore.draft(id: draftID) {
                draft.analysis = result
                draftStore.update(draft)
            }
            phase = .ready
        } catch {
            let astra = (error as? AstraError) ?? AstraError.provider(
                String(localized: "Kyra couldn't read that photo. Try again.",
                       comment: "Scanner analyze failure")
            )
            phase = .analyzeFailed(astra)
        }
    }

    func applyAnalysis(_ result: ClosetItemAnalysisResult) {
        analysis = result
        originalSuggestions = result
        ocrText = result.ocrText
        name = result.name?.value ?? ""
        brand = result.brand?.value ?? ""
        category = result.category?.value ?? .top
        subcategory = result.subcategory?.value ?? ""
        primaryColor = result.primaryColor?.value ?? ""
        secondaryColorsText = result.secondaryColors.map(\.value).joined(separator: ", ")
        pattern = result.pattern?.value
        materialText = result.material.map(\.value).joined(separator: ", ")
        size = result.size?.value ?? ""
        fit = result.fit?.value
        condition = result.condition?.value
        seasonality = Set(result.seasonality.map(\.value))
        formalityScoreText = result.formalityScore.map { String($0.value) } ?? ""
        warmthScoreText = result.warmthScore.map { String($0.value) } ?? ""
        waterResistanceScoreText = result.waterResistanceScore.map { String($0.value) } ?? ""
    }

    func buildItem(id: UUID, userID: UUID) -> ClosetItem {
        ClosetItem(
            id: id,
            userID: userID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: trimmedOrNil(brand),
            category: category,
            subcategory: trimmedOrNil(subcategory),
            primaryColor: trimmedOrNil(primaryColor),
            secondaryColors: splitList(secondaryColorsText),
            pattern: pattern,
            material: splitList(materialText),
            size: trimmedOrNil(size),
            fit: fit,
            condition: condition,
            seasonality: Array(seasonality).sorted { $0.rawValue < $1.rawValue },
            formalityScore: Int(formalityScoreText),
            warmthScore: Int(warmthScoreText),
            waterResistanceScore: Int(waterResistanceScoreText)
        )
    }

    func fieldsCorrectedCount() -> Int {
        guard let original = originalSuggestions else { return 0 }
        let checks: [Bool] = [
            name != (original.name?.value ?? ""),
            brand != (original.brand?.value ?? ""),
            category != (original.category?.value ?? .top),
            subcategory != (original.subcategory?.value ?? ""),
            primaryColor != (original.primaryColor?.value ?? ""),
            splitList(secondaryColorsText) != original.secondaryColors.map(\.value),
            pattern != original.pattern?.value,
            splitList(materialText) != original.material.map(\.value),
            size != (original.size?.value ?? ""),
            fit != original.fit?.value,
            condition != original.condition?.value,
            Set(seasonality) != Set(original.seasonality.map(\.value))
        ]
        return checks.filter(\.self).count
    }

    func deviceHints(from data: Data) -> GarmentDeviceHints? {
        // Dominant colour only until OCR (P3-SCAN-03) lands. Empty text is
        // honest — do not invent brand/size on device.
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return GarmentDeviceHints(dominantColorsRGB: [], detectedText: [])
        }
        let hexes = DominantColorExtraction.extract(from: image).prefix(3).map(\.hexRGB)
        return GarmentDeviceHints(dominantColorsRGB: Array(hexes), detectedText: [])
    }

    func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func splitList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
