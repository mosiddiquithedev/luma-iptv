import SwiftUI

@main struct LumaApp: App {
    @StateObject private var store = AppStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).frame(minWidth: 980, minHeight: 680).preferredColorScheme(store.appearance.colorScheme)
                .task {
                    #if DEBUG
                    if await DebugQA.run(store: store) { return }
                    #endif
                    store.restore()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.persist() }
        }.windowStyle(.hiddenTitleBar).defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Connect source…") { store.showConnection = true }.keyboardShortcut("o")
                Button("Refresh library") { store.refresh() }.keyboardShortcut("r").disabled(store.source == nil || store.loading)
            }
            CommandMenu("Library") {
                ForEach(Array(Destination.allCases.filter { $0 != .collection }.enumerated()), id: \.element) { index, destination in
                    Button(destination.title) { store.destination = destination }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
                Divider()
                Button("Search") { NotificationCenter.default.post(name: .lumaSearch, object: nil) }.keyboardShortcut("f")
                Button("Player settings…") { store.showSettings = true }.keyboardShortcut(",")
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
extension Notification.Name { static let lumaSearch = Notification.Name("LumaSearch") }

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var windowController = WindowController()
    var body: some View {
        Group {
            if store.source != nil { LibraryView() }
            else if store.restoringSession || store.sessionRestoreError != nil { SessionRestoreView() }
            else { ConnectionView() }
        }.background(Theme.background)
            .background(WindowAttachment(controller: windowController))
            .accessibilityHidden(store.playback != nil)
            .sheet(isPresented: $store.showConnection) { ConnectionView(isSheet: true).environmentObject(store) }
            .sheet(item: $store.selectedShow) { show in EpisodeView(show: show).environmentObject(store) }
            .sheet(item: $store.selectedMovie) { item in MovieDetailsView(item: item).environmentObject(store) }
            .sheet(isPresented: $store.showDiscoverSettings) { DiscoverSettingsView().environmentObject(store) }
            .sheet(isPresented: $store.showSettings) { SettingsView().environmentObject(store) }
            .overlay { if let item = store.playback { PlayerView(item: item).environmentObject(store).environment(\.colorScheme, .dark) } }
            .environmentObject(windowController)
    }
}
