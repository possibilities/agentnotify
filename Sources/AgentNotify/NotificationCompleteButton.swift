import SwiftUI

struct CompactIconButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(hovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 5))
        .onHover { hovered = $0 }
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
