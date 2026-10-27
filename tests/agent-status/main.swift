import Foundation

func event(_ type: String, _ payload: [String: Any], _ time: Date) -> [String: Any] {
    ["type": type, "payload": payload, "timestamp": ISO8601DateFormatter().string(from: time)]
}
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
let now = Date()
var a = AgentSession(provider: .codex, sessionID: "a")
a.consumeCodex(event("event_msg", ["type": "task_started"], now))
expect(a.state == .running, "start")
a.consumeCodex(event("response_item", ["type": "function_call", "name": "request_user_input", "call_id": "q1"], now))
expect(a.state == .waiting, "input request")
a.consumeCodex(event("response_item", ["type": "function_call_output", "call_id": "other"], now))
expect(a.state == .waiting, "unrelated response must not resolve input")
a.consumeCodex(event("response_item", ["type": "function_call_output", "call_id": "q1"], now))
expect(a.state == .running, "input resolution")
expect(a.resolved(at: now.addingTimeInterval(301)).state == .unknown, "stale is unknown")
a.consumeCodex(event("event_msg", ["type": "task_complete"], now))
expect(a.state == .completed, "completed")
expect(!AgentSummary(sessions: [a], now: now.addingTimeInterval(9)).isVisible, "completion fades")
a.consumeCodex(event("event_msg", ["type": "turn_aborted"], now))
expect(a.state == .idle, "cancel is not success")
var running = a; running.state = .running
var waiting = a; waiting.state = .waiting
let summary = AgentSummary(sessions: [running, waiting], now: now)
expect(summary.state == .waiting && summary.count == 1 && summary.runningCount == 1, "attention priority and running indicator")
var completed = a; completed.state = .completed
expect(AgentSummary(sessions: [running, completed], now: now).state == .completed, "brief completion notification")
expect(AgentSummary(sessions: [running, completed], now: now.addingTimeInterval(9)).state == .running, "restore active count after completion")
expect(AgentSession.claudeEvent(["version": 9]) == nil, "invalid bridge version")
let claude = AgentSession.claudeEvent(["version": 1, "session_id": "a", "timestamp": now.timeIntervalSince1970, "state": "running"])!
expect(claude.id != a.id, "provider IDs must not collide")
let qoder = AgentSession.hookEvent(["version": 1, "session_id": "a", "timestamp": now.timeIntervalSince1970, "state": "waiting"], provider: .qoder)!
expect(qoder.provider == .qoder && qoder.id != claude.id, "Qoder events keep their own provider and ID")

var overlapping = AgentSession(provider: .codex, sessionID: "overlap")
overlapping.consumeCodex(event("event_msg", ["type": "task_started", "turn_id": "new"], now))
overlapping.consumeCodex(event("event_msg", ["type": "task_complete", "turn_id": "old"], now))
expect(overlapping.state == .running, "late completion must not finish a newer turn")

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let codex = root.appendingPathComponent("codex")
let claudeRoot = root.appendingPathComponent("claude")
let logs = codex.appendingPathComponent("sessions/2026/10/27")
try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let file = logs.appendingPathComponent("rollout-2026-10-27T00-00-00-00000000-0000-0000-0000-000000000001.jsonl")
func encoded(_ row: [String: Any]) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: row); data.append(10); return data
}
try encoded(event("event_msg", ["type": "task_started"], now)).write(to: file)
let reader = AgentStatusReader()
let first = reader.scan(codex: codex, claude: claudeRoot, now: now).0
expect(first.count == 1 && first[0].state == .running, "discover real session")
let complete = try encoded(event("event_msg", ["type": "task_complete"], now))
let handle = try FileHandle(forWritingTo: file)
try handle.seekToEnd(); try handle.write(contentsOf: complete.prefix(complete.count / 2))
expect(reader.scan(codex: codex, claude: claudeRoot, now: now).0.first?.state == .running, "partial JSONL must not lose state")
try handle.write(contentsOf: complete.suffix(complete.count - complete.count / 2)); try handle.close()
expect(reader.scan(codex: codex, claude: claudeRoot, now: now).0.first?.state == .completed, "appended complete line")
expect(reader.scan(codex: codex, claude: claudeRoot, now: now).0.count == 1, "polling must not duplicate sessions")
try encoded(event("event_msg", ["type": "task_started"], now)).write(to: file)
expect(reader.scan(codex: codex, claude: claudeRoot, now: now).0.first?.state == .running, "rotation/truncation recovery")
try FileManager.default.removeItem(at: file)
expect(reader.scan(codex: codex, claude: claudeRoot, now: now.addingTimeInterval(16)).0.isEmpty, "archived or removed session disappears")
let qoderRoot = root.appendingPathComponent("qoder")
let qoderEvents = qoderRoot.appendingPathComponent("boring-notch-events")
try FileManager.default.createDirectory(at: qoderEvents, withIntermediateDirectories: true)
let qoderRecord: [String: Any] = ["version": 1, "session_id": "qoder-session", "state": "running",
                                  "project": "project", "timestamp": now.timeIntervalSince1970]
try JSONSerialization.data(withJSONObject: qoderRecord).write(to: qoderEvents.appendingPathComponent("event.json"))
let qoderSessions = reader.scan(codex: codex, claude: claudeRoot, qoder: qoderRoot, now: now.addingTimeInterval(16)).0
expect(qoderSessions.count == 1 && qoderSessions[0].provider == .qoder, "read Qoder hook events")
print("PASS: event transitions, stale state, aggregation, partial writes, deduplication, file rotation and Qoder events")
