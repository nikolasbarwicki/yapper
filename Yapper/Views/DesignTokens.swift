import SwiftUI

// MARK: - Design Tokens

/// Centralized design constants for all Yapper overlay UI.
/// All visible components (pills, cards, toasts) reference these tokens
/// so visual changes propagate from a single source of truth.
enum DesignTokens {

    // MARK: Corner Radius

    enum Radius {
        /// AI response card and similar panels
        static let card: CGFloat = 18
        /// Code blocks inside markdown content
        static let codeBlock: CGFloat = 8
        /// Copy button and small interactive elements
        static let button: CGFloat = 10
    }

    // MARK: Padding

    enum Padding {
        enum Pill {
            static let horizontal: CGFloat = 16
            static let vertical: CGFloat = 10
        }

        enum Card {
            static let horizontal: CGFloat = 16
            static let vertical: CGFloat = 10
            static let contentHorizontal: CGFloat = 16
            static let contentVertical: CGFloat = 10
        }

        enum Button {
            static let horizontal: CGFloat = 10
            static let vertical: CGFloat = 5
        }
    }

    // MARK: Spacing

    enum Spacing {
        /// HStack spacing inside pills (between dot, waveform, label)
        static let pillContent: CGFloat = 10
        /// HStack spacing inside card header
        static let cardHeader: CGFloat = 10
    }

    // MARK: Sizing

    enum Size {
        static let cardWidth: CGFloat = 480
        static let cardHeight: CGFloat = 360
        static let statusDot: CGFloat = 8
        static let maxOverlayWidth: CGFloat = 480
    }

    // MARK: Material / Background

    enum Material {
        static let glass: SwiftUI.Material = .ultraThinMaterial

        /// Tint applied on top of glass for text contrast
        static func glassTint(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45)
        }
        /// Subtle separator color for dividers on glass
        static func separator(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }
        /// Subtle highlight for interactive surfaces
        static func surfaceHighlight(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
        }
        /// Border stroke on glass surfaces
        static func border(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        }
        /// Border line width
        static let borderWidth: CGFloat = 0.5
    }

    // MARK: Typography

    enum Typography {
        static let pillLabel: Font = .system(size: 13, weight: .medium)
        static let cardHeaderLabel: Font = .system(size: 13, weight: .medium)
        static let cardHeaderIcon: Font = .system(size: 13, weight: .medium)
        static let body: Font = .system(size: 13, weight: .regular)
        static let caption: Font = .system(size: 11, weight: .regular)
        static let footnote: Font = .system(size: 10, weight: .regular)
        static let buttonLabel: Font = .system(size: 11, weight: .medium)
        static let buttonIcon: Font = .system(size: 10, weight: .medium)
        static let flagEmoji: Font = .system(size: 14)
    }

    // MARK: Text Colors

    /// Resolved text colors for overlay UI, adapting to light/dark appearance.
    enum TextColor {
        static func primary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.88)
        }
        static func secondary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.55)
        }
        static func tertiary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.35)
        }
        static func hint(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.25)
        }
    }

    // MARK: Animation

    enum Animation {
        /// Pill <-> card transition
        static let pillToCard: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.8)
        /// Dismissal shrink + fade
        static let dismiss: SwiftUI.Animation = .spring(response: 0.25, dampingFraction: 0.9)
        /// Auto-scroll during streaming
        static let autoScroll: SwiftUI.Animation = .easeOut(duration: 0.1)
        /// Status dot pulse
        static let pulse: SwiftUI.Animation = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        /// Waveform bar response
        static let waveformBar: SwiftUI.Animation = .easeOut(duration: 0.08)
        /// Checkmark pop-in
        static let checkmarkPop: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0)
        /// Processing wave
        static func processingWave(delay: Double) -> SwiftUI.Animation {
            .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)
        }
    }
}
