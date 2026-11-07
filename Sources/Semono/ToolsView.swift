import SwiftUI

private enum Tool: String, CaseIterable, Identifiable {
    case memory
    case screenCorners

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .memory: "Memory Monitor"
        case .screenCorners: "Screen Corners"
        }
    }

    var sidebarSubtitleKey: String {
        switch self {
        case .memory: "Live system memory"
        case .screenCorners: "Built-in display"
        }
    }

    var detailSubtitleKey: String {
        switch self {
        case .memory: "Live memory composition, pressure, swap and top applications."
        case .screenCorners: "Round the bottom corners of the built-in display."
        }
    }

    var icon: String {
        switch self {
        case .memory: "memorychip"
        case .screenCorners: "rectangle.roundedbottom"
        }
    }

    var detailIcon: String {
        switch self {
        case .memory: "memorychip.fill"
        case .screenCorners: "rectangle.roundedbottom.fill"
        }
    }

    var gradient: [Color] {
        switch self {
        case .memory: [.blue, .cyan]
        case .screenCorners: [.indigo, .purple]
        }
    }
}

/// A small, extensible home for utility tools. Each tool gets a row in the
/// sidebar and its own detail page; the Memory Monitor owns its sampling timer
/// and only runs while its page is visible.
struct ToolsView: View {
    @ObservedObject private var locale = LocaleManager.shared
    @State private var selection: Tool? = ToolsView.initialTool

    private static var initialTool: Tool {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SEMONO_TOOL"],
           let tool = Tool(rawValue: raw) {
            return tool
        }
        #endif
        return .memory
    }

    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
        } detail: {
            if let selection {
                toolDetail(selection)
            } else {
                ContentUnavailableView(
                    t("Tools"),
                    systemImage: "wrench.and.screwdriver"
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(t("Tools"))
        .frame(minWidth: 980, minHeight: 640)
        .background(WindowRegistration(window: .tools))
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(Tool.allCases) { tool in
                    ToolRow(
                        tool: tool,
                        title: t(tool.titleKey),
                        subtitle: t(tool.sidebarSubtitleKey)
                    )
                    .tag(tool)
                }
            } header: {
                Text(t("Utilities"))
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func toolDetail(_ tool: Tool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(tool)

                switch tool {
                case .memory:
                    MemoryMonitorView()
                case .screenCorners:
                    ScreenCornersToolView()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func header(_ tool: Tool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: tool.detailIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    LinearGradient(
                        colors: tool.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: .rect(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(t(tool.titleKey))
                    .font(.system(size: 26, weight: .semibold))
                Text(t(tool.detailSubtitleKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
        }
    }
}

private struct ToolRow: View {
    let tool: Tool
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tool.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    LinearGradient(
                        colors: tool.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: .rect(cornerRadius: 7)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
