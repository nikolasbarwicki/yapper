import SwiftUI

// MARK: - App Entry Point

/// The main entry point for the Yapper application.
///
/// SWIFT CONCEPT: @main
/// This is similar to the entry point in a Node.js app (like `index.ts`).
/// The @main attribute tells Swift "start here".
///
/// SWIFTUI CONCEPT: App protocol
/// SwiftUI apps conform to the `App` protocol, which requires a `body` property
/// that returns a `Scene`. Think of it like React's root component.
@main
struct YapperApp: App {

    // SWIFT CONCEPT: @NSApplicationDelegateAdaptor
    // This bridges SwiftUI's modern lifecycle with AppKit's traditional AppDelegate.
    // We need AppDelegate for menu bar apps because SwiftUI doesn't have native
    // menu bar support (yet). It's like using a class component wrapper in React
    // for features that hooks don't support.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // SWIFT TIP: `var body: some Scene` is a computed property.
    // `some Scene` means "returns something that conforms to Scene protocol"
    // This is similar to TypeScript's `(): React.ReactNode` return type.
    var body: some Scene {
        // Settings window - opens when user clicks "Settings" in menu
        // or presses Cmd+, (standard macOS shortcut)
        // Note: Menu bar is managed via NSStatusBar in AppDelegate for dynamic icon updates
        Settings {
            SettingsView()
                .environment(appDelegate.appState)
        }
    }
}
