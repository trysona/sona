import SwiftUI

/// Animation d'ouverture. Elle commence comme l'écran de lancement système (même « S », 72 pt, au centre de
/// l'écran) : le « S » se ramasse, grandit, bat en tranches comme un égaliseur, se recale d'un coup (onde et
/// vibration), puis « Sona » monte lettre par lettre. Avec `leaving`, le « S » fonce vers l'écran et laisse voir
/// l'app (voir `EncreApp`). « Réduire les animations » : logo et nom fixes, simple fondu.
struct LaunchSplashView: View {
    /// Durée de l'intro avant que la sortie puisse commencer.
    static let introSeconds = 1.8
    /// Instant où le « S » se recale : onde et vibration.
    private static let landing = 1.15
    private static let logoSize: CGFloat = 72
    private static let slices = 7

    var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var landed = false

    var body: some View {
        ZStack {
            Color.black

            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = reduceMotion ? Self.introSeconds : timeline.date.timeIntervalSince(start)
                ZStack {
                    wave(at: t)
                    logo(at: t)
                        .scaleEffect(leaving && !reduceMotion ? 11 : 1)
                        .animation(.easeIn(duration: 0.45), value: leaving)
                    title(at: t)
                        .offset(y: 112)
                        .opacity(leaving ? 0 : 1)
                        .animation(.easeOut(duration: 0.15), value: leaving)
                    // Le compte se vérifie encore après l'intro : on le montre.
                    ProgressView()
                        .tint(.white)
                        .offset(y: 210)
                        .opacity(!leaving && t > Self.introSeconds + 0.4 && !reduceMotion ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Sur toute la vue : le centre est celui de l'écran, comme au lancement système (sinon le logo sautait).
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .animation(.easeIn(duration: 0.3).delay(0.15), value: leaving)
        .sensoryFeedback(.impact(weight: .medium), trigger: landed)
        .task {
            start = Date()
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(Self.landing))
            landed = true
        }
        .accessibilityHidden(true)
    }

    /// Avancement de 0 à 1 entre deux instants.
    private func ramp(_ t: Double, _ from: Double, _ to: Double) -> Double {
        min(1, max(0, (t - from) / (to - from)))
    }

    private func logo(at t: Double) -> some View {
        // Se ramasse, puis jaillit en dépassant un peu sa taille finale.
        let squeeze = ramp(t, 0, 0.18)
        let back = ramp(t, 0.18, 0.62) - 1
        let overshoot = 1 + 2.7 * back * back * back + 1.7 * back * back
        let scale = t < 0.18 ? 1 - 0.18 * squeeze : 0.82 + 0.83 * overshoot
        // Force du battement : monte puis retombe à zéro à l'instant `landing`.
        let beat = sin(.pi * ramp(t, 0.4, Self.landing))
        let flash = t < Self.landing ? 0 : 1 - ramp(t, Self.landing, Self.landing + 0.5)
        let size = Self.logoSize
        let slice = size / CGFloat(Self.slices)

        return ZStack {
            if beat > 0.01 {
                ForEach(0..<Self.slices, id: \.self) { index in
                    mark
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: slice + 0.5).offset(x: CGFloat(index) * slice)
                        }
                        .offset(y: CGFloat(beat * 13 * sin(t * 17 + Double(index) * 0.95)))
                }
            } else {
                mark
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .white.opacity(0.12 * ramp(t, 0.3, 0.8) + 0.45 * flash), radius: 8 + 14 * CGFloat(flash))
        .scaleEffect(CGFloat(scale))
    }

    private var mark: some View {
        SonaMark()
            .fill(SonaMark.color)
            .frame(width: Self.logoSize, height: Self.logoSize)
    }

    private func wave(at t: Double) -> some View {
        let progress = ramp(t, Self.landing, Self.landing + 0.65)
        let spread = 1 - pow(1 - progress, 3)
        return Circle()
            .strokeBorder(Color.white.opacity(t < Self.landing ? 0 : 0.45 * (1 - progress)), lineWidth: 1.5)
            .frame(width: 120 + 420 * CGFloat(spread), height: 120 + 420 * CGFloat(spread))
    }

    private func title(at t: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(Array("Sona".enumerated()), id: \.offset) { index, letter in
                let from = Self.landing + 0.05 + Double(index) * 0.07
                let shown = ramp(t, from, from + 0.3)
                let rise = 1 - pow(1 - shown, 3)
                Text(String(letter))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Tone.primary)
                    .opacity(rise)
                    .offset(y: 18 * CGFloat(1 - rise))
            }
        }
    }
}
