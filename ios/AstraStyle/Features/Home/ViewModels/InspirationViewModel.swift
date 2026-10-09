import Foundation
import Observation

@MainActor
@Observable
final class InspirationViewModel: Identifiable {
    let id = UUID()
    let closetOnly: Bool
    var items: [ClosetItem] = []
    var selectedItemIDs: Set<UUID> = []
    var adjustment = ""
    private(set) var contextSummary = "Loading today's context…"
    private(set) var isPreparing = true
    private(set) var isGenerating = false
    private(set) var renderedItems: [ClosetItem] = []
    private(set) var imageURL: URL?
    private(set) var error: String?
    private(set) var job: StudioGeneration?
    private(set) var quotaSummary = "Preview allowance unavailable"
    private(set) var pendingPaywall: PaywallContext?
    private var lastCompletedJob: StudioGeneration?
    private var pendingItems: [ClosetItem] = []
    private var context = ""
    private var adjustments: [String] = []
    private let container: AppContainer
    private let weatherService: WeatherService
    private let initialItemIDs: Set<UUID>?
    private let currentOwnerID: @MainActor () async -> UUID?
    private var preparedOwnerID: UUID?
    private var ownerInvalidated = false
    private var weatherSnapshot: WeatherSnapshot?

    init(
        closetOnly: Bool,
        container: AppContainer,
        weatherService: WeatherService? = nil,
        initialItemIDs: Set<UUID>? = nil,
        currentOwnerID: (@MainActor () async -> UUID?)? = nil
    ) {
        self.closetOnly = closetOnly
        self.container = container
        self.weatherService = weatherService ?? container.weatherService
        self.initialItemIDs = initialItemIDs
        self.currentOwnerID = currentOwnerID ?? { await container.sessionStore.currentUserID() }
    }

    var canGenerate: Bool {
        !ownerInvalidated && preparedOwnerID != nil && !isPreparing && !isGenerating &&
            !context.isEmpty && (!closetOnly || (!selectedItemIDs.isEmpty && selectedItemIDs.count <= 12))
    }

    func prepare() async {
        guard isPreparing, !ownerInvalidated else { return }
        defer { isPreparing = false }
        guard let ownerID = await currentOwnerID(), !Task.isCancelled else {
            invalidateOwnerContext(message: "Sign in again to load your private style context.")
            return
        }
        preparedOwnerID = ownerID
        guard await refreshQuota(for: ownerID) else { return }

        do {
            guard try await loadContext(ownerID: ownerID) else { return }
            if closetOnly { await loadClosetItems(ownerID: ownerID) }
        } catch {
            guard await requireCurrentOwner(ownerID) else { return }
            handle(error)
            contextSummary = "Some context couldn't load"
        }
    }

    private func loadClosetSuggestions(ownerID: UUID) async {
        guard await requireCurrentOwner(ownerID) else { return }
        do {
            let request = OutfitGenerationRequest(
                naturalLanguageRequest: String(("What should I wear today? Use only my closet. " + context).prefix(500)),
                desiredCount: 1,
                weatherSnapshot: weatherSnapshot
            )
            let recommendations = try await container.outfitRepository.generateOutfits(request)
            guard await requireCurrentOwner(ownerID) else { return }
            selectedItemIDs = Set(recommendations.first?.itemIDs ?? [])
            selectedItemIDs.formIntersection(Set(items.map(\.id)))
            if selectedItemIDs.isEmpty { error = "Choose the pieces you want to include below." }
        } catch {
            guard await requireCurrentOwner(ownerID) else { return }
            self.error = "Couldn't suggest a set right now. Choose the pieces you want to include below."
        }
    }

    func generate(adjustment quickAdjustment: String? = nil) async {
        guard canGenerate, let ownerID = preparedOwnerID else { return }
        guard await requireCurrentOwner(ownerID) else { return }
        let newAdjustment = (quickAdjustment ?? adjustment).trimmingCharacters(in: .whitespacesAndNewlines)
        if !newAdjustment.isEmpty { adjustments.append(newAdjustment) }
        adjustment = ""
        isGenerating = true
        error = nil
        let sourceID = (!newAdjustment.isEmpty || Set(renderedItems.map(\.id)) != selectedItemIDs) && lastCompletedJob != nil
            ? lastCompletedJob?.id : nil
        job = nil
        defer { isGenerating = false }
        do {
            guard await requireCurrentOwner(ownerID) else { return }
            let request = StudioGenerationRequest(
                referenceImagePath: "",
                sourceGenerationID: sourceID,
                inspirationMode: closetOnly ? "closet_inspiration" : "inspiration",
                inspirationContext: context,
                inspirationInstructions: String(adjustments.joined(separator: "; then ").suffix(1500)),
                adHocItemIDs: closetOnly ? Array(selectedItemIDs).sorted { $0.uuidString < $1.uuidString } : [],
                variationNonce: lastCompletedJob == nil ? nil : UUID(),
                hasUserConsent: false
            )
            let initial = try await container.studioRepository.startGeneration(request)
            guard await requireCurrentOwner(ownerID) else { return }
            guard await refreshQuota(for: ownerID) else { return }
            job = initial
            pendingItems = items.filter { selectedItemIDs.contains($0.id) }
            try await finish(initial, ownerID: ownerID)
        } catch {
            guard await requireCurrentOwner(ownerID) else { return }
            handle(error)
        }
    }

    func retry() async {
        guard !isGenerating, let job, let ownerID = preparedOwnerID else { return }
        guard await requireCurrentOwner(ownerID) else { return }
        isGenerating = true
        error = nil
        imageURL = nil
        defer { isGenerating = false }
        do {
            guard await requireCurrentOwner(ownerID) else { return }
            let next: StudioGeneration
            if job.status == .failed && job.isRetryableWithoutCharge {
                next = try await container.studioRepository.retryGeneration(id: job.id)
                guard await requireCurrentOwner(ownerID) else { return }
            } else {
                next = job
            }
            try await finish(next, ownerID: ownerID)
        } catch {
            guard await requireCurrentOwner(ownerID) else { return }
            handle(error)
        }
    }

    var chatPrompt: String {
        "Help me refine today's \(closetOnly ? "closet-only look" : "style inspiration"). " +
            (closetOnly ? "Use only these owned pieces: " + renderedItems.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") + ". " : "") +
            "Style adjustments so far: " + adjustments.joined(separator: "; ") + ". Current request: " + adjustment + ". " + context
    }

    func refreshQuota() async {
        let ownerID: UUID
        if let preparedOwnerID {
            ownerID = preparedOwnerID
        } else if let currentOwner = await currentOwnerID() {
            ownerID = currentOwner
        } else {
            invalidateOwnerContext(message: "Sign in again to load your private style context.")
            return
        }
        _ = await refreshQuota(for: ownerID)
    }

    private func refreshQuota(for ownerID: UUID) async -> Bool {
        guard await requireCurrentOwner(ownerID) else { return false }
        do {
            let quota = try await container.studioRepository.fetchQuota()
            guard await requireCurrentOwner(ownerID) else { return false }
            quotaSummary = quota.summary
        } catch {
            guard await requireCurrentOwner(ownerID) else { return false }
            quotaSummary = "Couldn't load your preview allowance. Try again."
        }
        return true
    }

    func clearPaywall() { pendingPaywall = nil }

    func accountDidChange() {
        guard preparedOwnerID != nil else { return }
        invalidateOwnerContext(message: "Your account changed. Close and reopen this preview.")
    }

    private func requireCurrentOwner(_ expectedOwnerID: UUID) async -> Bool {
        guard !Task.isCancelled,
              await currentOwnerID() == expectedOwnerID,
              !ownerInvalidated else {
            invalidateOwnerContext(message: "Your account changed. Close and reopen this preview.")
            return false
        }
        return true
    }

    private func invalidateOwnerContext(message: String) {
        ownerInvalidated = true
        preparedOwnerID = nil
        isPreparing = false
        isGenerating = false
        items = []
        selectedItemIDs = []
        renderedItems = []
        pendingItems = []
        imageURL = nil
        job = nil
        lastCompletedJob = nil
        weatherSnapshot = nil
        pendingPaywall = nil
        adjustments = []
        adjustment = ""
        context = ""
        contextSummary = "Private style context cleared"
        quotaSummary = "Preview allowance unavailable"
        error = message
    }

    private func finish(_ initial: StudioGeneration, ownerID: UUID) async throws {
        var current = initial
        let deadline = ContinuousClock.now + .seconds(180)
        while current.status == .queued || current.status == .generating {
            guard await requireCurrentOwner(ownerID) else { throw CancellationError() }
            job = current
            guard ContinuousClock.now < deadline else {
                throw AstraError.network("This image is still processing. Try checking again.")
            }
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()
            guard await requireCurrentOwner(ownerID) else { throw CancellationError() }
            current = try await container.studioRepository.fetchStatus(generationID: current.id)
            guard await requireCurrentOwner(ownerID) else { throw CancellationError() }
        }
        guard await requireCurrentOwner(ownerID) else { throw CancellationError() }
        job = current
        guard current.status == .complete, let path = current.resultImagePath else {
            throw AstraError.provider(current.errorMessage ?? "The image couldn't finish. Please try again.")
        }
        guard await requireCurrentOwner(ownerID) else { throw CancellationError() }
        let signedURL = try await container.closetImageURLResolver.resolve(storagePath: path)
        guard await requireCurrentOwner(ownerID) else { throw CancellationError() }
        imageURL = signedURL
        lastCompletedJob = current
        renderedItems = pendingItems
    }

    private func handle(_ error: Error) {
        if let error = error as? AstraError {
            self.error = error.message
            if error.category == .subscriptionLimitReached,
               error.quotaDetails?.limit == "studio_trial_generation" {
                pendingPaywall = .studioQuota
            }
        } else if error is CancellationError {
            self.error = "Generation paused. Check again to resume."
        } else {
            self.error = "Couldn't finish this image. Please try again."
        }
    }
}

private extension InspirationViewModel {
    func loadContext(ownerID: UUID) async throws -> Bool {
        let profile = try await container.profileRepository.fetchCurrentProfile()
        guard await requireCurrentOwner(ownerID) else { return false }
        guard profile.id == ownerID else {
            invalidateOwnerContext(message: "Your style profile changed. Close and reopen this preview.")
            return false
        }
        let style = try await container.profileRepository.fetchStyleProfile()
        guard await requireCurrentOwner(ownerID) else { return false }
        var lines = contextLines(profile: profile, style: style)
        var summary: [String] = []
        guard await appendWeatherContext(to: &lines, summary: &summary, ownerID: ownerID),
              await appendCalendarContext(to: &lines, summary: &summary, profileID: ownerID, ownerID: ownerID) else { return false }
        guard await requireCurrentOwner(ownerID) else { return false }
        context = String(lines.joined(separator: "\n").prefix(6000))
        contextSummary = summary.joined(separator: " · ")
        return true
    }

    func loadClosetItems(ownerID: UUID) async {
        do {
            let fetchedItems = try await container.closetRepository.fetchItems()
            guard await requireCurrentOwner(ownerID) else { return }
            items = fetchedItems.filter { $0.userID == ownerID && !$0.isArchived && $0.isWearableToday }
            if let initialItemIDs {
                prepareInitialSelection(initialItemIDs)
            } else {
                await loadClosetSuggestions(ownerID: ownerID)
            }
        } catch {
            guard await requireCurrentOwner(ownerID) else { return }
            handle(error)
        }
    }

    func contextLines(profile: Profile, style: StyleProfile?) -> [String] {
        var lines = ["Date: \(Date.now.formatted(date: .complete, time: .omitted))"]
        lines.append("Wardrobe direction: \(profile.wardrobeGraph.rawValue)")
        guard let style else { return lines }
        lines.append("Style: \(style.styleSummary ?? style.primaryIdentity?.rawValue ?? "unspecified")")
        lines.append("Preferred colors: \(style.preferredColors.joined(separator: ", ")); avoid: \(style.avoidedColors.joined(separator: ", "))")
        lines.append("Fit: \(style.preferredFit?.rawValue ?? "unspecified"); formality: \(style.formalityPreference?.rawValue ?? "unspecified")")
        if let data = try? JSONEncoder().encode(style.preferenceVector),
           let vector = String(data: data, encoding: .utf8) {
            lines.append("Quiz preferences with confidence (unmeasured dimensions are unknown): \(vector)")
        }
        return lines
    }

    func appendWeatherContext(to lines: inout [String], summary: inout [String], ownerID: UUID) async -> Bool {
        if weatherService.currentAuthorization() == .authorized {
            let reading = try? await weatherService.currentReading()
            guard await requireCurrentOwner(ownerID) else { return false }
            if let reading {
                let weather = reading.snapshot
                weatherSnapshot = weather
                lines.append("\(reading.isLastKnown ? "Last-known weather" : "Weather"): \(weather.condition.rawValue), \(weather.temperatureLow)–\(weather.temperatureHigh) °F; precipitation probability \(weather.precipitationChance.map(String.init(describing:)) ?? "unknown"); season \(weather.season?.rawValue ?? "unknown")")
                summary.append(reading.isLastKnown ? "Last-known weather included" : "Current weather included")
                return true
            }
        }
        lines.append("Weather unavailable. Do not invent conditions.")
        summary.append(weatherService.currentAuthorization() == .authorized
            ? "Weather temporarily unavailable"
            : "Weather unavailable — enable it on Home")
        return true
    }

    func appendCalendarContext(to lines: inout [String], summary: inout [String], profileID: UUID, ownerID: UUID) async -> Bool {
        guard container.calendarService.currentAuthorization() == .authorized else {
            summary.append("Calendar unavailable — enable it on Home")
            return true
        }
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let events = await container.calendarService.fetchUpcomingEvents(in: DateInterval(start: start, end: end), userID: profileID)
        guard await requireCurrentOwner(ownerID) else { return false }
        lines.append("Today's calendar: " + events.map {
            "\($0.startsAt.formatted(date: .omitted, time: .shortened)): \($0.dressCode?.rawValue ?? "unspecified")"
        }.joined(separator: "; "))
        summary.append("\(events.count) calendar events considered")
        return true
    }

    func prepareInitialSelection(_ requestedIDs: Set<UUID>) {
        let wearableOwnedIDs = Set(items.map(\.id))
        guard !requestedIDs.isEmpty, requestedIDs.count <= 12, requestedIDs.isSubset(of: wearableOwnedIDs) else {
            selectedItemIDs = []
            error = "Those pieces aren't all available in your wearable closet. Choose available pieces and try again."
            return
        }
        selectedItemIDs = requestedIDs
    }
}
