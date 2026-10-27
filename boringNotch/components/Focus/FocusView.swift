import SwiftUI

struct FocusView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            timerSection
            Spacer(minLength: 0)
            Divider()
                .overlay(Color.white.opacity(0.1))
                .frame(height: 100)
            Spacer(minLength: 0)
            statsSection
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timerSection: some View {
        HStack(spacing: 16) {
            ring

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pomodoro.phase == .focus ? "Focus" : "Break")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Button(action: { pomodoro.cycleFocusDuration() }) {
                        Text(pomodoro.phase == .focus
                            ? "\(pomodoro.focusMinutes) min session"
                            : "\(pomodoro.breakMinutes) min break")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Change session length")
                }

                HStack(spacing: 2) {
                    HoverButton(icon: pomodoro.isRunning ? "pause.fill" : "play.fill", scale: .large) {
                        pomodoro.toggle()
                    }
                    HoverButton(icon: "arrow.counterclockwise", scale: .medium) {
                        pomodoro.reset()
                    }
                    HoverButton(icon: "forward.end.fill", scale: .medium) {
                        pomodoro.skip()
                    }
                }
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 6)

            Circle()
                .trim(from: 0, to: pomodoro.progress)
                .stroke(
                    pomodoro.phase == .focus ? Color.effectiveAccent : Color.green,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: pomodoro.progress)

            VStack(spacing: 1) {
                Text(timeText)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(pomodoro.isRunning ? "running" : "paused")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: 96, height: 96)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focused today")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.gray)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(todayText)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(sessionText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.gray)
            }

            weekChart
        }
    }

    private var weekChart: some View {
        let days = pomodoro.lastSevenDays
        let peak = max(days.map(\.seconds).max() ?? 0, 1)

        return HStack(alignment: .bottom, spacing: 7) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.seconds > 0
                            ? Color.effectiveAccent.opacity(0.9)
                            : Color.white.opacity(0.12))
                        .frame(width: 13, height: barHeight(seconds: day.seconds, peak: peak))
                        .help("\(day.seconds / 60) min")
                    Text(Self.weekdayFormatter.string(from: day.date))
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.gray)
                }
            }
        }
        .frame(height: 50, alignment: .bottom)
    }

    private func barHeight(seconds: Int, peak: Int) -> CGFloat {
        guard seconds > 0 else { return 3 }
        return max(3, CGFloat(seconds) / CGFloat(peak) * 34)
    }

    private var timeText: String {
        let seconds = Int(pomodoro.remaining.rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var todayText: String {
        let seconds = pomodoro.todayFocusSeconds
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var sessionText: String {
        let count = pomodoro.todaySessions
        return count == 1 ? "1 session" : "\(count) sessions"
    }
}

#Preview {
    FocusView()
        .frame(width: 640, height: 170)
        .background(.black)
}
