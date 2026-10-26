import SwiftUI

/// A burst of confetti falling over the view each time `trigger` changes.
/// Draws nothing with Reduce Motion on, and never takes clicks.
struct ConfettiView: View {
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst: Burst?

    var body: some View {
        TimelineView(.animation(paused: burst == nil)) { context in
            Canvas { canvas, size in
                guard let burst else {
                    return
                }
                let elapsed = context.date.timeIntervalSince(burst.start)
                for piece in burst.pieces {
                    piece.draw(in: &canvas, size: size, elapsed: elapsed)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            burst = reduceMotion ? nil : Burst()
        }
        .task(id: burst?.start) {
            guard burst != nil else {
                return
            }
            // Cancelled when a new burst replaces this one, which then ends
            // on its own schedule.
            guard await (try? Task.sleep(for: .seconds(Burst.duration))) != nil else {
                return
            }
            burst = nil
        }
    }
}

private struct Burst {
    static let duration = 2.5

    let start = Date.now
    let pieces = (0 ..< 150).map { _ in Piece() }
}

private struct Piece {
    private static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]
    /// Points per second squared.
    private static let gravity = 600.0

    let color = colors.randomElement() ?? .yellow
    /// Where the piece starts, as a fraction of the width.
    let startX = Double.random(in: 0 ... 1)
    /// How far above the top edge the piece starts, so the pieces arrive
    /// over time rather than in one row.
    let startHeight = Double.random(in: 0 ... 300)
    /// Points per second.
    let velocity = CGVector(dx: .random(in: -120 ... 120), dy: .random(in: 0 ... 150))
    let width = Double.random(in: 6 ... 10)
    let height = Double.random(in: 10 ... 16)
    /// Radians per second, for the spin and the flutter.
    let spin = Double.random(in: -8 ... 8)
    let flutter = Double.random(in: 4 ... 10)

    func draw(in canvas: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let left = startX * size.width + velocity.dx * elapsed
        let top = -height - startHeight + velocity.dy * elapsed + Self.gravity * elapsed * elapsed / 2
        var piece = canvas
        piece.opacity = min(1, max(0, (Burst.duration - elapsed) / 0.5))
        piece.translateBy(x: left, y: top)
        piece.rotate(by: .radians(spin * elapsed))
        // Squashing the height as it turns makes the piece look like it flips.
        piece.scaleBy(x: 1, y: cos(flutter * elapsed))
        piece.fill(Path(CGRect(x: -width / 2, y: -height / 2, width: width, height: height)), with: .color(color))
    }
}
