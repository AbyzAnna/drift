import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct IslandBundle: WidgetBundle {
    var body: some Widget {
        PipLiveActivity()
    }
}

struct PipLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PipAttributes.self) { ctx in
            LockScreenPip(species: ctx.attributes.species, state: ctx.state)
                .activityBackgroundTint(Color.black.opacity(0.25))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            let sp = ctx.attributes.species
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PipPicture(name: pipImage(sp, s.season, s.mood))
                        .frame(width: 70, height: 84)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HeartCount(count: s.hearts, tint: s.season.tint)
                        .padding(.trailing, 6)
                        .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pip the \(sp.title.lowercased())")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                        Text(s.line)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PipButtons(species: sp, state: s)
                        .padding(.top, 2)
                }
            } compactLeading: {
                PipPicture(name: pipImage(sp, s.season, s.mood, head: true))
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
            } compactTrailing: {
                if s.mood == .closed {
                    Text("z").font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(s.season.tint)
                } else if s.mood == .happy {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                } else {
                    Image(systemName: s.season.symbol).foregroundStyle(s.season.tint)
                }
            } minimal: {
                PipPicture(name: pipImage(sp, s.season, s.mood, head: true))
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
            }
            .keylineTint(s.season.tint)
        }
    }
}

/// A rendered Pip image that cross-fades when Pip's face or outfit changes.
struct PipPicture: View {
    let name: String
    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .id(name)
            .transition(.opacity)
    }
}

struct HeartCount: View {
    let count: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill").foregroundStyle(.pink)
            Text("\(count)").monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
    }
}

struct PipButtons: View {
    let species: PipSpecies
    let state: PipAttributes.ContentState
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: PetPipIntent()) {
                ButtonFace(title: "Pet", symbol: "hand.raised.fill", tint: state.season.tint)
            }
            Button(intent: FeedPipIntent(species: species)) {
                ButtonFace(title: "Snack", symbol: "fork.knife", tint: state.season.tint)
            }
            Button(intent: NapPipIntent()) {
                ButtonFace(title: state.mood == .closed ? "Wake" : "Nap",
                           symbol: state.mood == .closed ? "sun.max.fill" : "moon.zzz.fill",
                           tint: state.season.tint)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ButtonFace: View {
    let title: String
    let symbol: String
    let tint: Color
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(tint.opacity(0.28), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 0.5))
    }
}

struct LockScreenPip: View {
    let species: PipSpecies
    let state: PipAttributes.ContentState
    var body: some View {
        HStack(spacing: 12) {
            PipPicture(name: pipImage(species, state.season, state.mood))
                .frame(width: 84, height: 100)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pip the \(species.title.lowercased())")
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    HeartCount(count: state.hearts, tint: state.season.tint)
                }
                Text(state.line)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                PipButtons(species: species, state: state)
            }
            .foregroundStyle(.white)
        }
        .padding(14)
        .background(
            LinearGradient(colors: state.season.sky, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}
