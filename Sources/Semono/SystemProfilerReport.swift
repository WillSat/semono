import Foundation

// MARK: - Display tree

/// A parsed value ready to be rendered. Units, dates and byte counts are kept
/// typed here so formatting (including localization) happens at display time
/// instead of being baked into the cached report.
enum InfoValue: Equatable, Sendable {
    case scalar(String)
    case number(Double)
    case boolean(Bool)
    case bytes(Int64)
    case date(Date)
    case list([String])
}

enum InfoTitle: Equatable, Sendable {
    /// A `_name` from system_profiler, or a single-key container name.
    case literal(String)
    /// A dictionary key; translated through the field-label table.
    case key(String)
    /// Positional fallback for an unnamed list element.
    case index(Int)

    var rawValue: String? {
        switch self {
        case .literal(let value), .key(let value): value
        case .index: nil
        }
    }
}

struct InfoField: Equatable, Identifiable, Sendable {
    let id: String
    let rawKey: String
    let value: InfoValue
}

struct InfoCollection: Equatable, Identifiable, Sendable {
    let id: String
    let title: InfoTitle?
    let rawKey: String
    var items: [InfoItem]
}

struct InfoItem: Equatable, Identifiable, Sendable {
    let id: String
    var title: InfoTitle?
    var fields: [InfoField]
    var groups: [InfoItem]
    var collections: [InfoCollection]

    var isEmpty: Bool {
        fields.isEmpty && groups.isEmpty && collections.isEmpty
    }
}

struct DeviceReport: Equatable, Sendable {
    let category: DeviceCategory
    let items: [InfoItem]
    let fetchedAt: Date
}

// MARK: - Parser

enum SystemProfilerParseError: LocalizedError {
    case invalidJSON(String)
    case unexpectedRoot

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message):
            return "system_profiler returned invalid JSON: \(message)"
        case .unexpectedRoot:
            return "system_profiler returned an unexpected document."
        }
    }
}

enum SystemProfilerReportBuilder {
    /// Builds the display tree from the JSON emitted by
    /// `system_profiler -json <dataType>`.
    static func build(
        category: DeviceCategory,
        json: Data,
        now: Date = .now
    ) throws -> DeviceReport {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: json)
        } catch {
            throw SystemProfilerParseError.invalidJSON(error.localizedDescription)
        }
        guard let root = object as? [String: Any] else {
            throw SystemProfilerParseError.unexpectedRoot
        }
        return build(category: category, root: root, now: now)
    }

    static func build(
        category: DeviceCategory,
        root: [String: Any],
        now: Date = .now
    ) -> DeviceReport {
        let rawItems: [Any]
        if let array = root[category.dataType] as? [Any] {
            rawItems = array
        } else if let dictionary = root[category.dataType] as? [String: Any] {
            rawItems = [dictionary]
        } else {
            rawItems = []
        }

        var items: [InfoItem] = []
        for (index, raw) in rawItems.enumerated() {
            items.append(contentsOf: topLevelItems(raw, index: index, path: "\(index)", category: category))
        }
        return DeviceReport(category: category, items: items, fetchedAt: now)
    }

    // MARK: Items

    /// Root elements that only wrap an `_items` array (the audio report does
    /// this) are flattened so the window does not show an empty card around
    /// the actual devices.
    private static func topLevelItems(
        _ raw: Any,
        index: Int,
        path: String,
        category: DeviceCategory
    ) -> [InfoItem] {
        guard let dictionary = raw as? [String: Any] else { return [] }
        if dictionary["_name"] == nil,
           dictionary.keys.allSatisfy({ $0 == "_items" }),
           let children = dictionary["_items"] as? [Any] {
            return children.enumerated().flatMap { childIndex, child in
                topLevelItems(child, index: childIndex, path: "\(path).\(childIndex)", category: category)
            }
        }
        return [makeItem(dictionary, explicitTitle: nil, path: path, category: category)]
    }

    private static func makeEntry(
        _ raw: Any,
        index: Int,
        path: String,
        category: DeviceCategory
    ) -> InfoItem? {
        guard let original = raw as? [String: Any] else { return nil }

        var dictionary = original
        var explicitTitle: InfoTitle?

        // Bluetooth lists connected devices as `[{"AirPods": {...}}]`; the
        // wrapper key is the device name, not a field label.
        if original["_name"] == nil, original.count == 1, let (key, value) = original.first {
            if let nested = value as? [String: Any] {
                dictionary = nested
                explicitTitle = .literal(key)
            } else if let array = value as? [Any], array.allSatisfy({ $0 is [String: Any] }) {
                dictionary = [:]
                explicitTitle = .literal(key)
                let collection = makeCollection(
                    key: "_items",
                    array: array,
                    path: "\(path).c._items",
                    category: category
                )
                return InfoItem(
                    id: path,
                    title: explicitTitle,
                    fields: [],
                    groups: [],
                    collections: collection.map { [$0] } ?? []
                )
            }
        }

        var item = makeItem(dictionary, explicitTitle: explicitTitle, path: path, category: category)
        if item.title == nil, !item.isEmpty {
            item.title = .index(index + 1)
        }
        return item
    }

    /// Builds one card. An explicit title comes from the enclosing key (or a
    /// device wrapper); when it is present, a nested `_name` stays visible as
    /// a normal "Name" row.
    private static func makeItem(
        _ dictionary: [String: Any],
        explicitTitle: InfoTitle?,
        path: String,
        category: DeviceCategory
    ) -> InfoItem {
        var title = explicitTitle
        var nameBecameTitle = false
        if title == nil, let name = dictionary["_name"] as? String, !name.isEmpty {
            title = .literal(name)
            nameBecameTitle = true
        }

        var fields: [InfoField] = []
        var groups: [InfoItem] = []
        var collections: [InfoCollection] = []

        let keys = orderedKeys(
            dictionary.keys.filter { $0 != "_items" },
            category: category
        )
        for key in keys {
            guard let raw = dictionary[key] else { continue }
            // `_name` already became the title for top-level items.
            if key == "_name", nameBecameTitle {
                continue
            }
            // NVMe reports the drive size twice; the typed byte count is
            // richer (sortable, localized) than the preformatted string.
            if key == "size", dictionary["size_in_bytes"] != nil {
                continue
            }
            let fieldID = "\(path).f.\(key)"

            if let nested = raw as? [String: Any] {
                if nested.isEmpty {
                    fields.append(InfoField(id: fieldID, rawKey: key, value: .scalar("")))
                } else {
                    groups.append(makeItem(
                        nested,
                        explicitTitle: .key(key),
                        path: "\(path).g.\(key)",
                        category: category
                    ))
                }
                continue
            }

            if let array = raw as? [Any] {
                if array.allSatisfy({ !($0 is [String: Any]) && !($0 is [Any]) }) {
                    fields.append(InfoField(
                        id: fieldID,
                        rawKey: key,
                        value: .list(array.map { scalarString($0) })
                    ))
                } else if let collection = makeCollection(
                    key: key,
                    array: array,
                    path: "\(path).c.\(key)",
                    category: category
                ) {
                    collections.append(collection)
                } else {
                    fields.append(InfoField(id: fieldID, rawKey: key, value: .list([])))
                }
                continue
            }

            fields.append(InfoField(
                id: fieldID,
                rawKey: key,
                value: value(for: key, raw: raw)
            ))
        }

        if let items = dictionary["_items"] as? [Any],
           let collection = makeCollection(
               key: "_items",
               array: items,
               path: "\(path).c._items",
               category: category
           ) {
            collections.append(collection)
        }

        return InfoItem(
            id: path,
            title: title,
            fields: fields,
            groups: groups,
            collections: collections
        )
    }

    private static func makeCollection(
        key: String,
        array: [Any],
        path: String,
        category: DeviceCategory
    ) -> InfoCollection? {
        let items = array.enumerated().compactMap { index, raw in
            makeEntry(raw, index: index, path: "\(path).\(index)", category: category)
        }
        guard !items.isEmpty else { return nil }
        return InfoCollection(
            id: path,
            title: key == "_items" ? nil : .key(key),
            rawKey: key,
            items: items
        )
    }

    // MARK: Values

    private static func value(for key: String, raw: Any) -> InfoValue {
        if raw is NSNull {
            return .scalar("")
        }
        if let string = raw as? String {
            if let date = dateValue(for: key, string: string) {
                return .date(date)
            }
            return .scalar(string)
        }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            if isByteCountKey(key) {
                return .bytes(number.int64Value)
            }
            return .number(number.doubleValue)
        }
        if let array = raw as? [Any] {
            return .list(array.map { scalarString($0) })
        }
        return .scalar(scalarString(raw))
    }

    private static func scalarString(_ raw: Any) -> String {
        if raw is NSNull { return "" }
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let double = number.doubleValue
            if double == double.rounded(), abs(double) < Double(Int64.max) {
                return String(number.int64Value)
            }
            return String(double)
        }
        return String(describing: raw)
    }

    private static func isByteCountKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return lowered.hasSuffix("_bytes")
            || lowered.hasSuffix("bytesize")
            || lowered == "bytes"
    }

    private static func dateValue(for key: String, string: String) -> Date? {
        let lowered = key.lowercased()
        guard lowered.contains("date")
                || lowered.contains("lastmodified")
                || lowered.contains("last_modified")
                || lowered == "time"
        else { return nil }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10, trimmed.contains("-") else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

    // MARK: Ordering

    private static let globalKeyOrder: [String] = [
        "machine_name", "chip_type", "os_version", "kernel_version", "serial_number",
        "MAC Address", "name", "type", "interface", "status", "model", "family", "style",
        "version", "path", "lastModified", "install_date", "current_speed_key",
        "receptacle_status_key", "controller_chipset",
    ]

    private static func orderedKeys<S: Sequence>(
        _ keys: S,
        category: DeviceCategory
    ) -> [String] where S.Element == String {
        let preferred = category.preferredKeyOrder
        return keys.sorted { lhs, rhs in
            let leftRank = rank(of: lhs, preferred: preferred)
            let rightRank = rank(of: rhs, preferred: preferred)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private static func rank(of key: String, preferred: [String]) -> Int {
        if let index = preferred.firstIndex(of: key) { return index }
        if let index = globalKeyOrder.firstIndex(of: key) { return 10_000 + index }
        return 100_000
    }
}

// MARK: - Filtering

extension InfoItem {
    /// Keeps the item when it, or any descendant, contains `query`. A matching
    /// parent is returned whole so context is not stripped away; a parent that
    /// only contains a matching child keeps its own fields and only the
    /// matching descendants.
    func filtered(by query: String, chinese: Bool) -> InfoItem? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }

        if matches(trimmed, chinese: chinese) { return self }

        var copy = self
        copy.groups = groups.compactMap { $0.filtered(by: trimmed, chinese: chinese) }
        copy.collections = collections.compactMap { $0.filtered(by: trimmed, chinese: chinese) }
        if copy.groups.isEmpty, copy.collections.isEmpty { return nil }
        return copy
    }

    private func matches(_ query: String, chinese: Bool) -> Bool {
        if let title = DeviceInfoFormatting.title(title, chinese: chinese),
           title.localizedCaseInsensitiveContains(query) {
            return true
        }
        for field in fields {
            let label = DeviceInfoFormatting.fieldLabel(field.rawKey, chinese: chinese)
            let value = DeviceInfoFormatting.value(field, chinese: chinese)
            if label.localizedCaseInsensitiveContains(query)
                || value.localizedCaseInsensitiveContains(query)
                || field.rawKey.localizedCaseInsensitiveContains(query) {
                return true
            }
        }
        return false
    }
}

extension InfoCollection {
    func filtered(by query: String, chinese: Bool) -> InfoCollection? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        if let title = DeviceInfoFormatting.title(title, chinese: chinese),
           title.localizedCaseInsensitiveContains(trimmed) {
            return self
        }
        let filteredItems = items.compactMap { $0.filtered(by: trimmed, chinese: chinese) }
        guard !filteredItems.isEmpty else { return nil }
        var copy = self
        copy.items = filteredItems
        return copy
    }
}
