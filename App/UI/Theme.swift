import SwiftUI

enum Theme {
    static let bg = Color(red: 0.035, green: 0.039, blue: 0.047)
    static let panel = Color(red: 0.075, green: 0.082, blue: 0.094)
    static let panelHi = Color(red: 0.11, green: 0.12, blue: 0.135)
    static let stroke = Color.white.opacity(0.07)
    static let accent = Color(red: 0.30, green: 1.0, blue: 0.70)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let text = Color.white.opacity(0.92)
    static let dim = Color.white.opacity(0.48)
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

/// Faint noise + vignette background.
struct GrainBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            Canvas { ctx, size in
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<Int(size.width * size.height / 900) {
                    let x = CGFloat.random(in: 0...size.width, using: &rng)
                    let y = CGFloat.random(in: 0...size.height, using: &rng)
                    ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(Double.random(in: 0.015...0.05, using: &rng))))
                }
            }
            RadialGradient(colors: [Theme.accent.opacity(0.06), .clear], center: .topTrailing, startRadius: 10, endRadius: 600)
        }
        .drawingGroup()
        .ignoresSafeArea()
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial.opacity(0.35)))
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct Label2: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(Theme.mono(10, .semibold)).tracking(1.6).foregroundStyle(Theme.dim)
    }
}

struct AccentButton: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(prominent ? Color.black : Theme.text)
            .background(RoundedRectangle(cornerRadius: 9).fill(prominent ? Theme.accent : Theme.panelHi))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct DarkField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke))
            .onSubmit(onSubmit)
    }
}
