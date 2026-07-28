//
//  ClosetItemAnalysisResult.swift
//  AstraStyle
//
//  The output of the server-side scan analysis pipeline (spec §12
//  "Server-side": classify category/subtype, detect material/pattern,
//  infer brand from OCR, estimate condition, produce embedding).
//
//  Every suggested field carries a confidence score so the review screen
//  (spec §6.16) can visibly mark low-confidence fields while still leaving
//  every field editable (spec §12 "User verification").
//

import Foundation

public struct ClosetItemAnalysisResult: Codable, Hashable, Sendable {
    public var suggestedName: FieldSuggestion<String>?
    public var suggestedBrand: FieldSuggestion<String>?
    public var suggestedCategory: FieldSuggestion<ClothingCategory>
    public var suggestedSubcategory: FieldSuggestion<String>?
    public var suggestedPrimaryColor: FieldSuggestion<String>?
    public var suggestedSecondaryColors: [String]
    public var suggestedPattern: FieldSuggestion<GarmentPattern>?
    public var suggestedMaterial: [String]
    public var suggestedCondition: FieldSuggestion<ItemCondition>?
    public var normalizedImagePath: String?
    public var ocrText: String?

    public init(
        suggestedName: FieldSuggestion<String>? = nil,
        suggestedBrand: FieldSuggestion<String>? = nil,
        suggestedCategory: FieldSuggestion<ClothingCategory>,
        suggestedSubcategory: FieldSuggestion<String>? = nil,
        suggestedPrimaryColor: FieldSuggestion<String>? = nil,
        suggestedSecondaryColors: [String] = [],
        suggestedPattern: FieldSuggestion<GarmentPattern>? = nil,
        suggestedMaterial: [String] = [],
        suggestedCondition: FieldSuggestion<ItemCondition>? = nil,
        normalizedImagePath: String? = nil,
        ocrText: String? = nil
    ) {
        self.suggestedName = suggestedName
        self.suggestedBrand = suggestedBrand
        self.suggestedCategory = suggestedCategory
        self.suggestedSubcategory = suggestedSubcategory
        self.suggestedPrimaryColor = suggestedPrimaryColor
        self.suggestedSecondaryColors = suggestedSecondaryColors
        self.suggestedPattern = suggestedPattern
        self.suggestedMaterial = suggestedMaterial
        self.suggestedCondition = suggestedCondition
        self.normalizedImagePath = normalizedImagePath
        self.ocrText = ocrText
    }

    enum CodingKeys: String, CodingKey {
        case suggestedName = "suggested_name"
        case suggestedBrand = "suggested_brand"
        case suggestedCategory = "suggested_category"
        case suggestedSubcategory = "suggested_subcategory"
        case suggestedPrimaryColor = "suggested_primary_color"
        case suggestedSecondaryColors = "suggested_secondary_colors"
        case suggestedPattern = "suggested_pattern"
        case suggestedMaterial = "suggested_material"
        case suggestedCondition = "suggested_condition"
        case normalizedImagePath = "normalized_image_path"
        case ocrText = "ocr_text"
    }
}

/// A single suggested field value plus a 0–1 confidence score.
public struct FieldSuggestion<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var value: Value
    public var confidence: Double

    public init(value: Value, confidence: Double) {
        self.value = value
        self.confidence = confidence
    }

    /// Below this threshold the review UI must visibly flag the field
    /// (spec §12 "Low-confidence fields should be visibly marked").
    public static var lowConfidenceThreshold: Double { 0.6 }

    public var isLowConfidence: Bool { confidence < Self.lowConfidenceThreshold }
}
