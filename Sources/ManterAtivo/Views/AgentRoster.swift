import SwiftUI
import ManterAtivoCore

private enum AgentColumn {
    static let cpu: CGFloat = 68
    static let memory: CGFloat = 80
    static let copies: CGFloat = 54
}

struct AgentColumnHeadings: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Agente").frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU").frame(width: AgentColumn.cpu, alignment: .trailing)
            Text("Memória").frame(width: AgentColumn.memory, alignment: .trailing)
            Text("Cópias").frame(width: AgentColumn.copies, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
    }
}

struct AgentMeasureRow: View {
    var row: AgentBar.Row
    var selected: Bool
    var totalAgentBytes: Double = 0
    var compact = false
    @State private var hovered = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: row.title.hasSuffix(" MCP") ? "point.3.connected.trianglepath.dotted" : "terminal")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if compact {
                    Text("CPU " + row.cpuText + " · " + row.memoryText + " · " + row.copiesText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                Text(row.cpuText).frame(width: AgentColumn.cpu, alignment: .trailing)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(row.memoryText)
                    if totalAgentBytes > 0 {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.quaternary)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.tint)
                                        .frame(width: proxy.size.width * min(1, Double(row.residentBytes) / totalAgentBytes))
                                }
                        }
                        .frame(width: 52, height: 3)
                        .accessibilityHidden(true)
                    }
                }
                .frame(width: AgentColumn.memory, alignment: .trailing)
                .help("Memória usada e participação na memória dos agentes locais")
                Text(String(row.copyCount)).frame(width: AgentColumn.copies, alignment: .trailing)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 5 : 3)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(hovered ? 0.09 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title), CPU \(row.cpuText), memória \(row.memoryText), \(row.copiesText)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AgentInspector: View {
    var row: AgentBar.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(row.title, systemImage: "scope")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 14) {
                measure("CPU", row.cpuText)
                Divider()
                measure("Memória", row.memoryText)
                Divider()
                measure("Cópias", String(row.copyCount))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .panelSurface()
    }

    private func measure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AgentesView: View {
    var model: AppModel
    @State private var query = ""
    @State private var order = Order.memory

    private enum Order: String, CaseIterable {
        case memory = "Memória"
        case cpu = "CPU"
        case copies = "Cópias"
    }

    private var rows: [AgentBar.Row] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.bar.rows.filter { text.isEmpty || $0.title.localizedStandardContains(text) }
            .sorted { lhs, rhs in
                switch order {
                case .cpu where lhs.cpuPercent != rhs.cpuPercent: return lhs.cpuPercent > rhs.cpuPercent
                case .copies where lhs.copyCount != rhs.copyCount: return lhs.copyCount > rhs.copyCount
                default:
                    if lhs.residentBytes != rhs.residentBytes { return lhs.residentBytes > rhs.residentBytes }
                    return (lhs.title, lhs.id) < (rhs.title, rhs.id)
                }
            }
    }

    var body: some View {
        let visible = rows
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Agentes locais")
                        .font(.title.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Picker("Ordenar por", selection: $order) {
                        ForEach(Order.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .fixedSize()
                }
                if let inspected = visible.first(where: { $0.id == model.inspectedAgentID }) {
                    AgentInspector(row: inspected)
                }
                if visible.isEmpty {
                    ContentUnavailableView(
                        model.bar.rows.isEmpty ? "Nenhum agente local detectado" : "Nenhum agente encontrado",
                        systemImage: model.bar.rows.isEmpty ? "terminal" : "magnifyingglass",
                        description: Text(model.bar.rows.isEmpty
                            ? "Os apps assistentes, CLIs e servidores MCP aparecem aqui enquanto executam no Mac."
                            : "Tente outro nome na busca.")
                    )
                } else {
                    VStack(spacing: 7) {
                        AgentColumnHeadings()
                        ForEach(visible) { row in
                            Divider()
                            Button { model.selectAgent(row.id) } label: {
                                AgentMeasureRow(row: row, selected: model.inspectedAgentID == row.id,
                                                totalAgentBytes: model.totalAgentBytes)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .panelSurface()
                    Text("Cada processo raiz conta como uma cópia. CPU e memória incluem os processos filhos.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button(model.bar.quitTitle) { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
            .padding(20)
        }
        .searchable(text: $query, prompt: "Buscar agente")
    }
}
