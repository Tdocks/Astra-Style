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

    init(closetOnly: Bool, container: AppContainer) {
        self.closetOnly = closetOnly
        self.container = container
    }

    var canGenerate: Bool {
        !isPreparing && !isGenerating && !context.isEmpty && (!closetOnly || (!selectedItemIDs.isEmpty && selectedItemIDs.count <= 12))
    }

    func prepare() async {
        guard isPreparing else { return }
        await refreshQuota()
        defer { isPreparing = false }
        do {
            let profile = try await container.profileRepository.fetchCurrentProfile()
            let style = try await container.profileRepository.fetchStyleProfile()
            var lines = ["Date: \(Date.now.formatted(date: .complete, time: .omitted))"]
            lines.append("Wardrobe direction: \(profile.wardrobeGraph.rawValue)")
            if let style {
                lines.append("Style: \(style.styleSummary ?? style.primaryIdentity?.rawValue ?? "unspecified")")
                lines.append("Preferred colors: \(style.preferredColors.joined(separator: ", ")); avoid: \(style.avoidedColors.joined(separator: ", "))")
                lines.append("Fit: \(style.preferredFit?.rawValue ?? "unspecified"); formality: \(style.formalityPreference?.rawValue ?? "unspecified")")
                if let data = try? JSONEncoder().encode(style.preferenceVector), let vector = String(data: data, encoding: .utf8) {
                    lines.append("Quiz preferences with confidence (unmeasured dimensions are unknown): \(vector)")
                }
            }
            var summary: [String] = []
            if container.weatherService.currentAuthorization() == .authorized,
               let weather = try? await container.weatherService.currentSnapshot() {
                lines.append("Weather: \(weather.condition.rawValue), \(weather.temperatureLow)–\(weather.temperatureHigh) °C; precipitation probability \(weather.precipitationChance.map(String.init(describing:)) ?? "unknown"); season \(weather.season?.rawValue ?? "unknown")")
                summary.append("Current weather included")
            } else {
                lines.append("Weather unavailable. Do not invent conditions.")
                summary.append("Weather unavailable — enable it on Home")
            }
            if container.calendarService.currentAuthorization() == .authorized {
                let start = Calendar.current.startOfDay(for: .now)
                let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
                let events = await container.calendarService.fetchUpcomingEvents(in: DateInterval(start: start, end: end), userID: profile.id)
                // Share dress codes and timing only; calendar titles stay on device.
                lines.append("Today's calendar: " + events.map { "\($0.startsAt.formatted(date: .omitted, time: .shortened)): \($0.dressCode?.rawValue ?? "unspecified")" }.joined(separator: "; "))
                summary.append("\(events.count) calendar events considered")
            } else {
                summary.append("Calendar unavailable — enable it on Home")
            }
            context = String(lines.joined(separator: "\n").prefix(6000))
            contextSummary = summary.joined(separator: " · ")
            if closetOnly {
                items = try await container.closetRepository.fetchItems().filter { !$0.isArchived && $0.isWearableToday }
                let recommendations = try await container.outfitRepository.generateOutfits(.init(naturalLanguageRequest: String(("What should I wear today? Use only my closet. " + context).prefix(500)), desiredCount: 1))
                selectedItemIDs = Set(recommendations.first?.itemIDs ?? [])
                selectedItemIDs.formIntersection(Set(items.map(\.id)))
                if selectedItemIDs.isEmpty { error = "Choose the pieces you want to include below." }
            }
        } catch {
            self.error = (error as? AstraError)?.message ?? "Couldn't load your style context. Close and try again."
            contextSummary = "Some context couldn't load"
        }
    }

    func generate(adjustment quickAdjustment: String? = nil) async {
        guard canGenerate else { return }
        let newAdjustment = (quickAdjustment ?? adjustment).trimmingCharacters(in: .whitespacesAndNewlines)
        if !newAdjustment.isEmpty { adjustments.append(newAdjustment) }
        adjustment = ""
        isGenerating = true
        error = nil
        let sourceID = (!newAdjustment.isEmpty || Set(renderedItems.map(\.id)) != selectedItemIDs) && lastCompletedJob != nil ? lastCompletedJob?.id : nil
        job = nil
        defer { isGenerating = false }
        do {
            let request = StudioGenerationRequest(
                referenceImagePath: "",
                sourceGenerationID: sourceID,
                inspirationMode: closetOnly ? "closet_inspiration" : "inspiration",
                inspirationContext: context,
                inspirationInstructions: String(adjustments.joined(separator: "; then ").suffix(1500)),
                adHocItemIDs: closetOnly ? Array(selectedItemIDs).sorted { $0.uuidString < $1.uuidString } : [],
                hasUserConsent: false
            )
            let initial = try await container.studioRepository.startGeneration(request)
            await refreshQuota()
            job = initial
            pendingItems = items.filter { selectedItemIDs.contains($0.id) }
            try await finish(initial)
        } catch { handle(error) }
    }

    func retry() async {
        guard !isGenerating, let job else { return }
        isGenerating = true
        error = nil
        imageURL = nil
        defer { isGenerating = false }
        do {
            let next = job.status == .failed && job.isRetryableWithoutCharge
                ? try await container.studioRepository.retryGeneration(id: job.id) : job
            try await finish(next)
        } catch { handle(error) }
    }

    var chatPrompt: String {
        "Help me refine today's \(closetOnly ? "closet-only look" : "style inspiration"). " +
        (closetOnly ? "Use only these owned pieces: " + renderedItems.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") + ". " : "") +
        "Style adjustments so far: " + adjustments.joined(separator: "; ") + ". Current request: " + adjustment + ". " + context
    }

    func refreshQuota() async {
        do { quotaSummary = try await container.studioRepository.fetchQuota().summary } catch { quotaSummary = "Couldn't load your preview allowance. Try again." }
    }

    func clearPaywall() { pendingPaywall = nil }

    private func finish(_ initial: StudioGeneration) async throws {
        var current = initial
        let deadline = ContinuousClock.now + .seconds(180)
        while current.status == .queued || current.status == .generating {
            job = current
            guard ContinuousClock.now < deadline else { throw AstraError.network("This image is still processing. Try checking again.") }
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()
            current = try await container.studioRepository.fetchStatus(generationID: current.id)
        }
        job = current
        guard current.status == .complete, let path = current.resultImagePath else {
            throw AstraError.provider(current.errorMessage ?? "The image couldn't finish. Please try again.")
        }
        imageURL = try await container.closetImageURLResolver.resolve(storagePath: path)
        lastCompletedJob = current
        renderedItems = pendingItems
    }

    private func handle(_ error: Error) {
        if let error = error as? AstraError {
            self.error = error.message
            if error.category == .rateLimited && error.message.contains("free visual") { pendingPaywall = .studioQuota }
        } else if error is CancellationError {
            self.error = "Generation paused. Check again to resume."
        } else {
            self.error = "Couldn't finish this image. Please try again."
        }
    }
}
