//
//  CostPerWearCalculatorTests.swift
//  AstraStyleTests
//
//  Spec §22 "Unit tests: Cost-per-wear calculation".
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("CostPerWearCalculator")
struct CostPerWearCalculatorTests {

    @Test("Divides price by wear count")
    func basicDivision() {
        let result = CostPerWearCalculator.costPerWear(pricePaid: 100, wearCount: 4)
        #expect(result == 25)
    }

    @Test("Returns nil when never worn, rather than treating it as free or infinite")
    func neverWornReturnsNil() {
        let result = CostPerWearCalculator.costPerWear(pricePaid: 100, wearCount: 0)
        #expect(result == nil)
    }

    @Test("Returns nil when there's no purchase price on file")
    func noPriceReturnsNil() {
        let result = CostPerWearCalculator.costPerWear(pricePaid: nil, wearCount: 10)
        #expect(result == nil)
    }

    @Test("Rejects a negative price rather than returning a negative cost-per-wear")
    func negativePriceReturnsNil() {
        let result = CostPerWearCalculator.costPerWear(pricePaid: -50, wearCount: 5)
        #expect(result == nil)
    }

    @Test("Rounds to the currency's minor unit")
    func roundsToTwoDecimalPlaces() {
        let result = CostPerWearCalculator.costPerWear(pricePaid: 100, wearCount: 3)
        #expect(result == Decimal(string: "33.33"))
    }

    @Test("Average cost per wear is total spend over total wears, not the mean of each item's own cost-per-wear")
    func averageIsSpendOverWearsNotMeanOfMeans() {
        // Item A: $300, never worn (would be `nil` individually).
        // Item B: $30, worn 10 times ($3/wear individually).
        // A naive mean-of-means would drop item A entirely and report $3.
        // The correct aggregate blends the unworn item's cost in: $330 / 10 = $33.
        let items: [(pricePaid: Decimal?, wearCount: Int)] = [
            (300, 0),
            (30, 10),
        ]
        let result = CostPerWearCalculator.averageCostPerWear(items: items)
        #expect(result == 33)
    }

    @Test("Average cost per wear is nil when nothing has been worn")
    func averageIsNilWithNoWears() {
        let items: [(pricePaid: Decimal?, wearCount: Int)] = [(100, 0), (50, 0)]
        #expect(CostPerWearCalculator.averageCostPerWear(items: items) == nil)
    }

    @Test("Expected cost per wear projects a candidate purchase forward")
    func expectedCostPerWearProjection() {
        let result = CostPerWearCalculator.expectedCostPerWear(price: 200, projectedWears: 8)
        #expect(result == 25)
    }

    @Test("Expected cost per wear rejects zero projected wears")
    func expectedCostPerWearZeroWears() {
        #expect(CostPerWearCalculator.expectedCostPerWear(price: 200, projectedWears: 0) == nil)
    }
}
