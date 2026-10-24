import AppKit
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

@main
struct InvestmentSimulatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var mainWindowModel = MainWindowModel()

    var body: some Scene {
        WindowGroup(AppMetadata.displayName) {
            ContentView(model: mainWindowModel)
        }
    }
}

/// A bare SwiftPM executable launched via `swift run` starts as a background
/// process with no Dock icon or key window; promote it to a regular app.
/// The policy must change before launch finishes, or the menu bar can stay
/// unresponsive until the user switches apps.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.activate()
    }
}
