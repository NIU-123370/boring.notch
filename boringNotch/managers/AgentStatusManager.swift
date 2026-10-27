import AppKit
import Combine
import Foundation

@MainActor
final class AgentStatusManager: ObservableObject {
    static let shared = AgentStatusManager()
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var connections: [AgentProvider: String] = [:]
    @Published private(set) var summary = AgentSummary(sessions: [], now: Date())
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "agentIslandEnabled")
            if !enabled { sessions = []; summary = AgentSummary(sessions: [], now: Date()) }
            else { refresh() }
        }
    }

    private let queue = DispatchQueue(label: "boringnotch.agent-status", qos: .utility)
    private let reader = AgentStatusReader()
    private var timer: AnyCancellable?
    private var reading = false
    private var roots: [AgentProvider: URL] = [:]
    private var scopedURLs: [URL] = []

    private init() {
        enabled = UserDefaults.standard.object(forKey: "agentIslandEnabled") as? Bool ?? true
        let home = FileManager.default.homeDirectoryForCurrentUser
        for provider in AgentProvider.allCases {
            let key = "agentRootBookmark.\(provider.rawValue)"
            var stale = false
            if let data = UserDefaults.standard.data(forKey: key),
               let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
                roots[provider] = url
            } else {
                roots[provider] = home.appendingPathComponent(provider == .codex ? ".codex" : ".claude")
            }
        }
        timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        guard enabled, !reading, let codex = roots[.codex], let claude = roots[.claude] else { return }
        reading = true
        let reader = self.reader
        queue.async { [weak self] in
            let (sessions, connections) = reader.scan(codex: codex, claude: claude)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reading = false
                guard self.enabled, self.roots[.codex] == codex, self.roots[.claude] == claude else { return }
                if self.sessions != sessions { self.sessions = sessions }
                if self.connections != connections { self.connections = connections }
                let summary = AgentSummary(sessions: sessions, now: Date())
                if self.summary != summary { self.summary = summary }
            }
        }
    }

    func chooseDirectory(for provider: AgentProvider) {
        let panel = NSOpenPanel()
        panel.title = "连接 \(provider.title)"
        panel.message = "选择 \(provider == .codex ? ".codex" : ".claude") 文件夹。仅在本机读取会话状态。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = roots[provider]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                if let data = try? url.bookmarkData(options: .withSecurityScope,
                    includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(data, forKey: "agentRootBookmark.\(provider.rawValue)")
                }
                if let old = self.roots[provider], let index = self.scopedURLs.firstIndex(of: old) {
                    self.scopedURLs.remove(at: index).stopAccessingSecurityScopedResource()
                }
                if accessed { self.scopedURLs.append(url) }
                self.roots[provider] = url
                self.refresh()
            }
        }
    }

    func openSession(_ session: AgentSession) {
        if session.provider == .codex, UUID(uuidString: session.sessionID) != nil,
           let url = URL(string: "codex://threads/\(session.sessionID)") {
            NSWorkspace.shared.open(url)
        } else if session.provider == .claude {
            // Claude's terminal session has no universal app deep link. Copy a
            // safely quoted resume command rather than launching an unrelated shell.
            let escaped = session.sessionID.replacingOccurrences(of: "'", with: "'\\''")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("claude --resume '\(escaped)'", forType: .string)
        }
    }
}
