import SwiftUI

/// Device Information: a native sidebar-and-detail window over the same data
/// types `system_profiler -listDataTypes` exposes. Reports are fetched lazily
/// per category and rendered from a neutral tree, so a data type macOS adds
/// later still reads as labelled sections rather than raw JSON.
struct DeviceInfoView: View {
    @ObservedObject private var locale = LocaleManager.shared
    @StateObject private var store = DeviceInfoStore()
    @State private var selection: DeviceCategory? = DeviceInfoView.initialCategory
    @State private var searchText = ""

    /// Debug-only hook for screenshot automation; release builds always open
    /// on Hardware.
    private static var initialCategory: DeviceCategory {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SEMONO_DEVICE_INFO_CATEGORY"],
           let category = DeviceCategory(rawValue: raw) {
            return category
        }
        #endif
        return .hardware
    }

    private var chinese: Bool { locale.currentLanguage.usesChineseTechnicalLabels }
    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 218, ideal: 240, max: 280)
        } detail: {
            if let category = selection {
                DeviceDetailView(
                    category: category,
                    report: store.report(for: category),
                    failure: store.failure(for: category),
                    isLoading: store.isLoading(category),
                    searchText: searchText,
                    onRefresh: { store.load(category, force: true) }
                )
                .id(category)
            } else {
                ContentUnavailableView(
                    t("Device Information"),
                    systemImage: "desktopcomputer",
                    description: Text(t("Choose a category to inspect."))
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(t("Device Information"))
        .searchable(text: $searchText, placement: .toolbar, prompt: Text(t("Filter")))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let selection { store.load(selection, force: true) }
                } label: {
                    Label(t("Refresh"), systemImage: "arrow.clockwise")
                }
                .help(t("Refresh"))
                .keyboardShortcut("r", modifiers: .command)
                .disabled(selection == nil)
            }
        }
        .frame(minWidth: 900, minHeight: 580)
        .background(WindowRegistration(window: .deviceInfo))
        .task(id: selection) {
            if let selection { store.load(selection) }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(DeviceCategoryGroup.allCases) { group in
                    Section {
                        ForEach(DeviceCategory.categories(in: group)) { category in
                            SidebarRow(
                                category: category,
                                count: store.report(for: category)?.items.count,
                                title: t(category.titleKey)
                            )
                            .tag(category)
                        }
                    } header: {
                        Text(t(group.titleKey))
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text(t("Data from system_profiler"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    let category: DeviceCategory
    let count: Int?
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: category.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(category.tint)
                .frame(width: 20, height: 20)
                .background(category.tint.opacity(0.13), in: .rect(cornerRadius: 5))

            Text(title)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let count, count > 1 {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Detail

private struct DeviceDetailView: View {
    let category: DeviceCategory
    let report: DeviceReport?
    let failure: String?
    let isLoading: Bool
    let searchText: String
    let onRefresh: () -> Void

    @ObservedObject private var locale = LocaleManager.shared
    @State private var showAll = false

    private var chinese: Bool { locale.currentLanguage.usesChineseTechnicalLabels }
    private func t(_ key: String) -> String { locale.localized(key) }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [InfoItem] {
        guard let report else { return [] }
        guard !query.isEmpty else { return report.items }
        return report.items.compactMap { $0.filtered(by: query, chinese: chinese) }
    }

    private static let largeListThreshold = 20

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header

                if let report {
                    if category == .hardware {
                        HardwareSummaryCard(report: report, chinese: chinese)
                    } else if category == .software {
                        SoftwareSummaryCard(report: report, chinese: chinese)
                    }
                    if let failure {
                        errorBanner(failure)
                    }
                    if !query.isEmpty {
                        searchCount
                    }
                    reportBody
                } else if isLoading {
                    LoadingReportView()
                } else if let failure {
                    errorState(failure)
                } else {
                    LoadingReportView()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: category.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(category.tint)
                .frame(width: 46, height: 46)
                .background(category.tint.opacity(0.14), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(t(category.titleKey))
                    .font(.system(size: 26, weight: .semibold))
                HStack(spacing: 7) {
                    Text(category.dataType)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if let report, !report.items.isEmpty {
                        Text("·").foregroundStyle(.quaternary)
                        Text(itemCountText(report.items.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                if let report {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("\(t("Updated")) \(DeviceInfoFormatting.updatedText(report.fetchedAt, chinese: chinese, now: context.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func itemCountText(_ count: Int) -> String {
        if chinese { return "\(count) 项" }
        return "\(count) \(count == 1 ? "item" : "items")"
    }

    // MARK: Body states

    @ViewBuilder
    private var reportBody: some View {
        if filteredItems.isEmpty {
            if query.isEmpty {
                ContentUnavailableView(
                    t("No Data"),
                    systemImage: category.icon,
                    description: Text(t("This Mac does not report information for this category."))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ContentUnavailableView(
                    t("No Results"),
                    systemImage: "magnifyingglass",
                    description: Text(t("No information matches your filter."))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        } else {
            let large = filteredItems.count > Self.largeListThreshold
            let visible = (showAll || !query.isEmpty)
                ? filteredItems
                : Array(filteredItems.prefix(Self.largeListThreshold))

            ForEach(visible) { item in
                InfoItemCard(
                    item: item,
                    category: category,
                    chinese: chinese,
                    compact: large,
                    forceExpanded: !query.isEmpty
                )
            }

            if filteredItems.count > Self.largeListThreshold, query.isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showAll.toggle() }
                } label: {
                    Label(
                        showAll
                            ? t("Show Less")
                            : "\(t("Show All")) (\(filteredItems.count))",
                        systemImage: showAll ? "chevron.up" : "chevron.down"
                    )
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(.vertical, 4)
            }
        }
    }

    private var searchCount: some View {
        Text(chinese
             ? "\(filteredItems.count) 个结果"
             : "\(filteredItems.count) result\(filteredItems.count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("Unable to Read"))
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button(t("Try Again"), action: onRefresh)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.22))
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label(t("Unable to Read"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(t("Try Again"), action: onRefresh)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Hardware summary

/// Fast lookup of the handful of keys a summary card wants without knowing how
/// deeply macOS nested them.
private struct ReportFieldLookup {
    private let fields: [String: InfoField]

    init(report: DeviceReport) {
        var result: [String: InfoField] = [:]
        for field in report.items.flatMap(\.flattenedFields) where result[field.rawKey] == nil {
            result[field.rawKey] = field
        }
        fields = result
    }

    func value(_ key: String, chinese: Bool) -> String? {
        guard let field = fields[key] else { return nil }
        let value = DeviceInfoFormatting.value(field, chinese: chinese)
        guard value != "\u{2014}", !value.isEmpty else { return nil }
        return value
    }
}

/// The summary card used by Hardware and Software: the information people
/// open Device Information for, before the field list starts.
private struct SummaryCard: View {
    let title: String
    let subtitle: String?
    let tiles: [(String, String)]
    let colors: [Color]
    let watermark: String

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: watermark)
                .font(.system(size: 132, weight: .thin))
                .foregroundStyle(.white.opacity(0.09))
                .padding(.trailing, 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                if !tiles.isEmpty {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(tiles.indices, id: \.self) { index in
                            if index > 0 {
                                Divider()
                                    .frame(height: 30)
                                    .padding(.horizontal, 18)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tiles[index].0)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(tiles[index].1)
                                    .font(.system(.callout, design: .monospaced, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.10))
        }
    }
}

private struct HardwareSummaryCard: View {
    let report: DeviceReport
    let chinese: Bool

    private var lookup: ReportFieldLookup { ReportFieldLookup(report: report) }

    private var name: String {
        lookup.value("machine_name", chinese: chinese)
            ?? DeviceInfoFormatting.fieldLabel("machine_name", chinese: chinese)
    }

    private var subtitle: String? {
        let parts = [
            lookup.value("chip_type", chinese: chinese),
            lookup.value("physical_memory", chinese: chinese),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var tiles: [(String, String)] {
        [
            ("chip_type", lookup.value("chip_type", chinese: chinese)),
            ("physical_memory", lookup.value("physical_memory", chinese: chinese)),
            ("machine_model", lookup.value("machine_model", chinese: chinese)),
            ("serial_number", lookup.value("serial_number", chinese: chinese)),
        ].compactMap { pair in
            guard let value = pair.1 else { return nil }
            return (DeviceInfoFormatting.fieldLabel(pair.0, chinese: chinese), value)
        }
    }

    var body: some View {
        SummaryCard(
            title: name,
            subtitle: subtitle,
            tiles: tiles,
            colors: [Color.blue.opacity(0.20), Color.teal.opacity(0.09)],
            watermark: "laptopcomputer"
        )
    }
}

private struct SoftwareSummaryCard: View {
    let report: DeviceReport
    let chinese: Bool

    private var lookup: ReportFieldLookup { ReportFieldLookup(report: report) }

    private var title: String {
        lookup.value("os_version", chinese: chinese)
            ?? DeviceInfoFormatting.fieldLabel("os_version", chinese: chinese)
    }

    private var subtitle: String? {
        lookup.value("kernel_version", chinese: chinese)
    }

    private var tiles: [(String, String)] {
        [
            ("boot_volume", lookup.value("boot_volume", chinese: chinese)),
            ("uptime", lookup.value("uptime", chinese: chinese)),
            ("user_name", lookup.value("user_name", chinese: chinese)),
        ].compactMap { pair in
            guard let value = pair.1 else { return nil }
            return (DeviceInfoFormatting.fieldLabel(pair.0, chinese: chinese), value)
        }
    }

    var body: some View {
        SummaryCard(
            title: title,
            subtitle: subtitle,
            tiles: tiles,
            colors: [Color.purple.opacity(0.20), Color.indigo.opacity(0.09)],
            watermark: "gearshape.2"
        )
    }
}

// MARK: - Item card

private struct InfoItemCard: View {
    let item: InfoItem
    let category: DeviceCategory
    let chinese: Bool
    var nested = false
    var compact = false
    var forceExpanded = false

    @State private var expanded = false

    private var title: String? {
        DeviceInfoFormatting.title(item.title, chinese: chinese)
    }

    private var isExpanded: Bool {
        forceExpanded || expanded || !compact || title == nil
    }

    private var subtitle: String? {
        for key in category.summaryRowKeys {
            guard let field = item.fields.first(where: { $0.rawKey == key }) else { continue }
            let value = DeviceInfoFormatting.value(field, chinese: chinese)
            if value != "\u{2014}", !value.isEmpty { return value }
        }
        return nil
    }

    var body: some View {
        Group {
            if compact, let title {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .frame(width: 9)
                            Image(systemName: category.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(category.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                if let subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer(minLength: 6)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        Divider().padding(.vertical, 10)
                        detail
                    }
                }
                .padding(14)
                .background(background, in: .rect(cornerRadius: 12))
                .overlay { stroke }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .textSelection(.enabled)
                    }
                    detail
                }
                .padding(16)
                .background(background, in: .rect(cornerRadius: 14))
                .overlay { stroke }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !item.fields.isEmpty {
                InfoFieldGrid(fields: item.fields, chinese: chinese, labelWidth: nested ? 138 : 152)
            }
            ForEach(orderedDetailSections(for: item, category: category)) { section in
                switch section {
                case .group(let group):
                    InfoGroupSection(item: group, category: category, chinese: chinese, depth: 1)
                case .collection(let collection):
                    InfoCollectionSection(
                        collection: collection,
                        category: category,
                        chinese: chinese,
                        forceExpanded: forceExpanded,
                        depth: 1
                    )
                }
            }
        }
    }

    private var cornerRadius: CGFloat {
        compact && title != nil ? 12 : 14
    }

    private var background: Color {
        nested ? Color.primary.opacity(0.045) : Color(nsColor: .controlBackgroundColor)
    }

    private var stroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(nested ? 0.30 : 0.50))
    }
}

// MARK: - Nested dictionaries

private struct InfoGroupSection: View {
    let item: InfoItem
    let category: DeviceCategory
    let chinese: Bool
    let depth: Int

    private var title: String? {
        DeviceInfoFormatting.title(item.title, chinese: chinese)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.55)
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !item.fields.isEmpty {
                InfoFieldGrid(fields: item.fields, chinese: chinese, labelWidth: 138)
            }
            ForEach(orderedDetailSections(for: item, category: category)) { section in
                switch section {
                case .group(let group):
                    InfoGroupSection(item: group, category: category, chinese: chinese, depth: depth + 1)
                case .collection(let collection):
                    InfoCollectionSection(
                        collection: collection,
                        category: category,
                        chinese: chinese,
                        forceExpanded: false,
                        depth: depth + 1
                    )
                }
            }
        }
    }
}

// MARK: - Nested arrays

private struct InfoCollectionSection: View {
    let collection: InfoCollection
    let category: DeviceCategory
    let chinese: Bool
    let forceExpanded: Bool
    let depth: Int

    @ObservedObject private var locale = LocaleManager.shared
    @State private var showAll = false

    private var title: String? {
        DeviceInfoFormatting.title(collection.title, chinese: chinese)
    }

    private static let limit = 8

    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Divider().opacity(0.55)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            let visible = (forceExpanded || showAll)
                ? collection.items
                : Array(collection.items.prefix(Self.limit))

            ForEach(visible) { entry in
                InfoItemCard(
                    item: entry,
                    category: category,
                    chinese: chinese,
                    nested: true,
                    compact: collection.items.count > Self.limit,
                    forceExpanded: forceExpanded
                )
            }

            if collection.items.count > Self.limit, !forceExpanded {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showAll.toggle() }
                } label: {
                    Label(
                        showAll
                            ? t("Show Less")
                            : "\(t("Show All")) (\(collection.items.count))",
                        systemImage: showAll ? "chevron.up" : "chevron.down"
                    )
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
    }
}

// MARK: - Section order

/// Nested dictionaries and arrays are stored separately by the parser; the
/// renderer interleaves them again so the order follows the category's
/// preferred key order instead of "all dictionaries, then all arrays".
private enum InfoDetailSection: Identifiable {
    case group(InfoItem)
    case collection(InfoCollection)

    var id: String {
        switch self {
        case .group(let item): "g:\(item.id)"
        case .collection(let collection): "c:\(collection.id)"
        }
    }

    var rawKey: String? {
        switch self {
        case .group(let item): item.title?.rawValue
        case .collection(let collection): collection.rawKey
        }
    }
}

private func orderedDetailSections(
    for item: InfoItem,
    category: DeviceCategory
) -> [InfoDetailSection] {
    let groups = item.groups.map(InfoDetailSection.group)
    let collections = item.collections.map(InfoDetailSection.collection)
    return (groups + collections).sorted { lhs, rhs in
        let left = sectionRank(lhs.rawKey, category: category)
        let right = sectionRank(rhs.rawKey, category: category)
        if left.0 != right.0 { return left.0 < right.0 }
        return left.1.localizedStandardCompare(right.1) == .orderedAscending
    }
}

private func sectionRank(_ key: String?, category: DeviceCategory) -> (Int, String) {
    guard let key else { return (200_000, "") }
    if key == "_items" { return (200_000, key) }
    if let index = category.preferredKeyOrder.firstIndex(of: key) { return (index, key) }
    return (100_000, key)
}

// MARK: - Field grid

private struct InfoFieldGrid: View {
    let fields: [InfoField]
    let chinese: Bool
    let labelWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(fields) { field in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(DeviceInfoFormatting.fieldLabel(field.rawKey, chinese: chinese))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(field.rawKey)
                    FieldValueText(field: field, chinese: chinese)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct FieldValueText: View {
    let field: InfoField
    let chinese: Bool

    @ObservedObject private var locale = LocaleManager.shared
    @State private var expanded = false

    private var text: String {
        DeviceInfoFormatting.value(field, chinese: chinese)
    }

    private var isLong: Bool {
        text.count > 280 || text.filter { $0 == "\n" }.count > 3
    }

    private var isTechnical: Bool {
        isLong || DeviceInfoFormatting.isTechnicalField(field.rawKey)
    }

    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(isTechnical ? .system(.caption, design: .monospaced) : .callout)
                .foregroundStyle(text == "\u{2014}" ? Color.secondary : Color.primary)
                .textSelection(.enabled)
                .lineLimit(isLong && !expanded ? 4 : nil)
                .fixedSize(horizontal: false, vertical: true)

            if isLong {
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? t("Less") : t("More"))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
    }
}

// MARK: - Loading

private struct LoadingReportView: View {
    @ObservedObject private var locale = LocaleManager.shared

    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(t("Collecting information..."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 150, height: 13)
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.05))
                                .frame(width: 118, height: 9)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.05))
                                .frame(maxWidth: .infinity)
                                .frame(height: 9)
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4))
                }
            }
        }
        .accessibilityLabel(t("Collecting information..."))
    }
}

// MARK: - Tree helpers

extension InfoItem {
    /// Depth-first fields, used by the hardware summary to find the few keys
    /// it wants without knowing the nesting macOS used.
    var flattenedFields: [InfoField] {
        fields
            + groups.flatMap(\.flattenedFields)
            + collections.flatMap { $0.items.flatMap(\.flattenedFields) }
    }
}
