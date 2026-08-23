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
            ForEach(plan.dailyOutfitPlan, id: \.outfitID) { day in
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
            Text(String(localized: "\(plan.packingListItemIDs.count) pieces in the bag", comment: "Packing list count"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
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
    var hasLaundryAccess = false
    var luggage: LuggageConstraint = .carryOnOnly
    private(set) var isGenerating = false
    private(set) var plan: PackingPlan?
    private(set) var error: AstraError?

    private let outfitRepository: OutfitRepository

    init(outfitRepository: OutfitRepository) {
        self.outfitRepository = outfitRepository
    }

    func generate() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            plan = try await outfitRepository.generatePackingPlan(
                PackingRequest(
                    destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                    startDate: startDate,
                    endDate: max(startDate, endDate),
                    luggageConstraint: luggage,
                    hasLaundryAccess: hasLaundryAccess,
                    regenerate: true
                )
            )
        } catch let err as AstraError {
            error = err
        } catch {
            self.error = AstraError(category: .unknown, message: error.localizedDescription)
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
