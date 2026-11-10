import SwiftUI
import ManterAtivoCore

enum CockpitSection: String, CaseIterable, Identifiable {
    case agora
    case processos
    case espaco
    case mesa
    case energia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agora: "Agora"
        case .processos: "Processos"
        case .espaco: "Espaço"
        case .mesa: "Mesa"
        case .energia: "Energia"
        }
    }

    var symbol: String {
        switch self {
        case .agora: "waveform.path.ecg"
        case .processos: "square.stack.3d.up"
        case .espaco: "internaldrive"
        case .mesa: "display"
        case .energia: "battery.100percent"
        }
    }
}

struct MetricCard: View {
    var title: String
    var value: String
    var subtitle: String
    var samples: [Double]
    var tint: Color
    var alerts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(alerts ? Color.red : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: .topLeading)
            Sparkline(samples: samples)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(height: 28)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: 16, tint: alerts ? Color.red.opacity(0.18) : nil)
        .accessibilityElement(children: .combine)
    }
}

struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 12, content: content)
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func glassCard(corner: CGFloat = 16, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if #available(macOS 26, *) {
            let glass = tint.map { Glass.regular.tint($0) } ?? .regular
            self.glassEffect(glass, in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
        }
    }
}

struct Sparkline: Shape {
    var samples: [Double]

    func path(in rect: CGRect) -> Path {
        guard samples.count >= 2 else { return Path() }
        let low = samples.min() ?? 0
        let high = samples.max() ?? 1
        let span = high - low
        let flat = span < 0.001
        var path = Path()
        for (index, sample) in samples.enumerated() {
            let x = rect.minX + CGFloat(index) / CGFloat(samples.count - 1) * rect.width
            let y = flat
                ? rect.midY
                : rect.maxY - CGFloat((sample - low) / span) * rect.height
            let point = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

struct PhraseBanner: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassCard(corner: 18)
            .textSelection(.enabled)
    }
}
