import SwiftUI

struct SessionRestoreView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) { LumaMark(size: 40); Text("luma").font(.system(size: 32, weight: .semibold, design: .rounded)) }
            if let error = store.sessionRestoreError {
                Text("Your library is still saved").font(.system(size: 22, weight: .semibold))
                Text(error).font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 410)
                Button("Retry") { store.restore() }.buttonStyle(AccentButton())
            } else {
                ProgressView().controlSize(.small)
                Text("Opening your library…").font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
            Button("Connect a different source") { store.cancelRestore() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background).foregroundStyle(Theme.text)
    }
}
