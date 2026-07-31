//
//  OnboardingViewModel+Reference.swift
//  AstraStyle
//
//  §5.1 step 11 — the optional selfie / body reference photo: consent,
//  capture, removal, and the one upload.
//
//  In its own file rather than in `OnboardingViewModel` because this is the
//  §29 half of the flow and it deserves to be findable. Everything about how
//  the photograph is treated — when consent is recorded, when bytes leave the
//  device, when they stop existing — is in these hundred lines.
//

import Foundation

public extension OnboardingViewModel {

    // MARK: - Consent (§29)

    /// Whether the user has acknowledged the explanation on this screen.
    ///
    /// Reads off a timestamp rather than a Bool. §29 wants informed consent
    /// obtained before collection, and the only version of that claim worth
    /// keeping is "he agreed, at this moment, to this wording" — a Bool
    /// survives a rewrite of the copy and quietly re-authorises the new text.
    var hasGrantedReferenceConsent: Bool {
        draft.referenceConsentGrantedAt != nil
    }

    /// Records the acknowledgment. Nothing on this step may open a camera or a
    /// picker until this has been called, which is the ticket's second
    /// acceptance criterion stated as code.
    func grantReferenceConsent() async {
        guard draft.referenceConsentGrantedAt == nil else { return }
        draft.referenceConsentGrantedAt = .now
        await persist()
    }

    /// Withdraws the acknowledgment, and takes the photo with it.
    ///
    /// Withdrawing consent while keeping the image would leave the app holding
    /// a photograph under an authorisation the user has just revoked. There is
    /// only one honest implementation of "I take that back."
    func withdrawReferenceConsent() async {
        draft.referenceConsentGrantedAt = nil
        await removeReferenceImage()
    }

    /// Whether this session is a guest (ADR 0011).
    ///
    /// Exposed because the consent copy has to say where the photo goes, and
    /// for a guest the honest answer is "nowhere" — a sentence the screen
    /// cannot write without knowing. Reads through `SessionStore` at call time
    /// rather than being captured, since a guest session is minted per
    /// `continueAsGuest()`.
    func isGuestSession() async -> Bool {
        await sessionStore.currentIsGuest()
    }

    // MARK: - Capture

    /// Stores a chosen or captured photo locally and records its filename.
    ///
    /// Refuses without consent. That guard is redundant against the UI, which
    /// does not offer the controls at all until consent is given — and it is
    /// here anyway, because "the screen doesn't show the button" is a property
    /// of one layout and this is a property of the feature.
    func setReferenceImage(_ data: Data) async {
        guard hasGrantedReferenceConsent else { return }
        guard let filename = await referenceStore.save(data) else {
            referenceUploadFailure = String(
                localized: "That photo couldn't be saved on this device. Try another one.",
                comment: "Reference photo storage error"
            )
            return
        }
        // A previously uploaded path is dropped along with the old file. The
        // draft must describe one photo, not the union of every photo the user
        // has tried — and the object at the old path is superseded, not part
        // of this profile any more.
        draft.referenceStoragePaths = []
        draft.referenceImageFilename = filename
        referenceImageData = data
        referenceUploadFailure = nil
        await persist()
    }

    /// §29's "delete individual reference images", at the only point in the
    /// product where this image exists.
    func removeReferenceImage() async {
        if let filename = draft.referenceImageFilename {
            await referenceStore.remove(filename: filename)
        }
        draft.referenceImageFilename = nil
        draft.referenceStoragePaths = []
        referenceImageData = nil
        referenceUploadFailure = nil
        await persist()
    }

    // MARK: - Upload

    /// Uploads the captured photo, once, during submission.
    ///
    /// WHY NOT AT CAPTURE TIME. Three reasons, in order of weight.
    ///
    /// 1. ADR 0010 calls an uploaded-but-unused reference image an "abandoned
    ///    upload" and requires a retention sweep to delete it. That sweep does
    ///    not exist yet, and the ADR itself names "the scheduled deletion job
    ///    can fail silently" as a real cost. Uploading at capture would create
    ///    that inventory for every user who backs out of onboarding or force
    ///    quits — the population most likely to have second thoughts about a
    ///    photograph of their face. Uploading at submission means there is
    ///    nothing to sweep.
    /// 2. `removeReferenceImage()` would otherwise have to delete a remote
    ///    object as well as a local file: a second network path, with its own
    ///    failure mode, behind a control whose entire promise is that it
    ///    works. A remove that leaves the object behind is a broken promise
    ///    about a photograph, which is the worst kind to break.
    /// 3. The one branch that knows whether this session is a guest is
    ///    `submit()`. Doing the upload there means ADR 0011's "guests never
    ///    touch Supabase" is enforced by control flow that already exists,
    ///    rather than by a second `currentIsGuest()` check on a view.
    ///
    /// The cost is real and worth naming: a user on a slow connection waits
    /// for the photo during submission rather than earlier, when he could have
    /// been reading the next question. That is a few seconds once, against a
    /// standing corpus of abandoned selfies with no cleanup job.
    ///
    /// Never throws. The photo is optional; the answers are not.
    func uploadReferenceImageIfNeeded() async {
        guard draft.referenceStoragePaths.isEmpty,
              hasGrantedReferenceConsent,
              let filename = draft.referenceImageFilename else { return }
        guard let data = await referenceStore.load(filename: filename) else {
            // The file went missing between capture and submission. Forget it
            // rather than reporting an upload failure for something there is
            // nothing to upload.
            draft.referenceImageFilename = nil
            await persist()
            return
        }

        do {
            let path = try await profileRepository.uploadReferenceImage(data)
            draft.referenceStoragePaths = [path]
            referenceUploadFailure = nil
            await persist()
        } catch {
            logger.error("uploadReferenceImage failed: \(error.localizedDescription)")
            referenceUploadFailure = error.localizedDescription
        }
    }

    /// Retries just the photo, after the answers have already been saved.
    ///
    /// Two calls rather than one, because by this point `completeOnboarding`
    /// has already written `body_profiles` with an empty
    /// `reference_selfie_paths`. Uploading alone would leave an object in
    /// storage that no row points at — an orphan the account-deletion cascade
    /// would still catch (it is prefix-based, ADR 0010) but that nothing in
    /// the product could ever show the user or let him delete on its own.
    func retryReferenceUpload() async {
        guard referenceUploadFailure != nil else { return }
        await uploadReferenceImageIfNeeded()
        guard referenceUploadFailure == nil,
              !draft.referenceStoragePaths.isEmpty,
              let userID = await currentUserID() else { return }

        do {
            // Read-modify-write: the row may carry columns a Postgres trigger
            // computed (docs/14 §5's derived frame axes), and composing a
            // fresh one from the draft would hand the upsert a document that
            // is right about measurements and silent about everything else.
            var stored = try await profileRepository.fetchBodyProfile()
                ?? draft.bodyProfile(userID: userID)
            stored.appearance.referenceSelfiePaths = draft.referenceStoragePaths
            _ = try await profileRepository.updateBodyProfile(stored)
            await referenceStore.clear()
        } catch {
            logger.error("updateBodyProfile after reference retry failed: \(error.localizedDescription)")
            referenceUploadFailure = error.localizedDescription
        }
    }
}
