//
//  ProductDecisionCopy.swift
//  AstraStyle
//
//  Share only a skip/wait verdict. Buy and consider must not hand the
//  system share sheet a shopping CTA.
//

import Foundation

public enum ProductDecisionCopy {
    /// Nil for buy/consider — those verdicts already have a retailer
    /// button for the URL he pasted. Skip and wait share the refusal.
    public static func shareText(verdict: KyraVerdict, garmentName: String?) -> String? {
        let name = garmentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch verdict {
        case .skip:
            return named("Astra said skip", garment: name)
        case .waitForSale:
            return named("Astra said wait", garment: name)
        case .buy, .consider:
            return nil
        }
    }

    private static func named(_ verdict: String, garment: String) -> String {
        garment.isEmpty ? verdict : "\(verdict): \(garment)"
    }
}
