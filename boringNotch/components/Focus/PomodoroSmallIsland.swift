import SwiftUI

/// A background of the existing notch, so it never participates in the main
/// island's layout and inherits its display, Space and screen-recording policy.
struct PomodoroIslandAttachment: View {
    @ObservedObject private var pomodoro = PomodoroManager.shared
    let isClosed: Bool
    let isHidden: Bool
    let notchHeight: CGFloat
    let availableWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let size = min(36, notchHeight)
            // Wide HUDs absorb the satellite instead of clipping it at the window edge.
            let fits = (availableWidth - geometry.size.width) / 2 >= size + 8
            PomodoroSmallIsland(
                isPresented: pomodoro.isActive && isClosed && !isHidden && fits && size >= 20,
                size: max(20, size)
            )
            .opacity(isClosed && !isHidden && fits ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}

struct PomodoroSmallIsland: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var pomodoro = PomodoroManager.shared
    let isPresented: Bool
    let size: CGFloat

    @State private var separation: CGFloat = 0
    @State private var showsReadout = false

    private let gap: CGFloat = 8
    private let edgeInset: CGFloat = 6

    var body: some View {
        ZStack(alignment: .topLeading) {
            PomodoroIslandSilhouette(
                separation: separation, diameter: size, gap: gap, edgeInset: edgeInset
            )
            .fill(.black)

            readout
                .frame(width: size, height: size)
                .offset(x: edgeInset - gap - size)
                .opacity(showsReadout ? 1 : 0)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .opacity(separation > 0 ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pomodoro.phase == .focus ? "Focus timer" : "Break timer")
        .accessibilityValue("\(minutes) minutes remaining, \(pomodoro.isRunning ? "running" : "paused")")
        .accessibilityHidden(!isPresented)
        .task(id: isPresented) {
            // Cancellation handles reopening the notch or restarting during a split.
            if reduceMotion {
                separation = isPresented ? 1 : 0
                showsReadout = isPresented
                return
            }

            if isPresented {
                // Let the original notch finish closing before budding out.
                do { try await Task.sleep(for: .milliseconds(380)) }
                catch { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    separation = 0.38
                }
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
                withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                    separation = 1
                }
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    showsReadout = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.1)) {
                    showsReadout = false
                }
                withAnimation(.easeInOut(duration: 0.28)) {
                    separation = 0
                }
            }
        }
    }

    private var minutes: Int {
        max(0, Int(ceil(pomodoro.remaining / 60)))
    }

    private var readout: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 2)
            Circle()
                .trim(from: 0, to: pomodoro.progress)
                .stroke(
                    pomodoro.phase == .focus ? Color.effectiveAccent : .green,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: pomodoro.progress)
            Text("\(minutes)")
                .font(.system(size: size * 0.37, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Circle()
                .fill(pomodoro.isRunning ? Color.green : .gray)
                .frame(width: 3, height: 3)
                .offset(y: -(size - 12) / 2)
        }
        .padding(6)
    }
}

/// The circle and narrowing neck form a single black silhouette. The original
/// notch is drawn above the attachment and keeps its exact shape and position.
struct PomodoroIslandSilhouette: Shape {
    var separation: CGFloat
    let diameter: CGFloat
    let gap: CGFloat
    let edgeInset: CGFloat

    var animatableData: CGFloat {
        get { separation }
        set { separation = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = max(0, min(1, separation))
        let radius = diameter / 2 * (0.35 + 0.65 * progress)
        let startX = edgeInset + diameter / 2
        let endX = edgeInset - gap - diameter / 2
        let center = CGPoint(x: startX + (endX - startX) * separation, y: diameter / 2)
        var path = Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))

        // Pinch the bridge to zero before settling into the detached circle.
        let neck = max(0, 1 - progress / 0.88) * diameter * 0.32
        let edge = edgeInset + 2
        if neck > 0 && center.x < edge {
            let joinX = center.x + radius * 0.55
            let controlX = (joinX + edge) / 2
            path.move(to: CGPoint(x: joinX, y: center.y - neck))
            path.addCurve(
                to: CGPoint(x: edge, y: center.y - neck),
                control1: CGPoint(x: controlX, y: center.y - neck * 0.2),
                control2: CGPoint(x: controlX, y: center.y - neck)
            )
            path.addLine(to: CGPoint(x: edge, y: center.y + neck))
            path.addCurve(
                to: CGPoint(x: joinX, y: center.y + neck),
                control1: CGPoint(x: controlX, y: center.y + neck),
                control2: CGPoint(x: controlX, y: center.y + neck * 0.2)
            )
            path.closeSubpath()
        }
        return path
    }
}
