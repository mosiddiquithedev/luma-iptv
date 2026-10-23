import Foundation

public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case live, movie, series
    public var title: String { switch self { case .live: "Live TV"; case .movie: "Movies"; case .series: "Series" } }
    public var symbol: String { switch self { case .live: "dot.radiowaves.left.and.right"; case .movie: "film"; case .series: "tv" } }
}

public struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var providerID: String
    public var title: String
    public var kind: MediaKind
    public var categoryID: String
    public var artwork: URL?
    public var url: URL?
    public var fileExtension: String?
    public var summary: String?
    public var rating: String?
    public var year: String?
    public var seriesID: String?
    public var season: Int?
    public var episode: Int?
    public init(id: String, providerID: String = "", title: String, kind: MediaKind, categoryID: String, artwork: URL? = nil, url: URL? = nil, fileExtension: String? = nil, summary: String? = nil, rating: String? = nil, year: String? = nil, seriesID: String? = nil, season: Int? = nil, episode: Int? = nil) {
        self.id = id; self.providerID = providerID; self.title = title; self.kind = kind; self.categoryID = categoryID; self.artwork = artwork; self.url = url; self.fileExtension = fileExtension; self.summary = summary; self.rating = rating; self.year = year; self.seriesID = seriesID; self.season = season; self.episode = episode
    }
    public var releaseYear: Int? { ReleaseYear.value(metadata: year, title: title) }
    public var episodeLabel: String? { guard let season, let episode else { return nil }; return "S\(season) · E\(episode)" }
}

public struct Category: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: MediaKind
    public init(id: String, name: String, kind: MediaKind) { self.id = id; self.name = name; self.kind = kind }
}

public struct Library: Codable, Sendable {
    public var items: [MediaItem]
    public var categories: [Category]
    public var episodes: [String: [MediaItem]]
    public init(items: [MediaItem] = [], categories: [Category] = [], episodes: [String: [MediaItem]] = [:]) { self.items = items; self.categories = categories; self.episodes = episodes }
}

public enum SourceType: String, Codable, Sendable { case xtream, playlist }
public struct Source: Codable, Sendable {
    public var type: SourceType
    public var address: String
    public var username: String
    public var password: String
    public var name: String
    public init(type: SourceType, address: String, username: String = "", password: String = "", name: String = "My library") {
        self.type = type; self.address = address; self.username = username; self.password = password; self.name = name
    }
    public var baseURL: URL? {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: raw.contains("://") ? raw : "https://" + raw)
    }
    public func streamURL(for item: MediaItem) -> URL? {
        if let url = item.url { return url }
        guard let base = baseURL, item.kind != .series || item.seriesID != nil else { return nil }
        let path = item.seriesID != nil ? "series" : (item.kind == .live ? "live" : "movie")
        let ext = item.fileExtension ?? (item.kind == .live ? "ts" : "mp4")
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        let pieces = [path, username, password, item.providerID + "." + ext].map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        let basePath = components.percentEncodedPath.replacingOccurrences(of: "/player_api.php", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + (basePath.isEmpty ? "" : basePath + "/") + pieces.joined(separator: "/")
        components.query = nil; components.fragment = nil
        return components.url
    }
}

public struct WatchRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { item.id }
    public var item: MediaItem
    public var position: Double
    public var duration: Double
    public var updatedAt: Date
    public var completed: Bool
    public var fraction: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
    public init(item: MediaItem, position: Double, duration: Double, updatedAt: Date = Date(), completed: Bool = false) {
        self.item = item; self.position = position; self.duration = duration; self.updatedAt = updatedAt; self.completed = completed
    }
}

public struct UserLibrary: Codable, Sendable {
    public var favorites: Set<String> = []
    public var history: [String: WatchRecord] = [:]
    public var autoplay = true
    public var discoverCategories: [String: Set<String>] = [:]
    // nil is an old library needing migration; [] deliberately means no sections.
    public var discoverShelves: [DiscoverShelf]?
    public init() {}
    enum CodingKeys: String, CodingKey { case favorites, history, autoplay, discoverCategories, discoverShelves }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try values.decodeIfPresent(Set<String>.self, forKey: .favorites) ?? []
        history = try values.decodeIfPresent([String: WatchRecord].self, forKey: .history) ?? [:]
        autoplay = try values.decodeIfPresent(Bool.self, forKey: .autoplay) ?? true
        discoverCategories = try values.decodeIfPresent([String: Set<String>].self, forKey: .discoverCategories) ?? [:]
        discoverShelves = try values.decodeIfPresent([DiscoverShelf].self, forKey: .discoverShelves)
    }
    @discardableResult public mutating func initializeDiscoverShelves(categories: [Category]) -> Bool {
        guard discoverShelves == nil else { return false }
        var shelves = DiscoverSection.allCases.map { section in
            DiscoverShelf(id: section.rawValue, title: section.title, categoryIDs: discoverCategories[section.rawValue] ?? section.suggestedCategories(in: categories))
        }
        let liveIDs = Set(categories.filter { $0.kind == .live }.map(\.id))
        if !liveIDs.isEmpty { shelves.append(DiscoverShelf(id: "liveChannels", title: "On your channels", categoryIDs: liveIDs)) }
        discoverShelves = shelves
        return true
    }
    public var recent: [WatchRecord] { history.values.sorted { $0.updatedAt > $1.updatedAt } }
    public var continuing: [WatchRecord] {
        var seen = Set<String>()
        return recent.filter { record in
            guard record.item.kind != .live else { return false }
            let key = record.item.seriesID.map { "series-" + $0 } ?? record.id
            guard seen.insert(key).inserted else { return false }
            return !record.completed && record.position > 5
        }
    }
    public mutating func record(_ item: MediaItem, position: Double, duration: Double, completed: Bool = false) {
        guard position.isFinite, duration.isFinite else { return }
        history[item.id] = WatchRecord(item: item, position: max(0, position), duration: max(0, duration), completed: completed || (duration > 0 && position / duration >= 0.95))
    }
}

public enum EpisodeOrder {
    public static func sorted(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted { ($0.season ?? 0, $0.episode ?? 0, $0.title) < ($1.season ?? 0, $1.episode ?? 0, $1.title) }
    }
    public static func next(after item: MediaItem, in episodes: [MediaItem]) -> MediaItem? {
        let ordered = sorted(episodes)
        guard let i = ordered.firstIndex(where: { $0.id == item.id }), i + 1 < ordered.count else { return nil }
        return ordered[i + 1]
    }
}
