//
//  PackingTripView.swift
//  AstraStyle
//
//  Packing is the week-strip engine over a date range. Same scorer, no
//  second outfit brain. Wear This stays on Home.
//

import SwiftUI

struct PackingTripView: View {
    @State private var viewModel: PackingTripViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PackingTripViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.md) {
                    AstraTextField(
                        String(localized: "Where", comment: "Packing destination"),
                        text: $viewModel.destination,
                        placeholder: String(localized: "City or trip name", comment: "Packing destination placeholder")
                    )
                    .accessibilityIdentifier("packing.destination")

                    DatePicker(
                        String(localized: "Leaves", comment: "Packing start"),
                        selection: $viewModel.startDate,
                        displayedComponents: .date
                    )
                    .tint(AstraColor.accentChampagne)
                    DatePicker(
                        String(localized: "Back", comment: "Packing end"),
                        selection: $viewModel.endDate,
                        displayedComponents: .date
                    )
                    .tint(AstraColor.accentChampagne)

                    AstraTextField(
                        String(localized: "What's the trip for", comment: "Optional packing activities"),
                        text: $viewModel.tripFor,
                        placeholder: String(localized: "Dinner, board meeting…", comment: "Packing trip purpose placeholder")
                    )
                    .accessibilityIdentifier("packing.tripFor")

                    Toggle(
                        String(localized: "Laundry where you're going", comment: "Packing laundry access"),
                        isOn: $viewModel.hasLaundryAccess
                    )
                    .tint(AstraColor.accentChampagne)
                    .accessibilityIdentifier("packing.laundry")

                    Picker(
                        String(localized: "Bag", comment: "Luggage constraint"),
                        selection: $viewModel.luggage
                    ) {
                        ForEach(LuggageConstraint.allCases, id: \.self) { constraint in
                            Text(constraint.displayName).tag(constraint)
                        }
                    }
                    .pickerStyle(.menu)

                    if let error = viewModel.error {
                        Text(error.message)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }

                    AstraButton(
                        title: String(localized: "Build the bag", comment: "Runs packing generate"),
                        isLoading: viewModel.isGenerating
                    ) {
                        Task { await viewModel.generate() }
                    }
                    .disabled(viewModel.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("packing.generate")

                    if let plan = viewModel.plan {
                        planSection(plan)
                    }
                }
                .padding(AstraSpacing.pagePadding)
            }
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(String(localized: "Pack a trip", comment: "Packing title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { KyraPickerCloseButton() }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
    }

    @ViewBuilder
    private func planSection(_ plan: PackingPlan) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(String(localized: "Daily looks", comment: "Packing plan days"))
                .astraText(.headline)
            ForEach(plan.dailyOutfitPlan, id: \.dayKey) { day in
                HStack {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                    Spacer()
                    if day.isRewear {
                        Text(String(localized: "Rewear", comment: "Packing rewear chip"))
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textMuted)
                    }
                }
            }

            Text(String(localized: "In the bag", comment: "Named packing list"))
                .astraText(.headline)
            if viewModel.bagGarmentNames.isEmpty {
                Text(String(localized: "\(plan.packingListItemIDs.count) pieces in the bag", comment: "Packing list count fallback"))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
            } else {
                ForEach(Array(viewModel.bagGarmentNames.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textPrimary)
                }
            }

            ForEach(plan.missingEssentials, id: \.self) { line in
                Text(line)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
            }
            if let note = plan.weatherContingencyNote {
                Text(note)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textMuted)
            }
        }
        .accessibilityIdentifier("packing.plan")
    }
}

@MainActor
@Observable
final class PackingTripViewModel {
    var destination = ""
    var startDate = Date.now
    var endDate = Calendar.current.date(byAdding: .day, value: 3, to: Date.now) ?? Date.now
    var tripFor = ""
    var hasLaundryAccess = false
    var luggage: LuggageConstraint = .carryOnOnly
    private(set) var isGenerating = false
    private(set) var plan: PackingPlan?
    private(set) var bagGarmentNames: [String] = []
    private(set) var error: AstraError?

    private let outfitRepository: OutfitRepository
    private let closetRepository: ClosetRepository

    init(outfitRepository: OutfitRepository, closetRepository: ClosetRepository) {
        self.outfitRepository = outfitRepository
        self.closetRepository = closetRepository
    }

    func generate() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        let purpose = tripFor.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let generated = try await outfitRepository.generatePackingPlan(
                PackingRequest(
                    destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                    startDate: startDate,
                    endDate: max(startDate, endDate),
                    activities: purpose.isEmpty ? [] : [purpose],
                    luggageConstraint: luggage,
                    hasLaundryAccess: hasLaundryAccess,
                    regenerate: true
                )
            )
            plan = generated
            bagGarmentNames = await resolveGarmentNames(generated.packingListItemIDs)
        } catch let err as AstraError {
            error = err
        } catch {
            self.error = AstraError(category: .unknown, message: error.localizedDescription)
        }
    }

    private func resolveGarmentNames(_ ids: [UUID]) async -> [String] {
        guard !ids.isEmpty else { return [] }
        do {
            let items = try await closetRepository.fetchItems()
            let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            return ids.compactMap { id in
                let name = byID[id]?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty ? nil : name
            }
        } catch {
            return []
        }
    }
}

extension LuggageConstraint {
    var displayName: String {
        switch self {
        case .personalItemOnly: String(localized: "Personal item only", comment: "Luggage")
        case .carryOnOnly: String(localized: "Carry-on only", comment: "Luggage")
        case .checkedBag: String(localized: "Checked bag", comment: "Luggage")
        case .noConstraint: String(localized: "Whatever fits", comment: "Luggage")
        }
    }
}
