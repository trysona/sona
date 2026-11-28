import SwiftUI

/// Animation d'ouverture : la même intro que le site (web/presentation.html, `paintIntro`) — le « S » se trace,
/// se remplit en s'illuminant, puis « ona » apparaît à sa droite. L'écran de lancement système est le même fond
/// uni, sans logo : aucun saut. Avec `leaving`, on plonge dans le « S » : il devient une ouverture qui grandit
/// jusqu'à montrer toute l'app (voir `EncreApp`). L'app dessous n'est jamais agrandie ni déplacée.
/// « Réduire les animations » : le mot entier, fixe, puis un fondu.
struct LaunchSplashView: View {
    /// Mêmes durées que le site : départ après 0,35 s, puis 4,4 s.
    private static let delay = 0.35
    private static let duration = 4.4
    /// Durée de l'intro avant que la sortie puisse commencer.
    static let introSeconds = delay + duration
    /// Durée de la plongée dans le logo.
    static let exitSeconds = 0.9
    /// Point le plus « profond » du « S » et rayon du cercle qui y tient (fractions de son côté).
    private static let dive = (x: 0.3833, y: 0.2733, radius: 0.26)
    private static let background = Color(hex: 0x0A0A0B)

    var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    /// Largeur de « ona » une fois affiché en entier.
    @State private var restWidth: CGFloat = 0
    /// Place du « S » à l'écran, et début de la plongée.
    @State private var logoFrame = CGRect.zero
    @State private var leftAt: Date?

    var body: some View {
        GeometryReader { screen in
            let vmin = min(screen.size.width, screen.size.height)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                let p = reduceMotion ? 1 : clamp((t - Self.delay) / Self.duration)
                let q = leftAt.map { clamp(timeline.date.timeIntervalSince($0) / Self.exitSeconds) } ?? 0
                ZStack {
                    if q > 0 {
                        portal(q, screen: screen.size)
                    } else {
                        Self.background
                    }
                    halo(p, diameter: vmin * 0.7)
                    word(p, size: min(240, max(88, vmin * 0.24)), leaving: q)
                    // Le compte se vérifie encore après l'intro : on le montre.
                    ProgressView()
                        .tint(.white)
                        .offset(y: 150)
                        .opacity(!leaving && !reduceMotion && t > Self.introSeconds + 0.4 ? 1 : 0)
                }
                .frame(width: screen.size.width, height: screen.size.height)
                .coordinateSpace(.named("splash"))
            }
        }
        .ignoresSafeArea()
        .opacity(reduceMotion && leaving ? 0 : 1)
        .animation(.easeInOut(duration: 0.45), value: leaving)
        .onAppear { start = Date() }
        .onChange(of: leaving) { _, gone in
            if gone && !reduceMotion { leftAt = Date() }
        }
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

    /// La plongée : le fond est percé d'un « S » qui grandit autour de son point profond, ramené au centre de
    /// l'écran. Le « S » gris s'efface et on voit l'app à travers.
    @ViewBuilder
    private func portal(_ q: Double, screen: CGSize) -> some View {
        let anchor = CGPoint(
            x: logoFrame.minX + CGFloat(Self.dive.x) * logoFrame.width,
            y: logoFrame.minY + CGFloat(Self.dive.y) * logoFrame.height
        )
        let travel = CGFloat(q * q * (3 - 2 * q))
        let target = CGPoint(
            x: anchor.x + (screen.width / 2 - anchor.x) * travel,
            y: anchor.y + (screen.height / 2 - anchor.y) * travel
        )
        // À la fin, le cercle tenu dans le « S » dépasse les coins de l'écran.
        let full = hypot(screen.width, screen.height) / 2 / max(1, CGFloat(Self.dive.radius) * logoFrame.width) * 1.1
        let zoom = pow(full, CGFloat(pow(q, 1.5)))
        let transform = CGAffineTransform(translationX: target.x, y: target.y)
            .scaledBy(x: zoom, y: zoom)
            .translatedBy(x: -anchor.x, y: -anchor.y)
        let hole = SonaMark().path(in: logoFrame).applying(transform)
        let cover = Path { path in
            path.addRect(CGRect(origin: .zero, size: screen).insetBy(dx: -2, dy: -2))
            path.addPath(hole)
        }
        cover.fill(Self.background, style: FillStyle(eoFill: true))
        hole.fill(SonaMark.color).opacity(1 - clamp(q / 0.35))
    }

    private func word(_ p: Double, size: CGFloat, leaving q: Double) -> some View {
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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("splash")) } action: { logoFrame = $0 }
            // Pendant la plongée, c'est `portal` qui dessine le « S ».
            .opacity(q > 0 ? 0 : 1)

            // La place de « ona » s'ouvre peu à peu : le « S », centré avec elle, glisse vers la gauche.
            letters(p, size: size)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { restWidth = $0 }
                .frame(width: opening * restWidth, alignment: .leading)
                .opacity(1 - clamp(q / 0.2))
                .offset(x: CGFloat(q) * 90)
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
