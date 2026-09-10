import Foundation

public final class Store {
    private let db: Database
    private let lock = NSRecursiveLock()
    public let paths: NotifyPaths
    public init(paths: NotifyPaths) throws {
        self.paths = paths; try paths.prepare(); db = try Database(paths.database)
    }
    public func all() throws -> [NotificationRecord] {
        lock.lock(); defer { lock.unlock() }
        return try db.rows("SELECT json FROM notifications ORDER BY created DESC, id DESC").map { try JSONDecoder().decode(NotificationRecord.self, from: Data($0[0].utf8)) }
    }
    public func get(_ id: String) throws -> NotificationRecord {
        lock.lock(); defer { lock.unlock() }
        guard let row = try db.rows("SELECT json FROM notifications WHERE id=?", [id]).first else { throw NotifyError("not_found", "Notification not found: \(id).") }
        return try JSONDecoder().decode(NotificationRecord.self, from: Data(row[0].utf8))
    }
    public func cursor() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return Int(try db.rows("SELECT COALESCE(MAX(seq),0) FROM changes")[0][0]) ?? 0
    }
    public func preferences() throws -> AppPreferences {
        lock.lock(); defer { lock.unlock() }
        guard let row = try db.rows("SELECT json FROM preferences WHERE id=1").first else { return AppPreferences() }
        return try JSONDecoder().decode(AppPreferences.self, from: Data(row[0].utf8))
    }
    public func shimPromptHandled() throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return try !db.rows("SELECT key FROM app_setup WHERE key='terminal-notifier-offer'").isEmpty
    }
    private func save(_ item: NotificationRecord, kind: String) throws {
        let json = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        try db.run("INSERT INTO notifications(id,group_name,created,updated,status,json) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET group_name=excluded.group_name,updated=excluded.updated,status=excluded.status,json=excluded.json", [item.id, item.group, String(item.createdAt), String(item.updatedAt), item.status, json])
        try db.run("INSERT INTO changes(notification_id,kind,json) VALUES(?,?,?)", [item.id, kind, json])
    }
    public func perform(_ method: String, params: [String: Any], now: Double = Date().timeIntervalSince1970) throws -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        try Catalog.validate(method, params)
        return try db.transaction {
            let requestID = params["requestId"] as? String
            let fingerprint = JSON.string(["method": method, "params": params])
            if let requestID, let row = try db.rows("SELECT fingerprint,result FROM requests WHERE id=?", [requestID]).first {
                guard row[0] == fingerprint else { throw NotifyError("request_conflict", "requestId was already used for different input.") }
                var cached = try JSON.object(Data(row[1].utf8)); cached.removeValue(forKey: "effectClaim"); return cached
            }
            let result = try dispatch(method, params, now)
            if let requestID, Catalog.operations.first(where: { $0.name == method })?.mutates == true {
                try db.run("INSERT INTO requests(id,fingerprint,result) VALUES(?,?,?)", [requestID, fingerprint, JSON.string(result)])
            }
            return result
        }
    }
    private func dispatch(_ method: String, _ p: [String: Any], _ now: Double) throws -> [String: Any] {
        switch method {
        case "dismissShimSetup":
            try db.run("INSERT OR IGNORE INTO app_setup(key) VALUES('terminal-notifier-offer')")
            return ["promptHandled": true]
        case "preferences": return try JSON.encode(preferences())
        case "setPreferences":
            var current = try preferences()
            if let expected = p["expectedRevision"] as? Int, expected != current.revision {
                throw NotifyError("revision_conflict", "Preferences changed. Read preferences and retry with their current revision.")
            }
            let previous = current
            if let style = p["arrivalStyle"] as? String { current.arrivalStyle = ArrivalStyle(rawValue: style)! }
            if let show = p["showBannerReminder"] as? Bool { current.showBannerReminder = show }
            if current != previous {
                current.revision += 1
                try db.run("INSERT INTO preferences(id,json) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json", [JSON.string(try JSON.encode(current))])
            }
            return try JSON.encode(current)
        case "send": return try send(p, now)
        case "heartbeat":
            let id = p["id"] as! String, token = p["waiterId"] as! String
            guard let row = try db.rows("SELECT token FROM waiters WHERE notification_id=?", [id]).first, row[0] == token else { throw NotifyError("invalid_state", "No matching live CLI lease. Read the recorded outcome.") }
            try db.run("UPDATE waiters SET expires=? WHERE notification_id=?", [String(now + 5), id])
            return ["expiresAt": now + 5]
        case "get": return try JSON.encode(get(p["id"] as! String))
        case "list":
            let scope = p["filter"] as? String ?? "inbox"
            let group = p["group"] as? String
            let query = p["query"] as? String ?? ""
            let since = p["since"] as? Double ?? 0
            let before = p["before"] as? Double ?? .greatestFiniteMagnitude
            let offset = p["offset"] as? Int ?? 0, limit = p["limit"] as? Int ?? 100
            let items = try all().filter { item in
                let match: Bool
                switch scope {
                case "all": match = true
                case "unread": match = item.isInbox && item.readAt == nil
                case "later": match = ["scheduled", "snoozed"].contains(item.status)
                case "done": match = item.status == "done"
                case "delivered": match = item.status == "active" && item.delivery == "accepted" && item.response == nil
                case "pending": match = ["scheduled", "snoozed"].contains(item.status)
                default: match = item.isInbox
                }
                return match && (group == nil || item.group == group) && item.createdAt >= since && item.createdAt < before && (query.isEmpty || [item.title, item.subtitle, item.message, item.group].joined(separator: " ").localizedCaseInsensitiveContains(query))
            }
            let page = try JSON.boundedPage(items.dropFirst(offset).prefix(limit).map { try JSON.encode($0) })
            return ["items": page, "total": items.count, "cursor": try cursor(), "hasMore": offset + page.count < items.count]
        case "changes":
            let after = p["after"] as? Int ?? 0, limit = p["limit"] as? Int ?? 100
            guard after <= (try cursor()) else { throw NotifyError("invalid_cursor", "Cursor is ahead of this store. Bootstrap this server with changes after 0.") }
            let rows = try db.rows("SELECT seq,kind,json FROM changes WHERE seq>? ORDER BY seq LIMIT ?", [String(after), String(limit)])
            let changes: [[String: Any]] = try JSON.boundedPage(rows.map { ["cursor": Int($0[0])!, "kind": $0[1], "notification": try JSON.object(Data($0[2].utf8))] })
            let end = changes.last?["cursor"] as? Int ?? after
            return ["changes": changes, "cursor": end, "hasMore": end < (try cursor())]
        case "status": return try mutate(p, now)
        case "completeAll":
            var completed: [String] = []
            for var item in try all() where item.isInbox {
                complete(&item, now)
                item.updatedAt = now
                item.revision += 1
                try save(item, kind: "done")
                completed.append(item.id)
            }
            return ["completed": completed]
        case "statusBatch":
            let references = p["items"] as! [[String: Any]]
            let ids = references.map { $0["id"] as! String }
            guard Set(ids).count == ids.count else { throw NotifyError("invalid_argument", "statusBatch requires unique notification IDs.") }
            var items: [[String: Any]] = []
            for reference in references {
                var params: [String: Any] = ["id": reference["id"]!, "state": p["state"]!]
                if let expected = reference["expectedRevision"] { params["expectedRevision"] = expected }
                for key in ["until", "in", "at"] where p[key] != nil { params[key] = p[key] }
                items.append(try mutate(params, now))
            }
            return ["items": items, "count": items.count]
        case "respond": return try respond(p, now)
        case "remove":
            let group = p["group"] as! String
            var removed: [String] = []
            for var item in try all() where (group == "ALL" || item.group == group) && ["active", "scheduled", "snoozed"].contains(item.status) {
                item.status = "removed"; item.updatedAt = now; item.revision += 1
                if item.interactive && item.response == nil { item.response = Response(kind: "close", value: "@CLOSED", exitCode: 0, at: now) }
                try save(item, kind: "removed"); removed.append(item.id)
            }
            return ["removed": removed]
        case "diagnose":
            let items = try all()
            return ["version": Catalog.version, "compatibility": "terminal-notifier 3.1", "database": paths.database.path, "socket": paths.socket, "cursor": try cursor(), "inbox": items.filter(\.isInbox).count, "unread": items.filter { $0.isInbox && $0.readAt == nil }.count, "total": items.count]
        default: throw NotifyError("unknown_method", "Unknown operation: \(method).")
        }
    }
    private func send(_ p: [String: Any], _ now: Double) throws -> [String: Any] {
        let message = p["message"] as! String
        guard !message.isEmpty else { throw NotifyError("invalid_argument", "A nonempty message is required.", exitCode: 1) }
        let actions = p["actions"] as? [String] ?? []
        guard actions.allSatisfy({ !$0.isEmpty }), actions.count <= 100 else { throw NotifyError("invalid_argument", "Use 1–100 nonempty action labels; native macOS surfaces may show fewer.") }
        if let url = p["open"] as? String, URL(string: url)?.scheme?.isEmpty != false { throw NotifyError("invalid_argument", "open must be a URL with a scheme, such as https:// or file://.") }
        if let timeout = p["timeout"] as? Double, timeout <= 0 || !timeout.isFinite { throw NotifyError("invalid_argument", "timeout must be positive seconds.") }
        var due: Double?
        if let delay = p["in"] as? String { due = now + (try Schedule.duration(delay)) }
        if let at = p["at"] as? String {
            guard due == nil else { throw NotifyError("invalid_argument", "in and at are mutually exclusive.") }
            due = try Schedule.date(at, now: Date(timeIntervalSince1970: now)).timeIntervalSince1970
        }
        let interactive = !actions.isEmpty || p["reply"] != nil
        guard due == nil || !interactive else { throw NotifyError("invalid_argument", "Scheduled notifications cannot use action or reply.") }
        let group = p["group"] as? String ?? ""
        if let remove = p["remove"] as? String { _ = try dispatch("remove", ["group": remove], now) }
        if !group.isEmpty {
            for var item in try all() where item.group == group && ["active", "scheduled", "snoozed"].contains(item.status) {
                item.status = "superseded"; item.updatedAt = now; item.revision += 1
                if item.interactive && item.response == nil { item.response = Response(kind: "close", value: "@CLOSED", exitCode: 0, at: now) }
                try save(item, kind: "superseded")
            }
        }
        var item = NotificationRecord(id: UUID().uuidString.lowercased(), title: p["title"] as? String ?? "Terminal", subtitle: p["subtitle"] as? String ?? "", message: message, group: group, actions: actions, reply: p["reply"] as? String, execute: p["execute"] as? String, open: p["open"] as? String, activate: p["activate"] as? String, sound: p["sound"] as? String, contentImage: p["contentImage"] as? String, timeSensitive: p["ignoreDnD"] as? Bool ?? false, createdAt: now, updatedAt: now, scheduledAt: due, deadline: interactive ? (p["timeout"] as? Double).map { now + $0 } : nil, status: due == nil ? "active" : "scheduled", revision: 1, delivery: "pending", nativeRegistered: false)
        if let path = item.contentImage {
            do {
                let source = URL(string: path)?.isFileURL == true ? URL(string: path)! : URL(fileURLWithPath: path)
                guard path.hasPrefix("/") || URL(string: path)?.isFileURL == true else { throw NotifyError("invalid_argument", "Use an absolute image path or file URL.") }
                let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 20_000_000 else { throw NotifyError("invalid_argument", "Attachment must be a regular file under 20 MB.") }
                let directory = paths.root.appendingPathComponent("attachments/\(item.id)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let destination = directory.appendingPathComponent("original").appendingPathExtension(source.pathExtension)
                try FileManager.default.copyItem(at: source, to: destination); chmod(destination.path, 0o600)
                item.contentImage = destination.path
            } catch { item.deliveryError = "Image unavailable: \(error.localizedDescription)" }
        }
        if let token = p["waiterId"] as? String, interactive { try db.run("INSERT INTO waiters(notification_id,token,expires) VALUES(?,?,?)", [item.id, token, String(now + 5)]) }
        try save(item, kind: "created")
        return try JSON.encode(item)
    }
    private func checked(_ p: [String: Any]) throws -> NotificationRecord {
        let item = try get(p["id"] as! String)
        if let expected = p["expectedRevision"] as? Int, expected != item.revision { throw NotifyError("revision_conflict", "Notification changed. Fetch it and retry with its current revision.") }
        return item
    }
    private func mutate(_ p: [String: Any], _ now: Double) throws -> [String: Any] {
        var item = try checked(p)
        let state = p["state"] as! String
        switch state {
        case "read": item.readAt = now
        case "unread": item.readAt = nil
        case "done": complete(&item, now)
        case "reopen":
            guard !["removed", "superseded"].contains(item.status) else { throw NotifyError("invalid_state", "Removed or replaced notifications remain in history; send a new notification.") }
            item.status = "active"; item.snoozedUntil = nil
        case "snooze":
            guard item.status == "active", !item.interactive || item.response != nil else { throw NotifyError("invalid_state", "Answer or close a waiting prompt before snoozing it.") }
            let until: Double
            if let timestamp = p["until"] as? Double { until = timestamp }
            else if let delay = p["in"] as? String { until = now + (try Schedule.duration(delay)) }
            else if let at = p["at"] as? String { until = try Schedule.date(at, now: Date(timeIntervalSince1970: now)).timeIntervalSince1970 }
            else { throw NotifyError("invalid_argument", "Snooze requires until, in, or at.") }
            guard until > now else { throw NotifyError("invalid_argument", "Snooze time must be in the future.") }
            item.status = "snoozed"; item.presentable = true; item.snoozedUntil = until; item.nativeRegistered = false; item.delivery = "pending"
        default: throw NotifyError("invalid_argument", "Unknown state.")
        }
        item.updatedAt = now; item.revision += 1
        try save(item, kind: state)
        return try JSON.encode(item)
    }
    private func complete(_ item: inout NotificationRecord, _ now: Double) {
        item.status = "done"
        item.readAt = item.readAt ?? now
        if item.interactive && item.response == nil {
            item.response = Response(kind: "close", value: "@CLOSED", exitCode: 0, at: now)
        }
    }
    private func respond(_ p: [String: Any], _ now: Double) throws -> [String: Any] {
        var item = try checked(p)
        guard item.canRespond else { throw NotifyError("already_resolved", "This notification can no longer accept a response. Fetch its recorded outcome.") }
        if let deadline = item.deadline, deadline <= now { throw NotifyError("expired", "This prompt’s response deadline has passed.") }
        let kind = p["kind"] as! String
        var value = p["value"] as? String ?? "", exitCode: Int32 = 0
        switch kind {
        case "action":
            guard let index = p["actionIndex"] as? Int, item.actions.indices.contains(index) else { throw NotifyError("invalid_argument", "Choose an actionIndex from this notification’s actions array.") }
            value = item.actions[index]
        case "reply": guard item.reply != nil, p["value"] != nil else { throw NotifyError("invalid_argument", "This notification needs a reply value.") }
        case "body": value = item.hasBodyAction ? "" : "@ACTIONCLICKED"
        case "close": value = "@CLOSED"
        case "interrupt": value = ""; exitCode = 6
        default: throw NotifyError("invalid_argument", "Unknown response kind.")
        }
        item.presentable = false
        let effect = kind == "body" && item.hasBodyAction
        item.response = Response(kind: kind, value: value, exitCode: exitCode, at: now, effect: effect ? "running" : nil)
        item.readAt = item.readAt ?? now
        // Claim effects before running them. Only this invocation may execute the claim.
        if !effect { item.status = kind == "interrupt" ? "active" : "done" }
        item.updatedAt = now; item.revision += 1
        try save(item, kind: "responded")
        var result = try JSON.encode(item); if effect { result["effectClaim"] = true }; return result
    }
    public func updateDelivery(id: String, state: String, error: String? = nil, registered: Bool = true) throws {
        lock.lock(); defer { lock.unlock() }
        try db.transaction {
            var item = try get(id)
            guard item.delivery != state || item.deliveryError != error || item.nativeRegistered != registered else { return }
            item.delivery = state; item.deliveryError = error; item.nativeRegistered = registered
            item.updatedAt = Date().timeIntervalSince1970; item.revision += 1
            try save(item, kind: "delivery")
        }
    }
    public func finishEffect(id: String, error: String?) throws {
        lock.lock(); defer { lock.unlock() }
        try db.transaction {
            var item = try get(id)
            guard item.response?.effect == "running" else { return }
            item.response?.effect = error == nil ? "succeeded" : "failed"
            item.response?.error = error; item.response?.exitCode = error == nil ? 0 : 5
            if item.status == "active" { item.status = error == nil ? "done" : "active" }
            item.updatedAt = Date().timeIntervalSince1970; item.revision += 1
            try save(item, kind: "effect_finished")
        }
    }
    public func recoverEffects() throws {
        lock.lock(); defer { lock.unlock() }
        try db.transaction {
            for var item in try all() where item.response?.effect == "running" {
                item.response?.effect = "interrupted"; item.response?.error = "App stopped before execution was confirmed. Check the destination before taking further action."; item.response?.exitCode = 5
                item.updatedAt = Date().timeIntervalSince1970; item.revision += 1
                try save(item, kind: "effect_interrupted")
            }
        }
    }
    public func tick(now: Double = Date().timeIntervalSince1970) throws {
        lock.lock(); defer { lock.unlock() }
        try db.transaction {
            let leases = try db.rows("SELECT notification_id FROM waiters WHERE expires<=?", [String(now)])
            for lease in leases {
                var item = try get(lease[0])
                if item.canRespond {
                    item.response = Response(kind: "interrupt", value: "", exitCode: 6, at: now)
                    item.presentable = false; item.updatedAt = now; item.revision += 1
                    try save(item, kind: "disconnected")
                }
                try db.run("DELETE FROM waiters WHERE notification_id=?", [item.id])
            }
            let due = try db.rows("SELECT json FROM notifications WHERE (status='active' AND json_extract(json,'$.response') IS NULL AND json_extract(json,'$.deadline')<=?) OR (status='scheduled' AND json_extract(json,'$.scheduledAt')<=?) OR (status='snoozed' AND json_extract(json,'$.snoozedUntil')<=?)", [String(now), String(now), String(now)]).map { try JSONDecoder().decode(NotificationRecord.self, from: Data($0[0].utf8)) }
            for var item in due {
                if item.status == "active", item.response == nil, let deadline = item.deadline, deadline <= now {
                    item.presentable = false
                    item.response = Response(kind: "timeout", value: "@TIMEOUT", exitCode: 6, at: now)
                    item.updatedAt = now; item.revision += 1; try save(item, kind: "timeout")
                } else if (item.status == "scheduled" && (item.scheduledAt ?? .infinity) <= now) || (item.status == "snoozed" && (item.snoozedUntil ?? .infinity) <= now) {
                    item.status = "active"; item.snoozedUntil = nil; item.updatedAt = now; item.revision += 1
                    try save(item, kind: "due")
                }
            }
        }
    }
}
