import SwiftUI
import AppKit
import NotifyCore

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).background(Color.primary.opacity(hovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 5))
            .onHover { hovered = $0 }.help(label).accessibilityLabel(label)
    }
}

struct InboxDragRegion: NSViewRepresentable {
    final class DragView: NSView {
        private var dragStart: (pointer: NSPoint, origin: NSPoint)?
        override func mouseDown(with event: NSEvent) {
            dragStart = nil
            guard let panel = window as? InboxPanel, let pointer = event.cgEvent?.location else { return }
            dragStart = (pointer, panel.frame.origin)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let panel = window as? InboxPanel, let start = dragStart, let pointer = event.cgEvent?.location else { return }
            // Queued event locations belong to an earlier window frame. Use
            // the event's screen coordinates so moving the panel cannot move
            // the grab point. Quartz's screen Y axis runs opposite to AppKit's.
            let origin = NSPoint(x: start.origin.x + pointer.x - start.pointer.x, y: start.origin.y + start.pointer.y - pointer.y)
            guard origin != panel.frame.origin else { return }
            panel.onDrag?()
            panel.setFrameOrigin(origin)
        }
        override func mouseUp(with event: NSEvent) { dragStart = nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); dragStart = nil }
        override var mouseDownCanMoveWindow: Bool { false }
        override var acceptsFirstResponder: Bool { false }
    }
    func makeNSView(context: Context) -> DragView {
        let view = DragView(); view.setAccessibilityElement(false); return view
    }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct InboxView: View {
    @ObservedObject var model: InboxModel
    @FocusState private var searchFocused: Bool
    @State private var confirmingCompleteAll = false
    var body: some View {
        VStack(spacing: 0) {
            controls
            if !model.arrivalIDs.isEmpty {
                Button { model.onOpenArrivals?() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down").accessibilityHidden(true)
                        Text(model.arrivalIDs.count == 1 ? "1 new notification" : "\(model.arrivalIDs.count) new notifications")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).accessibilityHidden(true)
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.bottom, 12).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Reveals the latest arrival in the inbox")
            }
            if model.searchVisible {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search Notifications…", text: $model.query).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("Search notifications")
                    if !model.query.isEmpty { IconButton(symbol: "xmark.circle.fill", label: "Clear Search") { model.query = "" } }
                }.font(.system(size: 13)).padding(.horizontal, 20).padding(.bottom, 12)
            }
            if model.group != nil || model.period != "any" {
                HStack(spacing: 8) {
                    if let group = model.group { Button { model.group = nil } label: { Label(group, systemImage: "xmark").lineLimit(1) }.help("Clear Group Filter") }
                    if model.period != "any" { Button { model.period = "any" } label: { Label(model.period == "today" ? "Today" : "Last 7 Days", systemImage: "xmark") }.help("Clear Time Filter") }
                    Spacer(minLength: 0)
                }.font(.system(size: 11)).buttonStyle(QuietButtonStyle()).padding(.horizontal, 20).padding(.bottom, 12)
            }
            if let error = model.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                    Text(error).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    IconButton(symbol: "xmark", label: "Dismiss Error") { model.error = nil }
                }.font(.system(size: 12)).padding(12).background(Color.primary.opacity(0.05)).padding(.horizontal, 16).padding(.bottom, 10)
            }
            if model.visible.isEmpty { emptyState }
            else {
                ScrollViewReader { proxy in
                    GeometryReader { geometry in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(model.visible) { item in
                                    NotificationRow(item: item, model: model).id(item.id)
                                }
                            }.padding(.horizontal, 8).padding(.bottom, 12)
                            .frame(minHeight: geometry.size.height, alignment: .top)
                            .background { if model.presentedAsPanel { InboxDragRegion() } }
                        }
                        .onChange(of: model.selected) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
            if let undoItem = model.undoItem {
                let title = model.items.first(where: { $0.id == undoItem.id })?.title ?? "Notification"
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Completed").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(title.isEmpty ? "Notification" : title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Undo completion") { model.undo() }.buttonStyle(QuietButtonStyle())
                        .help("Return this notification to your inbox")
                        .accessibilityLabel("Undo completion of \(title)")
                    IconButton(symbol: "xmark", label: "Hide confirmation") { model.undoItem = nil }
                }.font(.system(size: 11)).padding(.leading, 20).padding(.trailing, 10).padding(.vertical, 10)
                    .background(Color.primary.opacity(0.035))
            }
        }
        .frame(minWidth: 360, minHeight: 340)
        // Behind content: blank space drags, controls and text keep their input.
        .background { if model.presentedAsPanel { InboxDragRegion() } }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: model.presentedAsPanel ? InboxPanel.cornerRadius : 0, style: .continuous))
        .tint(.primary)
        .ignoresSafeArea(.container, edges: .top)
        .onExitCommand { if model.searchVisible { model.query = ""; model.searchVisible = false } else if model.selected != nil { model.selected = nil } else { model.onClose?() } }
        .alert(completeAllTitle, isPresented: $confirmingCompleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Complete All", role: .destructive) { model.completeAll() }
        } message: {
            Text("This moves every active Inbox notification to Done and closes unanswered prompts. It does not run notification actions.")
        }
    }
    private var controls: some View {
        HStack(alignment: .center, spacing: 6) {
            Menu {
                ForEach(model.filters, id: \.0) { key, title in
                    Button { model.filter = key; model.selected = nil } label: { if model.filter == key { Label(title, systemImage: "checkmark") } else { Text(title) } }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(model.filters.first(where: { $0.0 == model.filter })?.1 ?? "Inbox").font(.system(size: 20, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Notification Category")
            Text(model.visible.count.formatted()).font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary).accessibilityLabel("\(model.visible.count) notifications")
            InboxDragRegion().frame(minWidth: 6, maxWidth: .infinity).frame(height: 28)
            IconButton(symbol: "magnifyingglass", label: "Search Notifications") { model.searchVisible.toggle(); searchFocused = model.searchVisible }
            Menu {
                Menu("Group") {
                    Button("All Groups") { model.group = nil }
                    ForEach(model.groups, id: \.self) { group in Button(group) { model.group = group } }
                }
                Menu("Time") {
                    Button("Any Time") { model.period = "any" }
                    Button("Today") { model.period = "today" }
                    Button("Last 7 Days") { model.period = "week" }
                }
                if model.group != nil || model.period != "any" { Button("Clear Filters") { model.group = nil; model.period = "any" } }
            } label: { Image(systemName: model.group != nil || model.period != "any" ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease").frame(width: 28, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Filter by Group or Time").accessibilityLabel("Filter by Group or Time")
            IconButton(symbol: model.detached ? "pin.fill" : "pin", label: model.detached ? "Unpin Inbox" : "Pin Inbox") { model.onDetach?() }
            Menu {
                Button("Mark All Read") { model.markAllRead() }
                    .disabled(!model.visible.contains { $0.readAt == nil })
                Button("Complete All…") { confirmingCompleteAll = true }
                    .disabled(model.inboxCount == 0)
                Divider()
                Button("Close Inbox") { model.onClose?() }
                Button("Preferences…") { model.onPreferences?() }.disabled(model.onPreferences == nil)
                Button("Quit AgentNotify") { model.onQuit?() }
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More Options").accessibilityLabel("More Options")
        }.padding(.leading, 20).padding(.trailing, 14).padding(.top, 18).padding(.bottom, 20)
    }
    private var completeAllTitle: String {
        model.inboxCount == 1 ? "Complete 1 inbox notification?" : "Complete all \(model.inboxCount) inbox notifications?"
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.filter == "inbox" && model.query.isEmpty && model.group == nil ? "checkmark" : "tray").font(.system(size: 27, weight: .regular)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(model.query.isEmpty && model.group == nil && model.period == "any" ? (model.filter == "inbox" ? "You’re All Caught Up" : "Nothing Here Yet") : "No Matching Notifications").font(.system(size: 15, weight: .semibold))
            if !model.query.isEmpty || model.group != nil || model.period != "any" {
                Text("Try another search or clear your filters.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Clear Filters") { model.query = ""; model.group = nil; model.period = "any" }.buttonStyle(QuietButtonStyle()).padding(.top, 4)
            }
            Spacer(); Spacer().frame(height: 40)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotificationRow: View {
    let item: NotificationRecord
    @ObservedObject var model: InboxModel
    @State private var hovered = false
    @State private var replyText = ""
    @State private var replying = false
    var expanded: Bool { model.selected == item.id }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Toggle(isOn: Binding(get: { item.status == "done" }, set: { completed in
                    if completed { model.done(item) }
                    else { model.call("status", ["id": item.id, "state": "reopen", "expectedRevision": item.revision]) }
                })) { Text(item.title) }
                .toggleStyle(.checkbox).labelsHidden().tint(.primary)
                .frame(width: 26, height: 26)
                .help(item.status == "done" ? "Reopen Notification" : "Mark Done")
                .accessibilityLabel("Completed: \(item.title)")
                .disabled(["removed", "superseded"].contains(item.status))
                VStack(alignment: .leading, spacing: 5) {
                    Button { model.select(item) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(item.title.isEmpty ? "Notification" : item.title).font(.system(size: 13, weight: .semibold)).lineLimit(expanded ? nil : 2).multilineTextAlignment(.leading)
                                if item.readAt == nil && item.isInbox { Circle().fill(Color.primary).frame(width: 4, height: 4).accessibilityLabel("Unread") }
                                Spacer(minLength: 2)
                                Text(Date(timeIntervalSince1970: item.createdAt), format: .relative(presentation: .numeric, unitsStyle: .abbreviated)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).fixedSize().help(Date(timeIntervalSince1970: item.createdAt).formatted(date: .complete, time: .shortened))
                            }
                            if !item.subtitle.isEmpty { Text(item.subtitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(expanded ? nil : 1) }
                            Text(item.message).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.85)).lineSpacing(3).lineLimit(expanded ? nil : 3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(item.title). \(item.message). \(expanded ? "Collapse" : "Show Details")")
                    HStack(spacing: 8) {
                        if !item.group.isEmpty { Button(item.group) { model.group = item.group }.buttonStyle(.plain).lineLimit(1).help("Show Group: \(item.group)") }
                        if ["scheduled", "snoozed"].contains(item.status), let due = item.snoozedUntil ?? item.scheduledAt {
                            Label { Text(Date(timeIntervalSince1970: due), format: .dateTime.month(.abbreviated).day().hour().minute()) } icon: { Image(systemName: "clock") }.lineLimit(1)
                        } else if !["active", "done"].contains(item.status) { Text(item.status.capitalized) }
                        Spacer(minLength: 0)
                        rowMenu
                    }.font(.system(size: 11)).foregroundStyle(.secondary).frame(minHeight: 20)
                    if item.canRespond { actions }
                    if expanded { details }
                }.padding(.top, 4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 13)
        .background(Color.primary.opacity(expanded ? 0.045 : (hovered ? 0.025 : 0)), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
        .contextMenu { menuContents }
    }
    @ViewBuilder private var actions: some View {
        HStack(spacing: 6) {
            if item.actions.count == 1 {
                Button(item.actions[0]) { model.respond(item, kind: "action", index: 0) }.lineLimit(1).help(item.actions[0])
            } else if item.actions.count > 1 {
                Menu { ForEach(Array(item.actions.enumerated()), id: \.offset) { index, title in Button(title) { model.respond(item, kind: "action", index: index) } } } label: { HStack(spacing: 5) { Text("Options"); Image(systemName: "chevron.down").font(.system(size: 9)) } }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.horizontal, 10).padding(.vertical, 6).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            if item.reply != nil { Button("Reply") { replying.toggle(); model.selected = item.id } }
            if item.hasBodyAction { Button { model.respond(item, kind: "body") } label: { Label(item.open != nil ? "Open" : (item.execute != nil ? "Run Action" : "Open App"), systemImage: "arrow.up.right") } }
            Spacer(minLength: 0)
        }.font(.system(size: 11, weight: .semibold)).buttonStyle(QuietButtonStyle()).padding(.top, 3)
        if replying, item.reply != nil {
            VStack(alignment: .leading, spacing: 7) {
                TextField(item.reply?.isEmpty == false ? item.reply! : "Your Reply…", text: $replyText, axis: .vertical).lineLimit(2...6).textFieldStyle(.plain).font(.system(size: 13)).padding(10).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Reply to \(item.title)")
                HStack {
                    Button("Send Reply") { model.respond(item, kind: "reply", value: replyText); replying = false }.buttonStyle(QuietButtonStyle())
                    Button("Cancel") { replying = false }.buttonStyle(.plain)
                }.font(.system(size: 11, weight: .semibold))
            }.padding(.top, 7)
        }
    }
    private var rowMenu: some View {
        Menu { menuContents } label: { Image(systemName: "ellipsis").frame(width: 22, height: 20) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Notification Options")
    }
    @ViewBuilder private var menuContents: some View {
        Button(item.readAt == nil ? "Mark Read" : "Mark Unread") { model.call("status", ["id": item.id, "state": item.readAt == nil ? "read" : "unread", "expectedRevision": item.revision]) }
        if item.isInbox && (!item.interactive || item.response != nil) {
            Menu("Remind Me") {
                Button("In 1 Hour") { model.snooze(item, seconds: 3600) }
                Button("In 3 Hours") { model.snooze(item, seconds: 10800) }
                Button("Tomorrow") { model.snooze(item, seconds: 86400) }
            }
        }
        if item.canRespond && item.interactive { Button("Dismiss Prompt") { model.respond(item, kind: "close") } }
        Button("Copy Text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString([item.title, item.subtitle, item.message].filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string) }
        Button("Copy Notification ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.id, forType: .string) }
    }
    @ViewBuilder private var details: some View {
        if let path = item.contentImage {
            let source = URL(fileURLWithPath: path)
            let durable = model.service?.store.paths.root.appendingPathComponent("attachments/\(item.id)/original").appendingPathExtension(source.pathExtension)
            if let image = NSImage(contentsOf: durable ?? source) ?? NSImage(contentsOf: source) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Notification Attachment").padding(.top, 6) }
        }
        if let response = item.response {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: response.effect == "failed" || response.effect == "interrupted" ? "exclamationmark.circle" : "checkmark").accessibilityHidden(true)
                Text(outcome(response)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
        }
        if let error = item.deliveryError { Text(error).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 5) }
        if item.hasBodyAction {
            VStack(alignment: .leading, spacing: 3) {
                if let command = item.execute { Text(command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                if let url = item.open { Text(url).font(.system(size: 11)).textSelection(.enabled) }
                if let bundle = item.activate { Text(bundle).font(.system(size: 11)).textSelection(.enabled) }
            }.foregroundStyle(.secondary).padding(.top, 5)
        }
    }
    private func outcome(_ response: Response) -> String {
        if let error = response.error { return error }
        if response.effect == "running" { return "Action Running…" }
        if response.effect == "succeeded" { return "Action Completed" }
        switch response.kind {
        case "action": return "Selected \(response.value)"
        case "reply": return "Replied: \(response.value)"
        case "timeout": return "Response timed out. The waiting script has finished."
        case "interrupt": return "The waiting script disconnected."
        case "close": return "Dismissed"
        default: return "Acknowledged"
        }
    }
}
