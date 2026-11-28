import SwiftUI

/// Réglages : compte Last.fm, scrobbling, administration (admins), serveur.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var config = APIConfig.shared
    @State private var scrobble = true
    @State private var shareListening = true
    @State private var smartDownloads = SmartDownloads.shared.enabled
    @State private var lovedImport: LovedImportStatus?
    @ObservedObject private var downloads = DownloadManager.shared
    /// Commit déployé sur le serveur : pour vérifier qu'une mise à jour est passée.
    @State private var serverVersion: String?
    @State private var errorMessage: String?
    @State private var quality = PlaybackQuality.current
    @ObservedObject private var notifications = NotificationManager.shared

    var body: some View {
        Form {
            if let account = auth.account {
                Section {
                    HStack(spacing: 14) {
                        Artwork(url: account.avatarURL, cornerRadius: 28, symbol: "person.fill")
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name).font(Typo.headline)
                            Text(account.id == nil ? "Jeton administrateur" : account.kindLabel)
                                .font(Typo.rowSubtitle)
                                .foregroundStyle(Tone.secondary)
                        }
                        Spacer()
                        if account.isAdmin {
                            Text("ADMIN")
                                .font(Typo.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Tone.surfaceStrong))
                        }
                    }
                    .padding(.vertical, 4)

                    if account.id != nil {
                        Toggle("Envoyer mes écoutes sur Last.fm", isOn: $scrobble)
                            .onChange(of: scrobble) { _, value in
                                guard value != account.scrobbleToLastfm else { return }
                                Task { await setScrobbling(value) }
                            }
                    }
                } footer: {
                    if account.id != nil {
                        Text("Chaque morceau écouté au moins à moitié est aussi ajouté à ton profil Last.fm (et donc visible sur Sonar). Un titre ajouté à ta bibliothèque devient un titre aimé ♥ sur Last.fm.")
                    }
                }

                if account.id != nil {
                    Section {
                        Toggle("Partager mon écoute avec mes amis", isOn: $shareListening)
                            .onChange(of: shareListening) { _, value in
                                guard value != (account.shareListening ?? true) else { return }
                                Task { await setSharing(value) }
                            }
                        Button {
                            Task { await startLovedImport() }
                        } label: {
                            HStack {
                                Label("Importer mes titres aimés Last.fm", systemImage: "heart")
                                Spacer()
                                if lovedImport?.running == true { ProgressView() }
                            }
                        }
                        .disabled(lovedImport?.running == true)
                    } footer: {
                        if let status = lovedImport {
                            if let error = status.error {
                                Text(error).foregroundStyle(Tone.danger)
                            } else if status.running {
                                Text("Import en cours… \(status.done) / \(status.total)")
                            } else if status.total > 0 {
                                Text(lovedSummary(status))
                            }
                        } else {
                            Text("Tes amis voient ce que tu écoutes en direct et tes dernières écoutes.")
                        }
                    }
                }

                Section {
                    Picker("Qualité audio", selection: $quality) {
                        ForEach(PlaybackQuality.choices, id: \.id) { choice in Text(choice.label).tag(choice.id) }
                    }
                    .onChange(of: quality) { _, value in
                        guard value != PlaybackQuality.current else { return }
                        PlaybackQuality.set(value)
                        Task { _ = try? await APIClient.shared.updateSettings(quality: value) }
                    }
                } header: {
                    Text("Lecture")
                } footer: {
                    Text(PlaybackQuality.choices.first { $0.id == quality }?.detail ?? "")
                }

                Section {
                    NavigationLink {
                        DeviceLinkView()
                    } label: {
                        Label("Connecter un appareil (TV…)", systemImage: "tv")
                    }
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        Label("Apparence", systemImage: "paintpalette")
                    }
                    NavigationLink {
                        ExclusivesView(path: .constant(NavigationPath()))
                    } label: {
                        Label("Exclus", systemImage: "sparkles")
                    }
                    NavigationLink {
                        WakeAlarmView()
                    } label: {
                        Label("Réveil musical", systemImage: "alarm")
                    }
                    NavigationLink {
                        PublicLinkView()
                    } label: {
                        Label("Page « J'écoute » publique", systemImage: "globe")
                    }
                    NavigationLink {
                        ShareLinksView()
                    } label: {
                        Label("Liens de partage", systemImage: "link")
                    }
                    NavigationLink {
                        CarModeSettingsView()
                    } label: {
                        Label("Mode voiture", systemImage: "car.fill")
                    }
                }

                Section {
                    Toggle("Récaps de la semaine et du mois", isOn: $notifications.recaps)
                    Toggle("Parties lancées par mes amis", isOn: $notifications.friends)
                    Toggle("Nouvelles sorties de mes artistes", isOn: $notifications.releases)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Récaps le lundi et le 1er du mois à 10 h. Les écoutes ensemble des amis sont signalées quand l'app tourne, même en arrière-plan pendant la lecture.")
                }

                Section {
                    Toggle("Télécharger en Wi-Fi uniquement", isOn: Binding(
                        get: { downloads.wifiOnly }, set: { downloads.wifiOnly = $0 }
                    ))
                    Toggle("Téléchargements intelligents", isOn: $smartDownloads)
                        .onChange(of: smartDownloads) { _, value in
                            SmartDownloads.shared.enabled = value
                            if value { SmartDownloads.shared.schedule() }
                        }
                } header: {
                    Text("Téléchargements")
                } footer: {
                    Text(downloadsSummary + "\nIntelligents : la nuit (Wi-Fi, en charge) et à l'ouverture en Wi-Fi, ton Mix du jour, « En boucle » et tes playlists hors ligne sont téléchargés d'avance.")
                }

                if account.managesPlayback {
                    Section {
                        NavigationLink {
                            StreamingHealthView()
                        } label: {
                            Label("Santé de la lecture", systemImage: "waveform.path.ecg")
                        }
                    } header: {
                        Text("Administration")
                    }
                }
            }

            Section {
                TextField("https://…", text: $config.baseURLString)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    Text("Version du serveur")
                    Spacer()
                    Text(serverVersion ?? "…")
                        .font(Typo.mono)
                        .foregroundStyle(Tone.secondary)
                }
            } header: {
                Text("Serveur")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Tone.danger) }
            }

            Section {
                Button("Se déconnecter", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }
        }
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            scrobble = auth.account?.scrobbleToLastfm ?? true
            shareListening = auth.account?.shareListening ?? true
        }
        .task {
            let health = try? await APIClient.shared.health()
            serverVersion = health?.version ?? (health == nil ? "injoignable" : "ancienne")
        }
        .task {
            // État d'un import déjà lancé, puis suivi tant qu'il tourne.
            lovedImport = try? await APIClient.shared.lovedImportStatus()
            if lovedImport?.total == 0 && lovedImport?.running == false { lovedImport = nil }
            while lovedImport?.running == true {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                lovedImport = try? await APIClient.shared.lovedImportStatus()
            }
        }
    }

    private var downloadsSummary: String {
        let count = downloads.items.count
        let titles = count == 1 ? "1 titre" : "\(count) titres"
        return "\(titles) sur l'iPhone · \(downloads.totalBytes.byteLabel)"
    }

    private func lovedSummary(_ status: LovedImportStatus) -> String {
        let added = status.added == 1 ? "1 titre ajouté" : "\(status.added) titres ajoutés"
        var text = "\(added) à ta bibliothèque"
        if status.missing > 0 {
            text += status.missing == 1 ? ", 1 introuvable" : ", \(status.missing) introuvables"
        }
        return text + "."
    }

    private func setSharing(_ value: Bool) async {
        do {
            auth.update(try await APIClient.shared.updateMe(shareListening: value))
        } catch {
            errorMessage = error.localizedDescription
            shareListening = !value
        }
    }

    private func startLovedImport() async {
        do {
            lovedImport = try await APIClient.shared.startLovedImport()
            while lovedImport?.running == true {
                try? await Task.sleep(for: .seconds(2))
                lovedImport = try? await APIClient.shared.lovedImportStatus()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setScrobbling(_ value: Bool) async {
        do {
            auth.update(try await APIClient.shared.updateMe(scrobbleToLastfm: value))
        } catch {
            errorMessage = error.localizedDescription
            scrobble = !value
        }
    }
}
