import Foundation

public enum M3UParser {
    public static func parse(_ text: String, relativeTo base: URL? = nil) throws -> Library {
        let text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else { throw ProviderError.invalidPlaylist }
        var items: [MediaItem] = []
        var categories: [Category] = []
        var categoryKeys = Set<String>()
        var ids = Set<String>()
        var showIDs = Set<String>()
        var episodes: [String: [MediaItem]] = [:]
        var info: String?
        var group: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") { info = line; group = nil; continue }
            if line.hasPrefix("#EXTGRP:") { group = String(line.dropFirst(8)); continue }
            guard !line.isEmpty, !line.hasPrefix("#"), let metadata = info else { continue }
            defer { info = nil; group = nil }
            guard let url = URL(string: line, relativeTo: base)?.absoluteURL, ["http", "https", "rtsp", "rtmp", "udp", "file"].contains(url.scheme?.lowercased() ?? "") else { continue }
            let attrs = attributes(metadata)
            let title = displayTitle(metadata) ?? attrs["tvg-name"] ?? "Untitled channel"
            let category = attrs["group-title"] ?? group ?? "Uncategorized"
            let ext = url.pathExtension.lowercased()
            let durationText = metadata.dropFirst(8).prefix { $0 != " " && $0 != "," }
            let isVOD = (Double(durationText) ?? -1) > 0 || ["mp4", "mkv", "avi", "mov", "m4v"].contains(ext)
            let episodeInfo = episodeIdentity(title)
            let kind: MediaKind = episodeInfo != nil ? .series : (isVOD ? .movie : .live)
            let categoryID = kind.rawValue + ":" + category
            // Deterministic IDs preserve favorites and progress when a playlist is refreshed.
            let id = "m3u:" + stableID(url.absoluteString)
            guard ids.insert(id).inserted else { continue }
            if categoryKeys.insert(categoryID).inserted { categories.append(Category(id: categoryID, name: category, kind: kind)) }
            let artwork = attrs["tvg-logo"].flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
            if let episodeInfo {
                let showID = "m3u-show:" + stableID(category + ":" + episodeInfo.title.lowercased())
                if showIDs.insert(showID).inserted {
                    items.append(MediaItem(id: showID, providerID: showID, title: episodeInfo.title, kind: .series, categoryID: categoryID, artwork: artwork, summary: attrs["series-description"], year: attrs["series-year"] ?? attrs["year"] ?? attrs["release-date"]))
                }
                episodes[showID, default: []].append(MediaItem(id: id, title: title, kind: .series, categoryID: categoryID, artwork: artwork, url: url, summary: attrs["description"] ?? attrs["tvg-description"], year: attrs["year"] ?? attrs["release-date"], seriesID: showID, season: episodeInfo.season, episode: episodeInfo.episode))
            } else {
                items.append(MediaItem(id: id, title: title, kind: kind, categoryID: categoryID, artwork: artwork, url: url, summary: attrs["description"] ?? attrs["tvg-description"], year: attrs["year"] ?? attrs["release-date"]))
            }
        }
        guard !items.isEmpty else { throw ProviderError.emptyPlaylist }
        return Library(items: items, categories: categories, episodes: episodes.mapValues { EpisodeOrder.sorted($0) })
    }
    static func episodeIdentity(_ title: String) -> (title: String, season: Int, episode: Int)? {
        let patterns = [#"(?i)^(.+?)[ ._-]+s(\d{1,2})[ ._-]*e(\d{1,3})(?:\b|[ ._-])"#, #"(?i)^(.+?)[ ._-]+(\d{1,2})x(\d{1,3})(?:\b|[ ._-])"#]
        let ns = title as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)), let season = Int(ns.substring(with: match.range(at: 2))), let episode = Int(ns.substring(with: match.range(at: 3))) else { continue }
            return (ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces), season, episode)
        }
        return nil
    }
    static func attributes(_ text: String) -> [String: String] {
        let pattern = #"([\w-]+)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let ns = text as NSString
        return Dictionary(regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { (ns.substring(with: $0.range(at: 1)).lowercased(), ns.substring(with: $0.range(at: 2))) }, uniquingKeysWith: { _, last in last })
    }
    static func displayTitle(_ text: String) -> String? {
        var quoted = false
        for i in text.indices {
            if text[i] == "\"" { quoted.toggle() }
            if text[i] == ",", !quoted {
                let title = text[text.index(after: i)...].trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : title
            }
        }
        return nil
    }
    public static func stableID(_ string: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 { hash ^= UInt64(byte); hash = hash &* 1099511628211 }
        return String(hash, radix: 16)
    }
}
