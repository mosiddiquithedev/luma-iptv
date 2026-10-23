import SwiftUI
import LumaCore

struct PlayerView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var windowController: WindowController
    @AppStorage("playerTimeFormat") private var timeFormat = PlaybackTimeFormat.remaining
    let item: MediaItem
    @StateObject private var controller = PlaybackController()
    @StateObject private var chrome = PlayerChrome()
    @State private var showInfo = false
    var mayHideControls: Bool { controller.playing && !controller.buffering && controller.error == nil && !finished && !seeking && !showInfo && nextCountdown == 0 }
    @State private var finished = false
    @State private var nextCountdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var seeking = false
    @State private var scrub = 0.0
    @State private var audioTracks: [(Int32, String)] = []
    @State private var subtitleTracks: [(Int32, String)] = []
    @FocusState private var keyboardFocused: Bool
    var body: some View {
        ZStack {
            Color.black
            VideoCanvas(controller: controller)
            Color.clear.contentShape(Rectangle()).onTapGesture { togglePlayback() }
                .accessibilityLabel("Video. Click to play or pause.")
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Button(action: close) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .medium)).frame(width: 28, height: 28) }.buttonStyle(QuietButton()).help("Back to library (Esc)")
                    VStack(alignment: .leading, spacing: 5) { Text(item.title).font(.system(size: 17, weight: .semibold)).lineLimit(1); HStack(spacing: 7) { Text(item.episodeLabel ?? item.kind.title); Text("·"); Text(controller.engineName) }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
                    Spacer()
                    if item.kind == .live { HStack(spacing: 5) { Circle().fill(Theme.accent).frame(width: 5, height: 5); Text("LIVE").tracking(1) }.font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent).padding(9).background(.white.opacity(0.07), in: Capsule()) }
                    Button { showInfo.toggle(); chrome.reveal() } label: { Image(systemName: "info.circle") }.buttonStyle(QuietButton()).help("Title and episode description")
                        .popover(isPresented: $showInfo) { DescriptionPanel(item: item).environmentObject(store).environment(\.colorScheme, .dark) }
                    Button { store.toggleFavorite(item) } label: { Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart").foregroundStyle(Theme.accent) }.buttonStyle(QuietButton()).help("Favorite")
                    Button { windowController.toggleFullScreen(); chrome.reveal() } label: { Image(systemName: windowController.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.buttonStyle(QuietButton()).help("Toggle full screen (F)")
                }.padding(24).background(LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
                if nextCountdown > 0, let next = store.nextEpisode(after: item) {
                    HStack(spacing: 15) {
                        VStack(alignment: .leading, spacing: 5) { Text("UP NEXT IN \(nextCountdown)").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.accent); Text(next.title).font(.system(size: 14, weight: .medium)).lineLimit(1) }
                        Spacer()
                        Button("Cancel") { countdownTask?.cancel(); nextCountdown = 0 }.buttonStyle(QuietButton())
                        Button { playNext() } label: { Label("Play now", systemImage: "forward.end.fill") }.buttonStyle(AccentButton())
                    }.padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 13)).frame(maxWidth: 630).padding(.bottom, 20)
                }
                controls
            }.opacity(chrome.state.visible ? 1 : 0)
                .allowsHitTesting(chrome.state.visible)
                .accessibilityHidden(!chrome.state.visible)
                .animation(.easeInOut(duration: 0.25), value: chrome.state.visible)
            if controller.buffering && controller.error == nil {
                VStack(spacing: 15) { ProgressView().controlSize(.large).tint(.white); Text("Opening your stream…").font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)) }.padding(30).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 15))
            }
            if let error = controller.error {
                VStack(spacing: 18) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 33, weight: .light)).foregroundStyle(Theme.accent)
                    Text("Unable to play this stream").font(.system(size: 22, weight: .semibold))
                    Text(error).font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 410)
                    HStack { Button("Back to library", action: close).buttonStyle(QuietButton()); Button("Try again", action: start).buttonStyle(AccentButton()) }
                }.padding(40).background(Theme.background, in: RoundedRectangle(cornerRadius: 18))
            } else if finished && nextCountdown == 0 {
                VStack(spacing: 18) {
                    Image(systemName: "checkmark.circle").font(.system(size: 35, weight: .light)).foregroundStyle(Theme.accent)
                    Text("\(item.kind == .live ? "Stream ended" : "All caught up")").font(.system(size: 23, weight: .semibold))
                    HStack {
                        Button("Back to library", action: close).buttonStyle(QuietButton())
                        if store.nextEpisode(after: item) != nil { Button("Next episode", action: playNext).buttonStyle(AccentButton()) }
                        else { Button("Watch again") { start(fromBeginning: true) }.buttonStyle(AccentButton()) }
                    }
                }.padding(35).background(Theme.background, in: RoundedRectangle(cornerRadius: 18))
            }
        }.foregroundStyle(.white).focusable().focused($keyboardFocused).focusEffectDisabled()
            .background(PlayerInputMonitor(onActivity: { chrome.reveal() }, onKey: handleKey))
            .onAppear {
                start(); chrome.start(); chrome.setMayHide(mayHideControls); keyboardFocused = true
                #if DEBUG
                PlayerQAProbe.controller = controller; PlayerQAProbe.chrome = chrome
                PlayerQAProbe.windowController = windowController
                PlayerQAProbe.key = handleKey; PlayerQAProbe.click = togglePlayback
                #endif
            }
            .onChange(of: mayHideControls) { chrome.setMayHide(mayHideControls) }
            .onChange(of: item.id) { start() }
            .onChange(of: controller.position) { if !seeking { scrub = controller.position } }
            .onDisappear {
                countdownTask?.cancel(); chrome.stop(); controller.shutdown()
                #if DEBUG
                PlayerQAProbe.reset()
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in controller.stop() }
    }
    var controls: some View {
        VStack(spacing: 14) {
            if item.kind != .live {
                HStack(spacing: 13) {
                    Slider(value: $scrub, in: 0...max(controller.duration, 1), onEditingChanged: { editing in seeking = editing; if !editing { controller.seek(to: scrub); keyboardFocused = true } }).tint(Theme.accent).disabled(controller.duration <= 0)
                    Button {
                        timeFormat = timeFormat.next; chrome.reveal(); keyboardFocused = true
                    } label: {
                        Text(timeFormat.label(position: seeking ? scrub : controller.position, duration: controller.duration))
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                            .frame(minWidth: 58, alignment: .trailing).fixedSize(horizontal: true, vertical: false)
                            .padding(.vertical, 6)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("playback-time")
                        .accessibilityLabel(timeFormat.title)
                        .accessibilityValue(timeFormat.label(position: seeking ? scrub : controller.position, duration: controller.duration))
                        .help("Click to show " + timeFormat.next.title.lowercased())
                }
            }
            HStack(spacing: 20) {
                Button { togglePlayback() } label: { Image(systemName: controller.playing ? "pause.fill" : "play.fill").font(.system(size: 21)).frame(width: 28) }.buttonStyle(.plain).help("Play / pause (Space)").disabled(finished || controller.error != nil)
                if item.kind != .live {
                    Button { controller.seek(to: controller.position - 10) } label: { Image(systemName: "gobackward.10").font(.system(size: 21)) }.buttonStyle(.plain).help("Back 10 seconds")
                    Button { controller.seek(to: controller.position + 10) } label: { Image(systemName: "goforward.10").font(.system(size: 21)) }.buttonStyle(.plain).help("Forward 10 seconds")
                }
                HStack(spacing: 8) { Image(systemName: controller.volume == 0 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 13)); Slider(value: $controller.volume, in: 0...100).tint(.white).frame(width: 90) }.foregroundStyle(.white.opacity(0.7))
                Spacer()
                if item.kind != .live {
                    Menu { ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { value in Button("\(value.formatted())×") { controller.rate = Float(value); chrome.reveal() } } } label: { Text("\(Double(controller.rate).formatted())×").font(.system(size: 12)).monospacedDigit() }.menuStyle(.borderlessButton).fixedSize().help("Playback speed")
                }
                if controller.usesVLC {
                    Menu {
                        Section("Audio") { if audioTracks.isEmpty { Text("No audio tracks available") }; ForEach(audioTracks, id: \.0) { id, name in Button(name) { controller.selectTrack(id, subtitles: false); chrome.reveal() } } }
                        Section("Subtitles") { Button("Off") { controller.selectTrack(-1, subtitles: true); chrome.reveal() }; ForEach(subtitleTracks.filter { $0.0 != -1 }, id: \.0) { id, name in Button(name) { controller.selectTrack(id, subtitles: true); chrome.reveal() } } }
                    } label: { Image(systemName: "captions.bubble").font(.system(size: 18)) }.menuStyle(.borderlessButton).fixedSize().help("Audio and subtitles").onHover { hover in if hover { updateTracks() } }
                }
                if store.nextEpisode(after: item) != nil { Button(action: playNext) { Label("Next episode", systemImage: "forward.end.fill").font(.system(size: 12)) }.buttonStyle(QuietButton()) }
            }.padding(.horizontal, 9)
        }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 24).background(LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom))
    }
    func togglePlayback() {
        chrome.reveal(); keyboardFocused = true
        guard !finished, controller.error == nil else { return }
        controller.toggle()
    }
    func handleKey(_ key: UInt16) -> Bool {
        // Keep Escape available for dismissing the info popover first.
        if showInfo { if key == 53 { showInfo = false; return true }; return false }
        switch key {
        case 3: windowController.toggleFullScreen()
        case 49: togglePlayback()
        case 123: controller.seek(to: controller.position - 10)
        case 124: controller.seek(to: controller.position + 10)
        case 126: controller.volume = min(100, controller.volume + 5)
        case 125: controller.volume = max(0, controller.volume - 5)
        case 53: close()
        default: return false
        }
        return true
    }
    func start() { start(fromBeginning: false) }
    func start(fromBeginning: Bool) {
        countdownTask?.cancel(); nextCountdown = 0; finished = false
        guard let source = store.source else { return }
        // Flush the old item before replacing progress callbacks during autoplay.
        controller.stop()
        let currentItem = item
        controller.onProgress = { position, duration in
            guard store.source?.address == source.address, store.source?.username == source.username else { return }
            store.record(currentItem, position: position, duration: duration)
        }
        controller.onFinished = {
            finished = true
            store.record(currentItem, position: controller.duration, duration: controller.duration, completed: currentItem.kind != .live)
            guard store.user.autoplay, store.nextEpisode(after: currentItem) != nil else { return }
            nextCountdown = 8
            countdownTask = Task { @MainActor in
                for value in stride(from: 8, through: 1, by: -1) {
                    nextCountdown = value
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
                if !Task.isCancelled { playNext() }
            }
        }
        let record = store.user.history[item.id]
        controller.play(item, source: source, resume: !fromBeginning && record?.completed != true ? record?.position ?? 0 : 0)
    }
    func close() { countdownTask?.cancel(); controller.stop(); store.playback = nil }
    func playNext() {
        guard let next = store.nextEpisode(after: item) else { return }
        countdownTask?.cancel(); controller.stop(); store.playback = next
    }
    func updateTracks() { audioTracks = controller.tracks(subtitles: false); subtitleTracks = controller.tracks(subtitles: true) }
}
