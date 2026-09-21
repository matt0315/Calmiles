import SwiftUI

enum CalmilesColor {
    /// Slate indigo — primary brand
    static let slateIndigo = Color(red: 0x1B / 255, green: 0x24 / 255, blue: 0x36 / 255)
    /// Ink — deepest background
    static let ink = Color(red: 0x0E / 255, green: 0x14 / 255, blue: 0x20 / 255)
    /// Mist — light text / secondary surfaces
    static let mist = Color(red: 0xE8 / 255, green: 0xEE / 255, blue: 0xF7 / 255)
    /// Cloud — page background (light)
    static let cloud = Color(red: 0xF5 / 255, green: 0xF7 / 255, blue: 0xFB / 255)
    /// Sand — warm accent
    static let sand = Color(red: 0xD4 / 255, green: 0xC4 / 255, blue: 0xA8 / 255)
    /// Copper — primary CTA / classify business
    static let copper = Color(red: 0xA6 / 255, green: 0x7C / 255, blue: 0x52 / 255)
    /// Copper soft
    static let copperSoft = Color(red: 0xC4 / 255, green: 0xA5 / 255, blue: 0x74 / 255)
    /// Success
    static let success = Color(red: 0x6B / 255, green: 0x8F / 255, blue: 0x71 / 255)
    /// Danger
    static let danger = Color(red: 0xB5 / 255, green: 0x6B / 255, blue: 0x6B / 255)

    static let business = copper
    static let personal = Color(red: 0x6B / 255, green: 0x7A / 255, blue: 0x8F / 255)
    static let undecided = sand
}

extension Color {
    static let calmilesBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(CalmilesColor.ink)
            : UIColor(CalmilesColor.cloud)
    })
    static let calmilesCard = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(CalmilesColor.slateIndigo)
            : UIColor.white
    })
    static let calmilesPrimaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(CalmilesColor.mist)
            : UIColor(CalmilesColor.slateIndigo)
    })
    static let calmilesSecondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(CalmilesColor.sand).withAlphaComponent(0.85)
            : UIColor(CalmilesColor.slateIndigo).withAlphaComponent(0.55)
    })
}
