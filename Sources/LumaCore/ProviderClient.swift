import Foundation

public enum ProviderError: LocalizedError {
    case invalidAddress, invalidCredentials, invalidPlaylist, emptyPlaylist, server(Int), badResponse, inactiveAccount, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter a valid HTTP or HTTPS provider address."
        case .invalidCredentials: return "The provider rejected these credentials. Check your username and password."
        case .inactiveAccount: return "This account is inactive or expired. Contact your IPTV provider."
        case .invalidPlaylist: return "This file is not an M3U playlist. It should begin with #EXTM3U."
        case .emptyPlaylist: return "The playlist contains no supported stream links."
        case .server(let code): return "The provider returned HTTP \(code). Check the address or try again later."
        case .badResponse: return "The provider returned an unexpected response. Check that this is an Xtream Codes server."
        case .tooLarge: return "This playlist is too large to import (maximum 100 MB)."
        }
    }
}

public struct ProviderClient: Sendable {
    public let source: Source
    public init(source: Source) { self.source = source }
    func apiURL(action: String? = nil, extra: [URLQueryItem] = []) throws -> URL {
        guard let base = source.baseURL, ["http", "https"].contains(base.scheme?.lowercased() ?? ""), base.host != nil else { throw ProviderError.invalidAddress }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = components.path.replacingOccurrences(of: "/player_api.php", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + (components.path.isEmpty ? "" : components.path + "/") + "player_api.php"
        components.queryItems = [URLQueryItem(name: "username", value: source.username), URLQueryItem(name: "password", value: source.password)]
        if let action { components.queryItems?.append(URLQueryItem(name: "action", value: action)) }
        components.queryItems?.append(contentsOf: extra)
        guard let url = components.url else { throw ProviderError.invalidAddress }
        return url
    }
    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue("Luma/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderError.badResponse }
        guard (200..<300).contains(response.statusCode) else { throw ProviderError.server(response.statusCode) }
        guard data.count < 100_000_000 else { throw ProviderError.tooLarge }
        return data
    }
    func json(action: String? = nil, extra: [URLQueryItem] = []) async throws -> Any {
        let data = try await data(from: apiURL(action: action, extra: extra))
        do { return try JSONSerialization.jsonObject(with: data) } catch { throw ProviderError.badResponse }
    }
    public func load() async throws -> Library {
        if source.type == .playlist {
            guard let url = source.baseURL else { throw ProviderError.invalidAddress }
            let bytes: Data
            if url.isFileURL { bytes = try Data(contentsOf: url) } else {
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw ProviderError.invalidAddress }
                bytes = try await data(from: url)
            }
            guard bytes.count < 100_000_000 else { throw ProviderError.tooLarge }
            guard let text = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) else { throw ProviderError.invalidPlaylist }
            return try M3UParser.parse(text, relativeTo: url)
        }
        guard let auth = try await json() as? [String: Any], let user = auth["user_info"] as? [String: Any] else { throw ProviderError.badResponse }
        guard string(user["auth"]) == "1" else { throw ProviderError.invalidCredentials }
        if let status = user["status"] as? String, status.lowercased() != "active" { throw ProviderError.inactiveAccount }
        async let live = catalog(.live)
        async let movies = catalog(.movie)
        async let series = catalog(.series)
        let libraries = try await [live, movies, series]
        return Library(items: libraries.flatMap(\.items), categories: libraries.flatMap(\.categories))
    }
    func catalog(_ kind: MediaKind) async throws -> Library {
        let prefix = kind == .live ? "live" : (kind == .movie ? "vod" : "series")
        async let categoriesJSON = json(action: "get_\(prefix)_categories")
        async let itemsJSON = json(action: kind == .series ? "get_series" : "get_\(prefix)_streams")
        let (rawCategories, rawItems) = try await (categoriesJSON, itemsJSON)
        guard let categoryRows = rawCategories as? [[String: Any]], let itemRows = rawItems as? [[String: Any]] else { throw ProviderError.badResponse }
        var categories = categoryRows.map { Category(id: kind.rawValue + ":" + string($0["category_id"]), name: string($0["category_name"]), kind: kind) }
        var categoryIDs = Set(categories.map(\.id))
        var seen = Set<String>()
        let items = itemRows.compactMap { row -> MediaItem? in
            let providerID = string(row[kind == .series ? "series_id" : "stream_id"])
            guard !providerID.isEmpty else { return nil }
            let id = kind.rawValue + ":" + providerID
            guard seen.insert(id).inserted else { return nil }
            let categoryID = kind.rawValue + ":" + string(row["category_id"])
            if categoryIDs.insert(categoryID).inserted { categories.append(Category(id: categoryID, name: "Uncategorized", kind: kind)) }
            let item = MediaItem(id: id, providerID: providerID, title: string(row["name"]), kind: kind, categoryID: categoryID, artwork: URL(string: string(row[kind == .series ? "cover" : "stream_icon"])), fileExtension: optionalString(row["container_extension"]), summary: optionalString(row["plot"]), rating: optionalString(row["rating"]), year: optionalString(row["year"]) ?? optionalString(row["releaseDate"]))
            return ProviderMetadata.enriching(item, with: row)
        }
        return Library(items: items, categories: categories)
    }
    public func details(for item: MediaItem) async throws -> MediaItem {
        guard source.type == .xtream, item.kind == .movie else { return item }
        guard let root = try await json(action: "get_vod_info", extra: [URLQueryItem(name: "vod_id", value: item.providerID)]) as? [String: Any] else { throw ProviderError.badResponse }
        let data = root["movie_data"] as? [String: Any] ?? [:]
        let info = root["info"] as? [String: Any] ?? [:]
        return ProviderMetadata.enriching(ProviderMetadata.enriching(item, with: data), with: info)
    }
    public func episodes(for show: MediaItem) async throws -> [MediaItem] { try await seriesDetails(for: show).episodes }
    public func seriesDetails(for show: MediaItem) async throws -> SeriesDetails {
        guard let root = try await json(action: "get_series_info", extra: [URLQueryItem(name: "series_id", value: show.providerID)]) as? [String: Any] else { throw ProviderError.badResponse }
        let enriched = ProviderMetadata.enriching(show, with: root["info"] as? [String: Any] ?? [:])
        if let empty = root["episodes"] as? [Any], empty.isEmpty { return SeriesDetails(show: enriched, episodes: []) }
        guard let seasons = root["episodes"] as? [String: Any] else { throw ProviderError.badResponse }
        var results: [MediaItem] = []
        for (seasonNumber, value) in seasons {
            guard let episodes = value as? [[String: Any]] else { continue }
            for row in episodes {
                let episodeID = string(row["id"])
                guard !episodeID.isEmpty else { continue }
                let info = row["info"] as? [String: Any] ?? [:]
                let episode = MediaItem(id: "episode:" + episodeID, providerID: episodeID, title: optionalString(row["title"]) ?? show.title, kind: .series, categoryID: show.categoryID, artwork: URL(string: string(info["movie_image"])) ?? show.artwork, fileExtension: optionalString(row["container_extension"]) ?? "mp4", summary: optionalString(info["plot"]), seriesID: show.providerID, season: Int(string(row["season"])) ?? Int(seasonNumber), episode: Int(string(row["episode_num"])))
                results.append(ProviderMetadata.enriching(episode, with: info))
            }
        }
        return SeriesDetails(show: enriched, episodes: EpisodeOrder.sorted(results))
    }
    func string(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }
    func optionalString(_ value: Any?) -> String? { let s = string(value); return s.isEmpty ? nil : s }
}
