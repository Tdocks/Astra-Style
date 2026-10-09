import Foundation

extension StudioGenerationDetailViewModel {
    public var canExportHighResolution: Bool {
        guard highResolutionChild == nil, !isCheckingHighResolutionLineage,
              hasCheckedHighResolutionLineage || highResolutionError != nil,
              case .loaded(let generation) = state else { return false }
        return Self.isEligibleHighResolutionSource(generation)
    }

    public var requiresHighResolutionPhotoConsent: Bool {
        highResolutionSourceRequiresConsent
    }

    public var highResolutionConfirmationMessage: String {
        if highResolutionSubmissionUncertain {
            var message = "The previous request may have been accepted. Confirm to safely check the same export; it will not reserve a second render."
            if highResolutionSourceRequiresConsent {
                message += " Confirm that you still agree to process the original photo under the current photo-consent terms (\(StudioConsentTerms.currentVersion))."
            }
            return message
        }
        guard let quota = highResolutionQuota else {
            return "This export uses one Premium Studio render."
        }
        var message = "This export uses one of your \(quota.remaining) remaining Premium Studio renders."
        if let resetsAt = quota.resetsAt {
            message += " Your allowance resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))."
        }
        if highResolutionSourceRequiresConsent {
            message += " It will process the original photo again under the current photo-consent terms (\(StudioConsentTerms.currentVersion))."
        }
        return message
    }

    public var highResolutionConfirmationActionTitle: String {
        if highResolutionSubmissionUncertain {
            return requiresHighResolutionPhotoConsent ? "Agree and check export" : "Check same export"
        }
        return requiresHighResolutionPhotoConsent ? "Agree and export" : "Use one render"
    }

    private var highResolutionSourceRequiresConsent: Bool {
        guard case .loaded(let generation) = state,
              case .object(let payload)? = generation.promptPayload,
              case .string(let mode)? = payload["mode"] else { return true }
        return mode != "inspiration" && mode != "closet_inspiration"
    }

    /// Loads the server-authoritative allowance before showing the one-credit
    /// disclosure. No export request is sent until the user confirms it.
    public func prepareHighResolutionExport() async {
        guard highResolutionChild == nil, !isPreparingHighResolutionExport, !isExportingHighResolution,
              case .loaded(let source) = state, Self.isEligibleHighResolutionSource(source) else { return }
        isPreparingHighResolutionExport = true
        isCheckingHighResolutionLineage = true
        highResolutionError = nil
        hasPendingHighResolutionConfirmation = false
        defer {
            isPreparingHighResolutionExport = false
            isCheckingHighResolutionLineage = false
        }
        do {
            let current = try await studioRepository.fetchGeneration(id: source.id)
            guard Self.isEligibleHighResolutionSource(current) else {
                throw AstraError.validation("This estimate is no longer available for high-resolution export.")
            }
            state = .loaded(current)
            if let child = try await studioRepository.fetchHiResExport(sourceID: current.id) {
                hasCheckedHighResolutionLineage = true
                await acceptRecoveredHighResolutionChild(child, ownerID: current.userID)
                return
            }
            hasCheckedHighResolutionLineage = true
            let quota = try await studioRepository.fetchQuota()
            highResolutionQuota = quota
            guard quota.premium || highResolutionSubmissionUncertain else {
                throw AstraError.validation("High-resolution export is a Premium feature.")
            }
            guard quota.remaining > 0 || highResolutionSubmissionUncertain else {
                throw AstraError.rateLimited("Your monthly Studio render allowance is used up. Try again after it resets.")
            }
            hasPendingHighResolutionConfirmation = true
        } catch is CancellationError {
            return
        } catch {
            highResolutionError = (error as? AstraError)?.message ?? "Couldn't check your Studio allowance. Try again."
        }
    }

    func restoreExistingHighResolutionExport(sourceID: UUID) async {
        isCheckingHighResolutionLineage = true
        defer { isCheckingHighResolutionLineage = false }
        do {
            guard let child = try await studioRepository.fetchHiResExport(sourceID: sourceID) else {
                hasCheckedHighResolutionLineage = true
                return
            }
            hasCheckedHighResolutionLineage = true
            guard case .loaded(let source) = state, source.id == sourceID else { return }
            await acceptRecoveredHighResolutionChild(child, ownerID: source.userID)
        } catch is CancellationError {
            return
        } catch {
            // Keep the source detail usable and expose a retry action; do not
            // silently proceed to a new charge while the lineage is unknown.
            hasCheckedHighResolutionLineage = false
            highResolutionError = (error as? AstraError)?.message ?? "Couldn't check for an existing high-resolution export. Try again."
        }
    }

    private func acceptRecoveredHighResolutionChild(_ child: StudioGeneration, ownerID: UUID) async {
        guard child.userID == ownerID else {
            highResolutionError = "That high-resolution export belongs to another account."
            return
        }
        guard !child.isDeleted else {
            highResolutionChild = child
            highResolutionError = "This high-resolution export is no longer available."
            return
        }
        highResolutionSubmissionUncertain = false
        highResolutionError = nil
        await followHighResolutionChild(child)
    }

    public func cancelHighResolutionExportConfirmation() {
        hasPendingHighResolutionConfirmation = false
        highResolutionQuota = nil
        highResolutionError = nil
    }

    /// Rechecks source eligibility and quota after confirmation, then submits
    /// the same source id. The server treats repeats as the same export lineage.
    public func confirmHighResolutionExport() async {
        guard hasPendingHighResolutionConfirmation, !isExportingHighResolution,
              case .loaded(let source) = state else { return }
        hasPendingHighResolutionConfirmation = false
        isExportingHighResolution = true
        highResolutionError = nil
        defer { isExportingHighResolution = false }
        do {
            let current = try await studioRepository.fetchGeneration(id: source.id)
            guard Self.isEligibleHighResolutionSource(current) else {
                throw AstraError.validation("This estimate is no longer available for high-resolution export.")
            }
            let quota = try await studioRepository.fetchQuota()
            guard quota.premium || highResolutionSubmissionUncertain else {
                throw AstraError.validation("High-resolution export is a Premium feature.")
            }
            guard quota.remaining > 0 || highResolutionSubmissionUncertain else {
                throw AstraError.rateLimited("Your monthly Studio render allowance is used up. Try again after it resets.")
            }
            guard quota.remaining == highResolutionQuota?.remaining,
                  quota.limit == highResolutionQuota?.limit,
                  quota.resetsAt == highResolutionQuota?.resetsAt else {
                state = .loaded(current)
                highResolutionQuota = quota
                hasPendingHighResolutionConfirmation = true
                return
            }
            state = .loaded(current)
            let consent = Self.requiresPhotoConsent(current)
                ? StudioConsentAttestation(acknowledged: true, termsVersion: StudioConsentTerms.currentVersion)
                : nil
            highResolutionSubmissionUncertain = true
            let child = try await studioRepository.exportHiRes(sourceID: current.id, consent: consent)
            highResolutionSubmissionUncertain = false
            highResolutionChild = child
            highResolutionImageURL = nil
            await followHighResolutionChild(child)
        } catch is CancellationError {
            return
        } catch let error as AstraError {
            if [.auth, .validation, .rateLimited, .unimplemented].contains(error.category) {
                highResolutionSubmissionUncertain = false
            }
            highResolutionError = error.message
        } catch {
            highResolutionError = (error as? AstraError)?.message ?? "Couldn't queue the high-resolution export. Try again."
        }
    }

    /// Retries an already-created provider-failed child without spending a
    /// second allowance reservation. The endpoint's source lineage remains
    /// the stable identity for all export submissions.
    public func retryHighResolutionExport() async {
        guard !isExportingHighResolution, let child = highResolutionChild,
              child.isRetryableWithoutCharge else { return }
        isExportingHighResolution = true
        highResolutionError = nil
        highResolutionImageURL = nil
        defer { isExportingHighResolution = false }
        do {
            let retry = try await studioRepository.retryGeneration(id: child.id)
            highResolutionChild = retry
            await followHighResolutionChild(retry)
        } catch is CancellationError {
            return
        } catch {
            highResolutionError = (error as? AstraError)?.message ?? "Couldn't retry the high-resolution export. Try again."
        }
    }

    public func refreshHighResolutionExport() async {
        guard !isExportingHighResolution, let child = highResolutionChild else { return }
        isExportingHighResolution = true
        defer { isExportingHighResolution = false }
        highResolutionError = nil
        do {
            let current = try await studioRepository.fetchGeneration(id: child.id)
            guard !current.isDeleted else {
                highResolutionChild = current
                highResolutionError = "This high-resolution export is no longer available."
                return
            }
            highResolutionError = nil
            await followHighResolutionChild(current)
        } catch let error as AstraError {
            highResolutionError = error.message
        } catch {
            highResolutionError = "Couldn't check the high-resolution export. Try again."
        }
    }

    private func followHighResolutionChild(_ initial: StudioGeneration) async {
        var generation = initial
        highResolutionChild = generation
        var delay = pollInterval
        let clock = ContinuousClock()
        let deadline = clock.now + maximumPollingDuration
        do {
            while generation.status == .queued || generation.status == .generating {
                guard clock.now < deadline else {
                    highResolutionError = "This export is taking longer than expected. Check its status again."
                    return
                }
                if delay > .zero {
                    try await Task.sleep(for: delay)
                    try Task.checkCancellation()
                }
                generation = try await studioRepository.fetchStatus(generationID: generation.id)
                guard !generation.isDeleted else {
                    highResolutionError = "This high-resolution export is no longer available."
                    highResolutionChild = generation
                    return
                }
                highResolutionChild = generation
                delay = min(delay + delay, maximumPollInterval)
            }
            guard generation.status == .complete, let path = generation.resultImagePath else { return }
            highResolutionImageURL = try await imageURLResolver.resolve(storagePath: path)
        } catch let error as AstraError {
            highResolutionError = error.message
        } catch is CancellationError {
            return
        } catch {
            highResolutionError = (error as? AstraError)?.message ?? "Couldn't load the high-resolution export. Try again."
        }
    }

    private static func isEligibleHighResolutionSource(_ generation: StudioGeneration) -> Bool {
        guard generation.status == .complete, !generation.isDeleted, generation.resultImagePath != nil else { return false }
        guard case .object(let values)? = generation.promptPayload else { return true }
        if case .string("hi_res")? = values["resolution"] { return false }
        if values["hi_res_source_generation_id"] != nil { return false }
        return true
    }

    private static func requiresPhotoConsent(_ generation: StudioGeneration) -> Bool {
        guard case .object(let payload)? = generation.promptPayload,
              case .string(let mode)? = payload["mode"] else { return true }
        return mode != "inspiration" && mode != "closet_inspiration"
    }
}
