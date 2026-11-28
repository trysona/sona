import CoreMotion
import MapKit
import SwiftUI

// MARK: - Nouvelles sorties

/// Accueil : albums, EP et singles sortis ces 3 dernières semaines chez tes
/// artistes les plus écoutés.
struct ReleasesSection: View {
    let releases: [Release]
    let onOpen: (Release) -> Void

    var body: some View {
        Carousel(items: releases) { release in
            Button { onOpen(release) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Artwork(url: release.coverURL, cornerRadius: 10)
                        .frame(width: 150, height: 150)
                        .overlay(alignment: .topLeading) {
                            Text(release.kind.uppercased())
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(.white))
                                .padding(8)
                        }
                    Text(release.title).font(Typo.rowTitle).foregroundStyle(Tone.primary).lineLimit(1)
                    Text("\(release.artist) · \(release.ageLabel)").font(Typo.rowSubtitle).foregroundStyle(Tone.secondary).lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)
            }
            .buttonStyle(.pressable)
        }
    }
}

// MARK: - Carte des écoutes

struct ListeningMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var location = LocationProvider.shared
    @AppStorage("encre.mapPlays") private var recordPlaces = true
    @State private var places: [ListeningPlace] = []
    @State private var selected: ListeningPlace?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(selection: Binding(get: { selected?.id }, set: { id in selected = places.first { $0.id == id } })) {
                    ForEach(places) { place in
                        Annotation(place.topArtist ?? "", coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)) {
                            Artwork(url: place.coverURL, cornerRadius: 10)
                                .frame(width: size(place), height: size(place))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 2))
                                .shadow(radius: 6)
                                .onTapGesture { withAnimation(Motion.snappy) { selected = place } }
                        }
                        .tag(place.id)
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .ignoresSafeArea(edges: .bottom)

                if let selected {
                    placeCard(selected).padding(16).transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !loading && places.isEmpty {
                    VStack(spacing: 8) {
                        Text("Ta carte se remplit au fil de tes écoutes.").font(Typo.headline).foregroundStyle(Tone.primary)
                        Text(location.status == .authorizedWhenInUse || location.status == .authorizedAlways
                             ? "Chaque écoute garde un lieu approximatif (à 1 km près)."
                             : "Autorise la localisation pour que tes écoutes soient placées sur la carte.")
                            .font(Typo.rowSubtitle).foregroundStyle(Tone.secondary).multilineTextAlignment(.center)
                        if location.status == .notDetermined {
                            PillButton(title: "Autoriser", systemImage: "location.fill") { location.request() }
                        }
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
                    .padding(16)
                }
            }
            .navigationTitle("Carte de tes écoutes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $recordPlaces) { Image(systemName: "location") }.toggleStyle(.button)
                }
            }
        }
        .task {
            location.request()
            places = (try? await APIClient.shared.listeningPlaces()) ?? []
            loading = false
        }
    }

    private func size(_ place: ListeningPlace) -> CGFloat {
        let most = Double(places.map(\.plays).max() ?? 1)
        return 34 + 30 * CGFloat(sqrt(Double(place.plays) / most))
    }

    private func placeCard(_ place: ListeningPlace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(place.plays) écoute\(place.plays > 1 ? "s" : "") ici").font(Typo.headline).foregroundStyle(Tone.primary)
                Spacer()
                Button { withAnimation { selected = nil } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tone.secondary) }
            }
            ForEach(Array(place.topTracks.prefix(3).enumerated()), id: \.offset) { index, top in
                Text("\(index + 1). \(top.title) — \(top.artist ?? "") · \(top.plays)")
                    .font(Typo.rowSubtitle).foregroundStyle(Tone.secondary).lineLimit(1)
            }
            if let track = place.track {
                PillButton(title: "Réécouter", systemImage: "play.fill", kind: .secondary) {
                    player.play(track, context: [track], name: "Carte des écoutes")
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
    }
}
