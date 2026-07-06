@preconcurrency import MarkdownUI
import SwiftUI

@MainActor
extension Theme {
    /// Adaptive theme for the Yapper floating overlay card.
    /// Returns dark-on-glass or light-on-glass colors based on the current color scheme.
    static func yapperOverlay(for scheme: ColorScheme) -> Theme {
        let isDark = scheme == .dark

        // Palette
        let textColor: Color = isDark ? .white.opacity(0.9) : .black.opacity(0.85)
        let headingColor: Color = isDark ? .white : .black
        let headingSubtleColor95: Color = isDark ? .white.opacity(0.95) : .black.opacity(0.88)
        let headingSubtleColor90: Color = isDark ? .white.opacity(0.9) : .black.opacity(0.82)
        let headingSubtleColor80: Color = isDark ? .white.opacity(0.8) : .black.opacity(0.72)
        let codeColor: Color = isDark
            ? Color(red: 0.78, green: 0.68, blue: 0.95)
            : Color(red: 0.55, green: 0.35, blue: 0.78)
        let codeBgColor: Color = isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
        let codeBlockTextColor: Color = isDark
            ? Color(red: 0.82, green: 0.87, blue: 0.82)
            : Color(red: 0.18, green: 0.35, blue: 0.18)
        let codeBlockBgColor: Color = isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
        let linkColor: Color = isDark
            ? Color(red: 0.4, green: 0.7, blue: 1.0)
            : Color(red: 0.1, green: 0.4, blue: 0.8)
        let blockquoteBorderColor: Color = isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.15)
        let blockquoteTextColor: Color = isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
        let dividerColor: Color = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        let tableBorderColor: Color = isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)

        return Theme()
            // MARK: - Text styles
            .text {
                ForegroundColor(textColor)
                FontSize(13)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                ForegroundColor(codeColor)
                BackgroundColor(codeBgColor)
            }
            .strong {
                FontWeight(.semibold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .link {
                ForegroundColor(linkColor)
            }
            .strikethrough {
                StrikethroughStyle(.single)
            }
            // MARK: - Block styles
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(18)
                        ForegroundColor(headingColor)
                    }
                    .relativeLineSpacing(.em(0.15))
                    .markdownMargin(top: 12, bottom: 6)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(16)
                        ForegroundColor(headingColor)
                    }
                    .relativeLineSpacing(.em(0.15))
                    .markdownMargin(top: 10, bottom: 4)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(14)
                        ForegroundColor(headingColor)
                    }
                    .markdownMargin(top: 8, bottom: 4)
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(13)
                        ForegroundColor(headingSubtleColor95)
                    }
                    .markdownMargin(top: 6, bottom: 2)
            }
            .heading5 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.medium)
                        FontSize(13)
                        ForegroundColor(headingSubtleColor90)
                    }
                    .markdownMargin(top: 4, bottom: 2)
            }
            .heading6 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.medium)
                        FontSize(12)
                        ForegroundColor(headingSubtleColor80)
                    }
                    .markdownMargin(top: 4, bottom: 2)
            }
            .paragraph { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: 0, bottom: 10)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(blockquoteBorderColor)
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(blockquoteTextColor)
                            FontStyle(.italic)
                        }
                        .padding(.leading, 10)
                }
                .markdownMargin(top: 4, bottom: 8)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(12)
                            ForegroundColor(codeBlockTextColor)
                        }
                        .padding(10)
                }
                .background(codeBlockBgColor)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.codeBlock))
                .markdownMargin(top: 4, bottom: 8)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: 2, bottom: 2)
            }
            .thematicBreak {
                Divider()
                    .overlay(dividerColor)
                    .markdownMargin(top: 8, bottom: 8)
            }
            .table { configuration in
                configuration.label
                    .markdownTableBorderStyle(
                        .init(color: tableBorderColor)
                    )
                    .markdownMargin(top: 4, bottom: 8)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(12)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
    }
}
