import SwiftUI
import UIKit

// Typography. Handoff §2.
// Archivo for headlines and UI text. JetBrains Mono for data and labels.
// Mono labels are always uppercase with wide tracking — see `MonoLabel`.

enum Type {
    enum Weight {
        case regular, medium, semibold, bold, extrabold, black

        var archivoName: String {
            switch self {
            case .regular:   return "Archivo-Regular"
            case .medium:    return "Archivo-Medium"
            case .semibold:  return "Archivo-SemiBold"
            case .bold:      return "Archivo-Bold"
            case .extrabold: return "Archivo-ExtraBold"
            case .black:     return "Archivo-Black"
            }
        }

        var systemWeight: Font.Weight {
            switch self {
            case .regular:   return .regular
            case .medium:    return .medium
            case .semibold:  return .semibold
            case .bold:      return .bold
            case .extrabold: return .heavy
            case .black:     return .black
            }
        }
    }

    /// Archivo at `size`, falling back to the system face if the TTF is not bundled.
    static func archivo(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        isAvailable(weight.archivoName)
            ? .custom(weight.archivoName, size: size)
            : .system(size: size, weight: weight.systemWeight)
    }

    /// JetBrains Mono at `size`, falling back to the system monospaced face.
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        let name = medium ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular"
        return isAvailable(name)
            ? .custom(name, size: size)
            : .system(size: size, weight: medium ? .medium : .regular, design: .monospaced)
    }

    // The big step figure. Mono, tabular, so digits do not jitter as it counts.
    static func figure(_ size: CGFloat, medium: Bool = true) -> Font { mono(size, medium: medium) }

    private static var cache: [String: Bool] = [:]
    private static func isAvailable(_ name: String) -> Bool {
        if let known = cache[name] { return known }
        let found = UIFont(name: name, size: 12) != nil
        cache[name] = found
        return found
    }
}

extension Text {
    /// Second line of a headline pair. Handoff §2 — first line ink, second line dim.
    func quiet() -> some View { self.foregroundStyle(Color.dim) }
}
