import SwiftUI

struct NotificationCompleteButton: View {
    let action: () -> Void
    var help = "Mark Done"
    var accessibilityLabel = "Complete notification"
    var accessibilityHint = "Moves this notification to Done"

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
