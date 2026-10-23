import SwiftUI
import LumaCore

struct EpisodeView: View {
    @EnvironmentObject var store: AppStore
    let show: MediaItem
    @State private var selectedSeason: Int?
    var detail: MediaItem { store.resolved(show) }
    var seasons: [Int] { Array(Set(store.episodes.compactMap(\.season))).sorted() }
    var visibleEpisodes: [MediaItem] { store.episodes.filter { selectedSeason == nil || $0.season == selectedSeason } }
    var lastEpisode: WatchRecord? { store.user.recent.first { $0.item.seriesID == show.providerID } }
    var resumeEpisode: MediaItem? {
        guard let lastEpisode else { return store.episodes.first }
        return lastEpisode.completed ? EpisodeOrder.next(after: lastEpisode.item, in: store.episodes) ?? store.episodes.first : store.episodes.first { $0.id == lastEpisode.id } ?? store.episodes.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                Artwork(item: detail).frame(width: 123, height: 177).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR SERIES").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Theme.accent)
                    Text(detail.title).font(.system(size: 25, weight: .semibold)).tracking(-0.6).lineLimit(2)
                    HStack { Text("\(seasons.count) seasons"); Text("·"); Text("\(store.episodes.count) episodes") }.font(.system(size: 11)).foregroundStyle(Theme.muted)
                    if let year = detail.releaseYear { Text("Released " + String(year)).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                    if let summary = detail.summary, !summary.isEmpty { ScrollView { Text(summary).font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90) }
                    if let episode = resumeEpisode {
                        Button { store.playEpisode(episode) } label: { Label(lastEpisode == nil ? "Play first episode" : "Continue · \(episode.episodeLabel ?? "Episode")", systemImage: "play.fill") }.buttonStyle(AccentButton())
                    }
                    if let lastEpisode { Text("Last watched: \(lastEpisode.item.episodeLabel ?? lastEpisode.item.title)\(lastEpisode.completed ? " · Finished" : " · " + timeString(lastEpisode.position))").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { store.selectedShow = nil } label: { Image(systemName: "xmark").foregroundStyle(Theme.muted) }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }.padding(28)
            Divider().overlay(Theme.border)
            HStack {
                Text("Episodes").font(.system(size: 17, weight: .semibold)); Spacer()
                if !seasons.isEmpty { Picker("Season", selection: $selectedSeason) { Text("All seasons").tag(Int?.none); ForEach(seasons, id: \.self) { Text("Season \($0)").tag(Optional($0)) } }.labelsHidden().frame(width: 150) }
            }.padding(.horizontal, 28).padding(.vertical, 18)
            if store.episodesLoading { VStack(spacing: 15) { ProgressView(); Text("Loading episodes…").font(.system(size: 12)).foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error = store.episodeError {
                VStack(spacing: 16) { Text(error).foregroundStyle(Theme.muted).multilineTextAlignment(.center); Button("Try again") { store.openShow(show) }.buttonStyle(AccentButton()) }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.episodes.isEmpty { EmptyLibrary(symbol: "tv", title: "No episodes available", detail: "Your provider has not added any episodes to this series.") }
            else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleEpisodes) { episode in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 14) {
                                    Button { store.playEpisode(episode) } label: { Artwork(item: episode).frame(width: 106, height: 62).clipShape(RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain).help("Play episode")
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(episode.episodeLabel ?? "Episode").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accent)
                                        Text(episode.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        if let record = store.user.history[episode.id] { Text(record.completed ? "Watched" : "Resume at \(timeString(record.position))").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                                    }
                                    Spacer()
                                    Button { store.playEpisode(episode) } label: { Image(systemName: store.user.history[episode.id]?.completed == true ? "checkmark.circle" : "play.circle").font(.system(size: 21, weight: .light)).foregroundStyle(Theme.accent) }.buttonStyle(.plain).help("Play episode")
                                }
                                if let summary = episode.summary, !summary.isEmpty {
                                    DisclosureGroup("Episode description") { Text(summary).font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6) }.font(.system(size: 11)).tint(Theme.accent)
                                }
                            }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28)
                }
            }
        }.frame(width: 720, height: 650).background(Theme.background).foregroundStyle(Theme.text)
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmSignOut = false
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack { Text("Make it yours").font(.system(size: 25, weight: .semibold)); Spacer(); Button { store.showSettings = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            VStack(alignment: .leading, spacing: 12) {
                Text("APPEARANCE").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.muted)
                Picker("Theme", selection: $store.appearance) { ForEach(AppAppearance.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 17) {
                Text("PLAYBACK").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.muted)
                Toggle("Autoplay next episode", isOn: $store.user.autoplay).toggleStyle(.switch).tint(Theme.accent).onChange(of: store.user.autoplay) { store.persist() }
                Text("Episodes play in season and episode order. Luma remembers the last episode and your place in every movie or episode.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
            }
            Divider()
            VStack(alignment: .leading, spacing: 13) {
                Text("YOUR SOURCE").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.muted)
                Text(store.source?.name ?? "No source connected").font(.system(size: 15, weight: .medium))
                Text(store.source?.type == .xtream ? "Xtream Codes · Credentials secured in Keychain" : "M3U playlist · Connection secured in Keychain").font(.system(size: 11)).foregroundStyle(Theme.muted)
                HStack { Button("Refresh library") { store.refresh() }.buttonStyle(QuietButton()).disabled(store.loading); Button("Disconnect") { confirmSignOut = true }.buttonStyle(QuietButton()) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) { LumaMark(size: 24); Text("Luma 1.3.1").font(.system(size: 13, weight: .medium)) }
                Text("A personal player for your content. Luma does not supply channels, playlists, movies, or subscriptions. Install VLC in Applications for broad format support; AVPlayer is used when VLC is unavailable.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
                Text("⌘F Search · ⌘R Refresh · Space / Click Pause · ← / → Seek · ↑ / ↓ Volume · F Full screen · Esc Close player").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }.padding(30).frame(width: 490).background(Theme.background).foregroundStyle(Theme.text)
            .confirmationDialog("Disconnect this source?", isPresented: $confirmSignOut) { Button("Disconnect", role: .destructive) { store.showSettings = false; store.disconnect() } } message: { Text("The saved login will be removed from Keychain. Favorites and watch progress remain on this Mac for when you reconnect.") }
    }
}
