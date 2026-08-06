import SwiftUI

// Shared components. Handoff §2.
// No rounded borders anywhere except the CTA and pill shapes. Hierarchy comes
// from type size and spacing — not boxes, not dividers.

// MARK: - Text

/// Uppercase mono label with wide tracking. The app's only label style.
struct MonoLabel: View {
    let text: String
    var size: CGFloat = 11
    var tracking: CGFloat = 0.16
    var color: Color = .dim
    var medium: Bool = false

    init(_ text: String,
         size: CGFloat = 11,
         tracking: CGFloat = 0.16,
         color: Color = .dim,
         medium: Bool = false) {
        self.text = text
        self.size = size
        self.tracking = tracking
        self.color = color
        self.medium = medium
    }

    var body: some View {
        Text(text.uppercased())
            .font(Type.mono(size, medium: medium))
            .tracking(size * tracking)
            .foregroundStyle(color)
    }
}

/// Two-line headline. First line ink, second line dim. Handoff §2.
struct Headline: View {
    let loud: String
    var soft: String?
    var size: CGFloat = 30

    init(_ loud: String, _ soft: String? = nil, size: CGFloat = 30) {
        self.loud = loud
        self.soft = soft
        self.size = size
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loud)
                .font(Type.archivo(size, .bold))
                .foregroundStyle(Color.ink)
            if let soft {
                Text(soft)
                    .font(Type.archivo(size, .bold))
                    .quiet()
            }
        }
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A plain fact line. Used on the permission and connect screens.
struct FactLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color.dimmer)
                .frame(width: 10, height: Space.hairline)
                .padding(.top, 10)
            Text(text)
                .font(Type.archivo(15))
                .foregroundStyle(Color.dim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Rules

struct Hairline: View {
    var color: Color = .line
    var body: some View {
        Rectangle().fill(color).frame(height: Space.hairline)
    }
}

// MARK: - Buttons

/// Bottom CTA. Full width, inverted — black label on white. Handoff §2.
struct PrimaryCTA: View {
    let title: String
    var destructive: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Type.archivo(17, .semibold))
                .foregroundStyle(destructive ? Color.ink : Color.void)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: Space.ctaRadius, style: .continuous)
                        .fill(destructive ? Color.danger : Color.ink)
                )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.28)
        .disabled(!enabled)
    }
}

/// Secondary action. No fill, no border — just quieter text.
struct GhostButton: View {
    let title: String
    var color: Color = .dim
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Type.archivo(15, .medium))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(.plain)
    }
}

/// Footer link, mono and uppercase. "ALREADY ON RECORD? LOG IN"
struct FooterLink: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MonoLabel(text, size: 11, color: .dim)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fields

/// Text field with a mono label above and a hairline beneath. No box.
struct StrideField: View {
    let label: String
    @Binding var value: String
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(label, size: 10, color: focused ? .steel : .dim)
            Group {
                if secure {
                    SecureField("", text: $value)
                } else {
                    TextField("", text: $value)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .font(Type.archivo(19, .medium))
            .foregroundStyle(Color.ink)
            .tint(Color.steel)
            .focused($focused)
            Hairline(color: focused ? .dim : .line)
        }
    }
}

// MARK: - Progress

/// Horizontal progress track. Fill is steel only when this is the live thing.
struct ProgressTrack: View {
    let fraction: Double
    var live: Bool = true
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.track)
                Rectangle()
                    .fill(live ? Color.steel : Color.dim)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// Vertical bar row — weekly challenge, hourly waveform.
struct BarRow: View {
    let values: [Int]
    let peak: Int
    /// Index rendered in steel. Everything else is track/dim.
    var liveIndex: Int?
    var hitThreshold: Int?
    var height: CGFloat = 90
    var spacing: CGFloat = 6

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(values.indices, id: \.self) { i in
                let v = Double(values[i])
                let p = Double(max(peak, 1))
                let h = max(2, height * min(v / p, 1))
                Rectangle()
                    .fill(color(for: i))
                    .frame(height: h)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private func color(for i: Int) -> Color {
        if i == liveIndex { return .steel }
        if let t = hitThreshold, values[i] >= t { return .ink }
        return values[i] == 0 ? .track : .dimmer
    }
}

// MARK: - Screen chrome

/// Every screen sits on pure black with the standard horizontal padding.
struct ScreenScaffold<Content: View>: View {
    var top: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.void.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, Space.screen)
                .padding(.top, top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .preferredColorScheme(.dark)
    }
}

/// Small back affordance. A chevron would be decorative; a word is not.
struct BackBar: View {
    var title: String = "Back"
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                MonoLabel(title, size: 10, color: .dim)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(height: 32)
    }
}

/// Progress dots for the intro and onboarding sequences.
struct StepDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Rectangle()
                    .fill(i == index ? Color.steel : Color.track)
                    .frame(width: i == index ? 18 : 10, height: 2)
            }
        }
    }
}
