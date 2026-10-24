import AppKit
import SwiftUI

/// Closes its hosting window when `isClosing` becomes true. SwiftUI's
/// `dismiss` and `dismissWindow` don't close a `DocumentGroup` window, so
/// this is the one place the app touches `NSWindow` (ADR-0011).
struct WindowCloser: NSViewRepresentable {
    let isClosing: Bool

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        guard isClosing, let window = view.window else {
            return
        }
        // AppKit won't close a window with a sheet attached, and SwiftUI's
        // sheet is still attached while it animates out.
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
        window.performClose(nil)
    }
}
