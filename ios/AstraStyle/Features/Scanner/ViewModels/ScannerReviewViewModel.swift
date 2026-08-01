//
//  ScannerReviewViewModel.swift
//  AstraStyle
//
//  Upload → analyze → editable review → save (P3-SCAN-05 / P3-SCAN-09).
//  Seeds fields from `ClosetItemAnalysisResult`, marks low-confidence via
//  `isLowConfidence(_:)`, and persists the user's corrections through
//  `createItem` — never the raw suggestions alone.
//

import CoreGraphics
import Foundation
import ImageIO
import Observation

@MainActor
@Observable
public final class ScannerReviewViewModel {

    public enum Phase: Equatable {
        case loading
        case uploading
        case analyzing
        case ready
        case saving
        case saved
        case uploadFailed(AstraError)
        case analyzeFailed(AstraError)
        case saveFailed(AstraError)
        case missingDraft

        public static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.uploading, .uploading), (.analyzing, .analyzing),
                 (.ready, .ready), (.saving, .saving), (.saved, .saved), (.missingDraft, .missingDraft):
                true
            case (.uploadFailed(let a), .uploadFailed(let b)),
                 (.analyzeFailed(let a), .analyzeFailed(let b)),
                 (.saveFailed(let a), .saveFailed(let b)):
                a == b
            default:
                false
            }
        }
    }

    public private(set) var phase: Phase = .loading
    public private(set) var draftID: UUID
    public private(set) var localPreviewData: Data?
    public private(set) var signedPreviewURL: URL?
    public private(set) var storagePath: String?
    public private(set) var analysis: ClosetItemAnalysisResult?
    public private(set) var ocrText: String?

    // Editable fields
    public var name: String = ""
    public var brand: String = ""
    public var category: ClothingCategory = .top
    public var subcategory: String = ""
    public var primaryColor: String = ""
    public var secondaryColorsText: String = ""
    public var pattern: GarmentPattern?
    public var materialText: String = ""
    public var size: String = ""
    public var fit: ItemFit?
    public var condition: ItemCondition?
    public var seasonality: Set<Season> = []
    public var formalityScoreText: String = ""
    public var warmthScoreText: String = ""
    public var waterResistanceScoreText: String = ""

    public var canSave: Bool {
        guard case .ready = phase else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var saveBlockedReason: String? {
        guard case .ready = phase else { return nil }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Add a name before saving.", comment: "Scanner review save blocked")
        }
        return nil
    }

    private let draftStore: CaptureDraftStore
    private let closetRepository: ClosetRepository
    private let imageURLResolver: ClosetImageURLResolving
    private let analyticsClient: AnalyticsClient
    private let currentUserID: () async -> UUID?
    private var originalSuggestions: ClosetItemAnalysisResult?

    public init(
        draftID: UUID,
        draftStore: CaptureDraftStore,
        closetRepository: ClosetRepository,
        imageURLResolver: ClosetImageURLResolving,
        analyticsClient: AnalyticsClient = NoOpAnalyticsClient(),
        currentUserID: @escaping () async -> UUID?
    ) {
        self.draftID = draftID
        self.draftStore = draftStore
        self.closetRepository = closetRepository
        self.imageURLResolver = imageURLResolver
        self.analyticsClient = analyticsClient
        self.currentUserID = currentUserID
    }

    // MARK: - Pipeline

    public func start() async {
        guard let draft = draftStore.draft(id: draftID) else {
            phase = .missingDraft
            return
        }
        localPreviewData = draft.prepared.data
        storagePath = draft.storagePath
        signedPreviewURL = draft.signedPreviewURL
        if let analysis = draft.analysis {
            applyAnalysis(analysis)
            phase = .ready
            return
        }

        if storagePath == nil {
            await upload(data: draft.prepared.data)
            guard case .analyzing = phase else { return }
        } else {
            phase = .analyzing
        }
        await analyze(imageData: draft.prepared.data)
    }

    public func retryUpload() async {
        guard let data = localPreviewData else { return }
        await upload(data: data)
        guard case .analyzing = phase else { return }
        await analyze(imageData: data)
    }

    public func retryAnalyze() async {
        guard let data = localPreviewData else { return }
        phase = .analyzing
        await analyze(imageData: data)
    }

    public func save() async {
        guard canSave else { return }
        guard let storagePath else {
            phase = .saveFailed(AstraError.validation(
                String(localized: "The photo is not uploaded yet. Try again.",
                       comment: "Scanner save without storage path")
            ))
            return
        }
        guard let userID = await currentUserID() else {
            phase = .saveFailed(AstraError.auth(
                String(localized: "Sign in to save this piece to your closet.",
                       comment: "Scanner save without session")
            ))
            return
        }

        phase = .saving
        let itemID = UUID()
        let item = buildItem(id: itemID, userID: userID)
        let image = ClosetItemImage(
            id: UUID(),
            closetItemID: itemID,
            imageType: .front,
            storagePath: storagePath,
            backgroundRemovedPath: analysis?.normalizedImagePath,
            isPrimary: true
        )

        do {
            _ = try await closetRepository.createItem(item, images: [image])
            let corrected = fieldsCorrectedCount()
            analyticsClient.log(.closetItemAdded(category: item.category, source: .scan))
            if corrected > 0 {
                analyticsClient.log(.scanCorrected(fieldsCorrectedCount: corrected))
            }
            draftStore.remove(id: draftID)
            AstraHaptics.success()
            phase = .saved
        } catch {
            let astra = (error as? AstraError) ?? AstraError.server(
                String(localized: "Couldn't save that piece. Try again.",
                       comment: "Scanner save failure")
            )
            phase = .saveFailed(astra)
        }
    }

    public func isLowConfidence(_ field: AnalysisField) -> Bool {
        analysis?.isLowConfidence(field) ?? false
    }

    public func lowConfidenceFootnote(_ field: AnalysisField) -> String? {
        guard isLowConfidence(field) else { return nil }
        return String(localized: "Kyra isn’t sure — check this.",
                      comment: "Low-confidence field footnote on scan review")
    }

    // MARK: - Private pipeline

    private func upload(data: Data) async {
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

    private func analyze(imageData: Data) async {
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

    private func applyAnalysis(_ result: ClosetItemAnalysisResult) {
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

    private func buildItem(id: UUID, userID: UUID) -> ClosetItem {
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

    private func fieldsCorrectedCount() -> Int {
        guard let original = originalSuggestions else { return 0 }
        var count = 0
        if name != (original.name?.value ?? "") { count += 1 }
        if brand != (original.brand?.value ?? "") { count += 1 }
        if category != (original.category?.value ?? .top) { count += 1 }
        if subcategory != (original.subcategory?.value ?? "") { count += 1 }
        if primaryColor != (original.primaryColor?.value ?? "") { count += 1 }
        if splitList(secondaryColorsText) != original.secondaryColors.map(\.value) { count += 1 }
        if pattern != original.pattern?.value { count += 1 }
        if splitList(materialText) != original.material.map(\.value) { count += 1 }
        if size != (original.size?.value ?? "") { count += 1 }
        if fit != original.fit?.value { count += 1 }
        if condition != original.condition?.value { count += 1 }
        if Set(seasonality) != Set(original.seasonality.map(\.value)) { count += 1 }
        return count
    }

    private func deviceHints(from data: Data) -> GarmentDeviceHints? {
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

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func splitList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
