import SwiftUI

/// Animation d'ouverture : la même intro que le site (web/presentation.html, `paintIntro`) — le « S » se trace,
/// se remplit en s'illuminant, puis « ona » apparaît à sa droite. L'écran de lancement système est le même fond
/// uni, sans logo : aucun saut. Avec `leaving`, tout se fond et laisse voir l'app (voir `EncreApp`).
/// « Réduire les animations » : le mot entier, fixe.
struct LaunchSplashView: View {
    /// Mêmes durées que le site : départ après 0,35 s, puis 4,4 s.
    private static let delay = 0.35
    private static let duration = 4.4
    /// Durée de l'intro avant que la sortie puisse commencer.
    static let introSeconds = delay + duration

    var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    /// Largeur de « ona » une fois affiché en entier.
    @State private var restWidth: CGFloat = 0

    var body: some View {
        GeometryReader { screen in
            let vmin = min(screen.size.width, screen.size.height)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                let p = reduceMotion ? 1 : clamp((t - Self.delay) / Self.duration)
                ZStack {
                    halo(p, diameter: vmin * 0.7)
                    word(p, size: min(240, max(88, vmin * 0.24)))
                    // Le compte se vérifie encore après l'intro : on le montre.
                    ProgressView()
                        .tint(.white)
                        .offset(y: 150)
                        .opacity(!leaving && !reduceMotion && t > Self.introSeconds + 0.4 ? 1 : 0)
                }
                .frame(width: screen.size.width, height: screen.size.height)
            }
        }
        .background(Color(hex: 0x0A0A0B))
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .animation(.easeInOut(duration: 0.45), value: leaving)
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }

    private func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    /// Avancement de 0 à 1 entre deux moments de l'intro (en fraction de sa durée).
    private func segment(_ p: Double, _ from: Double, _ to: Double) -> Double { clamp((p - from) / (to - from)) }

    private func eased(_ value: Double) -> Double { 1 - pow(1 - value, 3) }

    /// Lueur du logo : un éclat juste après le tracé, qui retombe.
    private func glow(_ p: Double) -> Double {
        let pulse = segment(p, 0.42, 0.5) * (1 - segment(p, 0.5, 0.66))
        return min(1, pulse * 1.6 + 0.25 * segment(p, 0.4, 0.5) * (1 - segment(p, 0.66, 1)))
    }

    private func halo(_ p: Double, diameter: CGFloat) -> some View {
        let light = glow(p)
        return Circle()
            .fill(RadialGradient(colors: [SonaMark.color.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
            .scaleEffect(0.8 + CGFloat(light) * 0.4)
            .opacity(light)
    }

    private func word(_ p: Double, size: CGFloat) -> some View {
        let light = glow(p)
        let side = size * 0.72
        let opening = CGFloat(eased(segment(p, 0.52, 0.85)))
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            ZStack {
                SonaMark()
                    .fill(SonaMark.color)
                    .opacity(segment(p, 0.4, 0.5))
                SonaMark()
                    .trim(from: 0, to: eased(segment(p, 0, 0.42)))
                    .stroke(SonaMark.color, style: StrokeStyle(lineWidth: side * 3 / 163, lineJoin: .round))
            }
            .frame(width: side, height: side)
            .compositingGroup()
            .shadow(color: Color(red: 236 / 255, green: 236 / 255, blue: 244 / 255).opacity(light * 0.95), radius: CGFloat(light) * 18)

            // La place de « ona » s'ouvre peu à peu : le « S », centré avec elle, glisse vers la gauche.
            letters(p, size: size)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { restWidth = $0 }
                .frame(width: opening * restWidth, alignment: .leading)
        }
    }

    private func letters(_ p: Double, size: CGFloat) -> some View {
        HStack(spacing: -0.05 * size) {
            ForEach(Array("ona".enumerated()), id: \.offset) { index, letter in
                let from = 0.56 + Double(index) * 0.07
                let shown = eased(segment(p, from, from + 0.22))
                Text(String(letter))
                    .font(.custom("FamiljenGrotesk-Bold", fixedSize: size))
                    .foregroundStyle(SonaMark.color)
                    .opacity(shown)
                    .offset(y: CGFloat(1 - shown) * size * 0.4)
                    .blur(radius: CGFloat(1 - shown) * 14)
            }
        }
        .padding(.leading, 0.04 * size)
        .padding(.trailing, 0.1 * size)
    }
}
