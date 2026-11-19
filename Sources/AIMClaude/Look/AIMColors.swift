import SwiftUI

/// Win98-era palette used by AIM 4.x/5.x.
enum AIMColors {
    static let window = Color(red: 0.753, green: 0.753, blue: 0.753)      // #C0C0C0
    static let highlight = Color.white
    static let light = Color(red: 0.875, green: 0.875, blue: 0.875)       // #DFDFDF
    static let shadow = Color(red: 0.502, green: 0.502, blue: 0.502)      // #808080
    static let darkShadow = Color(red: 0.04, green: 0.04, blue: 0.04)
    static let titleBlue = Color(red: 0, green: 0, blue: 0.502)           // #000080
    static let titleBlueEnd = Color(red: 0.063, green: 0.518, blue: 0.816) // #1084D0
    static let field = Color.white
    static let text = Color.black
    static let userName = Color(red: 1, green: 0, blue: 0)                // own name: red
    static let buddyName = Color(red: 0, green: 0, blue: 1)               // buddy: blue
    static let error = Color(red: 0.8, green: 0, blue: 0)
    static let system = Color(red: 0.4, green: 0.4, blue: 0.4)
    static let selection = Color(red: 0, green: 0, blue: 0.502)
}

enum AIMFonts {
    /// True once the skin's MS Sans Serif is registered; otherwise Verdana stands in.
    nonisolated(unsafe) static var hasMSSans = false

    static var label: Font { hasMSSans ? .custom("MS-Sans-Serif", size: 11) : .custom("Verdana", size: 11) }
    static var labelBold: Font { hasMSSans ? .custom("MS-Sans-Serif-Bold", size: 11) : .custom("Verdana", size: 11).weight(.bold) }
    static var small: Font { hasMSSans ? .custom("MS-Sans-Serif", size: 10) : .custom("Verdana", size: 10) }
    static let message = Font.system(size: 12, design: .monospaced)
    static let messageBold = Font.system(size: 12, design: .monospaced).weight(.bold)
    static let link = Color(red: 0, green: 0, blue: 0.8)
}
