import Foundation

public enum PlaybackTimeFormat: String, CaseIterable, Sendable {
    case remaining, current, currentAndTotal
    public var next: Self {
        switch self { case .remaining: .current; case .current: .currentAndTotal; case .currentAndTotal: .remaining }
    }
    public var title: String {
        switch self { case .remaining: "Remaining time"; case .current: "Current time"; case .currentAndTotal: "Current / total time" }
    }
    public func label(position: Double, duration: Double) -> String {
        let total = duration.isFinite && duration > 0 ? duration : nil
        let elapsed = position.isFinite ? max(0, position) : 0
        let current = total.map { min(elapsed, $0) } ?? elapsed
        switch self {
        case .remaining: return total.map { "−" + Self.clock(max(0, $0 - current)) } ?? "--:--"
        case .current: return Self.clock(current)
        case .currentAndTotal: return Self.clock(current) + " / " + (total.map(Self.clock) ?? "--:--")
        }
    }
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = Int(min(max(0, seconds), Double(Int.max / 2)))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}
