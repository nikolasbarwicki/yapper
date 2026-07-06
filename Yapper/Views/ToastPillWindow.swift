import SwiftUI
import AppKit

// MARK: - Pill Content

/// The type of content to display in the transient pill window.
/// Using a single window for all transient notifications ensures only one pill
/// is visible at a time — showing new content automatically replaces the old.
enum PillContent {
    case iconText(icon: String, text: String)
    case languageSwitch
}

// MARK: - Toast Pill Window Controller

/// Manages a single floating pill window for all brief toast-style confirmations.
/// Used for mode toggle feedback (auto-type on/off) and language switch notifications.
/// Only one pill is visible at a time — showing new content replaces any current pill.
@MainActor
final class ToastPillWindowController {

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var dismissTask: Task<Void, Never>?
    private let appState: AppState

    private let maxWindowWidth: CGFloat = 300
    private let windowHeight: CGFloat = 36

    init(appState: AppState) {
        self.appState = appState
        setupWindow()
    }

    private func setupWindow() {
        let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
        self.hostingController = hostingController

        let window = NonActivatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: maxWindowWidth, height: windowHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating

        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        self.window = window
    }

    // MARK: - Show / Hide

    /// Show the pill with the given content, auto-dismiss after 1.5 seconds.
    /// Any currently visible pill is replaced immediately.
    func show(_ content: PillContent) {
        dismissTask?.cancel()

        switch content {
        case .iconText(let icon, let text):
            hostingController?.rootView = AnyView(
                ToastPillView(icon: icon, text: text)
            )
        case .languageSwitch:
            hostingController?.rootView = AnyView(
                LanguageSwitchPillView()
                    .environment(appState)
            )
        }

        positionWindow()
        window?.orderFront(nil)

        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    /// Show the toast pill with an SF Symbol icon and text.
    func show(icon: String, text: String) {
        show(.iconText(icon: icon, text: text))
    }

    /// Show the language switch pill. Sets the display text on appState first.
    func show(languageSwitch text: String) {
        appState.languageSwitchDisplayText = text
        show(.languageSwitch)
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        window?.orderOut(nil)
    }

    // MARK: - Positioning

    private func positionWindow() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main

        guard let screen = screen, let window = window else { return }

        // Force layout to get correct content size
        window.layoutIfNeeded()
        let contentSize = window.contentView?.fittingSize ?? NSSize(width: maxWindowWidth, height: windowHeight)
        let pillWidth = min(contentSize.width, maxWindowWidth)
        let pillHeight = max(contentSize.height, self.windowHeight)

        if appState.overlayPositionFixed {
            // Fixed: top center of screen
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let x = screenFrame.midX - pillWidth / 2
            let y = visibleFrame.maxY - pillHeight - 20
            window.setFrame(NSRect(x: x, y: y, width: pillWidth, height: pillHeight), display: true)
        } else {
            // Cursor-following
            let offsetX: CGFloat = 15
            let offsetY: CGFloat = 10
            var x = mouseLocation.x + offsetX
            var y = mouseLocation.y + offsetY
            let screenFrame = screen.visibleFrame

            if x + pillWidth > screenFrame.maxX {
                x = mouseLocation.x - pillWidth - offsetX
            }
            if y + pillHeight > screenFrame.maxY {
                y = mouseLocation.y - pillHeight - offsetY
            }
            if x < screenFrame.minX { x = screenFrame.minX }
            if y < screenFrame.minY { y = screenFrame.minY }

            window.setFrame(NSRect(x: x, y: y, width: pillWidth, height: pillHeight), display: true)
        }
    }
}

// MARK: - Shared Pill Styling

/// Fixed content height so all pill variants render at the same size with no jump on switch.
private let pillContentHeight: CGFloat = 20

// MARK: - Toast Pill View

struct ToastPillView: View {
    let icon: String
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.pillContent) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.pillLabel)
                .foregroundStyle(DesignTokens.TextColor.secondary(for: colorScheme))

            Text(text)
                .font(DesignTokens.Typography.pillLabel)
                .foregroundStyle(DesignTokens.TextColor.primary(for: colorScheme))
                .lineLimit(1)
        }
        .frame(height: pillContentHeight)
        .padding(.horizontal, DesignTokens.Padding.Pill.horizontal)
        .padding(.vertical, DesignTokens.Padding.Pill.vertical)
        .background(
            Capsule()
                .fill(DesignTokens.Material.glassTint(for: colorScheme))
        )
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    DesignTokens.Material.border(for: colorScheme),
                    lineWidth: DesignTokens.Material.borderWidth
                )
        )
        .fixedSize()
    }
}

// MARK: - Language Switch Pill View

struct LanguageSwitchPillView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.pillContent) {
            Text(AppState.languageFlag(for: appState.activeLanguage))
                .font(DesignTokens.Typography.flagEmoji)

            Text(appState.languageSwitchDisplayText)
                .font(DesignTokens.Typography.pillLabel)
                .foregroundStyle(DesignTokens.TextColor.primary(for: colorScheme))
                .lineLimit(1)
        }
        .frame(height: pillContentHeight)
        .padding(.horizontal, DesignTokens.Padding.Pill.horizontal)
        .padding(.vertical, DesignTokens.Padding.Pill.vertical)
        .background(
            Capsule()
                .fill(DesignTokens.Material.glassTint(for: colorScheme))
        )
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    DesignTokens.Material.border(for: colorScheme),
                    lineWidth: DesignTokens.Material.borderWidth
                )
        )
        .fixedSize()
    }
}
