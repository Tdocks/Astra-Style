import XCTest

@MainActor
final class VoiceOverAcceptanceUITests: XCTestCase {
    private let app = XCUIApplication()

    func testVoiceOverSpeaksPrimaryScreens() throws {
        #if compiler(>=6.4)
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires the installed iOS 27 VoiceOver test service") }
        app.launchArguments = ["-astra-reset-state", "-astra-mock-backend", "-astra-skip-onboarding",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 30))
        let voice = XCUIDevice.shared.voiceOverService
        defer { try? voice.disable() }
        for tab in ["Home", "Closet", "Studio"] {
            if voice.isEnabled { try voice.disable() }
            app.tapChromeTab(tab)
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
            try voice.enable()
            XCTAssertTrue(voice.isEnabled)
            var spoken: [String] = []
            for _ in 0..<12 {
                let output = try voice.moveForward()
                spoken.append(output.utterance)
            }
            XCTAssertFalse(spoken.isEmpty, "VoiceOver produced no speech on \(tab)")
            XCTAssertTrue(spoken.contains { $0.localizedCaseInsensitiveContains("button") },
                          "VoiceOver did not identify actionable controls on \(tab)")
            let transcript = XCTAttachment(string: spoken.joined(separator: "\n"))
            transcript.name = "VoiceOver-\(tab)"
            transcript.lifetime = .keepAlways
            add(transcript)
        }
        #else
        throw XCTSkip("VoiceOver speech acceptance requires Xcode 27")
        #endif
    }
}
