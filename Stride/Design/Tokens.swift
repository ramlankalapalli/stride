import SwiftUI

// Design tokens. Handoff §2.
// Rule: `steel` appears in exactly one place per screen — the thing that is
// live or next. Never decorative.

extension Color {
    /// Background. Always pure black.
    static let void    = Color(hex: 0x000000)
    /// Inactive bars, empty progress tracks.
    static let track   = Color(hex: 0x12141A)
    /// Hairline dividers, borders.
    static let line    = Color(hex: 0x1C1F26)
    /// Disabled / locked text, faintest labels.
    static let dimmer  = Color(hex: 0x2E323B)
    /// Secondary text, labels.
    static let dim     = Color(hex: 0x737A8A)
    /// Primary text, primary buttons.
    static let ink     = Color(hex: 0xFFFFFF)
    /// Single accent. Live / active state only.
    static let steel   = Color(hex: 0xD6E0F5)
    /// Destructive actions only.
    static let danger  = Color(hex: 0xA8484C)

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Space {
    /// Standard screen padding. Handoff §2 — 24–26px horizontal.
    static let screen: CGFloat = 26
    static let tight: CGFloat  = 8
    static let small: CGFloat  = 12
    static let unit: CGFloat   = 16
    static let block: CGFloat  = 24
    static let section: CGFloat = 40
    /// Bottom CTA corner radius. The only radius in the app besides pills.
    static let ctaRadius: CGFloat = 12
    static let hairline: CGFloat = 1
}
