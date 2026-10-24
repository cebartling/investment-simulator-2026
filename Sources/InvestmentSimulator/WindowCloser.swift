import AppKit
import SwiftUI

/// Closes its hosting window when `isClosing` becomes true. SwiftUI's
/// `dismiss` and `dismissWindow` don't close a `DocumentGroup` window, so
/// this is the one place the app touches `NSWindow` (ADR-0011).
struct WindowCloser: NSViewRepresentable {
    let isClosing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard isClosing, !context.coordinator.didRequestClose, let window = view.window else {
            return
        }
        // Once only: if the close is vetoed (say, at a save prompt), later
        // redraws must not ask again.
        context.coordinator.didRequestClose = true
        // AppKit won't close a window with a sheet attached, and SwiftUI's
        // sheet is still attached while it animates out.
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
        window.performClose(nil)
    }

    final class Coordinator {
        var didRequestClose = false
    }
}
