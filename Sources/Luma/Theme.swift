import SwiftUI
import LumaCore

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}
enum Theme {
    static func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(0x101211, 0xF6F8F5)
    static let sidebar = adaptive(0x141715, 0xEDF1EC)
    static let surface = adaptive(0x1B201D, 0xFFFFFF)
    static let elevated = adaptive(0x242B26, 0xE1E8DE)
    static let accent = adaptive(0xBDDFB7, 0x2F663C)
    static let muted = adaptive(0x929C94, 0x626E64)
    static let text = adaptive(0xF5F7F4, 0x19251D)
    static let hero = adaptive(0x223029, 0xDFEADB)
    static let border = adaptive(0x2B322D, 0xDCE3D9)
}
extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
struct LumaMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29).fill(Theme.accent)
            Image(systemName: "play.fill").font(.system(size: size * 0.40, weight: .black)).foregroundStyle(Theme.background).offset(x: 1)
        }.frame(width: size, height: size)
    }
}
struct AccentButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 19).padding(.vertical, 12)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(Theme.background)
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.text.opacity(configuration.isPressed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(Theme.text.opacity(0.85))
    }
}
struct Artwork: View {
    let item: MediaItem
    var fill = true
    var body: some View {
        GeometryReader { geo in
            ZStack {
                let tint = palette
                LinearGradient(colors: [tint.opacity(0.55), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: item.kind.symbol).font(.system(size: min(geo.size.width * 0.24, 58), weight: .ultraLight)).foregroundStyle(.white.opacity(0.16))
                if let url = item.artwork, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    AsyncImage(url: url) { image in
                        if fill { image.resizable().scaledToFill() } else { image.resizable().scaledToFit().padding(20) }
                    } placeholder: { Color.clear }
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
        }
    }
    var palette: Color {
        let colors: [Color] = [Color(hex: 0x405D50), Color(hex: 0x685744), Color(hex: 0x48566A), Color(hex: 0x5A465B), Color(hex: 0x53604A)]
        let value = item.id.utf8.reduce(0) { ($0 + Int($1)) % colors.count }
        return colors[value]
    }
}
struct EmptyLibrary: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Theme.accent).padding(24).background(Theme.surface, in: Circle())
            Text(title).font(.system(size: 23, weight: .semibold))
            Text(detail).font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 390)
        }.frame(maxWidth: .infinity).padding(.vertical, 80)
    }
}
func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = max(0, Int(seconds))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
}
