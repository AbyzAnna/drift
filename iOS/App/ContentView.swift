import ActivityKit
import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("species") private var speciesRaw = PipSpecies.bunny.rawValue
    @AppStorage("season") private var seasonRaw = PipSeason.current.rawValue
    @State private var mood: PipMood = .open
    @State private var line = "Hi! I'm Pip."
    @State private var hearts: [Heart] = []
    @State private var islandOn = false
    @State private var squish = false
    @State private var breathe = false
    @State private var reacting = false
    @State private var lastDragX: CGFloat = 0
    @StateObject private var field = Field()
    @AppStorage("pip3D") private var pip3DOn = true
    @State private var pip3D = Pip3DController()

    private var species: PipSpecies { PipSpecies(rawValue: speciesRaw) ?? .bunny }
    private var season: PipSeason { PipSeason(rawValue: seasonRaw) ?? .snow }
    /// Animals with a 3D model (Pip3D_<species>.usdz) are shown in 3D unless switched off.
    private var has3D: Bool { Pip3DController.hasModel(species) }
    private var show3D: Bool { has3D && pip3DOn }

    var body: some View {
        ZStack {
            LinearGradient(colors: season.sky, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: seasonRaw)

            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    field.step(now: tl.date, size: size, season: season)
                    field.draw(&ctx, size: size, season: season, time: tl.date.timeIntervalSinceReferenceDate)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Text("Drift")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                Text("Tilt your phone. Shake it. Tap Pip.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))

                Spacer(minLength: 8)
                bubble
                pip
                Spacer(minLength: 8)

                speciesPicker
                seasonPicker.padding(.top, 10)
                islandButton.padding(.top, 14).padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            field.start()
            field.onShake = {
                pip3D.spin()
                react(.surprised, "Whoa! Everything's spinning!")
            }
            let f = field
            pip3D.tilt = { [weak f] in (f?.gx ?? 0, f?.gy ?? 1) }
            pip3D.setRim(season.tint)
            islandOn = IslandPip.isRunning
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        }
        .task { await blinkLoop() }
        .onChange(of: speciesRaw) { _, _ in
            react(.happy, "Hello! I'm a \(species.title.lowercased()) now.")
            pip3D.show(species)
            pip3D.hop()
            if islandOn { Task { await IslandPip.start(species: species, season: season) } }
        }
        .onChange(of: seasonRaw) { _, _ in
            react(.happy, seasonLine)
            pip3D.setRim(season.tint)
            pip3D.hop()
            if islandOn { Task { await IslandPip.setSeason(season) } }
        }
    }

    // MARK: pieces

    private var bubble: some View {
        Text(line)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .foregroundStyle(Color(white: 0.15))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.white.opacity(0.92), in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            .id(line)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: line)
    }

    private var pip: some View {
        ZStack {
            // soft contact shadow
            Ellipse()
                .fill(.black.opacity(show3D ? 0 : 0.28))
                .frame(width: 150, height: 22)
                .blur(radius: 8)
                .offset(y: 150)
            if show3D {
                Pip3DView(controller: pip3D)
                    .onAppear { pip3D.show(species) }
                    .frame(height: 340)
                    .contentShape(Rectangle())
                    .onTapGesture { pet() }
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { g in
                                pip3D.drag(g.translation.width - lastDragX)
                                lastDragX = g.translation.width
                            }
                            .onEnded { g in
                                pip3D.endDrag(g.velocity.width / 60)
                                lastDragX = 0
                            }
                    )
                    .transition(.opacity)
            } else {
                Image(pipImage(species, season, mood))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 320)
                    .scaleEffect(x: squish ? 1.08 : 1, y: squish ? 0.9 : (breathe ? 1.015 : 1), anchor: .bottom)
                    .animation(.spring(response: 0.25, dampingFraction: 0.45), value: squish)
                    .onTapGesture { pet() }
            }
            if has3D {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { pip3DOn.toggle() }
                    if pip3DOn { pip3D.hop() }
                } label: {
                    Text(pip3DOn ? "3D" : "2D")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                }
                .accessibilityLabel(pip3DOn ? "Show 2D Pip" : "Show 3D Pip")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            ForEach(hearts) { h in
                HeartView(heart: h)
            }
        }
        .frame(height: 340)
    }

    private var speciesPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PipSpecies.allCases) { s in
                    Button {
                        speciesRaw = s.rawValue
                    } label: {
                        Image(Pip3DController.hasModel(s) && pip3DOn ? "\(s.rawValue)_3d_thumb" : pipImage(s, season, .open, head: true))
                            .resizable().scaledToFit()
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(s == species ? 0.3 : 0.1), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(s == species ? 0.9 : 0), lineWidth: 2))
                    }
                    .accessibilityLabel(s.title)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var seasonPicker: some View {
        HStack(spacing: 6) {
            ForEach(PipSeason.allCases) { s in
                Button {
                    withAnimation { seasonRaw = s.rawValue }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: s.symbol).font(.system(size: 17))
                        Text(s.title).font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(s == season ? Color(white: 0.12) : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(s == season ? AnyShapeStyle(s.tint) : AnyShapeStyle(Color.white.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var islandButton: some View {
        Button {
            Task {
                if islandOn {
                    await IslandPip.stop()
                    islandOn = false
                    react(.happy, "I'm back home!")
                } else {
                    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                        line = "Turn on Live Activities for Drift in Settings first."
                        return
                    }
                    react(.happy, "Look up! I'm in the Dynamic Island.")
                    await IslandPip.start(species: species, season: season)
                    islandOn = IslandPip.isRunning
                }
            }
        } label: {
            Label(islandOn ? "Bring Pip back" : "Put Pip in the Dynamic Island",
                  systemImage: islandOn ? "house.fill" : "capsule.fill")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color(white: 0.1))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(.white, in: Capsule())
                .shadow(color: season.tint.opacity(0.6), radius: 12)
        }
    }

    // MARK: behaviour

    private var seasonLine: String {
        switch season {
        case .snow: return "Snow! Shake the phone for a blizzard."
        case .autumn: return "Crunchy leaves everywhere!"
        case .sakura: return "Sakura season, so pretty."
        case .flowers: return "I made a flower crown!"
        case .spring: return "Dandelion fluff, make a wish!"
        case .stardust: return "Look at all the stars…"
        }
    }

    private func pet() {
        squish = true
        if show3D { pip3D.hop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { squish = false }
        hearts.append(Heart())
        if hearts.count > 24 { hearts.removeFirst(12) }
        let lines = ["Hehe, that tickles!", "More pats please ♡", "I love you too!", "So cozy…"]
        react(.happy, lines.randomElement() ?? "♡")
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if islandOn { Task { await IslandPip.update { $0.hearts += 1 } } }
    }

    private func react(_ m: PipMood, _ text: String) {
        reacting = true
        mood = m
        line = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if mood == m { mood = .open }
            reacting = false
        }
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2.5...5.0) * 1_000_000_000))
            guard mood == .open, !reacting else { continue }
            mood = .closed
            try? await Task.sleep(nanoseconds: 140_000_000)
            if mood == .closed { mood = .open }
        }
    }
}

struct Heart: Identifiable {
    let id = UUID()
    let dx = Double.random(in: -60...60)
}

struct HeartView: View {
    let heart: Heart
    @State private var up = false
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 26))
            .foregroundStyle(.pink)
            .shadow(color: .pink.opacity(0.6), radius: 6)
            .offset(x: heart.dx * (up ? 1.2 : 0.4), y: up ? -190 : -60)
            .opacity(up ? 0 : 1)
            .scaleEffect(up ? 1.3 : 0.6)
            .onAppear { withAnimation(.easeOut(duration: 1.3)) { up = true } }
    }
}
