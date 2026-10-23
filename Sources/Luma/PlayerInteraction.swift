import AppKit
import SwiftUI
import LumaCore

@MainActor final class PlayerChrome: ObservableObject {
    @Published private(set) var state = PlaybackChromeState()
    private var timer: Timer?
    private var mayHide = false
    func start() {
        stop(); reveal()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var next = self.state
                next.update(at: ProcessInfo.processInfo.systemUptime, mayHide: self.mayHide)
                if next.visible != self.state.visible { self.state = next }
            }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func reveal() { state.reveal(at: ProcessInfo.processInfo.systemUptime) }
    func setMayHide(_ value: Bool) { mayHide = value; reveal() }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}

// Local, window-scoped monitoring works over both VLC's native child view and
// SwiftUI controls. Other application windows and modified shortcuts pass through.
struct PlayerInputMonitor: NSViewRepresentable {
    var onActivity: () -> Void
    var onKey: (UInt16) -> Bool
    func makeNSView(context: Context) -> InputView {
        let view = InputView(); view.onActivity = onActivity; view.onKey = onKey; view.install(); return view
    }
    func updateNSView(_ view: InputView, context: Context) { view.onActivity = onActivity; view.onKey = onKey }
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.remove() }
    final class InputView: NSView {
        var onActivity: (() -> Void)?
        var onKey: ((UInt16) -> Bool)?
        private var monitor: Any?
        private weak var monitoredWindow: NSWindow?
        private var previouslyAcceptedMovement = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            restoreWindow()
            if let window { monitoredWindow = window; previouslyAcceptedMovement = window.acceptsMouseMovedEvents; window.acceptsMouseMovedEvents = true }
        }
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .keyDown, .scrollWheel]) { [weak self] event in
                guard let self, event.window === self.window, self.window != nil else { return event }
                self.onActivity?()
                if event.type == .keyDown, event.keyCode == 3, event.isARepeat, event.modifierFlags.intersection([.command, .option, .control]).isEmpty { return nil }
                if event.type == .keyDown, event.modifierFlags.intersection([.command, .option, .control]).isEmpty, self.onKey?(event.keyCode) == true { return nil }
                return event
            }
        }
        private func restoreWindow() { monitoredWindow?.acceptsMouseMovedEvents = previouslyAcceptedMovement; monitoredWindow = nil }
        func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; restoreWindow() }
    }
}

#if DEBUG
@MainActor enum PlayerQAProbe {
    static weak var controller: PlaybackController?
    static weak var chrome: PlayerChrome?
    static weak var windowController: WindowController?
    static var key: ((UInt16) -> Bool)?
    static var click: (() -> Void)?
    static func reset() { controller = nil; chrome = nil; windowController = nil; key = nil; click = nil }
}
#endif
