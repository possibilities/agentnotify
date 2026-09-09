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
    var waitingCount: Int
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
    let dismiss: () -> Void
    let hover: (Bool) -> Void

    @State private var hovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button { open(model.content.id) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(metadata)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, 30)

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
                        Text(queueSummary)
                            .monospacedDigit()
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
            .accessibilityLabel(openAccessibilityLabel)
            .accessibilityHint("Opens the notification inbox")

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovered ? 0.9 : 0.45)
            .padding(.top, 9)
            .padding(.trailing, 9)
            .help("Dismiss Preview")
            .accessibilityLabel("Dismiss notification preview")
        }
        .frame(minWidth: 360, maxWidth: .infinity)
        .frame(height: Self.preferredSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: InboxPanel.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: InboxPanel.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovered ? 0.11 : 0.07), lineWidth: 0.5)
        }
        .onHover {
            hovered = $0
            hover($0)
        }
    }

    private var metadata: String {
        if !model.content.subtitle.isEmpty { return model.content.subtitle }
        if !model.content.group.isEmpty { return model.content.group }
        return "AgentNotify"
    }

    private var queueSummary: String {
        let waiting = max(0, model.content.waitingCount)
        let waitingText = "\(waiting) waiting"
        return model.content.newCount <= 1 ? "New  ·  \(waitingText)" : "\(model.content.newCount) new  ·  \(waitingText)"
    }

    private var openAccessibilityLabel: String {
        let title = model.content.title.isEmpty ? "Notification" : model.content.title
        return "\(title). \(model.content.message). \(max(0, model.content.waitingCount)) notifications waiting"
    }
}
