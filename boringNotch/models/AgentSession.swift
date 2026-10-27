import Foundation

enum AgentProvider: String, Codable, CaseIterable {
    case codex, claude, qoder
    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .qoder: return "Qoder"
        }
    }
    var directoryName: String {
        switch self {
        case .codex: return ".codex"
        case .claude: return ".claude"
        case .qoder: return ".qoder"
        }
    }
}

enum AgentState: String, Codable, CaseIterable {
    case waiting, failed, running, completed, unknown, idle
    var title: String {
        switch self {
        case .waiting: return "待处理"
        case .failed: return "失败"
        case .running: return "运行中"
        case .completed: return "已完成"
        case .unknown: return "状态未知"
        case .idle: return "空闲"
        }
    }
    var priority: Int { Self.allCases.firstIndex(of: self)! }
}

struct AgentSession: Identifiable, Equatable {
    let provider: AgentProvider
    let sessionID: String
    var title = ""
    var project = ""
    var state: AgentState = .unknown
    var detail = "尚未收到任务事件"
    var updatedAt = Date.distantPast
    var waitingCallID: String?
    var activeTurnID: String?
    var isSubagent = false
    var id: String { "\(provider.rawValue):\(sessionID)" }
    var displayTitle: String {
        title.isEmpty ? (project.isEmpty ? String(sessionID.suffix(8)) : project) : title
    }

    func resolved(at now: Date) -> AgentSession {
        var result = self
        // A stalled log is not proof that a task is still running or has finished.
        if [.running, .waiting].contains(state), now.timeIntervalSince(updatedAt) > 300 {
            result.state = .unknown
            result.detail = "超过 5 分钟没有新事件，请回到 Agent 确认"
        }
        return result
    }

    mutating func consumeCodex(_ record: [String: Any]) {
        guard let payload = record["payload"] as? [String: Any],
              let kind = record["type"] as? String else { return }
        let date = AgentEventDate.parse(record["timestamp"] as? String) ?? updatedAt
        if kind == "session_meta" {
            project = URL(fileURLWithPath: payload["cwd"] as? String ?? "").lastPathComponent
            isSubagent = (payload["source"] as? [String: Any])?["subagent"] != nil
            return
        }
        if kind == "turn_context", let cwd = payload["cwd"] as? String {
            project = URL(fileURLWithPath: cwd).lastPathComponent
            return
        }
        let type = payload["type"] as? String ?? ""
        if kind == "event_msg" {
            if ["task_complete", "turn_aborted", "task_failed"].contains(type),
               let activeTurnID, let turnID = payload["turn_id"] as? String, turnID != activeTurnID {
                return
            }
            switch type {
            case "task_started":
                activeTurnID = payload["turn_id"] as? String
                state = .running; detail = "正在处理任务"; waitingCallID = nil
            case "task_complete":
                state = .completed; detail = "本轮任务已结束"; waitingCallID = nil
            case "turn_aborted":
                state = .idle; detail = "任务已中断"; waitingCallID = nil
            case "task_failed":
                state = .failed; detail = "任务执行失败"; waitingCallID = nil
            default:
                // Token / item events confirm activity without exposing conversation content.
                if state == .running || state == .waiting { updatedAt = max(updatedAt, date) }
                return
            }
            updatedAt = date
        } else if kind == "response_item" {
            // A bounded log tail can start midway through a turn. Explicit agent
            // activity still supplies evidence without inventing a completed turn.
            if state == .unknown && ["function_call", "custom_tool_call", "reasoning"].contains(type) {
                state = .running
            }
            guard [.running, .waiting].contains(state) else { return }
            if type == "function_call" || type == "custom_tool_call" {
                let name = payload["name"] as? String ?? ""
                if name.split(separator: ".").last == "request_user_input" {
                    state = .waiting; detail = "等待你回答问题"
                    waitingCallID = payload["call_id"] as? String
                } else if state != .waiting {
                    detail = "执行工具：\(String(name.prefix(48)))"
                }
            } else if type == "function_call_output" || type == "custom_tool_call_output" {
                if let waitingCallID, payload["call_id"] as? String == waitingCallID {
                    state = .running; detail = "继续处理任务"; self.waitingCallID = nil
                }
            } else if type == "reasoning", state != .waiting {
                detail = "正在思考"
            } else if type == "message", payload["role"] as? String == "assistant", state != .waiting {
                detail = "正在回复"
            }
            updatedAt = max(updatedAt, date)
        }
    }

    static func claudeEvent(_ record: [String: Any]) -> AgentSession? {
        hookEvent(record, provider: .claude)
    }

    static func hookEvent(_ record: [String: Any], provider: AgentProvider) -> AgentSession? {
        guard record["version"] as? Int == 1,
              let id = record["session_id"] as? String, !id.isEmpty, id.count <= 200,
              let raw = record["state"] as? String, let state = AgentState(rawValue: raw),
              let timestamp = record["timestamp"] as? Double else { return nil }
        var session = AgentSession(provider: provider, sessionID: id)
        session.project = String((record["project"] as? String ?? "").prefix(160))
        session.detail = String((record["detail"] as? String ?? state.title).prefix(160))
        session.state = state
        session.updatedAt = Date(timeIntervalSince1970: timestamp)
        return session
    }
}

enum AgentEventDate {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct AgentSummary: Equatable {
    var state: AgentState = .idle
    var count = 0
    var runningCount = 0

    init(sessions: [AgentSession], now: Date) {
        let current = sessions.map { $0.resolved(at: now) }.filter { !$0.isSubagent }
        runningCount = current.filter { $0.state == .running }.count
        for candidate in [AgentState.waiting, .failed, .completed, .running, .unknown] {
            let matches = current.filter {
                $0.state == candidate && (candidate != .completed || now.timeIntervalSince($0.updatedAt) < 8)
                    && now.timeIntervalSince($0.updatedAt) < 3600
            }
            if !matches.isEmpty { state = candidate; count = matches.count; return }
        }
    }
    var isVisible: Bool { count > 0 }
}
