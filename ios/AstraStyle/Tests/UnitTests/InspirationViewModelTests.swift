import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Home inspiration")
struct InspirationViewModelTests {
    @Test("Inspiration is usable without selecting closet pieces")
    func inspirationWithoutCloset() async {
        let model = InspirationViewModel(
            closetOnly: false,
            container: .preview(),
            currentOwnerID: { SampleData.userID }
        )
        #expect(!model.canGenerate)
        await model.prepare()
        #expect(model.canGenerate)
        #expect(model.selectedItemIDs.isEmpty)
        #expect(model.contextSummary.contains("weather"))
        #expect(model.chatPrompt.contains("°F"))
        #expect(!model.chatPrompt.contains("°C"))
    }

    @Test("Closet generation requires selection within the server limit")
    func selectionLimits() async {
        let model = InspirationViewModel(
            closetOnly: true,
            container: .preview(),
            currentOwnerID: { SampleData.userID }
        )
        await model.prepare()
        model.selectedItemIDs = []
        #expect(!model.canGenerate)
        model.selectedItemIDs = Set((0..<13).map { _ in UUID() })
        #expect(!model.canGenerate)
    }

    @Test("Closet picker stays usable when outfit suggestions fail")
    func manualClosetSelectionAfterSuggestionFailure() async {
        let model = InspirationViewModel(
            closetOnly: true,
            container: .preview(outfitRepository: MockOutfitRepository(failsOutfitGeneration: true)),
            currentOwnerID: { SampleData.userID }
        )

        await model.prepare()

        #expect(!model.items.isEmpty)
        #expect(model.selectedItemIDs.isEmpty)
        #expect(model.error?.contains("Choose the pieces") == true)
        model.selectedItemIDs = [model.items[0].id]
        #expect(model.canGenerate)
    }

    @Test("Builder preview preserves the exact wearable owned selection without requesting suggestions")
    func initialOwnedSelectionIsExactAndDoesNotSuggestAgain() async {
        let repository = MockOutfitRepository()
        let chosenIDs: Set<UUID> = [SampleData.closetItems[0].id, SampleData.closetItems[5].id]
        let model = InspirationViewModel(
            closetOnly: true,
            container: .preview(outfitRepository: repository),
            initialItemIDs: chosenIDs,
            currentOwnerID: { SampleData.userID }
        )

        await model.prepare()

        #expect(model.selectedItemIDs == chosenIDs)
        #expect(chosenIDs.isSubset(of: Set(model.items.map(\.id))))
        #expect(model.canGenerate)
        #expect(model.error == nil)
        #expect(await repository.outfitGenerationCount == 0)
    }

    @Test("Builder preview fails closed when any selected ID is no longer wearable and does not suggest replacements")
    func invalidInitialOwnedSelectionDoesNotSuggest() async {
        let repository = MockOutfitRepository()
        let availableID = SampleData.closetItems[0].id
        let missingID = UUID()
        let model = InspirationViewModel(
            closetOnly: true,
            container: .preview(outfitRepository: repository),
            initialItemIDs: [availableID, missingID],
            currentOwnerID: { SampleData.userID }
        )

        await model.prepare()

        #expect(model.selectedItemIDs.isEmpty)
        #expect(!model.canGenerate)
        #expect(model.error?.contains("aren't all available") == true)
        #expect(await repository.outfitGenerationCount == 0)
    }

    @Test("Switching owners after preparation clears prior context and prevents provider requests")
    func ownerSwitchAfterPreparationFailsClosed() async {
        let owner = OwnerProbe(ownerID: SampleData.userID)
        let container = AppContainer.preview()
        guard let studio = container.studioRepository as? MockStudioRepository else {
            Issue.record("Preview container should use the Studio mock")
            return
        }
        let selectedID = SampleData.closetItems[0].id
        let model = InspirationViewModel(
            closetOnly: true,
            container: container,
            initialItemIDs: [selectedID],
            currentOwnerID: { await owner.currentOwnerID() }
        )

        await model.prepare()
        #expect(model.selectedItemIDs == Set([selectedID]))
        owner.ownerID = UUID()
        await model.generate()

        #expect(model.items.isEmpty)
        #expect(model.selectedItemIDs.isEmpty)
        #expect(model.renderedItems.isEmpty)
        #expect(!model.chatPrompt.contains("Wardrobe direction"))
        #expect(!model.canGenerate)
        #expect(await studio.lastGenerationRequest() == nil)
    }

    @Test("Owner change during suspended preparation prevents profile and outfit requests")
    func ownerSwitchDuringPreparationFailsClosed() async {
        let owner = OwnerProbe(ownerID: SampleData.userID)
        owner.suspend(onCall: 2)
        let outfitRepository = MockOutfitRepository()
        let model = InspirationViewModel(
            closetOnly: true,
            container: .preview(outfitRepository: outfitRepository),
            currentOwnerID: { await owner.currentOwnerID() }
        )

        let preparation = Task { await model.prepare() }
        await owner.waitForSuspension()
        owner.ownerID = UUID()
        owner.resume()
        await preparation.value

        #expect(model.items.isEmpty)
        #expect(model.selectedItemIDs.isEmpty)
        #expect(!model.chatPrompt.contains("Wardrobe direction"))
        #expect(model.error?.contains("account changed") == true)
        #expect(await outfitRepository.outfitGenerationCount == 0)
    }

    @Test("Inspiration request keeps the reference-photo consent separate")
    func inspirationRequest() async throws {
        let repository = MockStudioRepository()
        let result = try await repository.startGeneration(.init(
            referenceImagePath: "", inspirationMode: "inspiration",
            inspirationContext: "Rain today", inspirationInstructions: "More casual",
            hasUserConsent: false
        ))
        #expect(result.status == .queued)
        #expect(result.referenceImagePath.isEmpty)
        do {
            _ = try await repository.startGeneration(.init(referenceImagePath: "photo", hasUserConsent: false))
            Issue.record("Reference photos must still require consent")
        } catch {
            #expect(error is AstraError)
        }
    }

    @Test("An authorized weather failure does not ask the user to grant permission again")
    func authorizedWeatherUnavailable() async {
        let weather = CountingWeatherService(authorization: .authorized, fails: true)
        let model = InspirationViewModel(
            closetOnly: false,
            container: .preview(),
            weatherService: weather,
            currentOwnerID: { SampleData.userID }
        )
        await model.prepare()
        #expect(weather.snapshotCalls == 1)
        #expect(model.contextSummary.contains("Weather temporarily unavailable"))
        #expect(!model.contextSummary.contains("Weather unavailable — enable it on Home"))
        #expect(model.chatPrompt.contains("Weather unavailable. Do not invent conditions."))
    }

    @Test("Inspiration does not fetch weather before permission is granted")
    func weatherPermissionGate() async {
        for authorization in [WeatherLocationAuthorization.denied, .notDetermined] {
            let weather = CountingWeatherService(authorization: authorization)
            let model = InspirationViewModel(
                closetOnly: false,
                container: .preview(),
                weatherService: weather,
                currentOwnerID: { SampleData.userID }
            )

            await model.prepare()

            #expect(weather.snapshotCalls == 0)
            #expect(model.chatPrompt.contains("Weather unavailable"))
        }
    }
}

private final class CountingWeatherService: WeatherService, @unchecked Sendable {
    private let lock = NSLock()
    private let authorization: WeatherLocationAuthorization
    private var calls = 0
    private let fails: Bool

    init(authorization: WeatherLocationAuthorization, fails: Bool = false) {
        self.authorization = authorization
        self.fails = fails
    }

    var snapshotCalls: Int {
        lock.withLock { calls }
    }

    func currentAuthorization() -> WeatherLocationAuthorization { authorization }
    func requestLocationPermissionIfNeeded() async -> Bool { false }

    func currentSnapshot() async throws -> WeatherSnapshot {
        lock.withLock { calls += 1 }
        if fails { throw AstraError.network("Weather fixture unavailable") }
        return SampleData.weatherSnapshot
    }
}
@MainActor
private final class OwnerProbe {
    var ownerID: UUID?
    private var calls = 0
    private var suspendedCall: Int?
    private var continuation: CheckedContinuation<Void, Never>?

    init(ownerID: UUID?) {
        self.ownerID = ownerID
    }

    func currentOwnerID() async -> UUID? {
        calls += 1
        if calls == suspendedCall {
            await withCheckedContinuation { continuation = $0 }
            suspendedCall = nil
        }
        return ownerID
    }

    func suspend(onCall call: Int) {
        suspendedCall = call
    }

    func waitForSuspension() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
