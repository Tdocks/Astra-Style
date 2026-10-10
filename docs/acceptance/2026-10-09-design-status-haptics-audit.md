# Design status and haptics audit — 2026-10-09

## Color-independent status

The requested verdict, confidence, and laundry states communicate their meaning without color:

- Product verdicts render literal Buy, Consider, Wait for a sale, or Skip labels in `ios/AstraStyle/Features/Shopping/Views/ProductDecisionView.swift:174-178` and Kyra cards use the same labels in `ios/AstraStyle/Features/Kyra/Components/KyraCardView.swift:150-151,174-179`.
- Score/confidence meters pair the tier color with the numeric score and a text descriptor. Their VoiceOver label includes the title, score, and descriptor in `ios/AstraStyle/Core/DesignSystem/Components/AstraScoreMeter.swift:99-107,112-135`.
- Closet rows and the laundry picker show named availability/laundry states in `ios/AstraStyle/Features/Closet/Components/ClosetCompactList.swift:287-300` and `ios/AstraStyle/Features/Closet/Components/ClosetItemFieldRow.swift:171-186`.
- Low-confidence scan fields include “Kyra isn’t sure — check this.” alongside amber treatment in `ios/AstraStyle/Features/Scanner/ViewModels/ScannerReviewViewModel.swift:317-322` and `ios/AstraStyle/Features/Scanner/Views/ScannerReviewFormView.swift:81-85`.

No color-only defect was found in these requested status groups.

## Haptic mapping corrections

Per spec §3, selection feedback is used for reversible selection changes, success feedback after a successful save, and warning feedback for destructive actions.

- Closet filter clear-all and individual-filter removal use selection feedback (`ios/AstraStyle/Features/Closet/Views/ClosetFilterPanelView.swift:218-221,684-686`).
- Removing a color token from the editable form uses selection feedback (`ios/AstraStyle/Features/Closet/Components/ClosetColorPicker.swift:153-157`).
- Adding a typed value to an unsaved closet-form list uses selection feedback (`ios/AstraStyle/Features/Closet/Views/ClosetItemFormView.swift:656-661`).
- Capturing a scan image uses selection feedback; saving the reviewed closet item continues to use success feedback (`ios/AstraStyle/Features/Scanner/ViewModels/ScannerCaptureViewModel.swift:152-157,183-188`; `ios/AstraStyle/Features/Scanner/ViewModels/ScannerReviewViewModel+SaveRecovery.swift:104-114`).
- Withdrawing reference-photo consent and removing a first-item/reference photo now issue warning feedback before the asynchronous deletion begins; granting photo consent remains selection feedback (`ios/AstraStyle/Features/Onboarding/Views/OnboardingReferenceView.swift`; `ios/AstraStyle/Features/Onboarding/Views/OnboardingFirstItemsView.swift`).
- Archive/delete warnings remain at the destructive action sites. Outfit item swaps remain selection feedback.

## Snapshot date determinism

The Home date line previously called `Date.now` in the view. `HomeView` now reads an environment date with the production default set to the current date; the snapshot fixture supplies `SnapshotClock.date` (`ios/AstraStyle/Features/Home/Views/HomeView.swift`, `ios/AstraStyle/Features/Home/Views/HomeView+Content.swift`, `ios/AstraStyle/Tests/UnitTests/MajorSnapshotFixture.swift`).

Profile root snapshots do not render the Style Journey timeline; that timeline is a separate destination. The root screen's sample closet purchase dates are randomized in `SampleData`, but each is at least two months old, and no individual date is shown on the root screen. Shopping counts use a fixed fixture purchase. Kyra's mock message timestamps and generated UUIDs are not shown in its transcript rows. Those values therefore do not affect the current snapshot pixels. No product view-model clock seam was added solely for hidden data.

## Checks

Strict SwiftLint passed on the four haptic-edited files. `git diff --check` passed. No Xcode build or test was run for this audit.
