//
//  CostPerWearCalculator.swift
//  AstraStyle
//
//  Pure, side-effect-free cost-per-wear math (spec §6.15 "Cost per wear",
//  §22 "Unit tests: Cost-per-wear calculation"). Kept as free functions on
//  a caseless enum namespace rather than an instance so it never needs
//  dependency injection to be unit tested.
//

import Foundation

public enum CostPerWearCalculator {
    /// `pricePaid / wearCount`, rounded to the currency's minor unit.
    /// Returns `nil` when there isn't enough information to compute a
    /// meaningful value: no purchase price on file, or the item has never
    /// been worn (division by zero is not "infinite value", it's
    /// "unknown" — spec explicitly separates "not yet worn" from "free").
    public static func costPerWear(pricePaid: Decimal?, wearCount: Int) -> Decimal? {
        guard let pricePaid, pricePaid >= 0, wearCount > 0 else { return nil }
        return (pricePaid / Decimal(wearCount)).rounded(to: 2)
    }

    /// Aggregate cost-per-wear across a whole closet (spec §6.14 "Average
    /// cost per wear"): total spend divided by total wears, not the mean
    /// of each item's individual cost-per-wear — the latter would let a
    /// single never-worn expensive item silently disappear from the
    /// average instead of dragging it up.
    public static func averageCostPerWear(items: [(pricePaid: Decimal?, wearCount: Int)]) -> Decimal? {
        let totalSpend = items.reduce(Decimal.zero) { $0 + ($1.pricePaid ?? 0) }
        let totalWears = items.reduce(0) { $0 + $1.wearCount }
        guard totalWears > 0 else { return nil }
        return (totalSpend / Decimal(totalWears)).rounded(to: 2)
    }

    /// Projects what cost-per-wear a candidate purchase would settle at
    /// after a given number of future wears — used by the Product
    /// Decision Page's "Expected cost per wear" score (spec §6.19).
    public static func expectedCostPerWear(price: Decimal, projectedWears: Int) -> Decimal? {
        guard projectedWears > 0, price >= 0 else { return nil }
        return (price / Decimal(projectedWears)).rounded(to: 2)
    }
}

extension Decimal {
    fileprivate func rounded(to scale: Int) -> Decimal {
        var result = Decimal()
        var mutableSelf = self
        NSDecimalRound(&result, &mutableSelf, scale, .plain)
        return result
    }
}
