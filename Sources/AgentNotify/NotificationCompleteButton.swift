import SwiftUI

private struct IconHoverHighlight: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(hovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 5))
            .onHover { hovered = $0 }
    }
}

extension View {
    func iconHoverHighlight() -> some View { modifier(IconHoverHighlight()) }
}

struct IconMenuLabel: View {
    let symbol: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .iconHoverHighlight()
    }
}

struct CompactIconButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .iconHoverHighlight()
    }
}

struct NotificationCompleteButton: View {
    let action: () -> Void
    var help = "Mark Done"
    var accessibilityLabel = "Complete notification"
    var accessibilityHint = "Moves this notification to Done"

    var body: some View {
        CompactIconButton(symbol: "checkmark", action: action)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
