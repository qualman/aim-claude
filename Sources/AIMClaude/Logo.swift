import AIMCore
import AppKit
import SwiftUI

/// The skin's icons/logo if present, otherwise the original fallback runner.
struct AIMLogo: View {
    let skin: SkinStore

    var body: some View {
        if let url = skin.icon("logo"), let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            FallbackRunner().aspectRatio(0.85, contentMode: .fit)
        }
    }
}
