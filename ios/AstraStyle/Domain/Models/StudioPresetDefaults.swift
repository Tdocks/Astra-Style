import Foundation

/// Defaults fill the controls on selection; every field remains editable.
/// Palette describes the scene's mood, never recolors owned garments.
public struct StudioPresetDefaults: Sendable, Equatable {
    public let background: StudioBackground
    public let pose: StudioPose
    public let formality: FormalityLevel
    public let season: Season?
    public let palette: [String]
}

public extension StudioPromptPreset {
    var controlDefaults: StudioPresetDefaults {
        switch self {
        case .smartCasual:
            StudioPresetDefaults(background: .studio, pose: .standingFront,
                                 formality: .balanced, season: nil, palette: ["navy", "cream"])
        case .dateNight:
            StudioPresetDefaults(background: .urban, pose: .standingThreeQuarter,
                                 formality: .balanced, season: nil, palette: ["charcoal", "burgundy"])
        case .wedding:
            StudioPresetDefaults(background: .editorialOutdoor, pose: .standingThreeQuarter,
                                 formality: .veryFormal, season: nil, palette: ["navy", "ivory"])
        case .vacation:
            StudioPresetDefaults(background: .editorialOutdoor, pose: .walking,
                                 formality: .casual, season: .summer, palette: ["sand", "sky blue"])
        case .executive:
            StudioPresetDefaults(background: .studio, pose: .standingFront,
                                 formality: .formal, season: nil, palette: ["navy", "charcoal"])
        case .oldMoneyInspired:
            StudioPresetDefaults(background: .editorialOutdoor, pose: .standingThreeQuarter,
                                 formality: .balanced, season: nil, palette: ["cream", "forest green"])
        case .minimalist:
            StudioPresetDefaults(background: .neutral, pose: .standingFront,
                                 formality: .balanced, season: nil, palette: ["black", "white"])
        case .nightOut:
            StudioPresetDefaults(background: .urban, pose: .walking,
                                 formality: .balanced, season: nil, palette: ["black", "midnight blue"])
        }
    }
}
