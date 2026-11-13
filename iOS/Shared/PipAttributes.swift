import ActivityKit
import Foundation

/// What the Dynamic Island shows. The state changes when you pet, feed or put Pip to bed.
struct PipAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var mood: PipMood
        var season: PipSeason
        var line: String
        var hearts: Int
    }
    var species: PipSpecies
}
