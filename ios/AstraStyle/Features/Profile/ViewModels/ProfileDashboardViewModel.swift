//
//  ProfileDashboardViewModel.swift
//  AstraStyle
//
//  Builds Profile totals and a small Style Journey from the user's saved
//  closet and outfit records. Money stays grouped by currency.
//

import Foundation
import Observation

struct ProfileMonthlySpend: Hashable, Sendable, Identifiable {
    let currencyCode: String
    let amount: Decimal
    let purchaseCount: Int

    var id: String { currencyCode }
}

struct ProfileWornColor: Hashable, Sendable, Identifiable {
    let color: String
    let wears: Int

    var id: String { color }
}

struct ProfileJourneyEvent: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case itemAdded
        case itemWorn
        case outfitSaved
    }

    let id: String
    let date: Date
    let title: String
    let subtitle: String
    let kind: Kind
}

struct ProfileDashboardData: Sendable {
    let closetMetrics: ClosetMetrics
    let outfitCount: Int
    let monthlySpend: [ProfileMonthlySpend]
    let wornColors: [ProfileWornColor]
    let journey: [ProfileJourneyEvent]
}

@MainActor
@Observable
final class ProfileDashboardViewModel {
    enum Phase: Sendable {
        case loading
        case ready(ProfileDashboardData)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private let closetRepository: ClosetRepository
    private let outfitRepository: OutfitRepository

    init(closetRepository: ClosetRepository, outfitRepository: OutfitRepository) {
        self.closetRepository = closetRepository
        self.outfitRepository = outfitRepository
    }

    func load() async {
        do {
            async let closetTask = closetRepository.fetchItems()
            async let outfitsTask = outfitRepository.fetchOutfits()
            let (items, outfits) = try await (closetTask, outfitsTask)
            phase = .ready(Self.makeData(items: items, outfits: outfits, now: .now))
        } catch let error as AstraError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(String(localized: "Your profile details didn't load. Check your connection and try again.", comment: "Profile dashboard error"))
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    private static func makeData(items: [ClosetItem], outfits: [Outfit], now: Date) -> ProfileDashboardData {
        let activeItems = items.filter { !$0.isArchived }
        let activeOutfits = outfits.filter { !$0.isArchived }
        let month = Calendar.current.dateInterval(of: .month, for: now)
        return ProfileDashboardData(
            closetMetrics: ClosetMetrics.compute(for: activeItems),
            outfitCount: activeOutfits.count,
            monthlySpend: monthlySpend(from: items, during: month),
            wornColors: mostWornColors(in: activeItems),
            journey: recentJourney(items: activeItems, outfits: activeOutfits)
        )
    }

    private static func monthlySpend(
        from items: [ClosetItem],
        during month: DateInterval?
    ) -> [ProfileMonthlySpend] {
        guard let month else { return [] }
        var spendByCurrency: [String: (amount: Decimal, count: Int)] = [:]
        // Spending is historical and remains real after closet archiving.
        for item in items {
            guard let date = item.purchaseDate,
                  month.contains(date),
                  let price = item.pricePaid,
                  price >= 0 else { continue }
            let code = CurrencyFormatting.normalizedCurrencyCode(item.currency)
            let current = spendByCurrency[code] ?? (0, 0)
            spendByCurrency[code] = (current.amount + price, current.count + 1)
        }
        return spendByCurrency.map { code, value in
            ProfileMonthlySpend(currencyCode: code, amount: value.amount, purchaseCount: value.count)
        }.sorted {
            if $0.amount != $1.amount { return $0.amount > $1.amount }
            return $0.currencyCode < $1.currencyCode
        }
    }

    private static func mostWornColors(in items: [ClosetItem]) -> [ProfileWornColor] {
        var wearsByColor: [String: (label: String, wears: Int)] = [:]
        for item in items {
            guard let rawColor = item.primaryColor?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawColor.isEmpty,
                  item.wearCount > 0 else { continue }
            let key = rawColor.lowercased()
            let current = wearsByColor[key] ?? (rawColor, 0)
            wearsByColor[key] = (current.label, current.wears + item.wearCount)
        }
        let wornColors = wearsByColor.values.map {
            ProfileWornColor(color: $0.label, wears: $0.wears)
        }.sorted {
            if $0.wears != $1.wears { return $0.wears > $1.wears }
            return $0.color.localizedStandardCompare($1.color) == .orderedAscending
        }.prefix(3)
        return Array(wornColors)
    }

    private static func recentJourney(
        items: [ClosetItem],
        outfits: [Outfit]
    ) -> [ProfileJourneyEvent] {
        var journey: [ProfileJourneyEvent] = []
        for item in items {
            journey.append(ProfileJourneyEvent(
                id: "added-\(item.id.uuidString)",
                date: item.createdAt,
                title: item.name,
                subtitle: String(localized: "Added to your closet", comment: "Style Journey item event"),
                kind: .itemAdded
            ))
            if let lastWornAt = item.lastWornAt {
                journey.append(ProfileJourneyEvent(
                    id: "worn-\(item.id.uuidString)",
                    date: lastWornAt,
                    title: item.name,
                    subtitle: String(localized: "Worn", comment: "Style Journey wear event"),
                    kind: .itemWorn
                ))
            }
        }
        for outfit in outfits {
            journey.append(ProfileJourneyEvent(
                id: "outfit-\(outfit.id.uuidString)",
                date: outfit.createdAt,
                title: outfit.name,
                subtitle: String(localized: "Outfit saved", comment: "Style Journey outfit event"),
                kind: .outfitSaved
            ))
        }

        return journey.sorted { $0.date > $1.date }.prefix(8).map { $0 }
    }
}
