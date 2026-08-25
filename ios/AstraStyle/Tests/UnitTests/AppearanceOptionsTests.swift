//
//  AppearanceOptionsTests.swift
//  AstraStyleTests
//
//  The complexion picker used to be Warm / Cool / Olive with a vein hint —
//  a seasonal-analysis instrument that only makes sense on light skin.
//  Depth has to run through Deepest, and every undertone has to be shown
//  on more than a fair complexion, or the row is theatre.
//

import Foundation
import Testing
@testable import AstraStyle

struct AppearanceOptionsTests {
    @Test("Skin tone choices run light through deepest, not a fair-skin cluster")
    func skinToneScaleCoversDeepComplexions() {
        let tones = AppearanceOptions.skinTones
        #expect(tones.count == 6)
        #expect(tones.first?.label == "Light")
        #expect(tones.last?.label == "Deepest")
        #expect(tones.map(\.section) == [
            "Fair to light", "Fair to light",
            "Medium", "Medium",
            "Deep", "Deep",
        ])
        let luminances = tones.map { choice -> Double in
            let hex = choice.hexes[0]
            let red = Double((hex >> 16) & 0xFF)
            let green = Double((hex >> 8) & 0xFF)
            let blue = Double(hex & 0xFF)
            return 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        for index in 1..<luminances.count {
            #expect(
                luminances[index] < luminances[index - 1],
                "\(tones[index].label) should be darker than \(tones[index - 1].label)"
            )
        }
        #expect(
            luminances.last! < luminances.first! / 3,
            "Deepest must be substantially darker than Light"
        )
    }

    @Test("Undertone chips show the same temperature on light and deep skin")
    func undertoneChoicesAreNotFairSkinOnly() {
        for choice in AppearanceOptions.skinUndertoneChoices {
            #expect(choice.hexes.count == 3, "\(choice.label) needs a light, mid, and deep swatch")
            for index in 1..<choice.hexes.count {
                #expect(
                    luminance(choice.hexes[index]) < luminance(choice.hexes[index - 1]),
                    "\(choice.label) swatch \(index) should be deeper than \(index - 1)"
                )
            }
        }
        #expect(AppearanceOptions.skinUndertones == ["Warm", "Neutral", "Cool", "Olive"])
    }

    private func luminance(_ hex: UInt32) -> Double {
        let red = Double((hex >> 16) & 0xFF)
        let green = Double((hex >> 8) & 0xFF)
        let blue = Double(hex & 0xFF)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
