import SwiftUI

enum BlockFormatters {
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func formatPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// A usage metric label ("label value") where only the percentage is bold,
    /// e.g. "7d usage 34%". Shared by the 5h and 7d calendar blocks so their
    /// readings render identically.
    static func usageMetricText(label: String, value: Double, size: CGFloat) -> Text {
        let percent = formatPercent(value)
        var text = AttributedString("\(label) \(percent)")
        text.font = .system(size: size, weight: .regular)
        if let percentRange = text.range(of: percent) {
            text[percentRange].font = .system(size: size, weight: .semibold)
        }
        return Text(text)
            .monospacedDigit()
    }
}

/// Vertical tiers for how much information fits inside a window block.
/// Computed from block height (day view) or treated as `.small` in compact mode.
enum BlockDensity {
    case minimal       // only TL (start time)
    case corners       // 4 corners only
    case cornersCenter // 4 corners + 2-line center
    case full          // 4 corners + 2-line center + detail line

    static func forHeight(_ height: CGFloat, compact: Bool) -> BlockDensity {
        if compact { return .corners }
        switch height {
        case ..<32:    return .minimal
        case ..<60:    return .corners
        case ..<100:   return .cornersCenter
        default:       return .full
        }
    }

    var showsBottomCorners: Bool {
        switch self {
        case .minimal: return false
        default: return true
        }
    }

    var showsCenter: Bool {
        switch self {
        case .minimal, .corners: return false
        case .cornersCenter, .full: return true
        }
    }

    var showsDetailLine: Bool {
        self == .full
    }
}
