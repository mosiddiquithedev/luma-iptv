#if DEBUG
import AppKit
import SwiftUI
import LumaCore

// Opt-in, development-only render checks. No credentials are stored in this mode.
@MainActor enum DebugQA {
    static func run(store: AppStore) async -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let mode = env["LUMA_QA_MODE"] else { return false }
        let output = URL(fileURLWithPath: env["LUMA_QA_OUTPUT"] ?? "/tmp/luma-qa")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if mode == "startup", let playlist = env["LUMA_QA_PLAYLIST"] {
            await checkStartup(store: store, playlist: playlist, output: output)
            return true
        }
        if mode == "login" { store.cancelRestore() }
        if ["autoplay", "resume", "improvements", "controls", "discover"].contains(mode), let playlist = env["LUMA_QA_PLAYLIST"] {
            let fixtureSource = Source(type: .playlist, address: playlist, name: "Playback checks")
            if mode == "discover" {
                var oldState = UserLibrary()
                oldState.discoverCategories[DiscoverSection.bollywoodSeries.rawValue] = ["series:English Series"]
                if let preview = try? await ProviderClient(source: fixtureSource).load(), let live = preview.items.first(where: { $0.kind == .live }) { oldState.favorites.insert(live.id) }
                try? LibraryStorage().save(oldState, source: fixtureSource)
            }
            store.connect(fixtureSource, remember: false)
            while store.loading { try? await Task.sleep(for: .milliseconds(100)) }
        } else if mode != "login", let server = env["LUMA_TEST_SERVER"], let user = env["LUMA_TEST_USER"], let password = env["LUMA_TEST_PASSWORD"] {
            store.connect(Source(type: .xtream, address: server, username: user, password: password, name: "My IPTV library"), remember: false)
            while store.loading { try? await Task.sleep(for: .milliseconds(500)) }
        }
        try? await Task.sleep(for: .seconds(3))
        render(name: "\(mode)-library", output: output)
        var report: [String: Any] = ["windows": NSApp.windows.count, "items": store.library.items.count, "categories": store.library.categories.count, "authenticated": store.source != nil, "connectionError": store.loginError ?? ""]
        if ["player", "live"].contains(mode), let item = store.library.items.first(where: { $0.kind == (mode == "live" ? .live : .movie) }) {
            store.open(item)
            try? await Task.sleep(for: .seconds(15))
            render(name: "player-video", output: output)
            report["playbackStarted"] = store.playback != nil
            report["savedProgress"] = store.user.history[item.id]?.position ?? 0
            store.playback = nil
        }
        if mode == "resume", let item = store.library.items.first {
            store.record(item, position: 12, duration: 30)
            store.open(item)
            try? await Task.sleep(for: .seconds(8))
            store.playback = nil
            try? await Task.sleep(for: .seconds(1))
            let position = store.user.history[item.id]?.position ?? 0
            report["savedPosition"] = position
            report["resumedPastSavedPosition"] = position > 15 && position < 28
        }
        if mode == "autoplay", let show = store.library.items.first {
            store.user.autoplay = true
            store.openShow(show)
            while store.episodesLoading { try? await Task.sleep(for: .milliseconds(100)) }
            if let first = store.episodes.first {
                let episodeIDs = store.episodes.map(\.id)
                store.playEpisode(first)
                try? await Task.sleep(for: .seconds(19))
                report["episodeCount"] = episodeIDs.count
                report["firstCompleted"] = store.user.history[first.id]?.completed ?? false
                report["autoplayAdvanced"] = store.playback?.id == episodeIDs.last && episodeIDs.count > 1
                report["secondProgress"] = episodeIDs.last.flatMap { store.user.history[$0]?.position } ?? 0
                render(name: "autoplay-complete", output: output)
                store.playback = nil
            }
        }
        if mode == "improvements" {
            let previousAppearance = store.appearance
            store.appearance = .dark
            store.destination = .home
            report["fourDiscoverSections"] = DiscoverSection.allCases.allSatisfy { !store.discoverItems(for: $0).isEmpty }
            store.selectedYear = 2024
            report["discoverYearFilter"] = DiscoverSection.allCases.flatMap { store.discoverItems(for: $0) }.allSatisfy { $0.releaseYear == 2024 }
            store.browse(.bollywoodMovies)
            report["viewAllKeepsSectionAndYear"] = store.selectedYear == 2024 && store.visibleItems.allSatisfy { $0.categoryID.contains("Bollywood") && $0.releaseYear == 2024 }
            store.destination = .movie; store.categorySearch = "hOlLy"
            report["independentCategorySearch"] = store.matchingCategories.count == 1 && store.search.isEmpty
            store.appearance = .light
            try? await Task.sleep(for: .seconds(1))
            render(name: "light-categories", output: output)
            store.destination = .home
            try? await Task.sleep(for: .seconds(1))
            render(name: "light-discover", output: output)
            store.appearance = .dark
            try? await Task.sleep(for: .seconds(1))
            render(name: "dark-discover", output: output)
            if let movie = store.library.items.first(where: { $0.kind == .movie }) {
                store.showDetails(movie)
                try? await Task.sleep(for: .seconds(1))
                report["movieDescription"] = store.resolved(movie).summary?.isEmpty == false
                render(name: "movie-description", output: output)
                store.selectedMovie = nil
                if let show = store.library.items.first(where: { $0.kind == .series }) {
                    store.openShow(show)
                    while store.episodesLoading { try? await Task.sleep(for: .milliseconds(100)) }
                    report["episodeDescription"] = store.episodes.first?.summary?.isEmpty == false
                    try? await Task.sleep(for: .seconds(1))
                    render(name: "series-description", output: output)
                    store.selectedShow = nil
                }
                store.open(movie)
                try? await Task.sleep(for: .seconds(2))
                if let controller = PlayerQAProbe.controller, let chrome = PlayerQAProbe.chrome {
                    let initialVolume = controller.volume
                    _ = PlayerQAProbe.key?(126)
                    report["upIncreasesVolume"] = controller.volume == min(100, initialVolume + 5)
                    _ = PlayerQAProbe.key?(125)
                    report["downDecreasesVolume"] = controller.volume == initialVolume
                    for _ in 0..<25 { _ = PlayerQAProbe.key?(126) }
                    report["volumeUpperBound"] = controller.volume == 100
                    for _ in 0..<25 { _ = PlayerQAProbe.key?(125) }
                    report["volumeLowerBound"] = controller.volume == 0
                    controller.volume = initialVolume
                    PlayerQAProbe.click?()
                    report["videoClickPauses"] = !controller.playing
                    PlayerQAProbe.click?()
                    report["videoClickResumes"] = controller.playing
                    // Wait for the native decoder to start, then for the idle deadline.
                    for _ in 0..<20 {
                        if !controller.buffering { break }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    chrome.reveal()
                    try? await Task.sleep(for: .milliseconds(5500))
                    report["controlsHideAfterFiveSeconds"] = !chrome.state.visible
                    render(name: "player-hidden-controls", output: output)
                    chrome.reveal()
                    report["activityRevealsControls"] = chrome.state.visible
                    render(name: "player-visible-controls", output: output)
                    report["nativePlaybackAdvanced"] = controller.position > 0
                }
                store.playback = nil
                try? await Task.sleep(for: .seconds(1))
                for _ in 0..<3 {
                    store.open(movie)
                    try? await Task.sleep(for: .seconds(1))
                    store.playback = nil
                    try? await Task.sleep(for: .seconds(1))
                }
                report["repeatedPlayerTeardown"] = true
            }
            store.appearance = previousAppearance
        }
        if mode == "controls", let movie = store.library.items.first(where: { $0.kind == .movie }) {
            store.open(movie)
            try? await Task.sleep(for: .seconds(2))
            if let manager = PlayerQAProbe.windowController, let window = manager.window {
                let original = window.frame
                manager.toggleMaximize()
                if let target = window.screen?.visibleFrame {
                    report["maximizesToVisibleScreen"] = abs(window.frame.width - target.width) < 2 && abs(window.frame.height - target.height) < 2
                }
                manager.toggleMaximize()
                report["restoresPreviousWindowFrame"] = abs(window.frame.width - original.width) < 2 && abs(window.frame.height - original.height) < 2
                _ = PlayerQAProbe.key?(3)
                try? await Task.sleep(for: .seconds(2))
                report["fEntersFullscreen"] = window.styleMask.contains(.fullScreen)
                _ = PlayerQAProbe.key?(3)
                try? await Task.sleep(for: .seconds(2))
                report["fExitsFullscreen"] = !window.styleMask.contains(.fullScreen)
                render(name: "new-player-controls", output: output)
            }
            // Leave the local clip open for native mouse/keyboard verification.
        }
        if mode == "discover", let source = store.source {
            report["migratedExplicitSeriesCategories"] = store.shelf(DiscoverSection.bollywoodSeries.rawValue)?.categoryIDs == ["series:English Series"]
            store.updateDiscoverShelf(DiscoverSection.bollywoodSeries.rawValue) { $0.categoryIDs = ["series:Bollywood Series"] }
            report["customSeriesSelection"] = store.discoverItems(for: .bollywoodSeries).allSatisfy { $0.categoryID == "series:Bollywood Series" } && !store.discoverItems(for: .bollywoodSeries).isEmpty
            if let live = store.library.items.first(where: { $0.kind == .live }), let secondLive = store.library.items.last(where: { $0.kind == .live }), let movie = store.library.items.first(where: { $0.categoryID == "movie:Documentaries" }) {
                let docs = store.addDiscoverShelf(title: "Documentaries")
                store.updateDiscoverShelf(docs.id) { $0.categoryIDs = ["movie:Documentaries", "series:Documentary Series"]; $0.itemIDs = [live.id] }
                if let docs = store.shelf(docs.id) {
                    report["mixedLiveMovieSeriesSection"] = Set(store.discoverItems(for: docs).map(\.kind)) == Set(MediaKind.allCases)
                    store.selectedYear = 2024
                    store.browse(docs)
                    report["viewAllKeepsMixedSectionAndYear"] = store.selectedYear == 2024 && store.visibleItems.count == 2 && store.visibleItems.contains(where: { $0.kind == .live })
                }
                store.destination = .home
                let favorites = store.addDiscoverShelf(title: "Favorite TV Channels", favoritesOnly: true, kinds: [.live])
                report["favoriteChannelsInitiallyLiveOnly"] = store.discoverItems(for: favorites).count == 1
                store.toggleFavorite(secondLive); store.toggleFavorite(movie)
                report["favoriteSectionUpdatesDynamically"] = store.discoverItems(for: favorites).count == 2 && store.discoverItems(for: favorites).allSatisfy { $0.kind == .live }
                let previous = store.discoverShelves.firstIndex(where: { $0.id == docs.id })!
                store.moveDiscoverShelf(docs.id, by: -1)
                report["sectionReorder"] = store.discoverShelves.firstIndex(where: { $0.id == docs.id }) == previous - 1
                store.updateDiscoverShelf(docs.id) { $0.title = "Documentaries & more" }
                let reloaded = LibraryStorage().load(source)
                report["layoutAndSelectionsPersist"] = reloaded.discoverShelves == store.discoverShelves
                store.deleteDiscoverShelf(favorites.id)
                report["sectionRemovalKeepsFavorites"] = store.shelf(favorites.id) == nil && store.user.favorites.contains(live.id) && store.user.favorites.contains(movie.id)
                store.addDiscoverShelf(title: "Favorite TV Channels", favoritesOnly: true, kinds: [.live])
                store.editingDiscoverShelfID = DiscoverSection.bollywoodSeries.rawValue
                store.showDiscoverSettings = true
                try? await Task.sleep(for: .seconds(1))
                render(name: "discover-section-editor-light", output: output, sheet: true)
                store.appearance = .dark
                try? await Task.sleep(for: .milliseconds(500))
                render(name: "discover-section-editor-dark", output: output, sheet: true)
                store.editingDiscoverShelfID = store.discoverShelves.last?.id
                try? await Task.sleep(for: .milliseconds(500))
                render(name: "discover-favorites-editor", output: output, sheet: true)
                store.editingDiscoverShelfID = DiscoverSection.bollywoodSeries.rawValue
            }
        }
        if let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? bytes.write(to: output.appendingPathComponent("\(mode)-report.json")) }
        return true
    }
    static func checkStartup(store: AppStore, playlist: String, output: URL) async {
        let source = Source(type: .playlist, address: playlist, name: "Saved library")
        var report: [String: Bool] = [:]
        let fixture = (try? await ProviderClient(source: source).load()) ?? Library()
        let probe = AppStore(catalogLoader: { _ in
            try await Task.sleep(for: .milliseconds(600))
            return fixture
        })
        report["noLoginBeforeKeychainRead"] = probe.restoringSession && probe.source == nil
        probe.restore(loadSaved: {
            try await Task.sleep(for: .milliseconds(150))
            return source
        })
        try? await Task.sleep(for: .milliseconds(300))
        report["dashboardBeforeCatalogCompletes"] = probe.source?.address == source.address && probe.loading && !probe.restoringSession && probe.library.items.isEmpty
        while probe.loading { try? await Task.sleep(for: .milliseconds(50)) }
        report["savedAccountLoadsCatalog"] = probe.source != nil && probe.library.items.count == fixture.items.count && probe.library.items.count > 0 && probe.loginError == nil

        let absent = AppStore()
        absent.restore(loadSaved: { nil })
        try? await Task.sleep(for: .milliseconds(50))
        report["firstLaunchOpensConnection"] = absent.source == nil && !absent.restoringSession && absent.sessionRestoreError == nil

        let locked = AppStore(catalogLoader: { _ in fixture })
        locked.restore(loadSaved: { throw ProviderError.badResponse })
        try? await Task.sleep(for: .milliseconds(50))
        report["keychainFailureShowsRetryInsteadOfLogin"] = locked.source == nil && locked.sessionRestoreError != nil && !locked.restoringSession
        locked.restore(loadSaved: { source })
        try? await Task.sleep(for: .milliseconds(50))
        report["keychainRetryRestoresDashboard"] = locked.source != nil && locked.sessionRestoreError == nil && !locked.loading

        let offline = AppStore(catalogLoader: { _ in throw URLError(.notConnectedToInternet) })
        offline.restore(loadSaved: { source })
        try? await Task.sleep(for: .milliseconds(50))
        report["offlineKeepsDashboardAndSavedAccount"] = offline.source != nil && offline.catalogLoadFailed && offline.error != nil && offline.loginError == nil
        offline.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        report["failedRetryKeepsDashboard"] = offline.source != nil && offline.catalogLoadFailed && !offline.loading

        let expired = AppStore(catalogLoader: { _ in throw ProviderError.invalidCredentials })
        expired.restore(loadSaved: { source })
        try? await Task.sleep(for: .milliseconds(50))
        report["expiredCredentialsOfferUpdateOnDashboard"] = expired.source != nil && expired.catalogLoadFailed && expired.error == ProviderError.invalidCredentials.localizedDescription

        let cancelled = AppStore(catalogLoader: { _ in fixture })
        cancelled.restore(loadSaved: {
            // An OS Keychain operation may finish even after cancellation.
            try? await Task.sleep(for: .milliseconds(300))
            return source
        })
        cancelled.cancelRestore()
        try? await Task.sleep(for: .milliseconds(350))
        report["cancelledRestoreCannotReopenAccount"] = cancelled.source == nil && !cancelled.restoringSession

        store.restore(loadSaved: {
            try await Task.sleep(for: .seconds(1))
            return source
        })
        try? await Task.sleep(for: .milliseconds(150))
        render(name: "startup-restoring", output: output)
        try? await Task.sleep(for: .milliseconds(1200))
        while store.loading { try? await Task.sleep(for: .milliseconds(50)) }
        render(name: "startup-dashboard", output: output)
        report["visibleDashboardRestored"] = store.source != nil && !store.restoringSession && !store.library.items.isEmpty
        if let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? bytes.write(to: output.appendingPathComponent("startup-report.json"))
        }
    }
    static func render(name: String, output: URL, sheet: Bool = false) {
        let main = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible && $0.attachedSheet != nil }) ?? NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible })
        guard let window = sheet ? main?.attachedSheet : main, let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: output.appendingPathComponent(name + ".png")) }
    }
}
#endif
