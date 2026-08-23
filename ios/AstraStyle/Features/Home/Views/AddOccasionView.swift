//
//  AddOccasionView.swift
//  AstraStyle
//
//  Manual occasion. Writes `occasions`, then rebuilds the week so the
//  strip is keyed to a real date, not a placeholder calendar.
//

import SwiftUI

struct AddOccasionView: View {
    @State private var viewModel: AddOccasionViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: AddOccasionViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                AstraTextField(
                    String(localized: "What's coming up", comment: "Occasion title"),
                    text: $viewModel.title,
                    placeholder: String(localized: "Dinner, client meeting…", comment: "Occasion title placeholder")
                )
                .accessibilityIdentifier("occasion.title")

                DatePicker(
                    String(localized: "When", comment: "Occasion date"),
                    selection: $viewModel.startsAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .tint(AstraColor.accentChampagne)
                .accessibilityIdentifier("occasion.startsAt")

                Picker(
                    String(localized: "How dressed", comment: "Occasion dress code"),
                    selection: $viewModel.dressCode
                ) {
                    Text(String(localized: "Not sure", comment: "No dress code")).tag(Optional<DressCode>.none)
                    ForEach(DressCode.allCases, id: \.self) { code in
                        Text(code.displayName).tag(Optional(code))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("occasion.dressCode")

                if let error = viewModel.error {
                    Text(error.message)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                }

                AstraButton(
                    title: String(localized: "Save", comment: "Saves the occasion"),
                    isLoading: viewModel.isSaving
                ) {
                    Task {
                        if await viewModel.save() { dismiss() }
                    }
                }
                .disabled(viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("occasion.save")

                Spacer()
            }
            .padding(AstraSpacing.pagePadding)
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(String(localized: "Add to the week", comment: "Add occasion title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { KyraPickerCloseButton() }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
    }
}

@MainActor
@Observable
final class AddOccasionViewModel {
    var title = ""
    var startsAt = Date.now
    var dressCode: DressCode?
    private(set) var isSaving = false
    private(set) var error: AstraError?

    private let outfitRepository: OutfitRepository
    private let currentUserID: () async -> UUID?

    init(outfitRepository: OutfitRepository, currentUserID: @escaping () async -> UUID?) {
        self.outfitRepository = outfitRepository
        self.currentUserID = currentUserID
    }

    func save() async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            guard let userID = await currentUserID() else {
                throw AstraError.auth("Sign in to add something to the week.")
            }
            _ = try await outfitRepository.saveOccasion(
                Occasion(
                    id: UUID(),
                    userID: userID,
                    title: trimmed,
                    startsAt: startsAt,
                    dressCode: dressCode,
                    source: .manual
                )
            )
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: .now)
            guard let end = calendar.date(byAdding: .day, value: 6, to: start) else { return true }
            _ = try? await outfitRepository.generatePackingPlan(
                PackingRequest(
                    destination: "",
                    startDate: start,
                    endDate: end,
                    luggageConstraint: .noConstraint,
                    hasLaundryAccess: true,
                    regenerate: true
                )
            )
            return true
        } catch let err as AstraError {
            error = err
            return false
        } catch {
            self.error = AstraError(category: .unknown, message: error.localizedDescription)
            return false
        }
    }
}
