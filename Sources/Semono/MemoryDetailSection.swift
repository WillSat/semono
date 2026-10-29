import AppKit
import SwiftUI

/// Detailed memory composition, pressure, swap, and the apps using the most
/// memory. Embedded in Device Information's Memory page; the store owns its
/// own timer and runs only while the section is visible.
struct MemoryDetailSection: View {
    @ObservedObject private var locale = LocaleManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = MemoryDetailStore()
    @AppStorage("memoryDetailRefreshInterval") private var refreshInterval = 3

    private let refreshOptions = [1, 2, 3, 5, 10]

    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            refreshBar

            if let snapshot = store.snapshot {
                compositionCard(snapshot)
                pressureSwapCard(snapshot)
                topAppsCard
            } else {
                loadingCard
            }
        }
        .onAppear { store.start(interval: TimeInterval(refreshInterval)) }
        .onDisappear { store.stop() }
        .onChange(of: refreshInterval) { _, newValue in
            store.updateInterval(TimeInterval(newValue))
        }
    }

    private var refreshBar: some View {
        HStack(spacing: 8) {
            Text(t("Refresh"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $refreshInterval) {
                ForEach(refreshOptions, id: \.self) { seconds in
                    Text("\(seconds)\(locale.localized("s"))").tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 12)

            if let updated = store.snapshot?.timestamp {
                Text("\(t("Updated")) \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private func compositionCard(_ snapshot: MemoryDetailSnapshot) -> some View {
        MemoryCard(title: t("Memory Composition"), icon: "chart.pie.fill", tint: .blue) {
            HStack(alignment: .center, spacing: 28) {
                MemoryDonut(snapshot: snapshot, usedLabel: t("Used"))
                    .frame(width: 196, height: 196)
                    .padding(10)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 28) {
                        summary(t("Total"), bytes: snapshot.totalBytes)
                        summary(t("Used"), bytes: snapshot.usedBytes, detail: percent(snapshot.usedFraction))
                    }

                    Divider().opacity(0.5)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(snapshot.categories) { category in
                            categoryLegend(category, total: snapshot.totalBytes)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func summary(_ title: String, bytes: UInt64, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MemoryFormat.bytes(bytes))
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func categoryLegend(_ category: MemoryCategory, total: UInt64) -> some View {
        let fraction = total > 0 ? Double(category.bytes) / Double(total) : 0
        return HStack(spacing: 8) {
            Circle()
                .fill(category.kind.color)
                .frame(width: 8, height: 8)
            Text(t(category.kind.titleKey))
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(MemoryFormat.bytes(category.bytes))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(percent(fraction))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func pressureSwapCard(_ snapshot: MemoryDetailSnapshot) -> some View {
        MemoryCard(title: t("Pressure & Swap"), icon: "gauge.with.dots.needle.67percent", tint: .orange) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text(t("Memory Pressure"))
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 12)
                    pressureBadge(snapshot.pressureLevel)
                }

                Divider().opacity(0.5)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("Swap"))
                            .font(.callout.weight(.medium))
                        Text(swapDetail(snapshot))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 12)
                    Text(swapPercent(snapshot))
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .monospacedDigit()
                }

                if snapshot.swapTotalBytes != nil {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.purple.opacity(0.12))
                            Capsule()
                                .fill(Color.purple.opacity(0.72))
                                .frame(width: geo.size.width * snapshot.swapFraction)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
    }

    private var topAppsCard: some View {
        MemoryCard(title: t("Top Applications"), icon: "app.badge", tint: .purple) {
            VStack(alignment: .leading, spacing: 0) {
                if store.apps.isEmpty {
                    Text(t("No Data"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    let maxBytes = store.apps.map(\.bytes).max() ?? 1
                    ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                        appRow(index: index, app: app, maxBytes: maxBytes)
                        if index < store.apps.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private func appRow(index: Int, app: MemoryAppUsage, maxBytes: UInt64) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)

            Group {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "gearshape.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(MemoryFormat.bytes(app.bytes))
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                    Text(percent(app.percentOfTotal))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.purple.opacity(0.10))
                        Capsule()
                            .fill(Color.purple.opacity(0.62))
                            .frame(
                                width: geo.size.width * min(1, Double(app.bytes) / Double(max(1, maxBytes)))
                            )
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.vertical, 7)
    }

    private var loadingCard: some View {
        MemoryCard(title: t("Memory Composition"), icon: "memorychip", tint: .blue) {
            HStack(spacing: 12) {
                ProgressView()
                Text(t("Collecting information..."))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private func pressureBadge(_ level: Int?) -> some View {
        let current = level ?? -1
        return HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { value in
                let active = current == value
                let color = ColorScale.color(
                    forPressureLevel: value,
                    light: colorScheme == .light
                )
                Text(pressureLabel(value))
                    .font(.caption.weight(active ? .semibold : .regular))
                    .foregroundStyle(active ? color : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        active ? color.opacity(0.16) : Color.clear,
                        in: .rect(cornerRadius: 6)
                    )
                    .overlay {
                        if active {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(color.opacity(0.5), lineWidth: 0.8)
                        }
                    }
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 9))
    }

    private func pressureLabel(_ level: Int) -> String {
        switch level {
        case 0: t("Normal")
        case 1: t("Warning")
        case 2: t("Critical")
        default: "—"
        }
    }

    private func swapDetail(_ snapshot: MemoryDetailSnapshot) -> String {
        guard let used = snapshot.swapUsedBytes, let total = snapshot.swapTotalBytes else {
            return "—"
        }
        return "\(MemoryFormat.bytes(used)) / \(MemoryFormat.bytes(total))"
    }

    private func swapPercent(_ snapshot: MemoryDetailSnapshot) -> String {
        guard snapshot.swapTotalBytes != nil else { return "—" }
        return percent(snapshot.swapFraction)
    }

    private func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", min(1, max(0, fraction)) * 100)
    }
}

private struct MemoryCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    private let content: Content

    init(title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 6))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        }
    }
}

private struct MemoryDonut: View {
    let snapshot: MemoryDetailSnapshot
    let usedLabel: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 26)

            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(
                        segment.color,
                        style: StrokeStyle(lineWidth: 26, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 1) {
                Text(String(format: "%.1f%%", snapshot.usedFraction * 100))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(usedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct Segment: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let color: Color
    }

    private var segments: [Segment] {
        let total = max(1, Double(snapshot.totalBytes))
        var cursor = 0.0
        var result: [Segment] = []
        for category in snapshot.categories {
            let fraction = min(1, Double(category.bytes) / total)
            guard fraction > 0 else { continue }
            let start = cursor
            let end = min(1, cursor + fraction)
            result.append(
                Segment(
                    id: category.kind.rawValue,
                    start: start,
                    end: end,
                    color: category.kind.color
                )
            )
            cursor = end
        }
        return result
    }
}

private enum MemoryFormat {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}

private extension MemoryCategory.Kind {
    var color: Color {
        switch self {
        case .app: .blue
        case .wired: .indigo
        case .compressed: .purple
        case .cached: .teal
        case .free: .gray.opacity(0.35)
        }
    }
}
