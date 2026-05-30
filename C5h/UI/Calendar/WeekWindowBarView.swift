import SwiftUI
import C5hCore

/// Slim provider-colored bar used by the Week overview. Unlike the Day view's
/// dense block views, it carries only a single auto-shrinking start-time label
/// (or nothing, when too thin) — full detail lives in the click inspector and
/// the Day view. Lane-packing is handled by the caller; this view just draws
/// the bar at the size it is given.
struct WeekWindowBarView: View {
    enum Kind {
        case planned
        case actual
    }

    let providerID: ProviderID
    let kind: Kind
    let startLabel: String
    let width: CGFloat
    let height: CGFloat
    let clipsTop: Bool
    let clipsBottom: Bool
    let cornerRadius: CGFloat

    /// Below these the label can't render legibly, so the bar shows color only.
    private static let minLabelWidth: CGFloat = 28
    private static let minLabelHeight: CGFloat = 14

    private var showsLabel: Bool {
        width >= Self.minLabelWidth && height >= Self.minLabelHeight
    }

    var body: some View {
        let radius = min(cornerRadius, height / 2, width / 2)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: clipsTop ? 0 : radius,
            bottomLeadingRadius: clipsBottom ? 0 : radius,
            bottomTrailingRadius: clipsBottom ? 0 : radius,
            topTrailingRadius: clipsTop ? 0 : radius,
            style: .continuous
        )

        label
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(fill(shape))
            .clipShape(shape)
    }

    @ViewBuilder
    private var label: some View {
        if showsLabel {
            Text(startLabel)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
                .foregroundStyle(kind == .actual ? Color.white : brandColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func fill(_ shape: some InsettableShape) -> some View {
        switch kind {
        case .actual:
            shape.fill(brandColor)
        case .planned:
            shape.fill(brandColor.opacity(0.22))
                .overlay(shape.strokeBorder(brandColor.opacity(0.7), lineWidth: 1))
        }
    }

    private var brandColor: Color {
        C5hColors.tintForProvider(providerID)
    }
}
