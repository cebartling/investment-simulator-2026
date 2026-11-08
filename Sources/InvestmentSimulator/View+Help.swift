import SwiftUI

extension View {
    /// A tooltip of `text`, or none when it's nil, such as the full price
    /// when rounding to the cent hid no decimals (PIN-513). An empty tooltip
    /// shows nothing, and keeps the view in place as the text comes and goes.
    func help(ifPresent text: String?) -> some View {
        help(text ?? "")
    }
}
