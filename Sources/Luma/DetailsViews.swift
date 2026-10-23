import SwiftUI
import LumaCore

struct DescriptionPanel: View {
    @EnvironmentObject var store: AppStore
    let item: MediaItem
    var detail: MediaItem { store.resolved(item) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(detail.title).font(.system(size: 21, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(detail.episodeLabel ?? detail.kind.title)
                if let year = detail.releaseYear { Text("·"); Text(String(year)) }
                if let rating = detail.rating, rating != "0" { Text("·"); Label(rating, systemImage: "star") }
            }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            if store.metadataLoading.contains(item.id) { ProgressView().controlSize(.small) }
            ScrollView {
                Text(detail.summary?.isEmpty == false ? detail.summary! : "Your provider has not supplied a description for this title.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text.opacity(0.85)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 260)
            if let error = store.metadataErrors[item.id] {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.muted)
                Button("Retry details") { Task { await store.fetchDetails(item) } }.buttonStyle(QuietButton())
            }
        }.padding(26).frame(width: 420).background(Theme.background).foregroundStyle(Theme.text)
            .task(id: item.id) { await store.fetchDetails(item) }
    }
}

struct MovieDetailsView: View {
    @EnvironmentObject var store: AppStore
    let item: MediaItem
    var detail: MediaItem { store.resolved(item) }
    var body: some View {
        HStack(alignment: .top, spacing: 27) {
            Artwork(item: detail).frame(width: 193, height: 290).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text(detail.kind.title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Theme.accent); Spacer(); Button { store.selectedMovie = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).keyboardShortcut(.cancelAction) }
                Text(detail.title).font(.system(size: 26, weight: .semibold)).tracking(-0.5).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let year = detail.releaseYear { Text(String(year)) }
                    if let episode = detail.episodeLabel { Text(episode) }
                    if let rating = detail.rating, rating != "0" { Label(rating, systemImage: "star") }
                }.font(.system(size: 12)).foregroundStyle(Theme.muted)
                if store.metadataLoading.contains(item.id) { ProgressView().controlSize(.small) }
                ScrollView {
                    Text(detail.summary?.isEmpty == false ? detail.summary! : "Your provider has not supplied a description for this title.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 90, maxHeight: 200)
                if let error = store.metadataErrors[item.id] {
                    Text(error).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Button("Retry details") { Task { await store.fetchDetails(item) } }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
                HStack {
                    Button { store.selectedMovie = nil; store.open(detail) } label: { Label("Watch now", systemImage: "play.fill") }.buttonStyle(AccentButton())
                    Button { store.toggleFavorite(item) } label: { Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart") }.buttonStyle(QuietButton()).help("Toggle favorite")
                }
            }
        }.padding(30).frame(width: 720).background(Theme.background).foregroundStyle(Theme.text)
            .task(id: item.id) { await store.fetchDetails(item) }
    }
}

struct ReleaseYearPicker: View {
    @EnvironmentObject var store: AppStore
    var years: [Int] { Array(Set(store.availableYears + (store.selectedYear.map { [$0] } ?? []))).sorted(by: >) }
    var body: some View {
        Picker("Release year", selection: $store.selectedYear) {
            Text("All years").tag(Int?.none)
            ForEach(years, id: \.self) { Text(String($0)).tag(Optional($0)) }
        }.pickerStyle(.menu).fixedSize().font(.system(size: 12)).disabled(store.availableYears.isEmpty && store.selectedYear == nil)
            .help("Filter by supplied release year or a year explicitly marked in the title. Undated titles appear under All years.")
    }
}

