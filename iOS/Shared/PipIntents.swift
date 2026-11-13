import ActivityKit
import AppIntents
import Foundation

/// Starts, stops and updates Pip's Live Activity (the Dynamic Island and Lock Screen).
enum IslandPip {
    static var isRunning: Bool { !Activity<PipAttributes>.activities.isEmpty }

    static func greeting() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning!"
        case 12..<18: return "Hi! I live up here now."
        case 18..<22: return "Cozy evening, isn't it?"
        default: return "It's late… sleepy time soon."
        }
    }

    static func start(species: PipSpecies, season: PipSeason) async {
        await stop()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = PipAttributes.ContentState(mood: .happy, season: season, line: greeting(), hearts: 0)
        _ = try? Activity.request(attributes: PipAttributes(species: species),
                                  content: ActivityContent(state: state, staleDate: nil),
                                  pushType: nil)
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        await update { if $0.mood == .happy { $0.mood = .open } }
    }

    static func stop() async {
        for a in Activity<PipAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func update(_ change: (inout PipAttributes.ContentState) -> Void) async {
        for a in Activity<PipAttributes>.activities {
            var s = a.content.state
            change(&s)
            await a.update(ActivityContent(state: s, staleDate: nil))
        }
    }

    static func setSeason(_ season: PipSeason) async {
        await update { $0.season = season }
    }

    static func pet() async {
        let lines = ["Hehe, that tickles!", "More pats please ♡", "I love you too!", "Purr… so cozy."]
        await update { $0.mood = .happy; $0.hearts += 1; $0.line = lines.randomElement() ?? "♡" }
        await settle()
    }

    static func feed(_ species: PipSpecies) async {
        await update { $0.mood = .happy; $0.hearts += 1; $0.line = "Nom nom, \(species.snack)!" }
        await settle()
    }

    static func toggleNap() async {
        var sleeping = false
        for a in Activity<PipAttributes>.activities { sleeping = a.content.state.mood == .closed }
        if sleeping {
            await update { $0.mood = .surprised; $0.line = "Oh! I'm awake, I'm awake!" }
            await settle()
        } else {
            await update { $0.mood = .closed; $0.line = "Zzz… wake me with a tap." }
        }
    }

    /// Goes back to a calm face a few seconds after a reaction.
    private static func settle() async {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await update { if $0.mood != .closed { $0.mood = .open } }
    }
}

// Buttons in the expanded Dynamic Island and on the Lock Screen run these without opening the app.

struct PetPipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pet Pip"
    init() {}
    func perform() async throws -> some IntentResult {
        await IslandPip.pet()
        return .result()
    }
}

struct FeedPipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Give Pip a snack"
    @Parameter(title: "Animal") var species: String
    init() { species = PipSpecies.bunny.rawValue }
    init(species: PipSpecies) { self.species = species.rawValue }
    func perform() async throws -> some IntentResult {
        await IslandPip.feed(PipSpecies(rawValue: species) ?? .bunny)
        return .result()
    }
}

struct NapPipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Put Pip to bed"
    init() {}
    func perform() async throws -> some IntentResult {
        await IslandPip.toggleNap()
        return .result()
    }
}
