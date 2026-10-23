import Foundation
import LumaCore

final class LumaCoreTests {
    func testM3UCategoriesTitlesAndKinds() throws {
        let text = #"""
        #EXTM3U
        #EXTINF:-1 tvg-id="one" tvg-logo="https://example.com/logo.png" group-title="Bollywood, HD",Cinema, India
        https://example.com/live/1.ts
        #EXTINF:7200 group-title="Hollywood",A Movie
        https://example.com/movie/2.mp4
        #EXTINF:-1,Regional channel
        #EXTGRP:Regional
        https://example.com/live/3.m3u8
        """#
        let result = try M3UParser.parse(text)
        XCTAssertEqual(result.items.count, 3)
        XCTAssertEqual(result.items[0].title, "Cinema, India")
        XCTAssertEqual(result.categories.map(\.name), ["Bollywood, HD", "Hollywood", "Regional"])
        XCTAssertEqual(result.items.map(\.kind), [.live, .movie, .live])
        XCTAssertEqual(result.items[0].artwork?.host, "example.com")
    }
    func testPlaylistStableIDsDuplicatesAndRelativeURLs() throws {
        let text = "#EXTM3U\n#EXTINF:-1,One\nstream/1.ts\n#EXTINF:-1,Duplicate\nstream/1.ts"
        let first = try M3UParser.parse(text, relativeTo: URL(string: "https://example.com/list.m3u"))
        let second = try M3UParser.parse(text, relativeTo: URL(string: "https://example.com/list.m3u"))
        XCTAssertEqual(first.items.count, 1)
        XCTAssertEqual(first.items[0].id, second.items[0].id)
        XCTAssertEqual(first.items[0].url?.absoluteString, "https://example.com/stream/1.ts")
    }
    func testM3USeriesGroupingAndSeasonOrder() throws {
        let text = "\u{FEFF}#EXTM3U\n#EXTINF:-1 group-title=\"Drama\",My Show S02E01\nhttps://example.com/3.mkv\n#EXTINF:-1 group-title=\"Drama\",My Show S01E02\nhttps://example.com/2.mkv\n#EXTINF:-1 group-title=\"Drama\",My Show S01E01\nhttps://example.com/1.mkv"
        let result = try M3UParser.parse(text)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.title, "My Show")
        XCTAssertEqual(result.items.first?.kind, .series)
        let episodes = result.episodes[result.items[0].providerID] ?? []
        XCTAssertEqual(episodes.map { $0.season ?? 0 }, [1,1,2])
        XCTAssertEqual(episodes.map { $0.episode ?? 0 }, [1,2,1])
        XCTAssertTrue(episodes.allSatisfy { $0.url != nil })
        XCTAssertEqual(EpisodeOrder.next(after: episodes[1], in: episodes)?.season, 2)
    }
    func testPlaylistRejectsInvalidAndUnsupportedLinks() {
        XCTAssertThrowsError(try M3UParser.parse("<html>Server unavailable</html>"))
        XCTAssertThrowsError(try M3UParser.parse("#EXTM3U\n#EXTINF:-1,Nope\njavascript:alert(1)"))
        XCTAssertThrowsError(try M3UParser.parse("#EXTM3U\n#EXTINF:-1,Missing"))
    }
    func episode(_ id: String, season: Int, episode: Int) -> MediaItem {
        MediaItem(id: id, providerID: id, title: id, kind: .series, categoryID: "series:1", seriesID: "show", season: season, episode: episode)
    }
    func testEpisodeAutoplayCrossesSeasonNumerically() {
        let e1 = episode("1", season: 1, episode: 2)
        let e2 = episode("2", season: 1, episode: 10)
        let e3 = episode("3", season: 2, episode: 1)
        let e4 = episode("4", season: 10, episode: 1)
        XCTAssertEqual(EpisodeOrder.sorted([e4,e3,e2,e1]).map(\.id), ["1","2","3","4"])
        XCTAssertEqual(EpisodeOrder.next(after: e2, in: [e4,e3,e1,e2])?.id, e3.id)
        XCTAssertNil(EpisodeOrder.next(after: e4, in: [e4,e3,e1,e2]))
    }
    func testContinueWatchingDeduplicatesShowsAndExcludesLiveAndCompleted() throws {
        var state = UserLibrary()
        let older = episode("1", season: 1, episode: 1)
        let newer = episode("2", season: 1, episode: 2)
        state.history[older.id] = WatchRecord(item: older, position: 100, duration: 1000, updatedAt: Date(timeIntervalSince1970: 1))
        state.history[newer.id] = WatchRecord(item: newer, position: 200, duration: 1000, updatedAt: Date(timeIntervalSince1970: 2))
        let live = MediaItem(id: "live", title: "Live", kind: .live, categoryID: "live:1")
        state.record(live, position: 200, duration: 0)
        let movie = MediaItem(id: "movie", title: "Movie", kind: .movie, categoryID: "movie:1")
        state.record(movie, position: 1000, duration: 1000)
        XCTAssertEqual(state.continuing.map(\.id), [newer.id])
        XCTAssertTrue(state.history[movie.id]?.completed == true)
        state.favorites.insert(movie.id)
        let restored = try JSONDecoder().decode(UserLibrary.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.favorites, [movie.id])
        XCTAssertEqual(restored.continuing.first?.position, 200)
        state.record(newer, position: 1000, duration: 1000)
        XCTAssertTrue(state.continuing.isEmpty, file: #filePath, line: #line)
    }
    func testInvalidProgressIsIgnored() {
        var state = UserLibrary()
        let item = episode("1", season: 1, episode: 1)
        state.record(item, position: .nan, duration: .infinity)
        XCTAssertTrue(state.history.isEmpty)
        state.record(item, position: -5, duration: -1)
        XCTAssertEqual(state.history[item.id]?.position, 0)
    }
    func testStreamAddressesAndCredentialEncoding() throws {
        let source = Source(type: .xtream, address: "https://example.com:8080", username: "a user", password: "p&?#")
        let movie = MediaItem(id: "m1", providerID: "123", title: "Movie", kind: .movie, categoryID: "1", fileExtension: "mkv")
        XCTAssertEqual(source.streamURL(for: movie)?.pathExtension, "mkv")
        XCTAssertEqual(source.streamURL(for: movie)?.host, "example.com")
        XCTAssertTrue(source.streamURL(for: movie)!.absoluteString.contains("a%20user"))
        XCTAssertTrue(source.streamURL(for: movie)!.absoluteString.contains("p&%3F%23"))
        XCTAssertNil(source.streamURL(for: MediaItem(id: "show", title: "Show", kind: .series, categoryID: "1")))
    }
    func testReleaseMetadataAndMissingYears() {
        let movie = MediaItem(id: "m", title: "A title", kind: .movie, categoryID: "movies")
        let enriched = ProviderMetadata.enriching(movie, with: ["release_date": "2024-05-03", "description": " A provider synopsis. "])
        XCTAssertEqual(enriched.releaseYear, 2024)
        XCTAssertEqual(enriched.summary, "A provider synopsis.")
        XCTAssertEqual(ProviderMetadata.enriching(movie, with: ["year": 2023]).releaseYear, 2023)
        XCTAssertEqual(ProviderMetadata.enriching(movie, with: ["year": 0, "releasedate": "2025-06-01"]).releaseYear, 2025)
        XCTAssertNil(ProviderMetadata.enriching(movie, with: ["year": "0000-00-00"]).releaseYear)
        XCTAssertNil(ReleaseYear.value(metadata: nil, title: "2001 A Space Odyssey"))
        XCTAssertEqual(ReleaseYear.value(metadata: nil, title: "A film (2022)"), 2022)
        XCTAssertNil(ReleaseYear.value(metadata: nil, title: "A film 1080p"))
        XCTAssertEqual(ProviderMetadata.enriching(enriched, with: ["plot": "null"]).summary, enriched.summary)
    }
    func testDiscoverSuggestionsPreserveMediaKinds() {
        let categories = [
            LumaCore.Category(id: "m1", name: "BOLLYWOOD 2024", kind: .movie),
            LumaCore.Category(id: "m2", name: "HOLLYWOOD", kind: .movie),
            LumaCore.Category(id: "s1", name: "HINDI WEB SERIES", kind: .series),
            LumaCore.Category(id: "s2", name: "US | SERIES", kind: .series),
            LumaCore.Category(id: "s3", name: "RUSSIAN", kind: .series),
            LumaCore.Category(id: "l1", name: "BOLLYWOOD", kind: .live)
        ]
        XCTAssertEqual(DiscoverSection.bollywoodMovies.suggestedCategories(in: categories), ["m1"])
        XCTAssertEqual(DiscoverSection.hollywoodMovies.suggestedCategories(in: categories), ["m2"])
        XCTAssertEqual(DiscoverSection.bollywoodSeries.suggestedCategories(in: categories), ["s1"])
        XCTAssertEqual(DiscoverSection.hollywoodSeries.suggestedCategories(in: categories), ["s2"])
        let dubbed = [LumaCore.Category(id: "d", name: "HOLLYWOOD HINDI DUBBED", kind: .movie)]
        XCTAssertTrue(DiscoverSection.bollywoodMovies.suggestedCategories(in: dubbed).isEmpty)
        XCTAssertEqual(DiscoverSection.hollywoodMovies.suggestedCategories(in: dubbed), ["d"])
    }
    func testLegacyWatchStateSurvivesNewDiscoverPreferences() throws {
        let data = Data(#"{"favorites":["movie:1"],"history":{},"autoplay":false}"#.utf8)
        var state = try JSONDecoder().decode(UserLibrary.self, from: data)
        XCTAssertEqual(state.favorites, ["movie:1"])
        XCTAssertFalse(state.autoplay)
        XCTAssertTrue(state.discoverCategories.isEmpty)
        state.discoverCategories[DiscoverSection.bollywoodMovies.rawValue] = ["movie:2", "movie:3"]
        let restored = try JSONDecoder().decode(UserLibrary.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.discoverCategories, state.discoverCategories)
    }
    func testPlayerChromeFiveSecondInactivityAndReveal() {
        var chrome = PlaybackChromeState()
        chrome.reveal(at: 100)
        chrome.update(at: 104.99, mayHide: true)
        XCTAssertTrue(chrome.visible)
        chrome.update(at: 105, mayHide: true)
        XCTAssertFalse(chrome.visible)
        chrome.reveal(at: 108)
        XCTAssertTrue(chrome.visible)
        chrome.update(at: 112, mayHide: true)
        XCTAssertTrue(chrome.visible)
        chrome.update(at: 114, mayHide: false)
        XCTAssertTrue(chrome.visible)
        chrome.update(at: 118, mayHide: true)
        XCTAssertTrue(chrome.visible)
        chrome.update(at: 119, mayHide: true)
        XCTAssertFalse(chrome.visible)
    }
    func testPlaybackTimeFormatsAndCycle() {
        var mode = PlaybackTimeFormat.remaining
        XCTAssertEqual(mode.label(position: 83, duration: 120), "−0:37")
        mode = mode.next
        XCTAssertEqual(mode, .current)
        XCTAssertEqual(mode.label(position: 83, duration: 120), "1:23")
        mode = mode.next
        XCTAssertEqual(mode, .currentAndTotal)
        XCTAssertEqual(mode.label(position: 83, duration: 120), "1:23 / 2:00")
        XCTAssertEqual(mode.next, .remaining)
        XCTAssertEqual(PlaybackTimeFormat.remaining.label(position: 130, duration: 120), "−0:00")
        XCTAssertEqual(PlaybackTimeFormat.remaining.label(position: -3, duration: 120), "−2:00")
        XCTAssertEqual(PlaybackTimeFormat.remaining.label(position: 20, duration: 0), "--:--")
        XCTAssertEqual(PlaybackTimeFormat.currentAndTotal.label(position: 20, duration: .infinity), "0:20 / --:--")
        XCTAssertEqual(PlaybackTimeFormat.current.label(position: .nan, duration: 120), "0:00")
        XCTAssertEqual(PlaybackTimeFormat.remaining.label(position: 3660, duration: 7325), "−1:01:05")
    }
    func testDiscoverShelfMigrationKeepsExplicitChoices() throws {
        var state = try JSONDecoder().decode(UserLibrary.self, from: Data(#"{"favorites":["live:1"],"history":{},"autoplay":false,"discoverCategories":{"bollywoodSeries":["series:chosen"],"bollywoodMovies":[]}}"#.utf8))
        let categories = [LumaCore.Category(id: "series:hindi", name: "HINDI", kind: .series), LumaCore.Category(id: "series:chosen", name: "My chosen series", kind: .series), LumaCore.Category(id: "movie:bolly", name: "BOLLYWOOD", kind: .movie), LumaCore.Category(id: "live:docs", name: "Documentaries", kind: .live)]
        XCTAssertTrue(state.initializeDiscoverShelves(categories: categories))
        XCTAssertEqual(state.discoverShelves?.first(where: { $0.id == "bollywoodSeries" })?.categoryIDs, ["series:chosen"])
        XCTAssertTrue(state.discoverShelves?.first(where: { $0.id == "bollywoodMovies" })?.categoryIDs.isEmpty == true)
        XCTAssertEqual(state.discoverShelves?.last?.categoryIDs, ["live:docs"])
        XCTAssertEqual(state.favorites, ["live:1"])
        XCTAssertFalse(state.autoplay)
        let before = state.discoverShelves
        XCTAssertFalse(state.initializeDiscoverShelves(categories: []))
        XCTAssertEqual(state.discoverShelves, before)
        let restored = try JSONDecoder().decode(UserLibrary.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.discoverShelves, before)
        state.discoverShelves = []
        let deliberatelyEmpty = try JSONDecoder().decode(UserLibrary.self, from: JSONEncoder().encode(state))
        var empty = deliberatelyEmpty
        XCTAssertFalse(empty.initializeDiscoverShelves(categories: categories))
        XCTAssertEqual(empty.discoverShelves?.count, 0)
    }
    func testMixedDiscoverSelectionsAndFavoriteKinds() throws {
        let live = MediaItem(id: "live:1", title: "Documentary channel", kind: .live, categoryID: "live:other")
        let movie = MediaItem(id: "movie:1", title: "Documentary film", kind: .movie, categoryID: "movie:docs")
        let series = MediaItem(id: "series:1", title: "Documentary series", kind: .series, categoryID: "series:docs")
        let other = MediaItem(id: "movie:2", title: "Other film", kind: .movie, categoryID: "movie:other")
        let items = [live, movie, series, other]
        let shelf = DiscoverShelf(title: "Documentaries", categoryIDs: ["movie:docs", "series:docs"], itemIDs: [live.id, movie.id])
        XCTAssertEqual(items.filter { shelf.includes($0, favorites: []) }.map(\.id), [live.id, movie.id, series.id])
        let favorites = Set(items.map(\.id))
        let channels = DiscoverShelf(title: "Favorite TV Channels", favoritesOnly: true, favoriteKinds: [.live])
        XCTAssertEqual(items.filter { channels.includes($0, favorites: favorites) }.map(\.id), [live.id])
        XCTAssertFalse(channels.includes(live, favorites: []))
        XCTAssertFalse(DiscoverShelf(title: "Empty").includes(movie, favorites: favorites))
        XCTAssertEqual(DiscoverShelf(title: "  ").displayTitle, "Untitled section")
        var state = UserLibrary()
        state.discoverShelves = [channels, shelf]
        let restored = try JSONDecoder().decode(UserLibrary.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.discoverShelves, [channels, shelf])
    }
    func testLiveProviderIntegrationWhenConfigured() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["LUMA_TEST_SERVER"], let username = env["LUMA_TEST_USER"], let password = env["LUMA_TEST_PASSWORD"] else { throw XCTSkip("Set LUMA_TEST_SERVER, LUMA_TEST_USER, and LUMA_TEST_PASSWORD for the optional provider test.") }
        let client = ProviderClient(source: Source(type: .xtream, address: address, username: username, password: password))
        let library = try await client.load()
        XCTAssertFalse(library.items.isEmpty)
        XCTAssertFalse(library.categories.isEmpty)
        XCTAssertEqual(Set(library.items.map(\.id)).count, library.items.count)
        let categories = Set(library.categories.map(\.id))
        XCTAssertTrue(library.items.allSatisfy { categories.contains($0.categoryID) })
        if let movie = library.items.first(where: { $0.kind == .movie }) {
            let details = try await client.details(for: movie)
            XCTAssertEqual(details.id, movie.id)
        }
        if let show = library.items.first(where: { $0.kind == .series }) {
            let episodes = try await client.episodes(for: show)
            XCTAssertFalse(episodes.isEmpty)
            XCTAssertTrue(episodes.allSatisfy { $0.seriesID == show.providerID })
        }
    }
}

// A dependency-free check runner also works with Apple's Command Line Tools,
// which do not ship XCTest. A failed assertion exits with a nonzero status.
private var failures = 0
private func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) { if !value() { failures += 1; print("FAIL: \(file):\(line)") } }
private func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(!value(), file: file, line: line) }
private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(a == b, file: file, line: line) }
private func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(value == nil, file: file, line: line) }
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try expression(); XCTAssertTrue(false, file: file, line: line) } catch {} }
private struct XCTSkip: Error { let message: String; init(_ message: String) { self.message = message } }
@main struct Checks {
    static func main() async {
        let tests = LumaCoreTests()
        let checks: [(String, () throws -> Void)] = [
            ("M3U categories, titles, media kinds", tests.testM3UCategoriesTitlesAndKinds),
            ("Stable IDs, duplicate filtering, relative links", tests.testPlaylistStableIDsDuplicatesAndRelativeURLs),
            ("Invalid playlist rejection", tests.testPlaylistRejectsInvalidAndUnsupportedLinks),
            ("M3U episode grouping and season order", tests.testM3USeriesGroupingAndSeasonOrder),
            ("Autoplay order across seasons", tests.testEpisodeAutoplayCrossesSeasonNumerically),
            ("Continue watching, history and persistence", tests.testContinueWatchingDeduplicatesShowsAndExcludesLiveAndCompleted),
            ("Invalid progress rejection", tests.testInvalidProgressIsIgnored),
            ("Stream URLs and credential encoding", tests.testStreamAddressesAndCredentialEncoding),
            ("Release dates, descriptions and unknown years", tests.testReleaseMetadataAndMissingYears),
            ("Discover groups respect provider categories and media kind", tests.testDiscoverSuggestionsPreserveMediaKinds),
            ("Existing user data and Discover mapping persistence", tests.testLegacyWatchStateSurvivesNewDiscoverPreferences),
            ("Five-second player controls and activity reveal", tests.testPlayerChromeFiveSecondInactivityAndReveal),
            ("Remaining/current/total time cycle and edge cases", tests.testPlaybackTimeFormatsAndCycle),
            ("Discover migration retains explicit and empty category choices", tests.testDiscoverShelfMigrationKeepsExplicitChoices),
            ("Mixed Discover content, favorites types and saved order", tests.testMixedDiscoverSelectionsAndFavoriteKinds)
        ]
        for (name, check) in checks {
            let before = failures
            do { try check() } catch { failures += 1; print("FAIL: \(name)") }
            if failures == before { print("PASS: \(name)") }
        }
        do { try await tests.testLiveProviderIntegrationWhenConfigured(); print("PASS: Live provider authentication, catalog integrity and episodes") }
        catch let skip as XCTSkip { print("SKIP: \(skip.message)") }
        catch { failures += 1; print("FAIL: Provider integration: \((error as? ProviderError)?.localizedDescription ?? "network request failed")") }
        print("\(checks.count) local check groups; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
