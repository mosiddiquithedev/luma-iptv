import SwiftUI
import AVKit
import CVLC
import LumaCore

@MainActor final class PlaybackController: ObservableObject {
    @Published var playing = false
    @Published var buffering = true
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var error: String?
    @Published var volume = 85.0 { didSet { applyVolume() } }
    @Published var rate: Float = 1 { didSet { if let vlc { luma_vlc_rate(vlc, rate) } else { if playing { avPlayer.rate = rate } } } }
    let avPlayer = AVPlayer()
    let canvas = NSView()
    private var vlc: OpaquePointer?
    private var timer: Timer?
    private var avObserver: NSObjectProtocol?
    private var startDate = Date()
    private var resumePosition = 0.0
    private var restored = false
    private var finished = false
    private var tickCount = 0
    private var item: MediaItem?
    var onProgress: ((Double, Double) -> Void)?
    var onFinished: (() -> Void)?
    var usesVLC: Bool { vlc != nil }
    var engineName: String { usesVLC ? "VLC" : "AVPlayer" }
    init() {
        vlc = luma_vlc_create()
        canvas.wantsLayer = true; canvas.layer?.backgroundColor = NSColor.black.cgColor
        if let vlc { luma_vlc_attach(vlc, Unmanaged.passUnretained(canvas).toOpaque()) }
        avObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let ended = note.object as? AVPlayerItem, ended === self.avPlayer.currentItem else { return }
                self.complete()
            }
        }
    }
    func play(_ item: MediaItem, source: Source, resume: Double) {
        stop(save: true)
        self.item = item; position = 0; duration = 0; error = nil; buffering = true; playing = true
        restored = false; finished = false; tickCount = 0; resumePosition = resume; startDate = Date()
        guard let url = source.streamURL(for: item) else { error = "This item has no playable stream address."; playing = false; buffering = false; return }
        if let vlc {
            let result = url.absoluteString.withCString { luma_vlc_play(vlc, $0) }
            if result != 0 { error = "The playback engine could not open this stream."; playing = false; buffering = false }
        } else {
            avPlayer.replaceCurrentItem(with: AVPlayerItem(url: url)); avPlayer.play()
        }
        applyVolume()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    private func tick() {
        guard let item, !finished else { return }
        tickCount += 1
        if let vlc {
            let state = luma_vlc_state(vlc)
            position = max(0, Double(luma_vlc_time(vlc)) / 1000)
            duration = max(0, Double(luma_vlc_length(vlc)) / 1000)
            buffering = state == 1 || state == 2 || state == 0
            if state == 3 { playing = true }
            if state == 4 { playing = false }
            if state == 6 { complete(); return }
            if state == 7 { fail(); return }
        } else {
            let time = avPlayer.currentTime().seconds
            position = time.isFinite ? max(0, time) : 0
            let length = avPlayer.currentItem?.duration.seconds ?? 0
            duration = length.isFinite ? max(0, length) : 0
            buffering = avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
            if avPlayer.currentItem?.status == .failed { fail(); return }
        }
        if !restored, duration > 0, position > 0 || !buffering {
            restored = true
            if resumePosition > 5, resumePosition < duration - 5, item.kind != .live { seek(to: resumePosition) }
            if rate != 1 { if let vlc { luma_vlc_rate(vlc, rate) } else { avPlayer.rate = rate } }
        }
        if buffering && Date().timeIntervalSince(startDate) > 45 { fail(message: "The stream did not start within 45 seconds. It may be offline, or your provider may have reached its connection limit."); return }
        if tickCount % 10 == 0, position > 0 { onProgress?(position, duration) }
    }
    private func fail(message: String = "This stream could not be played. It may be offline or unavailable with your account. Try another item or retry.") {
        error = message; buffering = false; playing = false; timer?.invalidate(); timer = nil
        if let vlc { luma_vlc_stop(vlc) } else { avPlayer.pause() }
    }
    private func complete() {
        guard !finished else { return }
        finished = true; playing = false; buffering = false; timer?.invalidate(); timer = nil
        position = max(position, duration)
        onProgress?(position, duration); onFinished?()
    }
    func toggle() {
        guard error == nil else { return }
        playing.toggle()
        if let vlc { luma_vlc_pause(vlc, playing ? 0 : 1) } else { if playing { avPlayer.playImmediately(atRate: rate) } else { avPlayer.pause() } }
    }
    func seek(to seconds: Double) {
        guard duration > 0, item?.kind != .live else { return }
        let value = min(max(seconds, 0), duration)
        if let vlc { luma_vlc_seek(vlc, Int64(value * 1000)) } else { avPlayer.seek(to: CMTime(seconds: value, preferredTimescale: 600)) }
        position = value
    }
    func stop(save: Bool = true) {
        timer?.invalidate(); timer = nil
        if save, !finished, item != nil, position > 0 { onProgress?(position, duration) }
        if let vlc { luma_vlc_stop(vlc) } else { avPlayer.pause(); avPlayer.replaceCurrentItem(with: nil) }
        playing = false; item = nil
    }
    func shutdown() { stop(); onProgress = nil; onFinished = nil; if let vlc { luma_vlc_attach(vlc, nil) } }
    private func applyVolume() {
        if let vlc { luma_vlc_volume(vlc, Int32(volume)) } else { avPlayer.volume = Float(volume / 100) }
    }
    func tracks(subtitles: Bool) -> [(Int32, String)] {
        guard let vlc else { return [] }
        let count = luma_vlc_tracks(vlc, subtitles ? 1 : 0)
        return (0..<count).compactMap { index in
            guard let name = luma_vlc_track_name(vlc, subtitles ? 1 : 0, index) else { return nil }
            return (luma_vlc_track_id(vlc, subtitles ? 1 : 0, index), String(cString: name))
        }
    }
    func selectTrack(_ id: Int32, subtitles: Bool) { if let vlc { luma_vlc_select_track(vlc, subtitles ? 1 : 0, id) } }
    deinit {
        timer?.invalidate()
        if let avObserver { NotificationCenter.default.removeObserver(avObserver) }
        if let vlc { luma_vlc_destroy(vlc) }
    }
}

struct VideoCanvas: NSViewRepresentable {
    let controller: PlaybackController
    func makeNSView(context: Context) -> NSView {
        if controller.usesVLC { return controller.canvas }
        let view = AVPlayerView(); view.player = controller.avPlayer; view.controlsStyle = .none; view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
