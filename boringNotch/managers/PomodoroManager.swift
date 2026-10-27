import AppKit
import Combine
import Defaults
import Foundation

struct PomodoroStats: Codable, Equatable, Defaults.Serializable {
    var focusSeconds: [String: Int] = [:]
    var completedSessions: [String: Int] = [:]
}

final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    enum Phase: String {
        case focus
        case breakTime
    }

    struct DayTotal: Identifiable {
        let id: String
        let date: Date
        let seconds: Int
    }

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var stats: PomodoroStats = Defaults[.pomodoroStats]

    @Default(.pomodoroFocusMinutes) var focusMinutes: Int
    @Default(.pomodoroBreakMinutes) var breakMinutes: Int

    private var sessionEnd: Date?
    private var lastTick: Date?
    private var pendingFocus: TimeInterval = 0
    private var ticker: AnyCancellable?

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private init() {
        remaining = sessionDuration
    }

    // MARK: - Public state

    var sessionDuration: TimeInterval {
        TimeInterval((phase == .focus ? focusMinutes : breakMinutes) * 60)
    }

    var isActive: Bool {
        isRunning || remaining < sessionDuration
    }

    var progress: Double {
        guard sessionDuration > 0 else { return 0 }
        return min(max(1 - remaining / sessionDuration, 0), 1)
    }

    var todayFocusSeconds: Int {
        stats.focusSeconds[todayKey, default: 0] + Int(pendingFocus)
    }

    var todaySessions: Int {
        stats.completedSessions[todayKey, default: 0]
    }

    var lastSevenDays: [DayTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Self.dayFormatter.string(from: day)
            var seconds = stats.focusSeconds[key, default: 0]
            if offset == 0 {
                seconds += Int(pendingFocus)
            }
            return DayTotal(id: key, date: day, seconds: seconds)
        }
    }

    // MARK: - Controls

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        if remaining <= 0 {
            remaining = sessionDuration
        }
        sessionEnd = Date().addingTimeInterval(remaining)
        lastTick = Date()
        isRunning = true
        startTicker()
    }

    func pause() {
        guard isRunning else { return }
        syncRemaining()
        flushPendingFocus()
        isRunning = false
        sessionEnd = nil
        lastTick = nil
        stopTicker()
    }

    func reset() {
        pause()
        remaining = sessionDuration
    }

    func skip() {
        let shouldResume = isRunning
        pause()
        phase = phase == .focus ? .breakTime : .focus
        remaining = sessionDuration
        if shouldResume {
            start()
        }
    }

    func cycleFocusDuration() {
        let options = [15, 25, 50]
        focusMinutes = options.first(where: { $0 > focusMinutes }) ?? options[0]
        if !isRunning && phase == .focus {
            remaining = sessionDuration
        }
    }

    // MARK: - Ticking

    private func startTicker() {
        stopTicker()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard isRunning else { return }
        let now = Date()

        if phase == .focus, let last = lastTick {
            let delta = now.timeIntervalSince(last)
            // Ignore long gaps (sleep/wake) so suspended time is not credited as focus.
            if delta > 0, delta < 5 {
                addFocus(seconds: delta)
            }
        }
        lastTick = now

        guard let end = sessionEnd else { return }
        let left = end.timeIntervalSince(now)
        if left <= 0 {
            remaining = 0
            completePhase()
        } else {
            remaining = left
        }
    }

    private func syncRemaining() {
        guard let end = sessionEnd else { return }
        remaining = max(0, end.timeIntervalSince(Date()))
    }

    private func completePhase() {
        stopTicker()
        isRunning = false
        sessionEnd = nil
        lastTick = nil
        flushPendingFocus()
        if phase == .focus {
            recordCompletedSession()
        }
        phase = phase == .focus ? .breakTime : .focus
        remaining = sessionDuration
        NSSound.beep()
    }

    // MARK: - Stats

    private var todayKey: String {
        Self.dayFormatter.string(from: Date())
    }

    private func addFocus(seconds: Double) {
        pendingFocus += seconds
        if pendingFocus >= 10 {
            flushPendingFocus()
        }
    }

    private func flushPendingFocus() {
        let whole = Int(pendingFocus)
        guard whole > 0 else { return }
        pendingFocus -= Double(whole)
        var updated = stats
        updated.focusSeconds[todayKey, default: 0] += whole
        stats = updated
        Defaults[.pomodoroStats] = updated
    }

    private func recordCompletedSession() {
        var updated = stats
        updated.completedSessions[todayKey, default: 0] += 1
        stats = updated
        Defaults[.pomodoroStats] = updated
    }
}
