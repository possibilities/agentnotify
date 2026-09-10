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
        case .compactToast: return "A smaller preview that leaves more of your screen clear."
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
    let complete: (() -> Void)?
    @State private var hovered = false

    init(model: ArrivalViewModel, open: @escaping (String) -> Void,
         dismiss: @escaping () -> Void, complete: (() -> Void)? = nil) {
        self.model = model
        self.open = open
        self.dismiss = dismiss
        self.complete = complete
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch model.style {
                case .queuePeek: ArrivalView(model: model, open: open)
                case .compactToast: CompactToastView(content: model.content, open: { open(model.content.id) })
                case .queueShelf: QueueShelfView(content: model.content, open: { open(model.content.id) })
                }
            }
            HStack(spacing: 4) {
                if let complete { ArrivalCompleteButton(action: complete) }
                ArrivalDismissButton(action: dismiss)
            }
                .opacity(hovered ? 0.9 : 0.55)
                .padding(.top, 9)
                .padding(.trailing, 9)
        }
        .frame(maxWidth: .infinity)
        .frame(height: model.style.size.height)
        .onHover { hovered = $0 }
        .accessibilityAction(named: Text("Dismiss preview"), dismiss)
        .accessibilityActions {
            if let complete { Button("Complete notification", action: complete) }
        }
    }
}

private struct ArrivalCompleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Mark Done")
        .accessibilityLabel("Complete notification")
        .accessibilityHint("Moves this notification to Done")
    }
}

private struct ArrivalDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Dismiss preview")
        .accessibilityLabel("Dismiss notification preview")
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
                    Text(content.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(content.message).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    ArrivalSummaryText(content: content)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.trailing, 58)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(content.openAccessibilityLabel)
        .accessibilityHint("Opens the notification inbox")
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
                }
                .padding(.trailing, 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(content.message).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 7) {
                    Image(systemName: "tray.fill").font(.system(size: 10, weight: .medium))
                    ArrivalSummaryText(content: content)
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
        .accessibilityLabel(content.openAccessibilityLabel)
        .accessibilityHint("Opens the notification inbox")
    }
}
