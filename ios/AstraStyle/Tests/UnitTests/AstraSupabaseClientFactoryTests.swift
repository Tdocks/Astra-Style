import Foundation
import Supabase
import Testing
@testable import AstraStyle

@Suite("Supabase client local QA auth storage")
struct AstraSupabaseClientFactoryTests {
    @Test("Separate local clients share process-only session storage")
    func localClientsShareVolatileAuthStorage() throws {
        let firstClientStorage = AstraSupabaseClientFactory.localQAAuthStorage()
        let secondClientStorage = AstraSupabaseClientFactory.localQAAuthStorage()
        let key = "local-qa-storage-sharing-test"
        let marker = Data("session-marker".utf8)

        try firstClientStorage.store(key: key, value: marker)
        defer { try? secondClientStorage.remove(key: key) }

        #expect(try secondClientStorage.retrieve(key: key) == marker)
    }
}
