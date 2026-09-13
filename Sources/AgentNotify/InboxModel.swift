import AppKit
import SwiftUI
import NotifyCore

final class InboxModel: ObservableObject {
    @Published var items: [NotificationRecord] = []
    @Published var filter = "inbox"
    @Published var query = ""
    @Published var group: String? = nil
    @Published var period = "any"
    @Published var selected: String? = nil
    // Pin state is separate from placement: unpinning a manually moved panel
    // changes its lifetime without restoring the menu-bar triangle.
    @Published var detached = false
    @Published var presentedAsPanel = false
    @Published var pointerX: CGFloat?
    @Published var searchVisible = false
    @Published var arrivalIDs: [String] = []
    @Published var confirmingCompleteAll = false
    @Published var error: String?
    struct Completion {
        var items: [(id: String, revision: Int)]
        let isBulk: Bool
    }
    @Published var undoCompletion: Completion? {
        didSet {
            undoTimer?.invalidate(); undoTimer = nil
            undoGeneration += 1
            guard undoCompletion != nil else { return }
            let generation = undoGeneration
            let timer = Timer(timeInterval: undoDuration, repeats: false) { [weak self] _ in
                guard let self, self.undoGeneration == generation else { return }
                self.undoCompletion = nil
            }
            undoTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    // Preserve the single-item interface snapshot for existing clients.
    var undoItem: (id: String, revision: Int)? {
        get { guard undoCompletion?.items.count == 1 else { return nil }; return undoCompletion?.items.first }
        set { undoCompletion = newValue.map { Completion(items: [$0], isBulk: false) } }
    }
    private let undoDuration: TimeInterval
    private var undoTimer: Timer?
    private var undoGeneration = 0
    init(undoDuration: TimeInterval = 60) { self.undoDuration = undoDuration }
    deinit { undoTimer?.invalidate() }
    var service: NotifyService?
    var onDetach: (() -> Void)?
    var onPreferences: (() -> Void)?
    var onClose: (() -> Void)?
    var onQuit: (() -> Void)?
    var onChangeCount: ((Int) -> Void)?
    var onOpenArrivals: (() -> Void)?
    let filters = [("inbox", "Inbox"), ("unread", "Unread"), ("later", "Later"), ("done", "Done"), ("all", "All")]
    var groups: [String] { Array(Set(items.map(\.group).filter { !$0.isEmpty })).sorted() }
    var inboxCount: Int { items.filter(\.isInbox).count }
    var unreadCount: Int { items.filter { $0.isInbox && $0.readAt == nil }.count }
    var visible: [NotificationRecord] { matching(filter: filter, query: query, group: group, period: period) }
    func matching(filter: String, query: String, group: String?, period: String) -> [NotificationRecord] {
        let now = Date(), calendar = Calendar.current
        let since: Double
        switch period { case "today": since = calendar.startOfDay(for: now).timeIntervalSince1970; case "week": since = now.addingTimeInterval(-604800).timeIntervalSince1970; default: since = 0 }
        return items.filter { item in
            let matches: Bool
            switch filter {
            case "unread": matches = item.isInbox && item.readAt == nil
            case "later": matches = ["scheduled", "snoozed"].contains(item.status)
            case "done": matches = item.status == "done"
            case "all": matches = true
            default: matches = item.isInbox
            }
            return matches && (group == nil || item.group == group) && item.createdAt >= since && (query.isEmpty || [item.title, item.subtitle, item.message, item.group].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    func refresh() {
        do { items = try service?.store.all() ?? []; onChangeCount?(inboxCount) }
        catch { self.error = "Could not read the inbox. \(error.localizedDescription)" }
    }
    func call(_ method: String, _ params: [String: Any]) {
        do { _ = try service?.call(method, params); refresh() }
        catch { self.error = error.localizedDescription; refresh() }
    }
    func select(_ item: NotificationRecord) {
        selected = selected == item.id ? nil : item.id
        if selected != nil { arrivalIDs.removeAll { $0 == item.id } }
        if selected != nil && item.readAt == nil { call("status", ["id": item.id, "state": "read", "expectedRevision": item.revision]) }
    }
    func markRead(_ id: String) {
        arrivalIDs.removeAll { $0 == id }
        guard let item = items.first(where: { $0.id == id }), item.readAt == nil else { return }
        call("status", ["id": id, "state": "read", "expectedRevision": item.revision])
    }
    func markAllRead() {
        let references = visible.filter { $0.readAt == nil }.map { ["id": $0.id, "expectedRevision": $0.revision] as [String: Any] }
        guard !references.isEmpty else { return }
        call("statusBatch", ["items": references, "state": "read", "requestId": UUID().uuidString])
    }
    @discardableResult func done(_ item: NotificationRecord) -> Bool {
        do {
            let result = try service?.call("status", ["id": item.id, "state": "done", "expectedRevision": item.revision])
            if let revision = result?["revision"] as? Int { undoItem = (item.id, revision) }
            refresh()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    var completableVisible: [NotificationRecord] { visible.filter(\.isInbox) }
    func completeVisible() { complete(completableVisible) }
    // The global shortcut retains its confirmed, whole-Inbox scope.
    func completeAll() { complete(items.filter(\.isInbox)) }
    private func complete(_ snapshot: [NotificationRecord]) {
        guard let service, !snapshot.isEmpty else { return }
        var completed: [(id: String, revision: Int)] = []
        do {
            // statusBatch's shared contract allows 100 exact references per transaction.
            // Retain successful batches if a later transaction conflicts.
            for start in stride(from: 0, to: snapshot.count, by: 100) {
                let references = snapshot[start..<min(start + 100, snapshot.count)].map {
                    ["id": $0.id, "expectedRevision": $0.revision] as [String: Any]
                }
                let result = try service.call("statusBatch", ["items": references, "state": "done", "requestId": UUID().uuidString])
                let records = try (result["items"] as! [[String: Any]]).map { try JSON.decode(NotificationRecord.self, $0) }
                completed += records.map { ($0.id, $0.revision) }
            }
        } catch { self.error = "Could not complete every matching notification. \(error.localizedDescription)" }
        if !completed.isEmpty {
            undoCompletion = Completion(items: completed, isBulk: true)
            let ids = Set(completed.map(\.id))
            if let selected, ids.contains(selected) { self.selected = nil }
            arrivalIDs.removeAll { ids.contains($0) }
        }
        refresh()
    }
    func undo() {
        guard let service, let completion = undoCompletion else { return }
        var restored = Set<String>()
        var changed = Set<String>()
        do {
            let current = Dictionary(uniqueKeysWithValues: try service.store.all().map { ($0.id, $0) })
            let eligible = completion.items.filter { reference in
                guard let item = current[reference.id], item.status == "done", item.revision == reference.revision else {
                    changed.insert(reference.id); return false
                }
                return true
            }
            for start in stride(from: 0, to: eligible.count, by: 100) {
                let batch = eligible[start..<min(start + 100, eligible.count)]
                let references = batch.map { ["id": $0.id, "expectedRevision": $0.revision] as [String: Any] }
                _ = try service.call("statusBatch", ["items": references, "state": "reopen", "requestId": UUID().uuidString])
                restored.formUnion(batch.map(\.id))
            }
            undoCompletion = nil
            if !changed.isEmpty { error = "Restored \(restored.count) notifications. \(changed.count) changed since completion and were left unchanged." }
        } catch {
            let remaining = completion.items.filter { !restored.contains($0.id) && !changed.contains($0.id) }
            undoCompletion = remaining.isEmpty ? nil : Completion(items: remaining, isBulk: completion.isBulk)
            self.error = "Could not undo every completion. \(error.localizedDescription)"
        }
        refresh()
    }
    func respond(_ item: NotificationRecord, kind: String, index: Int? = nil, value: String? = nil) {
        var params: [String: Any] = ["id": item.id, "kind": kind, "expectedRevision": item.revision, "requestId": UUID().uuidString]
        if let index { params["actionIndex"] = index }; if let value { params["value"] = value }
        call("respond", params)
    }
    func snooze(_ item: NotificationRecord, seconds: Double) { call("status", ["id": item.id, "state": "snooze", "until": Date().timeIntervalSince1970 + seconds, "expectedRevision": item.revision]) }
    func reveal(_ id: String?) { if let id { filter = "all"; group = nil; query = ""; period = "any"; selected = id }; refresh() }
    func revealArrival(_ id: String) {
        reveal(id)
        if items.first(where: { $0.id == id })?.isInbox == true { filter = "inbox" }
    }
}
