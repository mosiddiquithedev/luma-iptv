import SwiftUI
import UniformTypeIdentifiers
import LumaCore

struct ConnectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var mode: SourceType = .xtream
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var name = ""
    @State private var revealPassword = false
    var isSheet = false
    var body: some View {
        HStack(spacing: 0) {
            if !isSheet {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) { LumaMark(size: 39); Text("luma").font(.system(size: 30, weight: .semibold, design: .rounded)) }
                    Spacer()
                    Text("A little less noise.\nA lot more watching.").font(.system(size: 43, weight: .medium)).tracking(-1.5).lineSpacing(2)
                    Text("Your channels, films, and series.\nOne beautifully simple place.").font(.system(size: 16)).foregroundStyle(Theme.muted).lineSpacing(6).padding(.top, 23)
                    HStack(spacing: 10) {
                        ForEach(["tv", "film", "play.rectangle.on.rectangle"], id: \.self) { icon in
                            Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(Theme.accent.opacity(0.8)).frame(width: 68, height: 68).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(Theme.border))
                        }
                    }.padding(.top, 35)
                    Spacer()
                    HStack(spacing: 7) { Image(systemName: "lock.shield"); Text("Your library. Your connection.") }.font(.system(size: 12)).foregroundStyle(Theme.muted)
                }.padding(52).frame(maxWidth: .infinity, maxHeight: .infinity).background(LinearGradient(colors: [Theme.hero, Theme.background], startPoint: .topLeading, endPoint: .bottomTrailing))
                Rectangle().fill(Theme.border).frame(width: 1)
            }
            VStack(alignment: .leading, spacing: 23) {
                if isSheet { HStack { Text("Connect a source").font(.system(size: 25, weight: .semibold)); Spacer(); Button { store.cancelConnection(); store.showConnection = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain) } }
                else {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Make yourself at home.").font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                        Text("Connect your provider to get started.").foregroundStyle(Theme.muted).font(.system(size: 14))
                    }
                }
                HStack(spacing: 4) {
                    connectionTab("Provider login", value: .xtream)
                    connectionTab("M3U playlist", value: .playlist)
                }.padding(4).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)).disabled(store.loading)
                VStack(alignment: .leading, spacing: 16) {
                    field("LIBRARY NAME", placeholder: "My library", text: $name)
                    field(mode == .xtream ? "SERVER ADDRESS" : "PLAYLIST URL", placeholder: mode == .xtream ? "https://your-provider.com" : "https://your-provider.com/playlist.m3u", text: $address)
                    if mode == .xtream {
                        field("USERNAME", placeholder: "Your username", text: $username)
                        VStack(alignment: .leading, spacing: 7) {
                            label("PASSWORD")
                            HStack {
                                Group { if revealPassword { TextField("Your password", text: $password) } else { SecureField("Your password", text: $password) } }.textFieldStyle(.plain)
                                Button { revealPassword.toggle() } label: { Image(systemName: revealPassword ? "eye.slash" : "eye").foregroundStyle(Theme.muted) }.buttonStyle(.plain).help(revealPassword ? "Hide password" : "Show password")
                            }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
                        }
                    }
                }.disabled(store.loading)
                if let error = store.loginError { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Button(action: connect) {
                    HStack { Spacer(); if store.loading { ProgressView().controlSize(.small); Text("Connecting to your library…") } else { Text("Connect library"); Image(systemName: "arrow.right") }; Spacer() }
                }.buttonStyle(AccentButton()).opacity(canConnect || store.loading ? 1 : 0.5).disabled(!canConnect || store.loading).keyboardShortcut(.defaultAction)
                if mode == .playlist {
                    Button(action: chooseFile) { Label("Or choose a local M3U file", systemImage: "folder") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent).disabled(store.loading)
                }
                if store.loading { Button("Cancel") { store.cancelConnection() }.buttonStyle(.plain).foregroundStyle(Theme.muted) }
                HStack(alignment: .top, spacing: 8) { Image(systemName: "info.circle"); Text("Luma is a player and does not provide any content. Connect a playlist or an Xtream Codes account from your provider. Login details are saved in macOS Keychain.") }.font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }.padding(isSheet ? 32 : 48).frame(width: isSheet ? 480 : 460)
        }.background(Theme.background).foregroundStyle(Theme.text)
    }
    func connectionTab(_ title: String, value: SourceType) -> some View {
        Button { mode = value; store.loginError = nil } label: {
            Text(title).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundStyle(mode == value ? Theme.accent : Theme.muted)
                .background(mode == value ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
    var canConnect: Bool { !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (mode == .playlist || (!username.isEmpty && !password.isEmpty)) }
    func label(_ text: String) -> some View { Text(text).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.muted) }
    func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            label(title)
            TextField(placeholder, text: text).textFieldStyle(.plain).padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
        }
    }
    func connect() { store.connect(Source(type: mode, address: address.trimmingCharacters(in: .whitespacesAndNewlines), username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password, name: name.isEmpty ? "My library" : name)) }
    func chooseFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "m3u") ?? .plainText, UTType(filenameExtension: "m3u8") ?? .plainText]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        address = url.absoluteString; connect()
    }
}
