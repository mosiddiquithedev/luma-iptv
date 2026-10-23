import SwiftUI
import LumaCore

enum Destination: String, CaseIterable {
    case home, live, movie, series, favorites, continuing, history, collection
    var title: String { switch self { case .home: "Discover"; case .live: "Live TV"; case .movie: "Movies"; case .series: "Series"; case .favorites: "Favorites"; case .continuing: "Continue watching"; case .history: "Watch history"; case .collection: "Discover section" } }
    var symbol: String { switch self { case .home: "square.grid.2x2"; case .live: "dot.radiowaves.left.and.right"; case .movie: "film"; case .series: "tv"; case .favorites: "heart"; case .continuing: "play.circle"; case .history: "clock.arrow.circlepath"; case .collection: "rectangle.stack" } }
    var kind: MediaKind? { MediaKind(rawValue: rawValue) }
}

@MainActor final class AppStore: ObservableObject {
    @Published var restoringSession = true
    @Published var sessionRestoreError: String?
    @Published var catalogLoadFailed = false
    @Published var source: Source?
    @Published var library = Library()
    @Published var user = UserLibrary()
    @Published var destination: Destination = .home { didSet { category = nil; search = ""; categorySearch = ""; selectedYear = nil; discoverFilter = nil } }
    @Published var categorySearch = ""
    @Published var selectedYear: Int?
    @Published var discoverFilter: String?
    @Published var showDiscoverSettings = false
    @Published var editingDiscoverShelfID: String?
    @Published var appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "dark") ?? .dark {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    @Published var selectedMovie: MediaItem?
    @Published var metadata: [String: MediaItem] = [:]
    @Published var metadataLoading: Set<String> = []
    @Published var metadataErrors: [String: String] = [:]
    @Published var category: String?
    @Published var search = ""
    @Published var loading = false
    @Published var error: String?
    @Published var loginError: String?
    @Published var showConnection = false
    @Published var selectedShow: MediaItem?
    @Published var episodes: [MediaItem] = []
    @Published var episodesLoading = false
    @Published var episodeError: String?
    @Published var playback: MediaItem?
    @Published var playbackQueue: [MediaItem] = []
    @Published var showSettings = false
    @Published var sortByName = false
    private var loadTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var episodeTask: Task<Void, Never>?
    private let storage = LibraryStorage()
    private let catalogLoader: @Sendable (Source) async throws -> Library
    init(catalogLoader: @escaping @Sendable (Source) async throws -> Library = { try await ProviderClient(source: $0).load() }) {
        self.catalogLoader = catalogLoader
    }
    private var itemsByKind: [MediaKind: [MediaItem]] = [:]
    private var yearsByID: [String: Int] = [:]
    var matchingCategories: [LumaCore.Category] {
        let term = categorySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return categories.filter { term.isEmpty || $0.name.localizedStandardContains(term) }
    }
    var discoverShelves: [DiscoverShelf] { user.discoverShelves ?? [] }
    func shelf(_ id: String) -> DiscoverShelf? { discoverShelves.first { $0.id == id } }
    func editDiscover(_ shelf: DiscoverShelf? = nil) { editingDiscoverShelfID = shelf?.id; showDiscoverSettings = true }
    func discoverItems(for shelf: DiscoverShelf, limit: Int = 14) -> [MediaItem] {
        Array(library.items.lazy.filter {
            shelf.includes($0, favorites: self.user.favorites) && ($0.kind == .live || self.selectedYear == nil || self.yearsByID[$0.id] == self.selectedYear)
        }.prefix(limit))
    }
    // Legacy templates remain useful for migrating old saved preferences and QA.
    func categoryIDs(for section: DiscoverSection) -> Set<String> { shelf(section.rawValue)?.categoryIDs ?? [] }
    func discoverItems(for section: DiscoverSection, limit: Int = 14) -> [MediaItem] {
        guard let shelf = shelf(section.rawValue) else { return [] }
        return discoverItems(for: shelf, limit: limit)
    }
    func browse(_ section: DiscoverSection) { if let shelf = shelf(section.rawValue) { browse(shelf) } }
    func browse(_ shelf: DiscoverShelf) {
        let year = selectedYear
        destination = .collection
        discoverFilter = shelf.id; selectedYear = year
    }
    @discardableResult func addDiscoverShelf(title: String = "New section", favoritesOnly: Bool = false, kinds: Set<MediaKind> = Set(MediaKind.allCases)) -> DiscoverShelf {
        let shelf = DiscoverShelf(title: title, favoritesOnly: favoritesOnly, favoriteKinds: kinds)
        user.discoverShelves = discoverShelves + [shelf]
        editingDiscoverShelfID = shelf.id; persist()
        return shelf
    }
    func updateDiscoverShelf(_ id: String, change: (inout DiscoverShelf) -> Void) {
        var shelves = discoverShelves
        guard let index = shelves.firstIndex(where: { $0.id == id }) else { return }
        change(&shelves[index]); user.discoverShelves = shelves; persist()
    }
    func moveDiscoverShelf(_ id: String, by offset: Int) {
        var shelves = discoverShelves
        guard let index = shelves.firstIndex(where: { $0.id == id }), shelves.indices.contains(index + offset) else { return }
        shelves.swapAt(index, index + offset); user.discoverShelves = shelves; persist()
    }
    func deleteDiscoverShelf(_ id: String) {
        user.discoverShelves = discoverShelves.filter { $0.id != id }
        if discoverFilter == id { discoverFilter = nil; destination = .home }
        if editingDiscoverShelfID == id { editingDiscoverShelfID = discoverShelves.first?.id }
        persist()
    }
    var availableYears: [Int] { Array(Set(scopedItems.filter { $0.kind != .live }.compactMap { yearsByID[$0.id] })).sorted(by: >) }
    private var scopedItems: [MediaItem] {
        var items: [MediaItem]
        switch destination {
        case .home, .collection: items = library.items
        case .favorites: items = library.items.filter { user.favorites.contains($0.id) }
        case .continuing: items = user.continuing.map(\.item)
        case .history: items = user.recent.map(\.item)
        default: items = itemsByKind[destination.kind ?? .live] ?? []
        }
        if let discoverFilter, let shelf = shelf(discoverFilter) { items = items.filter { shelf.includes($0, favorites: user.favorites) } }
        if let category { items = items.filter { $0.categoryID == category } }
        return items
    }
    func resolved(_ item: MediaItem) -> MediaItem { metadata[item.id] ?? item }
    func showDetails(_ item: MediaItem) {
        if item.kind == .series && item.seriesID == nil { openShow(item) }
        else if item.kind == .live { open(item) }
        else { selectedMovie = item }
    }
    func fetchDetails(_ item: MediaItem) async {
        guard metadata[item.id] == nil, !metadataLoading.contains(item.id), let source, item.kind == .movie else { return }
        metadataLoading.insert(item.id); metadataErrors[item.id] = nil
        defer { metadataLoading.remove(item.id) }
        do {
            let result = try await ProviderClient(source: source).details(for: item)
            try Task.checkCancellation()
            guard self.source?.address == source.address, self.source?.username == source.username else { return }
            metadata[item.id] = result
            if let year = result.releaseYear { yearsByID[item.id] = year }
        } catch is CancellationError { }
        catch { metadataErrors[item.id] = "Details could not be loaded. You can still play this title or try again." }
    }
    var categories: [LumaCore.Category] {
        library.categories.filter { destination.kind == nil || $0.kind == destination.kind }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var visibleItems: [MediaItem] {
        var items = scopedItems
        if let selectedYear { items = items.filter { $0.kind == .live || yearsByID[$0.id] == selectedYear } }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty { items = items.filter { $0.title.localizedStandardContains(term) } }
        if sortByName { items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
        return items
    }
    func count(_ kind: MediaKind) -> Int { itemsByKind[kind]?.count ?? 0 }
    func restore(loadSaved: @escaping @Sendable () async throws -> Source? = {
        try await Task.detached(priority: .userInitiated) { try SecureSource.load() }.value
    }) {
        guard source == nil, restoreTask == nil else { return }
        restoringSession = true; sessionRestoreError = nil
        restoreTask = Task {
            do {
                // Keychain access may wait for macOS approval. Keep the UI responsive.
                let saved = try await loadSaved()
                guard !Task.isCancelled, self.source == nil, !loading else { return }
                restoreTask = nil
                if let saved {
                    // Enter the dashboard before fetching the catalog. Network failures
                    // must never discard a remembered account or open the login form.
                    source = saved; user = storage.load(saved); destination = .home
                    restoringSession = false
                    connect(saved, remember: false)
                } else { restoringSession = false }
            } catch {
                guard !Task.isCancelled else { return }
                restoreTask = nil; restoringSession = false
                sessionRestoreError = "Your saved login could not be opened. Unlock your Mac or allow Luma to access its login in Keychain, then retry."
            }
        }
    }
    func cancelRestore() {
        restoreTask?.cancel(); restoreTask = nil
        restoringSession = false; sessionRestoreError = nil
    }
    func connect(_ newSource: Source, remember: Bool = true) {
        cancelRestore()
        loadTask?.cancel()
        loading = true; loginError = nil; error = nil; catalogLoadFailed = false
        loadTask = Task {
            do {
                let catalog = try await catalogLoader(newSource)
                try Task.checkCancellation()
                if remember {
                    do { try await Task.detached(priority: .userInitiated) { try SecureSource.save(newSource) }.value }
                    catch { self.error = error.localizedDescription }
                    try Task.checkCancellation()
                }
                if source?.address != newSource.address || source?.username != newSource.username {
                    playback = nil; destination = .home; selectedShow = nil; selectedMovie = nil; episodes = []
                }
                source = newSource; library = catalog
                itemsByKind = Dictionary(grouping: catalog.items, by: \.kind)
                yearsByID = Dictionary(uniqueKeysWithValues: catalog.items.compactMap { item in item.releaseYear.map { (item.id, $0) } })
                metadata = [:]; metadataLoading = []; metadataErrors = [:]
                user = storage.load(newSource)
                if user.initializeDiscoverShelves(categories: catalog.categories) { persist() }
                showConnection = false; loading = false
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                loading = false
                // Avoid including request URLs or credentials in surfaced network errors.
                let message = (error as? ProviderError)?.localizedDescription ?? "Could not reach the provider. Check your connection and server address, then try again."
                if source == nil || showConnection { loginError = message } else { self.error = message; catalogLoadFailed = true }
            }
        }
    }
    func cancelConnection() { loadTask?.cancel(); loading = false }
    func refresh() { if let source { connect(source, remember: false) } }
    func persist() {
        guard let source else { return }
        do { try storage.save(user, source: source) } catch { self.error = "Your watch progress could not be saved. Check available disk space and folder permissions." }
    }
    func favoriteID(for item: MediaItem) -> String {
        if let seriesID = item.seriesID, let show = library.items.first(where: { $0.kind == .series && $0.providerID == seriesID }) { return show.id }
        return item.id
    }
    func isFavorite(_ item: MediaItem) -> Bool { user.favorites.contains(favoriteID(for: item)) }
    func toggleFavorite(_ item: MediaItem) {
        let id = favoriteID(for: item)
        if user.favorites.contains(id) { user.favorites.remove(id) } else { user.favorites.insert(id) }
        persist()
    }
    func record(_ item: MediaItem, position: Double, duration: Double, completed: Bool = false) {
        user.record(item, position: position, duration: duration, completed: completed); persist()
    }
    func open(_ item: MediaItem) {
        if item.kind == .series, item.seriesID == nil { openShow(item); return }
        if let seriesID = item.seriesID, let show = library.items.first(where: { $0.kind == .series && $0.providerID == seriesID }) {
            openShow(show, play: item)
        } else { playbackQueue = []; playback = item }
    }
    func openShow(_ show: MediaItem, play item: MediaItem? = nil) {
        episodeTask?.cancel()
        selectedShow = show; episodes = []; episodeError = nil; episodesLoading = true
        guard let source else { return }
        episodeTask = Task {
            do {
                let result: [MediaItem]
                if source.type == .playlist { result = library.episodes[show.providerID] ?? [] }
                else {
                    let detail = try await ProviderClient(source: source).seriesDetails(for: show)
                    try Task.checkCancellation()
                    metadata[show.id] = detail.show
                    if let year = detail.show.releaseYear { yearsByID[show.id] = year }
                    result = detail.episodes
                }
                try Task.checkCancellation()
                episodes = result; episodesLoading = false
                if let item {
                    playbackQueue = result; playback = item; selectedShow = nil
                }
            } catch is CancellationError { }
            catch { episodesLoading = false; episodeError = (error as? ProviderError)?.localizedDescription ?? "Episodes could not be loaded. Try again when the provider is available." }
        }
    }
    func playEpisode(_ item: MediaItem) { playbackQueue = episodes; playback = item; selectedShow = nil }
    func nextEpisode(after item: MediaItem) -> MediaItem? { EpisodeOrder.next(after: item, in: playbackQueue) }
    func clearHistory() { user.history = [:]; persist() }
    func removeHistory(_ item: MediaItem) { user.history.removeValue(forKey: item.id); persist() }
    func disconnect() {
        cancelRestore()
        loadTask?.cancel(); episodeTask?.cancel(); SecureSource.delete(); playback = nil; source = nil
        library = Library(); itemsByKind = [:]; user = UserLibrary(); error = nil; loginError = nil; loading = false; catalogLoadFailed = false
    }
}
