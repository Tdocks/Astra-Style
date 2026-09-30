//
//  OnboardingReferenceView.swift
//  AstraStyle
//
//  §5.1 step 11 — the optional selfie / body reference photo.
//
//  THE CAMERA CODE IS THE EASY PART. This is the one screen in Astra Style
//  that asks for a photograph of the user's face, and spec §29 governs it:
//  informed consent, an honest account of processing and retention, and the
//  ability to delete. `docs/11-risk-register.md` risk 7 and the biometric
//  question flagged in `legal/README.md` are why the copy below was written
//  slowly.
//
//  FOUR DECISIONS, EACH OF WHICH COULD HAVE GONE THE LAZY WAY.
//
//  1. THE EXPLANATION IS THE SCREEN, NOT A LINK. Spec §29 is satisfied by
//     text a man reads before he decides, not by a Privacy Policy link he
//     doesn't tap. The current site has legal pages, but their counsel
//     placeholders mean this explanation must accurately describe the photo
//     flow by itself; see docs/03-progress.md's pre-release legal blocker.
//
//  2. CONSENT IS A DELIBERATE ACT, AND IT GATES THE CONTROLS THEMSELVES.
//     The picker and the camera button do not exist until the acknowledgment
//     row is tapped. Not disabled — absent. A greyed-out button invites the
//     tap that dismisses the explanation on the way past, which is how
//     "consent before capture" becomes "consent shaped like a speed bump".
//
//  3. NOTHING IS UPLOADED FROM HERE. The photo is written to on-device
//     storage and stays there until onboarding is submitted; see
//     `OnboardingViewModel.uploadReferenceImageIfNeeded()` for the argument.
//     That is also what makes the Remove control below honest — it deletes a
//     file, not a server object it might fail to reach.
//
//  4. SKIPPING IS FREE AND SAID SO. `FrameProfile` is built to degrade
//     (docs/14 §2). Daily style help and closet management do not depend on
//     this image; only a Visualize request uses it. A man who skips loses
//     nothing from those daily features, and the screen should not imply
//     otherwise by leaning on the ask.
//
//  WHAT IS NOT HERE. No face detection, no quality scoring, no "your photo
//  looks great" affirmation, no retake coaching. Every one of those would be
//  the app forming an opinion about a photograph of a man's face, which is
//  precisely what the consent copy above promises it does not do.
//

import PhotosUI
import SwiftUI

struct OnboardingReferenceView: View {
    let model: OnboardingViewModel

    @State private var pickedItem: PhotosPickerItem?
    @State private var isShowingCamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            ReferenceConsentPanel()

            acknowledgment

            if model.hasGrantedReferenceConsent {
                captureControls
            }

            if let failure = model.referenceUploadFailure {
                storageFailureNotice(failure)
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                // `loadTransferable` is the only supported way to get bytes out
                // of a PhotosPickerItem, and it returns nil for an asset the
                // system could not vend (an iCloud photo that failed to
                // download, a format it declined to transcode). Treated as
                // "nothing was chosen" rather than as an error, because from
                // the user's side he tapped a photo and no photo arrived.
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let prepared = ReferenceImagePreparation.jpeg(from: data) else {
                    pickedItem = nil
                    return
                }
                await model.setReferenceImage(prepared)
                pickedItem = nil
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            ReferenceCameraPicker { data in
                isShowingCamera = false
                guard let prepared = ReferenceImagePreparation.jpeg(from: data) else { return }
                Task { await model.setReferenceImage(prepared) }
            } onCancel: {
                isShowingCamera = false
            }
        }
    }

    // MARK: - Acknowledgment (the §29 gate)

    /// A checkbox rather than a button, and the wording says what tapping it
    /// means rather than "Continue".
    ///
    /// Tapping it a second time withdraws consent AND removes the photo —
    /// see `withdrawReferenceConsent()`. Keeping the image after a withdrawal
    /// would leave the app holding a photograph under permission the user had
    /// just taken back.
    private var acknowledgment: some View {
        Button {
            Task {
                if model.hasGrantedReferenceConsent {
                    await model.withdrawReferenceConsent()
                } else {
                    await model.grantReferenceConsent()
                }
                AstraHaptics.selection()
            }
        } label: {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                // Shape changes as well as colour — spec §19 forbids meaning
                // carried by colour alone.
                Image(systemName: model.hasGrantedReferenceConsent ? "checkmark.circle.fill" : "circle")
                    .astraIcon(.emphasis)
                    .foregroundStyle(
                        model.hasGrantedReferenceConsent
                            ? AstraColor.accentChampagneAccessible
                            : AstraColor.textMuted
                    )
                    .accessibilityHidden(true)

                Text("I've read this, and I'd like to add a photo.")
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AstraSpacing.md)
            .frame(minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .strokeBorder(
                        model.hasGrantedReferenceConsent
                            ? AstraColor.accentChampagne
                            : AstraColor.divider,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.reference.consent")
        .accessibilityAddTraits(model.hasGrantedReferenceConsent ? .isSelected : AccessibilityTraits())
        .accessibilityHint(Text("Turning this on shows the camera and photo controls. Turning it off removes any photo you added.",
                                comment: "Reference consent checkbox hint"))
    }

    // MARK: - Capture

    @ViewBuilder
    private var captureControls: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            if let data = model.referenceImageData, let image = UIImage(data: data) {
                preview(image)
            } else {
                pickerButtons
            }
        }
    }

    private func preview(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: AstraSize.referencePreviewHeight)
                .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                        .strokeBorder(AstraColor.divider, lineWidth: 1)
                )
                // Not described to VoiceOver beyond "your photo". Astra does
                // not look at this image, so it has nothing to say about it.
                .accessibilityLabel(Text("The photo you added", comment: "Reference photo preview"))
                .accessibilityIdentifier("onboarding.reference.preview")

            Text("It stays on this phone until you finish these questions.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button(String(localized: "Remove this photo", comment: "Remove the reference photo")) {
                Task {
                    await model.removeReferenceImage()
                    AstraHaptics.warning()
                }
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("onboarding.reference.remove")
        }
    }

    private var pickerButtons: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                Text("Choose a photo")
            }
            .buttonStyle(.astraPrimary)
            .accessibilityIdentifier("onboarding.reference.choosePhoto")

            // Only offered where a camera exists. On a device without one —
            // including every simulator — the button would open a picker that
            // cannot start, which is §22's "no dead buttons" in its most
            // literal form.
            if ReferenceCameraPicker.isAvailable {
                Button(String(localized: "Take one now", comment: "Open the camera for a reference photo")) {
                    isShowingCamera = true
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("onboarding.reference.takePhoto")
            }

            Text("A clear, front-on photo in even light works best. Head and shoulders is enough.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Local storage failed. Rare, and still said out loud: the alternative is
    /// a screen where the user taps a photo and nothing happens.
    private func storageFailureNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text("That didn't save.")
                .astraText(.headline)
                .foregroundStyle(AstraColor.warningAmber)

            Text(message)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .strokeBorder(AstraColor.warningAmber, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.reference.storageError")
    }
}

// MARK: - The consent copy itself

/// Spec §29's four obligations, as four sentences a man can read in ten
/// seconds: what it is for, where it goes, what is never done with it, and how
/// to get rid of it.
///
/// Keep this copy aligned with the real Studio data path: the photo is saved
/// in private account storage and, only when the user requests a preview, may
/// be sent to the configured image-generation provider. The provider's exact
/// identity and retention terms still need to be finalized in the Privacy
/// Policy before a broader release.
private struct ReferenceConsentPanel: View {

    /// Split out of the stack only because the sentence is longer than a line
    /// of source will hold. It is one paragraph on screen.
    private var signedInDestination: String {
        String(localized: "To private storage linked to your Astra account when you finish onboarding.",
               comment: "Reference consent destination, first sentence")
            + " "
            + String(localized: "If you request a Style Studio preview, Astra may send the photo to its configured image-generation provider to make that preview.",
                     comment: "Reference consent destination, provider processing")
            + " "
            + String(localized: "That provider's own data-handling and retention terms apply to the request.",
                     comment: "Reference consent destination, provider retention")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "What would happen to it", comment: "Reference consent panel title"),
                eyebrow: String(localized: "BEFORE YOU DECIDE", comment: "Reference consent panel eyebrow")
            )

            ConsentRow(
                title: String(localized: "What it's for", comment: "Reference consent heading"),
                detail: String(
                    localized: "If you choose Visualize in Style Studio, this photo is used as the person reference for the outfit preview.",
                    comment: "Reference consent detail"
                ) + " " + String(
                    localized: "This is optional; daily style help and closet management work without it.",
                    comment: "Reference consent detail"
                )
            )

            ConsentRow(
                title: String(localized: "Where it goes", comment: "Reference consent heading"),
                detail: signedInDestination
            )

            ConsentRow(
                title: String(localized: "What Astra does not do", comment: "Reference consent heading"),
                detail: String(localized: "Astra does not create a face identifier or take body measurements from this photo. It is used only as a visual reference for a preview you request.",
                               comment: "Reference consent detail")
            )

            ConsentRow(
                title: String(localized: "Changing your mind", comment: "Reference consent heading"),
                detail: String(localized: "Remove it here before finishing onboarding, or later in Profile under Privacy & Data → Reference Photos. Removing it also deletes saved Style Studio previews made with it.",
                               comment: "Reference consent detail")
            )

            // The site is reachable but the legal content still has counsel
            // placeholders. Avoid presenting that draft as final disclosure.
            Text("Astra's Privacy Policy is still being finalized. It must name the image provider and explain its data handling before a broader release.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .strokeBorder(AstraColor.divider, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.reference.consentPanel")
    }
}

private struct ConsentRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preparing the bytes

/// Downscales and re-encodes a chosen image before it is stored.
///
/// Data minimisation, not performance (risk 7's mitigation names it in those
/// words): a modern phone photo is a 12-megapixel file carrying EXIF that can
/// include the location it was taken. Re-encoding through `UIImage` drops the
/// metadata, and 1600px on the long edge is more than any likeness needs.
enum ReferenceImagePreparation {
    static let maxDimension: CGFloat = 1600
    static let compressionQuality: CGFloat = 0.85

    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > 0 else { return nil }

        let scale = min(1, maxDimension / longEdge)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: compressionQuality)
    }
}

#Preview("Reference — consent") {
    ScrollView {
        ReferenceConsentPanel()
            .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
}
