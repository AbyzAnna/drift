import SwiftUI

/// The animals Pip can be. Each has its own 3D-rendered images in Pip.xcassets.
enum PipSpecies: String, CaseIterable, Codable, Hashable, Identifiable {
    case bunny, penguin, lamb, otter, seal, hedgehog
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bunny: return "Bunny"
        case .penguin: return "Penguin chick"
        case .lamb: return "Lamb"
        case .otter: return "Otter pup"
        case .seal: return "Seal pup"
        case .hedgehog: return "Hedgehog"
        }
    }

    var snack: String {
        switch self {
        case .bunny: return "a crunchy carrot"
        case .penguin: return "a tiny fish"
        case .lamb: return "fresh clover"
        case .otter: return "a little clam"
        case .seal: return "a sardine"
        case .hedgehog: return "a juicy berry"
        }
    }
}

/// Weather themes. Each one dresses Pip in its own outfit.
enum PipSeason: String, CaseIterable, Codable, Hashable, Identifiable {
    case snow, autumn, sakura, flowers, spring, stardust
    var id: String { rawValue }

    var title: String {
        switch self {
        case .snow: return "Snow"
        case .autumn: return "Autumn"
        case .sakura: return "Sakura"
        case .flowers: return "Flowers"
        case .spring: return "Spring"
        case .stardust: return "Stardust"
        }
    }

    var symbol: String {
        switch self {
        case .snow: return "snowflake"
        case .autumn: return "leaf.fill"
        case .sakura: return "camera.macro"
        case .flowers: return "sun.max.fill"
        case .spring: return "wind"
        case .stardust: return "sparkles"
        }
    }

    /// Image set name for Pip's outfit in this season.
    var look: String {
        switch self {
        case .stardust: return "plain"
        default: return rawValue
        }
    }

    var tint: Color {
        switch self {
        case .snow: return Color(red: 0.62, green: 0.82, blue: 1.0)
        case .autumn: return Color(red: 1.0, green: 0.62, blue: 0.28)
        case .sakura: return Color(red: 1.0, green: 0.68, blue: 0.80)
        case .flowers: return Color(red: 1.0, green: 0.84, blue: 0.40)
        case .spring: return Color(red: 0.55, green: 0.86, blue: 0.48)
        case .stardust: return Color(red: 0.78, green: 0.72, blue: 1.0)
        }
    }

    var sky: [Color] {
        switch self {
        case .snow: return [Color(red: 0.05, green: 0.09, blue: 0.24), Color(red: 0.16, green: 0.29, blue: 0.52)]
        case .autumn: return [Color(red: 0.20, green: 0.09, blue: 0.10), Color(red: 0.62, green: 0.30, blue: 0.16)]
        case .sakura: return [Color(red: 0.36, green: 0.22, blue: 0.40), Color(red: 0.93, green: 0.66, blue: 0.74)]
        case .flowers: return [Color(red: 0.25, green: 0.36, blue: 0.62), Color(red: 0.98, green: 0.78, blue: 0.62)]
        case .spring: return [Color(red: 0.16, green: 0.38, blue: 0.48), Color(red: 0.62, green: 0.86, blue: 0.70)]
        case .stardust: return [Color(red: 0.03, green: 0.02, blue: 0.10), Color(red: 0.18, green: 0.12, blue: 0.36)]
        }
    }

    static var current: PipSeason {
        switch Calendar.current.component(.month, from: Date()) {
        case 12, 1, 2: return .snow
        case 3, 4: return .sakura
        case 5: return .spring
        case 6, 7, 8: return .flowers
        default: return .autumn
        }
    }
}

enum PipMood: String, Codable, Hashable {
    case open, closed, happy, surprised
}

/// Asset name for a rendered Pip, e.g. "bunny_snow_happy" (whole body) or "bunny_snow_happy_head".
func pipImage(_ species: PipSpecies, _ season: PipSeason, _ mood: PipMood, head: Bool = false) -> String {
    "\(species.rawValue)_\(season.look)_\(mood.rawValue)" + (head ? "_head" : "")
}
