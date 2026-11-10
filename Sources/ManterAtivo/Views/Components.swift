import SwiftUI
import ManterAtivoCore

enum CockpitSection: String, CaseIterable, Identifiable {
    case agora
    case agentes
    case processos
    case espaco
    case mesa
    case energia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agora: "Agora"
        case .agentes: "Agentes"
        case .processos: "Processos"
        case .espaco: "Espaço"
        case .mesa: "Mesa"
        case .energia: "Energia"
        }
    }

    var symbol: String {
        switch self {
        case .agora: "waveform.path.ecg"
        case .agentes: "sparkles"
        case .processos: "square.stack.3d.up"
        case .espaco: "internaldrive"
        case .mesa: "display"
        case .energia: "battery.100percent"
        }
    }
}

struct MetricCard: View {
    var title: String
    var symbol: String
    var value: String
    var subtitle: String
    var samples: [Double]
    var tint: Color
    var alerts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 27, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Sparkline(samples: samples)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(height: 21)
                .accessibilityHidden(true)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .panelSurface()
        .accessibilityElement(children: .combine)
        .accessibilityHint(alerts ? "Uso elevado." : "")
    }
}

extension View {
    func panelSurface(corner: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay { shape.strokeBorder(.separator.opacity(0.55), lineWidth: 1) }
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
    var model: AppModel

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Estado do Mac", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.96, green: 0.83, blue: 0.62))
                Text(model.phrase)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 5) {
                ZStack {
                    ForEach(0..<3) { index in
                        Circle()
                            .strokeBorder(.white.opacity(0.12 + Double(index) * 0.12), lineWidth: 1)
                            .padding(CGFloat(index) * 8)
                    }
                    Circle()
                        .fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.85, blue: 0.63)],
                                             center: .topLeading, startRadius: 2, endRadius: 55))
                        .padding(21)
                    Image(systemName: model.wakeSymbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.13))
                }
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
                Text(model.wakeKnown ? "Vigília · " + model.wake.mode.title : "Lendo vigília")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [Color(red: 0.075, green: 0.11, blue: 0.18),
                                        Color(red: 0.17, green: 0.24, blue: 0.34)],
                               startPoint: .leading, endPoint: .trailing)
                Canvas { context, size in
                    let center = CGPoint(x: size.width - 66, y: size.height / 2)
                    for radius in stride(from: 68, through: 260, by: 22) {
                        let r = CGFloat(radius)
                        let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
                        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.055)), lineWidth: 1)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
