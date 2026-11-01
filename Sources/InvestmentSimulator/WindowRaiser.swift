import AppKit
import SwiftUI

/// Brings its hosting window forward when `raiseCount` changes, so a sheet
/// started from Research is seen. `openDocument` can't reach an untitled
/// document (ADR-0020).
struct WindowRaiser: NSViewRepresentable {
    let raiseCount: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(raiseCount: raiseCount)
    }

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard raiseCount != context.coordinator.raiseCount else {
            return
        }
        context.coordinator.raiseCount = raiseCount
        view.window?.makeKeyAndOrderFront(nil)
    }

    final class Coordinator {
        var raiseCount: Int

        init(raiseCount: Int) {
            self.raiseCount = raiseCount
        }
    }
}
