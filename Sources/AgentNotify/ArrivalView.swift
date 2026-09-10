import AppKit
import SwiftUI
import NotifyCore

struct ArrivalContent: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var message: String
    var group: String
    var newCount: Int
    var unreadCount: Int
    var waitingCount: Int

    var queueSummary: String {
        let waiting = max(0, waitingCount)
        let unread = max(0, min(unreadCount, waiting))
        let read = waiting - unread
        var parts: [String] = []

        if newCount > 1 { parts.append("Latest of \(newCount) arrivals") }
        if unread > 0 {
            parts.append(unread == 1 ? "1 unread notification" : "\(unread) unread notifications")
        }
        if read > 0 {
            parts.append(read == 1 ? "1 read notification still needs attention" : "\(read) read still need attention")
        }
        if parts.isEmpty { parts.append("No notifications waiting") }
        return parts.joined(separator: "  ·  ")
    }

    var queueAccessibilitySummary: String {
        let waiting = max(0, waitingCount)
        let unread = max(0, min(unreadCount, waiting))
        let read = waiting - unread
        var parts: [String] = []
        if newCount > 1 { parts.append("Latest of \(newCount) arrivals") }
        parts.append(unread == 1 ? "1 unread notification" : "\(unread) unread notifications")
        if read > 0 {
            parts.append(read == 1 ? "1 read notification still needs attention" : "\(read) read notifications still need attention")
        }
        return parts.joined(separator: ". ")
    }

    var compactQueueSummary: String {
        let waiting = max(0, waitingCount)
        let unread = max(0, min(unreadCount, waiting))
        let read = waiting - unread
        var parts: [String] = []
        if newCount > 1 { parts.append("Latest of \(newCount)") }
        if unread > 0 { parts.append("\(unread) unread") }
        if read > 0 { parts.append("\(read) read pending") }
        if parts.isEmpty { parts.append("Nothing waiting") }
        return parts.joined(separator: "  ·  ")
    }

    var openAccessibilityLabel: String {
        let displayTitle = title.isEmpty ? "Notification" : title
        return "\(displayTitle). \(message). \(queueAccessibilitySummary)"
    }
}

final class ArrivalViewModel: ObservableObject {
    @Published var content: ArrivalContent
    @Published var style: ArrivalStyle = .queuePeek

    init(content: ArrivalContent) {
        self.content = content
    }
}

/// The brief heads-up surface for a newly durable inbox item.
///
/// Its geometry and type roles deliberately echo the full inbox. The entire
/// body opens that inbox; notification effects remain behind explicit controls
/// in the full surface.
struct ArrivalView: View {
    static let preferredSize = NSSize(width: 440, height: 126)

    @ObservedObject var model: ArrivalViewModel
    let open: (String) -> Void

    var body: some View {
        Button { open(model.content.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(metadata)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.trailing, 58)

                Text(model.content.title.isEmpty ? "Notification" : model.content.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.top, 8)

                Text(model.content.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                Spacer(minLength: 5)

                HStack(spacing: 6) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 10, weight: .medium))
                        .accessibilityHidden(true)
                    ArrivalSummaryText(content: model.content)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.content.openAccessibilityLabel)
        .accessibilityHint("Opens the notification inbox")
        .frame(minWidth: 360, maxWidth: .infinity)
        .frame(height: Self.preferredSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: InboxPanel.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: InboxPanel.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
    }

    private var metadata: String {
        if !model.content.subtitle.isEmpty { return model.content.subtitle }
        if !model.content.group.isEmpty { return model.content.group }
        return "AgentNotify"
    }
}

struct ArrivalSummaryText: View {
    let content: ArrivalContent

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(content.queueSummary).fixedSize(horizontal: true, vertical: false)
            Text(content.compactQueueSummary).lineLimit(1)
        }
        .monospacedDigit()
    }
}
