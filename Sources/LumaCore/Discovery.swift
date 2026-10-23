import Foundation

public enum DiscoverSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case bollywoodMovies, hollywoodMovies, bollywoodSeries, hollywoodSeries
    public var id: String { rawValue }
    public var kind: MediaKind { switch self { case .bollywoodMovies, .hollywoodMovies: .movie; default: .series } }
    public var title: String { switch self { case .bollywoodMovies: "Bollywood Movies"; case .hollywoodMovies: "Hollywood Movies"; case .bollywoodSeries: "Bollywood TV Series"; case .hollywoodSeries: "Hollywood TV Series" } }
    public func suggestedCategories(in categories: [Category]) -> Set<String> {
        Set(categories.filter { category in
            guard category.kind == kind else { return false }
            let name = category.name.lowercased()
            let bollywood = name.contains("bollywood")
            let hollywood = name.contains("hollywood")
            if bollywood || hollywood {
                switch self {
                case .bollywoodMovies, .bollywoodSeries: return bollywood && !hollywood
                case .hollywoodMovies, .hollywoodSeries: return hollywood && !bollywood
                }
            }
            switch self {
            case .bollywoodMovies, .bollywoodSeries:
                return name.contains("bollywood") || name.contains("hindi") || (kind == .series && name.contains("indian web"))
            case .hollywoodMovies, .hollywoodSeries:
                return name.contains("hollywood") || name.contains("english") || (kind == .series && ["usa", "us", "uk", "american", "british"].contains(where: { name.split(whereSeparator: { !$0.isLetter }).contains(Substring($0)) }))
            }
        }.map(\.id))
    }
}

/// A saved Discover row. Category and item IDs are provider-scoped by UserLibrary.
public struct DiscoverShelf: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var categoryIDs: Set<String>
    public var itemIDs: Set<String>
    public var favoritesOnly: Bool
    public var favoriteKinds: Set<MediaKind>
    public init(id: String = UUID().uuidString, title: String, categoryIDs: Set<String> = [], itemIDs: Set<String> = [], favoritesOnly: Bool = false, favoriteKinds: Set<MediaKind> = Set(MediaKind.allCases)) {
        self.id = id; self.title = title; self.categoryIDs = categoryIDs; self.itemIDs = itemIDs
        self.favoritesOnly = favoritesOnly; self.favoriteKinds = favoriteKinds
    }
    public var displayTitle: String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled section" : cleaned
    }
    public func includes(_ item: MediaItem, favorites: Set<String>) -> Bool {
        if favoritesOnly { return favoriteKinds.contains(item.kind) && favorites.contains(item.id) }
        return categoryIDs.contains(item.categoryID) || itemIDs.contains(item.id)
    }
    public var isEmptySelection: Bool { !favoritesOnly && categoryIDs.isEmpty && itemIDs.isEmpty }
}

public enum ReleaseYear {
    private static let metadataPattern = try! NSRegularExpression(pattern: #"(?<!\d)((?:18|19|20|21)\d{2})(?!\d)"#)
    private static let titlePattern = try! NSRegularExpression(pattern: #"[\(\[]((?:18|19|20|21)\d{2})[\)\]]"#)
    public static func value(metadata: String?, title: String = "") -> Int? {
        if let metadata, let value = match(metadata, regex: metadataPattern) { return value }
        return match(title, regex: titlePattern)
    }
    private static func match(_ text: String, regex: NSRegularExpression) -> Int? {
        let ns = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Int(ns.substring(with: result.range(at: 1)))
    }
}

public enum ProviderMetadata {
    public static func enriching(_ item: MediaItem, with info: [String: Any]) -> MediaItem {
        var item = item
        func text(_ keys: [String]) -> String? {
            for key in keys {
                let value: String
                if let string = info[key] as? String { value = string }
                else if let number = info[key] as? NSNumber { value = number.stringValue }
                else { continue }
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty, !["null", "n/a", "none"].contains(cleaned.lowercased()) { return cleaned }
            }
            return nil
        }
        item.summary = text(["plot", "description", "overview"]) ?? item.summary
        let dateKeys = ["year", "releaseDate", "release_date", "releasedate", "first_air_date", "air_date"]
        if let year = dateKeys.compactMap({ text([$0]) }).compactMap({ ReleaseYear.value(metadata: $0) }).first { item.year = String(year) }
        item.rating = text(["rating"]) ?? item.rating
        return item
    }
}

public struct SeriesDetails: Sendable {
    public var show: MediaItem
    public var episodes: [MediaItem]
    public init(show: MediaItem, episodes: [MediaItem]) { self.show = show; self.episodes = episodes }
}

// Monotonic time is supplied by the player, making the five-second behavior testable.
public struct PlaybackChromeState {
    public private(set) var visible = true
    public private(set) var deadline: TimeInterval = 5
    public init() {}
    public mutating func reveal(at time: TimeInterval) { visible = true; deadline = time + 5 }
    public mutating func update(at time: TimeInterval, mayHide: Bool) {
        if !mayHide { reveal(at: time) }
        else if time >= deadline { visible = false }
    }
}
