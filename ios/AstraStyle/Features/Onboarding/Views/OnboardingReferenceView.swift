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
//     doesn't tap. That would be true even if the policy were published —
//     and it is not: `AstraLegal.isPublished` is `false` and every URL
//     accessor returns nil, so a link here would be a dead control on the
//     one screen where trust is the entire product. So the four things that
//     matter are on the screen in plain words, and they are written to stand
//     alone: nothing below depends on a document existing.
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
//     (docs/14 §2) and no recommendation anywhere reads this image, so the
//     step's rationale line leads with "nothing else in Astra needs it". A
//     man who skips loses nothing, and the screen should not imply otherwise
//     by leaning on the ask.
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
/// Every claim here is true of the app as it stands today, which is why two of
/// them are shorter and less reassuring than a normal privacy notice would be:
/// Style Studio does not exist yet, so this photo is currently stored and
/// nothing more, and saying anything grander would be describing a product
/// rather than this one. `legal/README.md`'s second rule — "nothing is promised
/// that is not built" — applies to interface copy at least as much as to a
/// policy document, because this is the text the user actually reads.
private struct ReferenceConsentPanel: View {

    /// Split out of the stack only because the sentence is longer than a line
    /// of source will hold. It is one paragraph on screen.
    private var signedInDestination: String {
        String(localized: "To a private folder that only your account can open, when you finish these questions.",
               comment: "Reference consent destination, first sentence")
            + " "
            + String(localized: "Until then it stays on this phone.",
                     comment: "Reference consent destination, second sentence")
            + " "
            + String(localized: "It is not shown to anyone, and not sent to any other company.",
                     comment: "Reference consent destination, third sentence")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "What would happen to it", comment: "Reference consent panel title"),
                eyebrow: String(localized: "BEFORE YOU DECIDE", comment: "Reference consent panel eyebrow")
            )

            ConsentRow(
                title: String(localized: "What it's for", comment: "Reference consent heading"),
                detail: String(localized: "Later, Style Studio will use it to picture an outfit on you rather than on a model. Style Studio isn't built yet — so for now the photo would simply be kept.",
                               comment: "Reference consent detail")
            )

            ConsentRow(
                title: String(localized: "Where it goes", comment: "Reference consent heading"),
                detail: signedInDestination
            )

            ConsentRow(
                title: String(localized: "What is never done with it", comment: "Reference consent heading"),
                detail: String(localized: "It is never used to train anyone's model, and nothing here measures or identifies your face. If that were ever going to change, you'd be asked again first.",
                               comment: "Reference consent detail")
            )

            ConsentRow(
                title: String(localized: "Changing your mind", comment: "Reference consent heading"),
                detail: String(localized: "Remove it from this screen whenever you like. Deleting your account removes it too.",
                               comment: "Reference consent detail")
            )

            // Said plainly rather than linked, because there is nothing to link
            // to: `AstraLegal.isPublished` is false and every document URL is
            // nil. The sentence exists so a reader who expects a policy knows
            // why he is not being offered one, and it is careful to say that
            // nothing above is waiting on it.
            Text("Our full Privacy Policy will be published before Astra Style is released. Everything above describes the app as it works today and doesn't depend on it.")
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
