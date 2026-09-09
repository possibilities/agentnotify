import AppKit
import SwiftUI
import NotifyCore

extension ArrivalStyle {
    var title: String {
        switch self {
        case .queuePeek: return "Queue Peek"
        case .compactToast: return "Compact Toast"
        case .queueShelf: return "Queue Shelf"
        }
    }
    var detail: String {
        switch self {
        case .queuePeek: return "A glimpse of your inbox, with context and a waiting count."
        case .compactToast: return "A smaller banner that leaves more of your screen clear."
        case .queueShelf: return "More room for the message, with a distinct queue footer."
        }
    }
    var size: NSSize {
        switch self {
        case .queuePeek: return ArrivalView.preferredSize
        case .compactToast: return NSSize(width: 360, height: 96)
        case .queueShelf: return NSSize(width: 440, height: 144)
        }
    }
}

/// Shared by live arrivals, Preferences, and the debug studio.
struct ArrivalSurface: View {
    @ObservedObject var model: ArrivalViewModel
    let open: (String) -> Void
    let dismiss: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        Group {
            switch model.style {
            case .queuePeek: ArrivalView(model: model, open: open, dismiss: dismiss, hover: { _ in })
            case .compactToast: CompactToastView(content: model.content, open: { open(model.content.id) })
            case .queueShelf: QueueShelfView(content: model.content, open: { open(model.content.id) })
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: model.style.size.height)
        .onHover(perform: hover)
        .accessibilityAction(named: Text("Dismiss preview"), dismiss)
    }
}

struct CompactToastView: View {
    let content: ArrivalContent
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(content.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(content.waitingCount == 1 ? "1 waiting" : "\(content.waitingCount) waiting")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text(content.message).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(content.title). \(content.message). \(content.waitingCount) waiting. Open notifications.")
    }
}

struct QueueShelfView: View {
    let content: ArrivalContent
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(content.group.isEmpty ? "Notification" : content.group)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(content.newCount > 1 ? "+\(content.newCount) new" : "New")
                        .font(.system(size: 11, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(content.message).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 7) {
                    Circle().frame(width: 5, height: 5)
                    Text(content.waitingCount == 1 ? "1 item stays in your inbox" : "\(content.waitingCount) items stay in your inbox")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(content.title). \(content.message). \(content.waitingCount) waiting. Open notifications.")
    }
}
