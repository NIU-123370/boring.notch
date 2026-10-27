import AppKit
import Combine
import SwiftUI

@MainActor
final class PomodoroIslandController {
    static let shared = PomodoroIslandController()

    private let islandSize: CGFloat = 34
    private let gap: CGFloat = 7
    private let presentation = IslandPresentation()
    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var hideWork: DispatchWorkItem?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        PomodoroManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
            .store(in: &cancellables)

        refresh()
    }

    private func refresh() {
        if PomodoroManager.shared.isActive {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        guard let screen = targetScreen() else { return }
        hideWork?.cancel()

        let panel = window ?? makeWindow()
        window = panel
        panel.setFrame(islandFrame(on: screen), display: false)

        if !presentation.shown {
            presentation.shown = true
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        guard let panel = window, panel.isVisible else { return }
        presentation.shown = false
        hideWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.window?.orderOut(nil) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func reposition() {
        guard let panel = window, panel.isVisible, let screen = targetScreen() else { return }
        panel.setFrame(islandFrame(on: screen), display: true)
    }

    private func makeWindow() -> NSPanel {
        let rect = NSRect(x: 0, y: 0, width: islandSize, height: islandSize)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        panel.contentView = NSHostingView(
            rootView: PomodoroSmallIsland(presentation: presentation, size: islandSize)
        )
        return panel
    }

    private func islandFrame(on screen: NSScreen) -> NSRect {
        let notchWidth = closedNotchWidth(on: screen)
        let centerX = notchWindow(on: screen)?.frame.midX ?? screen.frame.midX
        return NSRect(
            x: centerX + notchWidth / 2 + gap,
            y: screen.frame.maxY - islandSize,
            width: islandSize,
            height: islandSize
        )
    }

    private func closedNotchWidth(on screen: NSScreen) -> CGFloat {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return 200 }
        return screen.frame.width - left.width - right.width + 4
    }

    private func notchWindow(on screen: NSScreen) -> NSWindow? {
        NSApp.windows.first { $0 is BoringNotchSkyLightWindow && $0.screen == screen }
            ?? NSApp.windows.first { $0 is BoringNotchSkyLightWindow }
    }

    private func targetScreen() -> NSScreen? {
        if let main = NSScreen.main,
           let window = notchWindow(on: main),
           let screen = window.screen {
            return screen
        }
        if let window = NSApp.windows.first(where: { $0 is BoringNotchSkyLightWindow }),
           let screen = window.screen {
            return screen
        }
        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }
}
