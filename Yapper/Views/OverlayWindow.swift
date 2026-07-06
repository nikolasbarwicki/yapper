import AppKit
import MarkdownUI
import SwiftUI

// MARK: - Non-Activating Window

/// A custom NSWindow subclass that never becomes key or main.
/// This prevents stealing focus from other apps when shown.
final class NonActivatingWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Overlay Window Controller

/// Manages the floating overlay window shown during recording and processing.
@MainActor
final class OverlayWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private let appState: AppState
    private nonisolated(unsafe) var contentSizeObserver: NSObjectProtocol?
    private var lastWindowSize: NSSize = .zero

    private let maxWindowWidth: CGFloat = DesignTokens.Size.maxOverlayWidth
    private let windowHeight: CGFloat = 36
    private let cardHeight: CGFloat = DesignTokens.Size.cardHeight

    /// The cursor position captured when the overlay was first shown.
    /// Used to anchor the expanded card in cursor-following mode.
    private var initialCursorPosition: NSPoint?

    init(appState: AppState) {
        self.appState = appState
        setupWindow()
        observeContentSize()
    }

    deinit {
        if let observer = contentSizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupWindow() {
        let overlayView = AnyView(
            OverlayView()
                .environment(appState)
        )

        let hostingController = NSHostingController(rootView: overlayView)
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
            .fullScreenAuxiliary,
        ]

        window.contentView?.postsFrameChangedNotifications = true
        self.window = window
    }

    private func observeContentSize() {
        guard let contentView = window?.contentView else { return }
        contentSizeObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                    self.window?.isVisible == true
                else { return }
                if self.appState.overlayPositionFixed {
                    self.positionAtTopCenter()
                } else {
                    self.positionAtCursorAnchored()
                }
            }
        }
    }

    func show() {
        lastWindowSize = .zero
        initialCursorPosition = NSEvent.mouseLocation
        if appState.overlayPositionFixed {
            // Hide window during initial layout to prevent position flicker.
            // SwiftUI may not report accurate fittingSize until after orderFront
            // triggers a full layout pass, so we position → show invisible →
            // let SwiftUI settle → reposition → reveal.
            window?.alphaValue = 0
            positionAtTopCenter()
            window?.orderFront(nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.positionAtTopCenter()
                self.window?.alphaValue = 1
            }
        } else {
            positionAtCursor()
            window?.orderFront(nil)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func positionAtCursor() {
        let mouseLocation = NSEvent.mouseLocation

        // Find which screen the cursor is on
        let screen =
            NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main

        guard let screen = screen, let window = window else { return }

        // Get actual content size (respects .fixedSize() on the SwiftUI view)
        let contentSize =
            window.contentView?.fittingSize ?? NSSize(width: maxWindowWidth, height: windowHeight)
        let windowWidth = min(contentSize.width, maxWindowWidth)
        let windowHeight = max(contentSize.height, self.windowHeight)

        // Position the pill slightly above and to the right of the cursor
        let offsetX: CGFloat = 15
        let offsetY: CGFloat = 10

        var x = mouseLocation.x + offsetX
        var y = mouseLocation.y + offsetY

        // Ensure the window stays within screen bounds
        let screenFrame = screen.visibleFrame

        // Adjust if window would go off right edge
        if x + windowWidth > screenFrame.maxX {
            x = mouseLocation.x - windowWidth - offsetX
        }

        // Adjust if window would go off top edge
        if y + windowHeight > screenFrame.maxY {
            y = mouseLocation.y - windowHeight - offsetY
        }

        // Adjust if window would go off left edge
        if x < screenFrame.minX {
            x = screenFrame.minX
        }

        // Adjust if window would go off bottom edge
        if y < screenFrame.minY {
            y = screenFrame.minY
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Reposition the window using the stored initial cursor position.
    /// Called when content size changes (e.g. pill → card transition) in cursor-following mode.
    private func positionAtCursorAnchored() {
        guard let anchor = initialCursorPosition else {
            positionAtCursor()
            return
        }

        let screen =
            NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) }
            ?? NSScreen.main

        guard let screen = screen, let window = window else { return }

        let contentSize =
            window.contentView?.fittingSize ?? NSSize(width: maxWindowWidth, height: windowHeight)
        let windowWidth = min(contentSize.width, maxWindowWidth)
        let windowHeight = max(contentSize.height, self.windowHeight)

        let offsetX: CGFloat = 15
        let offsetY: CGFloat = 10

        var x = anchor.x + offsetX
        var y = anchor.y + offsetY

        let screenFrame = screen.visibleFrame

        if x + windowWidth > screenFrame.maxX {
            x = anchor.x - windowWidth - offsetX
        }
        if y + windowHeight > screenFrame.maxY {
            y = anchor.y - windowHeight - offsetY
        }
        if x < screenFrame.minX { x = screenFrame.minX }
        if y < screenFrame.minY { y = screenFrame.minY }

        let newSize = NSSize(width: windowWidth, height: windowHeight)
        if abs(newSize.width - lastWindowSize.width) > 0.5
            || abs(newSize.height - lastWindowSize.height) > 0.5
        {
            lastWindowSize = newSize
            window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        } else {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func positionAtTopCenter() {
        let mouseLocation = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main

        guard let screen = screen, let window = window else { return }

        window.layoutIfNeeded()
        let contentSize =
            window.contentView?.fittingSize ?? NSSize(width: maxWindowWidth, height: windowHeight)
        // Round to whole points to prevent sub-pixel oscillation across display scales
        let pillWidth = ceil(max(min(contentSize.width, maxWindowWidth), 1))
        let pillHeight = ceil(max(contentSize.height, self.windowHeight))

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        let x = screenFrame.midX - pillWidth / 2
        let y = visibleFrame.maxY - pillHeight - 20

        let newSize = NSSize(width: pillWidth, height: pillHeight)

        // Only call setFrame when size actually changed to break the
        // notification → reposition → setFrame → notification feedback loop.
        // When only position needs updating, setFrameOrigin avoids changing
        // the content view's frame and won't re-trigger frameDidChange.
        if abs(newSize.width - lastWindowSize.width) > 0.5
            || abs(newSize.height - lastWindowSize.height) > 0.5
        {
            lastWindowSize = newSize
            window.setFrame(NSRect(x: x, y: y, width: pillWidth, height: pillHeight), display: true)
        } else {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// MARK: - Overlay State

/// Visual state for the overlay, derived from AppState
enum OverlayDisplayState: Equatable {
    case recording
    case aiRecording      // AI Transform mode — recording voice instruction
    case processing
    case aiTransforming   // AI transform — LLM rewriting selected text
    case aiTransformResult(hasError: Bool)  // Transform result displayed for copy/dismiss
    case aiQA             // AI Q&A — LLM answering a question
    case aiQAResult(hasError: Bool)  // Q&A answer displayed for copy/dismiss
    case completed
    case error(message: String)

    var dotColor: Color {
        switch self {
        case .recording: return .red
        case .aiRecording: return .purple
        case .processing: return .blue
        case .aiTransforming: return .purple
        case .aiTransformResult(let hasError): return hasError ? .orange : .green
        case .aiQA: return .purple
        case .aiQAResult(let hasError): return hasError ? .orange : .green
        case .completed: return .green
        case .error: return .red
        }
    }

    var label: String {
        switch self {
        case .recording: return "Listening"
        case .aiRecording: return "AI Listening"
        case .processing: return "Transcribing"
        case .aiTransforming: return "Transforming"
        case .aiTransformResult(let hasError): return hasError ? "Partial Result" : "Transform Complete"
        case .aiQA: return "Thinking"
        case .aiQAResult(let hasError): return hasError ? "Partial Answer" : "Answer Ready"
        case .completed: return "Success"
        case .error(let message): return message.isEmpty ? "Error" : message
        }
    }

    var isAIResponseCard: Bool {
        switch self {
        case .aiTransformResult, .aiQAResult: return true
        default: return false
        }
    }
}

// MARK: - Overlay SwiftUI View

struct OverlayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private let barCount = 4
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 14
    private let minBarHeight: CGFloat = 4

    @State private var pulseAnimation = false
    @State private var elapsedSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var dismissalScale: CGFloat = 1.0
    @State private var dismissalOpacity: Double = 1.0

    /// Tracks the last seen overlay visibility to detect show/hide transitions
    @State private var wasOverlayVisible: Bool = false

    private var displayState: OverlayDisplayState {
        if appState.showCompletedIndicator {
            return .completed
        }
        switch appState.recordingState {
        case .recording:
            if appState.interactionMode?.isAITransform == true {
                return .aiRecording
            }
            return .recording
        case .processing:
            return .processing
        case .aiTransforming:
            return .aiTransforming
        case .aiTransformResult:
            return .aiTransformResult(hasError: appState.aiResponseError != nil)
        case .aiQA:
            return .aiQA
        case .aiQAResult:
            return .aiQAResult(hasError: appState.aiResponseError != nil)
        case .error(let message):
            return .error(message: message)
        case .idle:
            return .recording
        }
    }

    /// Whether to show the expanded card instead of the pill
    private var shouldShowExpandedCard: Bool {
        if displayState.isAIResponseCard { return true }
        // Also show expanded card during streaming once tokens start arriving
        if case .aiTransforming = displayState, !appState.aiResponseText.isEmpty { return true }
        if case .aiQA = displayState, !appState.aiResponseText.isEmpty { return true }
        return false
    }

    private var formattedDuration: String {
        DurationFormatter.format(TimeInterval(elapsedSeconds))
    }

    var body: some View {
        Group {
            if shouldShowExpandedCard {
                aiResponseCard
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                pillView
                    .transition(.opacity)
            }
        }
        .animation(DesignTokens.Animation.pillToCard, value: shouldShowExpandedCard)
        .onChange(of: appState.recordingState.isRecording) { _, isRecording in
            if isRecording {
                startTimer()
            } else {
                stopTimer()
            }
        }
        .onChange(of: appState.showCompletedIndicator) { oldValue, newValue in
            if newValue {
                dismissalScale = 1.0
                dismissalOpacity = 1.0
                startDismissalAnimation()
            } else if oldValue && !newValue {
                dismissalScale = 1.0
                dismissalOpacity = 1.0
            }
        }
        .onChange(of: appState.showOverlay) { _, isVisible in
            if isVisible && !wasOverlayVisible {
                resetAnimationStates()
            }
            wasOverlayVisible = isVisible
        }
        .onAppear {
            wasOverlayVisible = appState.showOverlay
            if appState.showOverlay {
                resetAnimationStates()
            }
            if appState.recordingState.isRecording {
                startTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: - Pill View (existing capsule overlay)

    private var pillView: some View {
        HStack(spacing: DesignTokens.Spacing.pillContent) {
            statusDot
            visualIndicator

            if displayState == .recording || displayState == .aiRecording {
                HStack(spacing: 4) {
                    Text("\(displayState.label) \(formattedDuration)")
                        .font(DesignTokens.Typography.pillLabel)
                        .foregroundStyle(DesignTokens.TextColor.primary(for: colorScheme))
                        .lineLimit(1)
                        .monospacedDigit()

                    if displayState == .recording && appState.isUsingSecondaryLanguage {
                        Text(AppState.languageFlag(for: appState.activeLanguage))
                            .font(DesignTokens.Typography.flagEmoji)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(displayState.label)
                    .font(DesignTokens.Typography.pillLabel)
                    .foregroundStyle(DesignTokens.TextColor.primary(for: colorScheme))
                    .lineLimit(1)
            }
        }
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
        .scaleEffect(dismissalScale)
        .opacity(dismissalOpacity)
    }

    // MARK: - AI Response Card (shared by Transform and Q&A)

    @State private var showCopiedConfirmation = false
    @State private var scrollProxy: ScrollViewProxy?

    /// Whether this card is showing a Q&A response (vs AI Transform)
    private var isQAMode: Bool {
        appState.interactionMode?.isAIQA == true
    }

    private var aiResponseCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.cardHeader) {
                Circle()
                    .fill(displayState.dotColor)
                    .frame(width: DesignTokens.Size.statusDot, height: DesignTokens.Size.statusDot)

                if appState.isAIResponseStreaming {
                    Image(systemName: isQAMode ? "bubble.left.and.text.bubble.right" : "sparkles")
                        .font(DesignTokens.Typography.cardHeaderIcon)
                        .foregroundStyle(.purple)
                        .symbolEffect(.pulse, options: .repeating)
                } else {
                    Image(systemName: isQAMode ? "bubble.left.and.text.bubble.right" : "sparkles")
                        .font(DesignTokens.Typography.cardHeaderIcon)
                        .foregroundStyle(.green)
                }

                Text(aiResponseHeaderLabel)
                    .font(DesignTokens.Typography.cardHeaderLabel)
                    .foregroundStyle(DesignTokens.TextColor.primary(for: colorScheme))
                    .lineLimit(1)

                Spacer()

                if !appState.isAIResponseStreaming && !appState.aiResponseText.isEmpty {
                    Button(action: copyAIResponse) {
                        HStack(spacing: 4) {
                            Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
                                .font(DesignTokens.Typography.buttonIcon)
                            Text(showCopiedConfirmation ? "Copied" : "Copy")
                                .font(DesignTokens.Typography.buttonLabel)
                        }
                        .foregroundStyle(showCopiedConfirmation ? .green : DesignTokens.TextColor.secondary(for: colorScheme))
                        .padding(.horizontal, DesignTokens.Padding.Button.horizontal)
                        .padding(.vertical, DesignTokens.Padding.Button.vertical)
                        .background(
                            Capsule()
                                .fill(DesignTokens.Material.surfaceHighlight(for: colorScheme))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Padding.Card.horizontal)
            .padding(.vertical, DesignTokens.Padding.Card.vertical)

            Rectangle()
                .fill(DesignTokens.Material.separator(for: colorScheme))
                .frame(height: DesignTokens.Material.borderWidth)

            // Question display (Q&A mode only)
            if case .aiQA(let question) = appState.interactionMode {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(DesignTokens.Typography.buttonLabel)
                        .foregroundStyle(DesignTokens.TextColor.tertiary(for: colorScheme))
                    Text(question)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.TextColor.secondary(for: colorScheme))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, DesignTokens.Padding.Card.horizontal)
                .padding(.vertical, 8)
                .background(DesignTokens.Material.surfaceHighlight(for: colorScheme))

                Rectangle()
                    .fill(DesignTokens.Material.separator(for: colorScheme))
                    .frame(height: DesignTokens.Material.borderWidth)
            }

            // Error banner (if present)
            if let errorMessage = appState.aiResponseError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DesignTokens.Typography.buttonIcon)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(DesignTokens.Typography.buttonLabel)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Padding.Card.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            // Streamed text content
            aiResponseContent

            Rectangle()
                .fill(DesignTokens.Material.separator(for: colorScheme))
                .frame(height: DesignTokens.Material.borderWidth)

            // Footer hint
            HStack {
                Spacer()
                Text(appState.isAIResponseStreaming ? "Press Esc to cancel" : "Press Esc to dismiss")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.TextColor.hint(for: colorScheme))
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(width: DesignTokens.Size.cardWidth, height: DesignTokens.Size.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(DesignTokens.Material.glassTint(for: colorScheme))
        )
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(
                    DesignTokens.Material.border(for: colorScheme),
                    lineWidth: DesignTokens.Material.borderWidth
                )
        )
        .fixedSize()
    }

    /// Scrollable, Markdown-rendered AI response content with auto-scroll during streaming.
    private var aiResponseContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if appState.aiResponseText.isEmpty && appState.isAIResponseStreaming {
                        Text("Waiting for response...")
                            .font(.system(size: 13))
                            .foregroundStyle(DesignTokens.TextColor.hint(for: colorScheme))
                            .italic()
                    } else {
                        Markdown(appState.aiResponseText)
                            .markdownTheme(.yapperOverlay(for: colorScheme))
                            .id(colorScheme)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Invisible anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, DesignTokens.Padding.Card.contentHorizontal)
                .padding(.vertical, DesignTokens.Padding.Card.contentVertical)
            }
            .onChange(of: appState.aiResponseText) { _, _ in
                if appState.isAIResponseStreaming {
                    withAnimation(DesignTokens.Animation.autoScroll) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Header label for the AI response card — differentiates Transform vs Q&A
    private var aiResponseHeaderLabel: String {
        if appState.isAIResponseStreaming {
            return isQAMode ? "Thinking..." : "Transforming..."
        }
        return displayState.label
    }

    private func copyAIResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.aiResponseText, forType: .string)
        showCopiedConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                showCopiedConfirmation = false
            }
        }
    }

    private func resetAnimationStates() {
        // Reset all animation states to their initial values without animation
        // to prevent flickering of old states when overlay reappears
        dismissalScale = 1.0
        dismissalOpacity = 1.0
        checkmarkScale = 0.0
        pulseAnimation = false
        // Re-enable pulse if needed for recording state
        if displayState == .recording || displayState == .aiRecording {
            pulseAnimation = true
        }
    }

    private func startDismissalAnimation() {
        // Wait most of the display time, then animate out
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            await MainActor.run {
                // Only animate if still in completed state
                guard appState.showCompletedIndicator else { return }
                withAnimation(DesignTokens.Animation.dismiss) {
                    dismissalScale = 0.8
                    dismissalOpacity = 0
                }
            }
        }
    }

    private func startTimer() {
        elapsedSeconds = 0
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    elapsedSeconds += 1
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private var statusDot: some View {
        Circle()
            .fill(displayState.dotColor)
            .frame(width: DesignTokens.Size.statusDot, height: DesignTokens.Size.statusDot)
            .opacity(pulseAnimation ? 0.5 : 1.0)
            .animation(
                displayState == .recording || displayState == .aiRecording
                    ? DesignTokens.Animation.pulse
                    : .default,
                value: pulseAnimation
            )
            .onAppear { pulseAnimation = true }
            .onChange(of: displayState) { _, newState in
                pulseAnimation = newState == .recording || newState == .aiRecording
            }
    }

    @ViewBuilder
    private var visualIndicator: some View {
        switch displayState {
        case .recording:
            waveformBars
        case .aiRecording:
            aiRecordingIndicator
        case .processing:
            spinnerView
        case .aiTransforming, .aiQA:
            enhancingView  // Reuse pulsing sparkle
        case .aiTransformResult, .aiQAResult:
            // Card handles its own header — this is only for pill fallback
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
        case .completed:
            completedCheckmark
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
        }
    }

    private var completedCheckmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.green)
            .scaleEffect(checkmarkScale)
            .onAppear {
                // Reset and animate with spring pop effect
                checkmarkScale = 0.0
                withAnimation(DesignTokens.Animation.checkmarkPop) {
                    checkmarkScale = 1.0
                }
            }
            .onDisappear {
                checkmarkScale = 0.0
            }
    }

    private var spinnerView: some View {
        SpinnerView()
            .frame(width: 14, height: 14)
    }

    private var enhancingView: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.purple)
            .symbolEffect(.pulse, options: .repeating)
    }

    private var aiRecordingIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.purple)
            waveformBars
        }
    }

    private var waveformBars: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    index: index,
                    audioLevel: appState.audioLevel,
                    isRecording: appState.recordingState.isRecording,
                    isProcessing: appState.recordingState == .processing,
                    minHeight: minBarHeight,
                    maxHeight: maxBarHeight,
                    width: barWidth
                )
            }
        }
        .frame(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing)
    }
}

// MARK: - Waveform Bar

struct WaveformBar: View {
    let index: Int
    let audioLevel: Float
    let isRecording: Bool
    let isProcessing: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let width: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var animatedHeight: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2)
            .fill(DesignTokens.TextColor.primary(for: colorScheme))
            .frame(width: width, height: animatedHeight)
            .frame(height: maxHeight, alignment: .center)
            .animation(DesignTokens.Animation.waveformBar, value: animatedHeight)
            .onAppear {
                updateHeight()
            }
            .onChange(of: audioLevel) { _, _ in
                updateHeight()
            }
            .onChange(of: isRecording) { _, newValue in
                if !newValue && !isProcessing {
                    withAnimation(.easeOut(duration: 0.2)) {
                        animatedHeight = minHeight
                    }
                }
            }
            .onChange(of: isProcessing) { _, newValue in
                if newValue {
                    startProcessingAnimation()
                }
            }
    }

    private func updateHeight() {
        guard isRecording else { return }

        // Amplify the audio level for more sensitivity (boost low levels significantly)
        let amplifiedLevel = pow(Double(audioLevel), 0.4) * 1.5
        let clampedLevel = min(amplifiedLevel, 1.0)

        // Create variation between bars based on index
        let variation = sin(Double(index) * 0.8 + clampedLevel * 10) * 0.3 + 0.7
        let levelWithVariation = CGFloat(clampedLevel) * variation

        // Map to height range
        let targetHeight = minHeight + (maxHeight - minHeight) * levelWithVariation
        animatedHeight = max(minHeight, min(maxHeight, targetHeight))
    }

    private func startProcessingAnimation() {
        // Subtle wave animation during processing
        let delay = Double(index) * 0.1
        withAnimation(DesignTokens.Animation.processingWave(delay: delay)) {
            animatedHeight = minHeight + (maxHeight - minHeight) * 0.4
        }
    }
}

// MARK: - Spinner View

/// Custom spinner that renders reliably on overlay backgrounds
struct SpinnerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(DesignTokens.TextColor.primary(for: colorScheme), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Preview

#Preview("Recording") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .recording
                state.audioLevel = 0.6
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Processing") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .processing
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Success") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .idle
                state.showCompletedIndicator = true
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("AI Recording") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .recording
                state.interactionMode = .aiTransform(selectedText: "Hello world")
                state.audioLevel = 0.5
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("AI Transforming") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .aiTransforming
                state.interactionMode = .aiTransform(selectedText: "Hello world")
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Error") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .error(message: "Mic unavailable")
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("AI Transform Result") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .aiTransformResult
                state.aiResponseText = "Here is the transformed text that was generated by the AI model. It demonstrates how the streaming result card looks when the transform is complete."
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("AI Transform Streaming") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .aiTransforming
                state.isAIResponseStreaming = true
                state.aiResponseText = "Tokens streaming in..."
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("AI Q&A Result") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .aiQAResult
                state.interactionMode = .aiQA(question: "How do I center a div with flexbox?")
                state.aiResponseText = "Use `display: flex` on the parent container, then add `justify-content: center` for horizontal centering and `align-items: center` for vertical centering."
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("AI Q&A Streaming") {
    OverlayView()
        .environment(
            {
                let state = AppState()
                state.recordingState = .aiQA
                state.interactionMode = .aiQA(question: "What is the capital of France?")
                state.isAIResponseStreaming = true
                state.aiResponseText = "The capital of France is..."
                return state
            }()
        )
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
