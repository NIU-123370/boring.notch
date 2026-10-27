import SwiftUI

final class IslandPresentation: ObservableObject {
    @Published var shown: Bool = false
}

struct PomodoroSmallIsland: View {
    @ObservedObject var presentation: IslandPresentation
    @ObservedObject var pomodoro = PomodoroManager.shared
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black)

            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: pomodoro.progress)
                .stroke(
                    pomodoro.phase == .focus ? Color.effectiveAccent : Color.green,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: pomodoro.progress)

            Text(minutesText)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Circle()
                .fill(pomodoro.isRunning ? Color.green : Color.gray)
                .frame(width: 5, height: 5)
                .offset(x: size * 0.33, y: -size * 0.33)
        }
        .frame(width: size, height: size)
        .scaleEffect(presentation.shown ? 1 : 0.1, anchor: .leading)
        .opacity(presentation.shown ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.68), value: presentation.shown)
    }

    private var minutesText: String {
        "\(Int((pomodoro.remaining / 60).rounded(.up)))"
    }
}
