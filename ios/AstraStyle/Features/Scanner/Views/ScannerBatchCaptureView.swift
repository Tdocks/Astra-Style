//
//  ScannerBatchCaptureView.swift
//  AstraStyle
//
//  Root of `ScannerRoute.batchCloset`. Replaces the honest placeholder that
//  stood here while P3-SCAN-08's server and repository halves shipped with
//  nothing calling them.
//
//  Deliberately import-only, no camera. Batch is the "sit down with a pile
//  of clothes" path, and a phone camera taken twenty times in a row is a
//  worse tool for that than a photo roll the user has already shot. The
//  single-item route keeps the live capture session; this one does not open
//  one at all, which is also why it never asks for camera permission.
//

import PhotosUI
import SwiftUI

struct ScannerBatchCaptureView: View {
    let viewModel: ScannerBatchViewModel

    /// Called with the drafts to walk through review, in submission order.
    var onReady: ([UUID]) -> Void

    @State private var pickedItems: [PhotosPickerItem] = []

    var body: some View {
        ScrollView {
            VStack(spacing: AstraSpacing.xl) {
                switch viewModel.phase {
                case .idle:
                    intro
                case .preparing(let done, let total):
                    progress(
                        title: String(localized: "Preparing photos", comment: "Batch scan preparing"),
                        detail: String(localized: "\(done) of \(total)", comment: "Batch scan progress count")
                    )
                case .uploading(let done, let total):
                    progress(
                        title: String(localized: "Uploading", comment: "Batch scan uploading"),
                        detail: String(localized: "\(done) of \(total)", comment: "Batch scan progress count")
                    )
                case .analyzing(let total):
                    progress(
                        title: String(localized: "Reading \(total) garments", comment: "Batch scan analysing"),
                        detail: String(localized: "This takes a few seconds each.",
                                       comment: "Batch scan analysing detail")
                    )
                case .ready(let outcome):
                    summary(outcome)
                case .failed(let error):
                    message(
                        title: String(localized: "That batch didn't go through",
                                      comment: "Batch scan failure title"),
                        body: error.message
                    )
                case .capReached(let limit):
                    message(
                        title: String(localized: "Closet is full", comment: "Batch scan cap title"),
                        body: FreeTierClosetError.capReached(limit: limit).errorDescription ?? ""
                    )
                }
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
            .padding(.vertical, AstraSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .background(AstraColor.backgroundPrimary)
        .navigationTitle(Text("Add several", comment: "Batch scan screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                // `loadTransferable` returning nil means the library would
                // not hand the asset over — on a real phone, most often a
                // photo that is in iCloud and not on the device. A nil among
                // twenty must not lose the other nineteen, so nils are
                // skipped here.
                //
                // The count is then passed separately. This comment used to
                // claim "the count difference falls through to the view
                // model's own accounting", and it did not: the view model
                // saw only the surviving array, so every photo the library
                // declined to vend disappeared with nothing to say it had.
                // A summary that reports a clean batch several garments
                // short is the exact failure `Outcome` was built to prevent,
                // and it was introduced one layer above where `Outcome`
                // could see it.
                let selectedCount = items.count
                var payloads: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        payloads.append(data)
                    }
                }
                pickedItems = []
                await viewModel.importImages(payloads, selectedCount: selectedCount)
            }
        }
    }

    // MARK: - States

    private var intro: some View {
        VStack(spacing: AstraSpacing.lg) {
            Text(String(localized: "Photograph your clothes, then bring them in together.",
                        comment: "Batch scan intro"))
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(String(localized: "Up to \(BatchScanLimits.maxItemsPerBatch) at once. Kyra reads them all, then walks you through each one so you can correct anything she got wrong.",
                        comment: "Batch scan intro detail"))
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)

            picker(label: String(localized: "Choose photos", comment: "Batch scan picker button"))
                .accessibilityIdentifier("scanner.batch.choose")
        }
    }

    private func progress(title: String, detail: String) -> some View {
        VStack(spacing: AstraSpacing.md) {
            ProgressView()
                .tint(AstraColor.accentChampagne)
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            Text(detail)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scanner.batch.progress")
    }

    private func summary(_ outcome: ScannerBatchViewModel.Outcome) -> some View {
        VStack(spacing: AstraSpacing.lg) {
            Text(outcome.readyCount > 0
                 ? String(localized: "\(outcome.readyCount) ready to review",
                          comment: "Batch scan success title")
                 : String(localized: "Nothing came through", comment: "Batch scan empty title"))
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.center)

            // Every loss is named. A batch that says "12 ready" after being
            // handed 15 and explains nothing is the failure this screen
            // exists to avoid — the user would find the gap weeks later by
            // noticing an absence, with no way to tell which three.
            if !outcome.isCompletelyClean {
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    ForEach(lossLines(outcome), id: \.self) { line in
                        Text(line)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AstraSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                        .fill(AstraColor.surfaceElevated)
                )
                .accessibilityIdentifier("scanner.batch.losses")
            }

            if outcome.readyCount > 0 {
                Button {
                    onReady(outcome.draftIDs)
                } label: {
                    Text(String(localized: "Review them", comment: "Batch scan continue to review"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.astraPrimary)
                .accessibilityIdentifier("scanner.batch.review")
            }

            picker(label: outcome.readyCount > 0
                   ? String(localized: "Choose different photos", comment: "Batch scan re-pick")
                   : String(localized: "Try other photos", comment: "Batch scan retry pick"))
                .accessibilityIdentifier("scanner.batch.repick")
        }
    }

    private func message(title: String, body: String) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
            picker(label: String(localized: "Try again", comment: "Batch scan retry"))
                .accessibilityIdentifier("scanner.batch.retry")
        }
    }

    private func picker(label: String) -> some View {
        PhotosPicker(
            selection: $pickedItems,
            maxSelectionCount: BatchScanLimits.maxItemsPerBatch,
            matching: .images
        ) {
            Text(label)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.astraSecondary)
        .disabled(viewModel.isWorking)
    }

    private func lossLines(_ outcome: ScannerBatchViewModel.Outcome) -> [String] {
        var lines: [String] = []
        if outcome.skippedOverLimit > 0 {
            lines.append(String(
                localized: "\(outcome.skippedOverLimit) not included — \(BatchScanLimits.maxItemsPerBatch) is the most in one go.",
                comment: "Batch scan over-limit line"
            ))
        }
        if outcome.couldNotLoad > 0 {
            lines.append(String(
                localized: "\(outcome.couldNotLoad) couldn't be loaded from your library — they may still be in iCloud. Open them in Photos once, then try again.",
                comment: "Batch scan iCloud-not-downloaded line"
            ))
        }
        if outcome.unreadable > 0 {
            lines.append(String(
                localized: "\(outcome.unreadable) couldn't be opened as a photo.",
                comment: "Batch scan unreadable line"
            ))
        }
        if outcome.uploadFailed > 0 {
            lines.append(String(
                localized: "\(outcome.uploadFailed) didn't finish uploading. Nothing wrong with the photos — try those again.",
                comment: "Batch scan upload failure line"
            ))
        }
        for reason in ClosetItemAnalysisFailureReason.allCases {
            guard let count = outcome.analysisFailures[reason], count > 0 else { continue }
            lines.append(failureLine(reason: reason, count: count))
        }
        return lines
    }

    private func failureLine(reason: ClosetItemAnalysisFailureReason, count: Int) -> String {
        switch reason {
        case .imageUnusable:
            String(localized: "\(count) were too blurry or too dark to read.",
                   comment: "Batch scan unusable line")
        case .noGarmentDetected:
            String(localized: "\(count) had no garment Kyra could find.",
                   comment: "Batch scan no-garment line")
        case .providerUnavailable, .timedOut:
            String(localized: "\(count) couldn't be read just now — try those again.",
                   comment: "Batch scan retryable failure line")
        case .rateLimited:
            String(localized: "\(count) hit a limit. Give it a minute and try those again.",
                   comment: "Batch scan rate-limited line")
        case .unknown:
            String(localized: "\(count) didn't come back with a reason.",
                   comment: "Batch scan unknown failure line")
        }
    }
}
