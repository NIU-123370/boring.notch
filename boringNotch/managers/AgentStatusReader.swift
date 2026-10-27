import Foundation

/// Only metadata and lifecycle events are retained, never prompts or tool output.
/// All disk work runs on AgentStatusManager's serial utility queue.
final class AgentStatusReader: @unchecked Sendable {
    private let lock = NSLock()
    private struct Cursor {
        var offset: UInt64 = 0
        var pending = Data()
        var discardPartial = false
        var session: AgentSession
        var fileID: UInt64 = 0
    }
    private var cursors: [URL: Cursor] = [:]
    private var discovered: [URL] = []
    private var lastDiscovery = Date.distantPast
    private var roots: [URL] = []

    func scan(codex: URL, claude: URL, now: Date = Date()) -> ([AgentSession], [AgentProvider: String]) {
        lock.lock()
        defer { lock.unlock() }
        if roots != [codex, claude] {
            roots = [codex, claude]; cursors.removeAll(); lastDiscovery = .distantPast
        }
        var connection: [AgentProvider: String] = [:]
        let sessionsURL = codex.appendingPathComponent("sessions")
        let codexReadable = FileManager.default.isReadableFile(atPath: sessionsURL.path)
        connection[.codex] = codexReadable ? "本地事件已连接" : "未连接：请选择 .codex 文件夹"
        if now.timeIntervalSince(lastDiscovery) >= 15 {
            discovered = discover(in: sessionsURL, since: now.addingTimeInterval(-86400))
            let retained = Set(discovered)
            cursors = cursors.filter { retained.contains($0.key) }
            lastDiscovery = now
        }
        let titles = readTitles(codex.appendingPathComponent("session_index.jsonl"))
        var result: [AgentSession] = []
        if codexReadable {
            for url in discovered {
                guard var session = readCodex(url) else { continue }
                session.title = titles[session.sessionID] ?? ""
                if !session.isSubagent, session.updatedAt > now.addingTimeInterval(-86400) {
                    result.append(session.resolved(at: now))
                }
            }
        }
        let hooksURL = claude.appendingPathComponent("boring-notch-events")
        let hookInstalled = FileManager.default.fileExists(atPath: hooksURL.appendingPathComponent("installed").path)
        connection[.claude] = hookInstalled ? "Hooks 已配置，等待事件" : "未连接：需安装 Claude hooks"
        if let files = try? FileManager.default.contentsOfDirectory(at: hooksURL, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for url in files.filter({ $0.pathExtension == "json" }).prefix(200) {
                guard let data = boundedData(url, limit: 16384),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let session = AgentSession.claudeEvent(json),
                      session.updatedAt > now.addingTimeInterval(-86400),
                      session.updatedAt <= now.addingTimeInterval(60) else { continue }
                result.append(session.resolved(at: now))
                if now.timeIntervalSince(session.updatedAt) < 300 { connection[.claude] = "本地事件已连接" }
            }
        }
        // Namespaced IDs prevent collisions between providers; one row per session.
        let unique = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt > b.updatedAt ? a : b })
        return (unique.values.sorted {
            if $0.state.priority != $1.state.priority { return $0.state.priority < $1.state.priority }
            return $0.updatedAt > $1.updatedAt
        }, connection)
    }

    private func discover(in root: URL, since: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  info.isRegularFile == true, let modified = info.contentModificationDate, modified > since else { continue }
            files.append((url, modified))
        }
        return files.sorted { $0.1 > $1.1 }.prefix(200).map(\.0)
    }

    private func readCodex(_ url: URL) -> AgentSession? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let inode = attrs[.systemFileNumber] as? UInt64 ?? 0
        var cursor = cursors[url] ?? Cursor(session: AgentSession(provider: .codex,
            sessionID: String(url.deletingPathExtension().lastPathComponent.suffix(36))))
        if size < cursor.offset || (cursor.fileID != 0 && cursor.fileID != inode) {
            cursor = Cursor(session: AgentSession(provider: .codex, sessionID: cursor.session.sessionID))
        }
        cursor.fileID = inode
        if cursor.offset == 0 {
            // Session headers may be large; inspect at most 512 KiB, then bootstrap
            // from a bounded tail. Never load a whole conversation into memory.
            if let header = try? handle.read(upToCount: 512 * 1024), let end = header.firstIndex(of: 10) {
                consume(header.prefix(upTo: end), into: &cursor.session)
            }
            let tailSize: UInt64 = 2 * 1024 * 1024
            if size > tailSize { cursor.offset = size - tailSize; cursor.discardPartial = true }
        }
        do {
            try handle.seek(toOffset: cursor.offset)
            let data = try handle.read(upToCount: 2 * 1024 * 1024) ?? Data()
            cursor.offset += UInt64(data.count)
            cursor.pending.append(data)
            while let end = cursor.pending.firstIndex(of: 10) {
                let line = cursor.pending.prefix(upTo: end)
                if !cursor.discardPartial { consume(line, into: &cursor.session) }
                cursor.discardPartial = false
                cursor.pending.removeSubrange(...end)
            }
            if cursor.pending.count > 2 * 1024 * 1024 {
                cursor.pending.removeAll(); cursor.discardPartial = true
            }
            cursors[url] = cursor
            return cursor.session
        } catch { return nil }
    }

    private func consume(_ line: Data.SubSequence, into session: inout AgentSession) {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return }
        session.consumeCodex(json)
    }

    private func boundedData(_ url: URL, limit: Int) -> Data? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size <= limit else { return nil }
        return try? Data(contentsOf: url)
    }

    private func readTitles(_ url: URL) -> [String: String] {
        guard let data = boundedData(url, limit: 2 * 1024 * 1024) else { return [:] }
        var result: [String: String] = [:]
        for line in data.split(separator: 10) {
            if let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               let id = row["id"] as? String, let title = row["thread_name"] as? String {
                result[id] = String(title.prefix(120))
            }
        }
        return result
    }
}
