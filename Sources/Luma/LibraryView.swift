import SwiftUI
import LumaCore

struct LibraryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool
    @State private var confirmClear = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                Rectangle().fill(Theme.border).frame(height: 1)
                if let error = store.error {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                        Text(error).font(.system(size: 12))
                        Spacer()
                        if store.catalogLoadFailed {
                            Button("Retry") { store.refresh() }.buttonStyle(QuietButton())
                            Button("Update connection") { store.showConnection = true }.buttonStyle(QuietButton())
                        }
                        Button("Dismiss") { store.error = nil }.buttonStyle(.plain)
                    }.foregroundStyle(.orange).padding(15).background(Color.orange.opacity(0.08))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        if store.loading && store.library.items.isEmpty { loadingLibrary }
                        else if store.catalogLoadFailed && store.library.items.isEmpty {
                            EmptyLibrary(symbol: "wifi.exclamationmark", title: "Your library couldn't load", detail: "Your account is still saved. Retry when your provider is available, or update your connection.")
                        }
                        else if store.destination == .home && store.search.isEmpty { discover }
                        else { catalog }
                    }.padding(32).frame(maxWidth: 1600)
                }.background(Theme.background)
            }
        }.foregroundStyle(Theme.text)
            .onReceive(NotificationCenter.default.publisher(for: .lumaSearch)) { _ in searchFocused = true }
            .confirmationDialog("Clear your watch history?", isPresented: $confirmClear) { Button("Clear history", role: .destructive) { store.clearHistory() } } message: { Text("This also removes Continue watching and saved episode progress for this source.") }
    }
    var loadingLibrary: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Welcome back.").font(.system(size: 32, weight: .semibold)).tracking(-0.8)
            HStack(spacing: 12) { ProgressView().controlSize(.small); Text("Loading your channels, movies, and series…").font(.system(size: 14)).foregroundStyle(Theme.muted) }
            RoundedRectangle(cornerRadius: 17).fill(Theme.surface).frame(height: 240)
            HStack(spacing: 18) {
                ForEach(0..<5) { _ in RoundedRectangle(cornerRadius: 10).fill(Theme.surface).frame(height: 200) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { LumaMark(size: 30); Text("luma").font(.system(size: 25, weight: .semibold, design: .rounded)); Spacer(); Text("PLAYER").font(.system(size: 8, weight: .bold)).tracking(1.7).foregroundStyle(Theme.muted) }.padding(.horizontal, 23).padding(.top, 39).padding(.bottom, 33)
            VStack(spacing: 5) { ForEach([Destination.home, .live, .movie, .series], id: \.self) { destination in navigationRow(destination) } }.padding(.horizontal, 12)
            Text("YOUR LIBRARY").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Theme.muted).padding(.leading, 25).padding(.top, 33).padding(.bottom, 12)
            VStack(spacing: 5) { ForEach([Destination.favorites, .continuing, .history], id: \.self) { destination in navigationRow(destination) } }.padding(.horizontal, 12)
            if store.destination.kind != nil {
                HStack { Text("CATEGORIES").font(.system(size: 9, weight: .semibold)).tracking(1.8); Spacer(); Text("\(store.categories.count)").font(.system(size: 10)).monospacedDigit() }.foregroundStyle(Theme.muted).padding(.horizontal, 25).padding(.top, 30).padding(.bottom, 10)
                categorySearch
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        categoryRow("All categories", id: nil)
                        if store.matchingCategories.isEmpty { Text("No matching categories").font(.system(size: 10)).foregroundStyle(Theme.muted).padding(13) }
                        ForEach(store.matchingCategories) { category in categoryRow(category.name, id: category.id) }
                    }.padding(.horizontal, 12)
                }
            } else { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: 16) {
                Rectangle().fill(Theme.border).frame(height: 1)
                Button { store.showConnection = true } label: {
                    HStack(spacing: 10) {
                        ZStack { RoundedRectangle(cornerRadius: 9).fill(Theme.elevated); Image(systemName: "link").foregroundStyle(Theme.accent) }.frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 4) { Text(store.source?.name ?? "My library").font(.system(size: 12, weight: .medium)).lineLimit(1); HStack(spacing: 4) { Circle().fill(Theme.accent).frame(width: 4, height: 4); Text(store.loading ? "Loading library" : store.catalogLoadFailed ? "Connection unavailable" : "Connected").font(.system(size: 10)).lineLimit(1).foregroundStyle(Theme.muted) } }
                        Spacer(); Image(systemName: "arrow.left.arrow.right").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }.buttonStyle(.plain).help("Connect another source")
                Button { store.showSettings = true } label: { Label("Settings", systemImage: "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(Theme.muted) }.buttonStyle(.plain)
            }.padding(22)
        }.frame(width: 223).background(Theme.sidebar)
    }
    func navigationRow(_ destination: Destination) -> some View {
        let selected = store.destination == destination
        return Button { store.destination = destination } label: {
            HStack(spacing: 12) {
                Image(systemName: destination.symbol).font(.system(size: 15, weight: .medium)).frame(width: 20)
                Text(destination.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                Spacer()
                if let kind = destination.kind { Text(store.count(kind).formatted()).font(.system(size: 10)).foregroundStyle(selected ? Theme.accent.opacity(0.8) : Theme.muted) }
                if destination == .favorites, !store.user.favorites.isEmpty { Text("\(store.user.favorites.count)").font(.system(size: 10)).foregroundStyle(Theme.muted) }
            }.foregroundStyle(selected ? Theme.accent : Theme.text.opacity(0.66)).padding(.horizontal, 13).frame(height: 41).background(selected ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    func categoryRow(_ title: String, id: String?) -> some View {
        Button { store.discoverFilter = nil; store.category = id } label: {
            HStack { Text(title).lineLimit(1); Spacer(); if store.category == id && store.discoverFilter == nil { Circle().fill(Theme.accent).frame(width: 4, height: 4) } }.font(.system(size: 11)).foregroundStyle(store.category == id && store.discoverFilter == nil ? Theme.accent : Theme.muted).padding(.horizontal, 13).padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain).help(title)
    }
    var categorySearch: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Search categories", text: $store.categorySearch).textFieldStyle(.plain).font(.system(size: 11))
                .accessibilityLabel("Search provider categories")
            if !store.categorySearch.isEmpty { Button { store.categorySearch = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain) }
        }.padding(9).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 17).padding(.bottom, 8)
    }
    var topbar: some View {
        HStack(spacing: 20) {
            HStack {
                Text(store.destination == .home ? "Your space to unwind" : store.destination.title).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
            }.frame(maxHeight: .infinity).background(TitlebarZoomArea())
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search \(store.destination == .home ? "your library" : store.destination.title.lowercased())", text: $store.search).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                if !store.search.isEmpty { Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.muted) }
                else { Text("⌘ F").font(.system(size: 10)).foregroundStyle(Theme.muted) }
            }.padding(10).frame(width: 300).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
            Button { store.appearance = colorScheme == .light ? .dark : .light } label: { Image(systemName: colorScheme == .light ? "moon" : "sun.max").foregroundStyle(Theme.muted) }.buttonStyle(.plain).help("Switch light / dark appearance")
            Button { store.refresh() } label: { if store.loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise").foregroundStyle(Theme.muted) } }.buttonStyle(.plain).disabled(store.loading).help("Refresh library (⌘R)")
        }.padding(.horizontal, 32).frame(height: 79)
    }
    var discover: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .firstTextBaseline) { VStack(alignment: .leading, spacing: 8) { Text("Settle in.").font(.system(size: 32, weight: .semibold)).tracking(-0.8); Text("Something good is waiting in your library.").font(.system(size: 13)).foregroundStyle(Theme.muted) }; Spacer(); Label("YOUR CONTENT, BEAUTIFULLY SIMPLE", systemImage: "sparkle").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(Theme.muted) }
            if let record = store.user.continuing.first { hero(record.item, resume: true) }
            else if let featured = homeMovies.first(where: { $0.artwork != nil }) ?? homeMovies.first ?? store.discoverShelves.lazy.compactMap({ store.discoverItems(for: $0, limit: 1).first }).first { hero(featured) }
            if !store.user.continuing.isEmpty { shelf("Pick up where you left off", subtitle: "CONTINUE WATCHING", items: Array(store.user.continuing.prefix(10).map(\.item)), destination: .continuing, wide: true) }
            HStack(spacing: 14) {
                ForEach(MediaKind.allCases, id: \.self) { kind in
                    Button { store.destination = Destination(rawValue: kind.rawValue) ?? .home } label: {
                        HStack(spacing: 12) { Image(systemName: kind.symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Theme.accent); VStack(alignment: .leading, spacing: 5) { Text(kind.title).font(.system(size: 13, weight: .semibold)); Text("\(store.count(kind).formatted()) titles").font(.system(size: 10)).foregroundStyle(Theme.muted) }; Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(Theme.muted) }.padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                ReleaseYearPicker()
                Spacer()
                Button { store.editDiscover() } label: { Label("Customize sections", systemImage: "slider.horizontal.3") }.buttonStyle(QuietButton())
            }
            ForEach(store.discoverShelves) { section in discoverShelf(section) }
            if store.discoverShelves.isEmpty {
                HStack { Text("Make Discover your own. Add a section for channels, films, or series.").font(.system(size: 13)).foregroundStyle(Theme.muted); Spacer(); Button("Add a section") { store.editDiscover() }.buttonStyle(AccentButton()) }.padding(24).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if store.library.items.isEmpty { EmptyLibrary(symbol: "rectangle.stack", title: "Your source is connected", detail: "The provider returned an empty library. Refresh or connect another source.") }
            HStack(spacing: 7) { Image(systemName: "leaf"); Text("Only the content you bring. Always.") }.font(.system(size: 10)).foregroundStyle(Theme.muted.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 8)
        }
    }
    var homeMovies: [MediaItem] {
        let preferred = store.discoverItems(for: .bollywoodMovies)
        if !preferred.isEmpty { return preferred }
        return Array(store.library.items.lazy.filter { item in item.kind == .movie && (store.selectedYear == nil || item.releaseYear == store.selectedYear) && store.discoverShelves.contains { $0.includes(item, favorites: store.user.favorites) } }.prefix(14))
    }
    func discoverShelf(_ section: DiscoverShelf) -> some View {
        let items = store.discoverItems(for: section)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(section.displayTitle).font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { store.editDiscover(section) } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(Theme.muted) }.buttonStyle(.plain).help("Edit this Discover section")
                Button { store.browse(section) } label: { Label("View all", systemImage: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.muted) }.buttonStyle(.plain)
            }
            if items.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: section.favoritesOnly ? "heart" : "rectangle.stack").foregroundStyle(Theme.accent)
                    Text(section.favoritesOnly ? "Favorite some titles or channels to see them here." : section.isEmptySelection ? "Choose categories or individual titles for this section." : "No titles match this section and release year.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Customize") { store.editDiscover(section) }.buttonStyle(QuietButton())
                }.padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView(.horizontal, showsIndicators: false) { LazyHStack(alignment: .top, spacing: 16) { ForEach(items) { item in MediaCard(item: item, wide: items.allSatisfy { $0.kind == .live }).frame(width: items.allSatisfy { $0.kind == .live } ? 238 : 153) } }.padding(.bottom, 3) }
            }
        }
    }
    func hero(_ item: MediaItem, resume: Bool = false) -> some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) { Theme.hero; Artwork(item: item).frame(width: 330) }
            LinearGradient(stops: [.init(color: Theme.hero, location: 0.25), .init(color: Theme.hero.opacity(0.96), location: 0.47), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) { Circle().fill(Theme.accent).frame(width: 4, height: 4); Text(resume ? "RIGHT WHERE YOU LEFT OFF" : "IN YOUR LIBRARY").tracking(1.8) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(item.title).font(.system(size: 32, weight: .semibold)).tracking(-0.8).lineLimit(2).frame(maxWidth: 480, alignment: .leading)
                HStack(spacing: 10) { Text(item.episodeLabel ?? item.kind.title); Text("·"); Text(store.library.categories.first(where: { $0.id == item.categoryID })?.name ?? "Your library").lineLimit(1) }.font(.system(size: 11)).foregroundStyle(Theme.text.opacity(0.5)).frame(maxWidth: 460, alignment: .leading)
                HStack(spacing: 10) {
                    Button { store.open(item) } label: { Label(resume ? "Continue watching" : item.kind == .series ? "Explore episodes" : "Watch now", systemImage: "play.fill") }.buttonStyle(AccentButton())
                    if item.kind != .live { Button { store.showDetails(item) } label: { Image(systemName: "info.circle") }.buttonStyle(QuietButton()).help("Description and details") }
                    Button { store.toggleFavorite(item) } label: { Image(systemName: store.isFavorite(item) ? "heart.fill" : "plus").frame(width: 16, height: 16) }.buttonStyle(QuietButton()).help("Toggle favorite")
                }.padding(.top, 5)
            }.padding(32)
        }.frame(height: 277).clipShape(RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(Theme.border))
    }
    func shelf(_ title: String, subtitle: String, items: [MediaItem], destination: Destination, wide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) { Text(subtitle).font(.system(size: 8, weight: .medium)).tracking(1.7).foregroundStyle(Theme.muted); Text(title).font(.system(size: 19, weight: .semibold)).tracking(-0.3) }
                Spacer(); Button { store.destination = destination } label: { HStack(spacing: 6) { Text("View all"); Image(systemName: "arrow.right") }.font(.system(size: 11)).foregroundStyle(Theme.muted) }.buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) { ForEach(items) { item in MediaCard(item: item, wide: wide).frame(width: wide ? 238 : 153) } }.padding(.bottom, 3)
            }
        }
    }
    var catalog: some View {
        let items = store.visibleItems
        let wide = store.destination == .live || store.destination == .continuing || (!items.isEmpty && items.allSatisfy { $0.kind == .live })
        return VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(catalogTitle).font(.system(size: 29, weight: .semibold)).tracking(-0.8)
                    Text("\(items.count.formatted()) \(items.count == 1 ? "title" : "titles")\(store.search.isEmpty ? " · From your library" : " matching ‘\(store.search)’")").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if store.destination == .history && !store.user.history.isEmpty { Button { confirmClear = true } label: { Image(systemName: "trash") }.buttonStyle(QuietButton()).help("Clear watch history") }
                if store.destination != .live { ReleaseYearPicker() }
                Menu { Button("Provider order") { store.sortByName = false }; Button("Name (A–Z)") { store.sortByName = true } } label: { Label(store.sortByName ? "Name" : "Sort", systemImage: "arrow.up.arrow.down").font(.system(size: 11)) }.menuStyle(.borderlessButton).fixedSize()
            }
            if !items.isEmpty {
                if store.destination == .history {
                    LazyVStack(spacing: 10) { ForEach(items) { item in HistoryRow(item: item) } }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: wide ? 215 : 148, maximum: 230), spacing: 18)], alignment: .leading, spacing: 26) {
                        ForEach(items) { item in MediaCard(item: item, wide: wide) }
                    }
                }
            } else {
                EmptyLibrary(symbol: emptySymbol, title: emptyTitle, detail: emptyDetail)
            }
        }
    }
    var catalogTitle: String {
        if let id = store.discoverFilter, let section = store.shelf(id) { return section.displayTitle }
        if let id = store.category, let category = store.categories.first(where: { $0.id == id }) { return category.name }
        return store.search.isEmpty ? store.destination.title : "Search results"
    }
    var emptySymbol: String { !store.search.isEmpty ? "magnifyingglass" : store.destination.symbol }
    var emptyTitle: String { if !store.search.isEmpty { return "No titles found" }; switch store.destination { case .favorites: return "Keep your favorites close"; case .continuing: return "Your next chapter starts here"; case .history: return "A fresh start"; default: return "Nothing here yet" } }
    var emptyDetail: String { if store.selectedYear != nil { return "No titles match this release year. Choose All years to include titles without release dates." }; if !store.search.isEmpty { return "Try a different title or choose another category." }; switch store.destination { case .favorites: return "Tap the heart on any channel, film, or series to save it here."; case .continuing: return "Start a movie or episode. Your unfinished titles will be waiting here."; case .history: return "The channels, movies, and episodes you watch will appear here."; default: return "This provider has no titles in this category. Refresh your library or choose another category." } }
}

struct MediaCard: View {
    @EnvironmentObject var store: AppStore
    let item: MediaItem
    var wide = false
    @State private var hovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                Artwork(item: item, fill: item.kind != .live).aspectRatio(wide ? 16/9 : 2/3, contentMode: .fit)
                LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .center, endPoint: .bottom)
                if item.kind == .live { Text("LIVE").font(.system(size: 8, weight: .bold)).tracking(1).padding(.horizontal, 7).padding(.vertical, 4).background(Theme.background.opacity(0.8), in: Capsule()).padding(10) }
                if let record = store.user.history[item.id], record.fraction > 0, item.kind != .live {
                    GeometryReader { geo in VStack { Spacer(); ZStack(alignment: .leading) { Theme.text.opacity(0.2); Theme.accent.frame(width: geo.size.width * record.fraction) }.frame(height: 3) } }
                }
                if hovered {
                    Color.black.opacity(0.28)
                    Image(systemName: item.kind == .series && item.seriesID == nil ? "list.bullet" : "play.fill").font(.system(size: 21)).foregroundStyle(Theme.background).padding(17).background(Theme.accent, in: Circle()).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack { HStack { Spacer(); Button { store.toggleFavorite(item) } label: { Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart").font(.system(size: 12, weight: .medium)).foregroundStyle(store.isFavorite(item) ? Color(hex: 0xBDDFB7) : .white).padding(8).background(.black.opacity(0.55), in: Circle()) }.buttonStyle(.plain).opacity(hovered || store.isFavorite(item) ? 1 : 0) }; Spacer() }.padding(8)
            }.clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(hovered ? Theme.accent.opacity(0.4) : Theme.border)).contentShape(Rectangle()).onTapGesture { store.showDetails(item) }
            Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                if let episode = item.episodeLabel { Text(episode) } else { Text(item.kind.title) }
                if let year = store.resolved(item).releaseYear { Text("·"); Text(String(year)) }
                if let rating = item.rating, rating != "0", rating != "" { Text("·"); Image(systemName: "star.fill").font(.system(size: 8)); Text(rating) }
            }.font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
        }.onHover { hovered = $0 }.contextMenu {
            Button(item.kind == .series && item.seriesID == nil ? "View episodes" : "Play") { store.open(item) }
            if item.kind != .live { Button("Description and details") { store.showDetails(item) } }
            Button(store.isFavorite(item) ? "Remove from favorites" : "Add to favorites") { store.toggleFavorite(item) }
            if store.user.history[item.id] != nil { Button("Remove from history") { store.removeHistory(item) } }
        }.help(item.title)
    }
}
struct HistoryRow: View {
    @EnvironmentObject var store: AppStore
    let item: MediaItem
    var body: some View {
        HStack(spacing: 17) {
            Artwork(item: item).frame(width: 110, height: 66).clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.episodeLabel ?? item.kind.title)
                    if let record = store.user.history[item.id] { Text("·"); Text(record.updatedAt, style: .relative); if item.kind != .live { Text("·"); Text(record.completed ? "Watched" : timeString(record.position) + " played") } }
                }.font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { store.open(item) } label: { Image(systemName: "play.fill") }.buttonStyle(QuietButton()).help("Play")
            Button { store.removeHistory(item) } label: { Image(systemName: "xmark").foregroundStyle(Theme.muted) }.buttonStyle(.plain).help("Remove from history")
        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}
