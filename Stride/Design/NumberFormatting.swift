import Foundation

// Number formatting shared by the app and the widget. Kept out of Copy.swift
// so the widget target — which includes Design/ but not Copy/Models/Logic —
// can use it without pulling in the rest of the app's dependency graph.

extension Int {
    /// 6,800 — grouped, never abbreviated. The record shows the real number.
    var formattedSteps: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// "four", used where the copy spells small numbers ("Four isn't five.")
    var spelled: String {
        let words = ["zero", "one", "two", "three", "four", "five",
                     "six", "seven", "eight", "nine", "ten"]
        return (0...10).contains(self) ? words[self] : "\(self)"
    }

    var ordinal: String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
