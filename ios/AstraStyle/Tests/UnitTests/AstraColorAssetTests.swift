import Testing
import UIKit
@testable import AstraStyle

private struct ColorExpectation {
    let name: String
    let dark: UInt32
    let light: UInt32
}

@Suite("Astra adaptive Asset Catalog colors")
struct AstraColorAssetTests {
    private let palette: [ColorExpectation] = [
        ColorExpectation(name: "AstraBackgroundPrimary", dark: 0x0D0D0D, light: 0xF8F5EF),
        ColorExpectation(name: "AstraBackgroundSecondary", dark: 0x151515, light: 0xEFEAE1),
        ColorExpectation(name: "AstraSurfaceElevated", dark: 0x1B1B1B, light: 0xFFFFFF),
        ColorExpectation(name: "AstraSurfaceMarble", dark: 0x0D0D0D, light: 0x0D0D0D),
        ColorExpectation(name: "AstraTextPrimary", dark: 0xF7F3EA, light: 0x111111),
        ColorExpectation(name: "AstraTextSecondary", dark: 0xB9B3A8, light: 0x56514B),
        ColorExpectation(name: "AstraTextMuted", dark: 0x88847C, light: 0x746E66),
        ColorExpectation(name: "AstraTextOnAccent", dark: 0x14110A, light: 0x14110A),
        ColorExpectation(name: "AstraAccentChampagne", dark: 0xD7B46A, light: 0xAB8545),
        ColorExpectation(name: "AstraAccentChampagnePressed", dark: 0xB8944D, light: 0x9C7B42),
        ColorExpectation(name: "AstraAccentChampagneAccessible", dark: 0xD7B46A, light: 0x8A6A2E),
        ColorExpectation(name: "AstraDivider", dark: 0x2A2927, light: 0xDDD6CB),
        ColorExpectation(name: "AstraSuccessOlive", dark: 0x69745D, light: 0x4E5744),
        ColorExpectation(name: "AstraWarningAmber", dark: 0xA98652, light: 0x7E6339),
        ColorExpectation(name: "AstraDestructive", dark: 0xB65F59, light: 0x9B4F4A)
    ]

    @Test("Every design-system token resolves to its exact dark and light specification values")
    func everyColorMatchesBothAppearances() throws {
        for token in palette {
            try expectColor(token.name, appearance: .dark, equals: token.dark)
            try expectColor(token.name, appearance: .light, equals: token.light)
        }
    }

    private func expectColor(
        _ name: String,
        appearance: UIUserInterfaceStyle,
        equals expected: UInt32
    ) throws {
        let traits = UITraitCollection(userInterfaceStyle: appearance)
        let color = try #require(
            UIColor(named: name, in: Bundle.main, compatibleWith: traits),
            "Missing color asset \(name)"
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #expect(color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let actual = UInt32((red * 255).rounded()) << 16 |
            UInt32((green * 255).rounded()) << 8 |
            UInt32((blue * 255).rounded())
        #expect(alpha == 1)
        #expect(actual == expected, "\(name) \(appearance) asset hex mismatch")
    }
}
