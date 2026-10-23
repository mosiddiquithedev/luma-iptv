import AppKit
import SwiftUI

@MainActor final class WindowController: ObservableObject {
    @Published private(set) var isFullScreen = false
    private(set) weak var window: NSWindow?
    private var restoredFrame: NSRect?
    private var transitioning = false
    private var notifications: [NSObjectProtocol] = []

    func attach(_ window: NSWindow?) {
        guard self.window !== window else { return }
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications = []; restoredFrame = nil
        self.window = window
        isFullScreen = window?.styleMask.contains(.fullScreen) == true
        transitioning = false
        guard let window else { return }
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] note in
                Task { @MainActor in
                    guard let self, let window else { return }
                    self.transitioning = note.name == NSWindow.willEnterFullScreenNotification || note.name == NSWindow.willExitFullScreenNotification
                    self.isFullScreen = window.styleMask.contains(.fullScreen)
                }
            })
        }
    }
    func toggleFullScreen() {
        guard let window, !transitioning else { return }
        transitioning = true
        window.toggleFullScreen(nil)
    }
    func toggleMaximize() {
        guard let window, !window.styleMask.contains(.fullScreen), !transitioning, let screen = window.screen else { return }
        let target = screen.visibleFrame
        let frame = window.frame
        let maximized = abs(frame.minX - target.minX) < 2 && abs(frame.minY - target.minY) < 2 && abs(frame.width - target.width) < 2 && abs(frame.height - target.height) < 2
        if maximized, let restoredFrame {
            window.setFrame(window.constrainFrameRect(restoredFrame, to: screen), display: true, animate: false)
            self.restoredFrame = nil
        } else {
            restoredFrame = frame
            window.setFrame(target, display: true, animate: false)
        }
    }
    deinit { notifications.forEach(NotificationCenter.default.removeObserver) }
}

// Observe only this window. Keep AppKit's dragging and traffic-light buttons intact.
struct WindowAttachment: NSViewRepresentable {
    let controller: WindowController
    func makeNSView(context: Context) -> WindowEventView {
        let view = WindowEventView(); view.controller = controller; view.nativeTitlebar = true; view.install(); return view
    }
    func updateNSView(_ view: WindowEventView, context: Context) { view.controller = controller }
    static func dismantleNSView(_ view: WindowEventView, coordinator: ()) { view.remove() }
}

// Apply behind only the noninteractive title/empty space in a custom header.
struct TitlebarZoomArea: NSViewRepresentable {
    @EnvironmentObject var controller: WindowController
    func makeNSView(context: Context) -> WindowEventView {
        let view = WindowEventView(); view.controller = controller; view.install(); return view
    }
    func updateNSView(_ view: WindowEventView, context: Context) { view.controller = controller }
    static func dismantleNSView(_ view: WindowEventView, coordinator: ()) { view.remove() }
}

final class WindowEventView: NSView {
    weak var controller: WindowController?
    var nativeTitlebar = false
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { if nativeTitlebar { controller?.attach(window) } }
    func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, event.clickCount == 2, !window.styleMask.contains(.fullScreen) else { return event }
            let point = event.locationInWindow
            let matches: Bool
            if self.nativeTitlebar {
                let titlebarBottom = min(window.contentLayoutRect.maxY, window.frame.height - 28)
                matches = point.y >= titlebarBottom && point.x > 90
            } else {
                matches = self.bounds.contains(self.convert(point, from: nil))
            }
            guard matches else { return event }
            self.controller?.toggleMaximize()
            return nil
        }
    }
    func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}
