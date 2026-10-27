import SwiftUI

extension AgentState {
    var color: Color {
        switch self {
        case .waiting: return .yellow
        case .failed: return .red
        case .running: return .cyan
        case .completed: return .green
        case .unknown, .idle: return .gray
        }
    }
    var symbol: String {
        switch self {
        case .waiting, .failed: return "exclamationmark"
        case .running: return "sparkles"
        case .completed: return "checkmark"
        case .unknown: return "questionmark"
        case .idle: return "moon"
        }
    }
}

struct AgentIslandAttachment: View {
    @ObservedObject private var manager = AgentStatusManager.shared
    let isClosed: Bool
    let isHidden: Bool
    let notchHeight: CGFloat
    let availableWidth: CGFloat
    let openAgents: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = min(36, notchHeight)
            let fits = (availableWidth - geometry.size.width) / 2 >= size + 8
            if manager.enabled && manager.summary.isVisible && isClosed && !isHidden && fits && size >= 20 {
                Button(action: openAgents) {
                    AgentIslandBadge(summary: manager.summary, size: size)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("Agent：\(manager.summary.state.title) \(manager.summary.count) 个会话。点击查看列表")
                .accessibilityLabel("Agent 状态")
                .accessibilityValue("\(manager.summary.state.title)，\(manager.summary.count) 个会话")
                .position(x: geometry.size.width + 8 + size / 2 - 6, y: size / 2)
            }
        }
    }
}

struct AgentIslandBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let summary: AgentSummary
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.black)
            Circle().stroke(summary.state.color.opacity(0.6), lineWidth: 1.5).padding(3)
            HStack(spacing: 2) {
                Image(systemName: summary.state.symbol)
                    .font(.system(size: size * 0.25, weight: .bold))
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && summary.state == .running)
                Text(summary.count > 99 ? "99+" : "\(summary.count)")
                    .font(.system(size: size * 0.31, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(summary.state.color)
            .padding(5)
            if summary.runningCount > 0 && summary.state != .running {
                Circle().fill(.cyan).frame(width: 4, height: 4).offset(y: -size * 0.36)
            }
        }
        .frame(width: size, height: size)
    }
}

struct AgentSessionsView: View {
    @ObservedObject private var manager = AgentStatusManager.shared
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("Agent 状态", isOn: $manager.enabled).toggleStyle(.switch).controlSize(.mini)
                Spacer()
                ForEach(AgentProvider.allCases, id: \.self) { provider in
                    Button(provider.title) { manager.chooseDirectory(for: provider) }
                        .help(manager.connections[provider] ?? "正在连接")
                }
            }
            .font(.system(size: 11))
            if !manager.enabled {
                Text("开启后在右侧小岛查看本机 Agent 会话").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("暂时没有最近 24 小时的会话事件")
                    ForEach(AgentProvider.allCases, id: \.self) { provider in
                        Text("\(provider.title)：\(manager.connections[provider] ?? "正在连接")")
                    }
                    Text("Claude Code 和 Qoder 首次使用需要安装仓库中的 hooks；详情见使用说明。")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(AgentState.allCases, id: \.self) { state in
                            let sessions = manager.sessions.filter { $0.state == state }
                            if !sessions.isEmpty {
                                Text("\(state.title) · \(sessions.count)")
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(state.color)
                                ForEach(sessions) { session in row(session) }
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    ForEach(AgentProvider.allCases, id: \.self) { provider in
                        Text("\(provider.title)：\(manager.connections[provider] ?? "正在连接")")
                    }
                }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func row(_ session: AgentSession) -> some View {
        Button {
            manager.openSession(session)
            if session.provider == .claude { copiedID = session.id }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.state.symbol)
                    .foregroundStyle(session.state.color).frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(session.provider.title) · \(session.displayTitle)")
                        .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(session.detail)
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if copiedID == session.id {
                    Text("已复制恢复命令").font(.system(size: 9)).foregroundStyle(.green)
                } else if session.provider != .qoder {
                    Image(systemName: session.provider == .codex ? "arrow.up.right" : "doc.on.doc")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("\(session.sessionID) · \(session.provider == .codex ? "打开会话" : session.provider == .claude ? "复制 Claude Code 恢复命令" : "Qoder 会话")")
    }
}
