import Foundation
import Testing
@testable import AstraStyle

@Suite("Calendar context for daily styling")
struct ScheduleSnapshotBuilderTests {
    @Test("No upcoming events produces an empty summary")
    func emptyScheduleHasNoFormalityOrHeadline() {
        let snapshot = ScheduleSnapshotBuilder.build(from: [])

        #expect(snapshot.eventCount == 0)
        #expect(snapshot.earliestFormalityLevel == nil)
        #expect(snapshot.headline == nil)
    }

    @Test("The nearest event determines formality and event titles stay off the wire")
    func nearestEventSetsFormalityWithoutSendingDetails() throws {
        let nearest = event(
            title: "Private dinner reservation",
            startsIn: 60 * 60,
            dressCode: .casual
        )
        let later = event(
            title: "Private gala invitation",
            startsIn: 2 * 60 * 60,
            dressCode: .blackTie
        )

        let snapshot = ScheduleSnapshotBuilder.build(from: [later, nearest])
        let encoded = try JSONEncoder().encode(snapshot)
        let payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(snapshot.eventCount == 2)
        #expect(snapshot.earliestFormalityLevel == .casual)
        #expect(snapshot.headline == "2 events coming up today")
        #expect(Set(payload.keys) == ["event_count", "earliest_formality_level", "headline"])
        #expect(!json.contains("Private"))
    }

    @Test("A single event has a neutral count headline")
    func oneEventHasSingularHeadline() {
        let snapshot = ScheduleSnapshotBuilder.build(from: [event(title: "Client meeting", startsIn: 60)])

        #expect(snapshot.eventCount == 1)
        #expect(snapshot.earliestFormalityLevel == .formal)
        #expect(snapshot.headline == "One event coming up today")
    }

    private func event(title: String, startsIn seconds: TimeInterval, dressCode: DressCode? = nil) -> Occasion {
        Occasion(
            id: UUID(),
            userID: SampleData.userID,
            title: title,
            startsAt: Date.now.addingTimeInterval(seconds),
            location: "Private location",
            dressCode: dressCode,
            source: .calendarSync
        )
    }
}
