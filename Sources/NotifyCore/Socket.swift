import Foundation
import Darwin

private let maxFrame = 1_048_576
private func address(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw NotifyError("unsafe_path", "Socket path is too long. Set AGENTNOTIFY_STATE_DIR to a shorter absolute path.") }
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + Array(repeating: 0, count: $0.count - bytes.count)) }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return addr
}
private func configure(_ fd: Int32) {
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    var timeout = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
}
private func writeFrame(_ fd: Int32, _ object: [String: Any]) throws {
    var data = try JSON.data(object); data.append(10)
    try data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let sent = Darwin.send(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
            if sent < 0 && errno == EINTR { continue }
            guard sent > 0 else { throw NotifyError("service_unavailable", "Socket write failed.", exitCode: 4) }
            offset += sent
        }
    }
}
private func readFrame(_ fd: Int32, buffer: inout Data) throws -> Data? {
    while true {
        if let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]; buffer.removeSubrange(...newline); return Data(line)
        }
        guard buffer.count < maxFrame else { throw NotifyError("invalid_request", "Request exceeds 1 MiB.") }
        var chunk = [UInt8](repeating: 0, count: 8192)
        let count = recv(fd, &chunk, min(chunk.count, maxFrame - buffer.count), 0)
        if count < 0 && errno == EINTR { continue }
        if count == 0 { return nil }
        guard count > 0 else { throw NotifyError("service_unavailable", "Socket read timed out or disconnected.", exitCode: 4) }
        buffer.append(contentsOf: chunk.prefix(count))
    }
}

public final class SocketClient {
    public let path: String
    public init(path: String) { self.path = path }
    public func call(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NotifyError("service_unavailable", "Cannot create socket.", exitCode: 4) }
        defer { close(fd) }; configure(fd)
        var addr = try address(path)
        let connected = withUnsafePointer(to: &addr) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard connected == 0 else { throw NotifyError("service_unavailable", "AgentNotify is not running at \(path). Open AgentNotify.app or run agentnotify serve for headless use.", exitCode: 4) }
        let id = UUID().uuidString
        try writeFrame(fd, ["id": id, "method": method, "params": params])
        var buffer = Data()
        guard let data = try readFrame(fd, buffer: &buffer) else { throw NotifyError("service_unavailable", "Service closed without a response. Retry mutations only with the same requestId.", exitCode: 4) }
        let result = try JSON.object(data)
        guard result["id"] as? String == id else { throw NotifyError("invalid_request", "Mismatched response ID.") }
        return result
    }
    public func result(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let response = try call(method, params)
        if response["ok"] as? Bool != true {
            let error = response["error"] as? [String: Any] ?? [:]
            throw NotifyError(error["code"] as? String ?? "internal_error", error["message"] as? String ?? "Service error.", exitCode: (error["exit_code"] as? NSNumber)?.int32Value ?? 5)
        }
        return response["data"] as? [String: Any] ?? [:]
    }
}

public final class SocketServer {
    private var fd: Int32 = -1
    private var lockFD: Int32 = -1
    private let path: String
    private let handler: ([String: Any]) -> [String: Any]
    private let connections = DispatchSemaphore(value: 32)
    public init(paths: NotifyPaths, handler: @escaping ([String: Any]) -> [String: Any]) throws {
        try paths.prepare(); path = paths.socket; self.handler = handler
        lockFD = open(paths.root.appendingPathComponent("service.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { if lockFD >= 0 { close(lockFD) }; lockFD = -1; throw NotifyError("already_running", "An AgentNotify service already owns this inbox.", exitCode: 4) }
        do {
            var statbuf = stat()
            if lstat(path, &statbuf) == 0 {
                guard statbuf.st_mode & S_IFMT == S_IFSOCK, statbuf.st_uid == getuid() else { throw NotifyError("unsafe_path", "Refusing to replace a foreign file at the socket path.") }
                unlink(path)
            }
            fd = socket(AF_UNIX, SOCK_STREAM, 0); configure(fd)
            var addr = try address(path)
            let bound = withUnsafePointer(to: &addr) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 32) == 0 else { throw NotifyError("service_unavailable", "Could not bind the private notification socket.", exitCode: 4) }
        } catch { if fd >= 0 { close(fd); fd = -1 }; close(lockFD); lockFD = -1; throw error }
    }
    public func start() {
        let listener = fd
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let self, self.fd == listener {
                let client = accept(listener, nil, nil)
                if client < 0 { if errno == EINTR { continue }; break }
                configure(client)
                var uid: uid_t = 0, gid: gid_t = 0
                guard getpeereid(client, &uid, &gid) == 0, uid == getuid(), self.connections.wait(timeout: .now()) == .success else { close(client); continue }
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { close(client); self.connections.signal() }
                    var buffer = Data()
                    do {
                        while let frame = try readFrame(client, buffer: &buffer) {
                            var response: [String: Any]
                            do {
                                let request = try JSON.object(frame)
                                response = self.handler(request); response["id"] = request["id"] ?? NSNull()
                            } catch { response = JSON.failure(error); response["id"] = NSNull() }
                            try writeFrame(client, response)
                        }
                    } catch { try? writeFrame(client, JSON.failure(error)) }
                }
            }
        }
    }
    public func stop() {
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); fd = -1; unlink(path) }
        if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1 }
    }
    deinit { stop() }
}
