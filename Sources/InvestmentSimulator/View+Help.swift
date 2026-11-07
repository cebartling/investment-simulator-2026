import SwiftUI

extension View {
    /// A tooltip of `text`, or none when it's nil, such as the full price
    /// when rounding to the cent hid no decimals (PIN-513).
    @ViewBuilder func help(ifPresent text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
    }
}
