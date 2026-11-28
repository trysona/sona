import SwiftUI

/// Mini-lecteur, posé en accessoire de la barre d'onglets (le verre et la
/// place sont fournis par le système) : pochette, titre, lecture/pause,
/// suivant, et une fine barre de progression en bas. En version « rangée »
/// (barre d'onglets réduite au défilement), il se resserre. Tout le bloc
/// ouvre le lecteur plein écran, qui en *grandit* (voir `RootTabView`).
struct MiniPlayerView: View {
    @ObservedObject var player: PlayerManager
    var onExpand: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @ObservedObject private var artistsCache = TrackArtistsCache.shared

    private var isInline: Bool { placement == .inline }
    /// Retour au titre d'avant : le texte entre par la gauche au lieu de la droite.
    @State private var backwards = false

    var body: some View {
        if let track = player.current {
            // En « répéter tout » ou en radio, il y a toujours un suivant.
            let ended = player.upNext.isEmpty && player.repeatMode != .all && !player.isStation
            HStack(spacing: 12) {
                Artwork(url: track.coverURL, cornerRadius: isInline ? 5 : 7)
                    .frame(width: isInline ? 28 : 34, height: isInline ? 28 : 34)
                    .scaleEffect(player.isPlaying ? 1 : 0.9)
                    .animation(Motion.bouncy, value: player.isPlaying)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(Typo.rowTitle)
                        .foregroundStyle(Tone.primary)
                        .lineLimit(1)
                    if !isInline {
                        Text(artistsCache.line(for: track))
                            .font(.system(size: 13))
                            .foregroundStyle(Tone.secondary)
                            .lineLimit(1)
                            .task(id: track.id) { await artistsCache.load(track) }
                    }
                }
                .id(track.id)
                .transition(.asymmetric(
                    insertion: .move(edge: backwards ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: backwards ? .trailing : .leading).combined(with: .opacity)
                ))
                // Un tour de plus avant de changer de titre : le texte sortant connaît alors le sens.
                .modifier(TrackSwipe(
                    canNext: !ended,
                    next: {
                        backwards = false
                        Task { player.next() }
                    },
                    previous: {
                        backwards = true
                        Task {
                            player.previousTrack()
                            try? await Task.sleep(for: .milliseconds(500))
                            backwards = false
                        }
                    }
                ))
                Button {
                    player.togglePlayPause()
                } label: {
                    Group {
                        if player.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .contentTransition(.symbolEffect(.replace.downUp))
                        }
                    }
                    .font(.system(size: isInline ? 17 : 19, weight: .semibold))
                    .foregroundStyle(Tone.primary)
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(.pressable(scale: 0.85))
                .sensoryFeedback(.impact(weight: .light), trigger: player.isPlaying)

                if !isInline {
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ended ? Tone.tertiary : Tone.primary)
                        .frame(width: 36, height: 40)
                }
                .buttonStyle(.pressable(scale: 0.85))
                .disabled(ended)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: proxy.size.width * player.progress, height: 2)
                        .animation(.linear(duration: 0.5), value: player.progress)
                }
                .frame(height: 2)
                .padding(.horizontal, 22)
                .padding(.bottom, 3)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
            .animation(Motion.snappy, value: track.id)
        }
    }
}

/// Comme dans Musique : le titre du mini-lecteur suit le doigt ; glissé à gauche, il passe au suivant, à droite,
/// il revient au précédent. Prend toute la place libre, pour que le geste soit facile.
struct TrackSwipe: ViewModifier {
    var canNext = true
    var next: () -> Void
    var previous: () -> Void
    @State private var drag: CGFloat = 0
    @State private var swipes = 0

    func body(content: Content) -> some View {
        content
            .offset(x: drag)
            .opacity(1 - Double(min(abs(drag) / 200, 0.6)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        // Plus de suivant : le titre résiste.
                        let x = value.translation.width
                        drag = x < 0 && !canNext ? x / 4 : x
                    }
                    .onEnded { value in
                        // Un geste long, ou court mais vif.
                        let x = value.predictedEndTranslation.width
                        if x < -90 && canNext {
                            swipes += 1
                            next()
                        } else if x > 90 {
                            swipes += 1
                            previous()
                        }
                        withAnimation(Motion.snappy) { drag = 0 }
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: swipes)
    }
}
