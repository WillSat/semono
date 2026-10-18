import Foundation
import Testing
@testable import Semono

struct DeviceInfoParserTests {
    private func report(
        _ json: String,
        _ category: DeviceCategory
    ) throws -> DeviceReport {
        try SystemProfilerReportBuilder.build(
            category: category,
            json: Data(json.utf8),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func hardwareFieldsAreOrderedForReading() throws {
        let json = #"""
        {"SPHardwareDataType":[{"_name":"hardware_overview","serial_number":"SN123",
        "machine_name":"MacBook Air","chip_type":"Apple M5","physical_memory":"16 GB",
        "model_number":"MDH74CH/A","machine_model":"Mac17,3"}]}
        """#
        let report = try report(json, .hardware)
        #expect(report.items.count == 1)

        let item = try #require(report.items.first)
        #expect(item.title == .literal("hardware_overview"))
        #expect(item.fields.map(\.rawKey) == [
            "machine_name", "chip_type", "machine_model", "model_number",
            "physical_memory", "serial_number",
        ])
    }

    @Test func nestedDictionaryBecomesAKeyedGroup() throws {
        let json = #"""
        {"SPStorageDataType":[{"_name":"Macintosh HD","mount_point":"/",
        "size_in_bytes":494332366848,"free_space_in_bytes":275235905536,
        "physical_drive":{"device_name":"APPLE SSD AP0512Z","is_internal_disk":"yes",
        "medium_type":"ssd"}}]}
        """#
        let report = try report(json, .storage)
        let item = try #require(report.items.first)

        #expect(item.fields.first(where: { $0.rawKey == "size_in_bytes" })?.value == .bytes(494332366848))
        #expect(item.fields.first(where: { $0.rawKey == "mount_point" })?.value == .scalar("/"))

        let drive = try #require(item.groups.first)
        #expect(drive.title == .key("physical_drive"))
        #expect(drive.fields.first(where: { $0.rawKey == "medium_type" })?.value == .scalar("ssd"))
    }

    @Test func arrayOfDictionariesBecomesACollection() throws {
        let json = #"""
        {"SPDisplaysDataType":[{"_name":"Apple M5","sppci_model":"Apple M5",
        "spdisplays_ndrvs":[{"_name":"Color LCD","spdisplays_main":"spdisplays_yes",
        "_spdisplays_resolution":"1710 x 1112 @ 60.00Hz"}]}]}
        """#
        let report = try report(json, .displays)
        let item = try #require(report.items.first)

        let collection = try #require(item.collections.first)
        #expect(collection.title == .key("spdisplays_ndrvs"))
        #expect(collection.items.count == 1)
        #expect(collection.items.first?.title == .literal("Color LCD"))
        #expect(collection.items.first?.fields.first(where: {
            $0.rawKey == "_spdisplays_resolution"
        })?.value == .scalar("1710 x 1112 @ 60.00Hz"))
    }

    @Test func bluetoothDeviceWrapperKeepsTheDeviceNameAsTitle() throws {
        let json = #"""
        {"SPBluetoothDataType":[{"controller_chipset":"Apple N1",
        "device_connected":[{"Will's AirPods":{"device_address":"AA:BB:CC",
        "device_rssi":"-45"}}]}]}
        """#
        let report = try report(json, .bluetooth)
        let item = try #require(report.items.first)
        let collection = try #require(item.collections.first)

        #expect(collection.title == .key("device_connected"))
        let device = try #require(collection.items.first)
        #expect(device.title == .literal("Will's AirPods"))
        #expect(device.fields.first(where: { $0.rawKey == "device_address" })?.value == .scalar("AA:BB:CC"))
    }

    @Test func audioRootItemsAreFlattened() throws {
        let json = #"""
        {"SPAudioDataType":[{"_items":[
            {"_name":"MacBook Air Speakers","coreaudio_device_manufacturer":"Apple Inc."},
            {"_name":"AirPods","coreaudio_device_manufacturer":"Apple Inc."}
        ]}]}
        """#
        let report = try report(json, .audio)
        #expect(report.items.count == 2)
        #expect(report.items.map(\.title) == [.literal("MacBook Air Speakers"), .literal("AirPods")])
    }

    @Test func emptyAndMissingDataTypesProduceAnEmptyReport() throws {
        #expect(try report(#"{"SPCardReaderDataType":[]}"#, .cardReader).items.isEmpty)
        #expect(try report("{}", .diagnostics).items.isEmpty)
    }

    @Test func datesAndNumbersAreTyped() throws {
        let json = #"""
        {"SPInstallHistoryDataType":[{"_name":"macOS 27.0",
        "install_date":"2026-06-15T11:03:25Z","install_version":"27.0"}]}
        """#
        let report = try report(json, .installHistory)
        let field = try #require(report.items.first?.fields.first(where: { $0.rawKey == "install_date" }))

        guard case .date(let date) = field.value else {
            Issue.record("Expected a parsed date, got \(field.value)")
            return
        }
        #expect(date.timeIntervalSince1970 == 1_781_521_405)
    }

    @Test func invalidJSONThrows() {
        #expect(throws: SystemProfilerParseError.self) {
            try SystemProfilerReportBuilder.build(category: .hardware, json: Data("not json".utf8))
        }
    }

    @Test func nestedNameStaysVisibleWhenTheEnclosingKeyIsTheTitle() throws {
        let json = #"""
        {"SPAirPortDataType":[{"spairport_airport_interfaces":[{"_name":"en0",
        "spairport_current_network_information":{"_name":"Will's iPhone",
        "spairport_network_rate":1200}}]}]}
        """#
        let report = try report(json, .wifi)
        let item = try #require(report.items.first)
        let entry = try #require(item.collections.first?.items.first)
        let group = try #require(entry.groups.first)

        #expect(group.title == .key("spairport_current_network_information"))
        #expect(group.fields.first(where: { $0.rawKey == "_name" })?.value == .scalar("Will's iPhone"))
        #expect(group.fields.first(where: { $0.rawKey == "spairport_network_rate" })?.value == .number(1200))
    }

    @Test func extensionModificationDatesAreTyped() throws {
        let json = #"""
        {"SPExtensionsDataType":[{"_name":"AppleA7IOP",
        "spext_lastModified":"2026-10-10T14:42:06Z","spext_version":"1.0"}]}
        """#
        let report = try report(json, .extensions)
        let field = try #require(report.items.first?.fields.first(where: { $0.rawKey == "spext_lastModified" }))
        guard case .date = field.value else {
            Issue.record("Expected a parsed date, got \(field.value)")
            return
        }
    }

    @Test func rootArrayWithoutNamesKeepsFieldsVisible() throws {
        let json = #"{"SPMemoryDataType":[{"dimm_manufacturer":"Micron","dimm_type":"LPDDR5","SPMemoryDataType":"16 GB"}]}"#
        let report = try report(json, .memory)
        let item = try #require(report.items.first)
        #expect(item.title == nil)
        #expect(item.fields.map(\.rawKey) == ["SPMemoryDataType", "dimm_type", "dimm_manufacturer"])
    }
}

struct DeviceInfoFormattingTests {
    @Test func fieldLabelsUseTheLocalizedTable() {
        #expect(DeviceInfoFormatting.fieldLabel("physical_memory", chinese: false) == "Memory")
        #expect(DeviceInfoFormatting.fieldLabel("physical_memory", chinese: true) == "内存")
        #expect(DeviceInfoFormatting.fieldLabel("machine_model", chinese: false) == "Model Identifier")
        #expect(DeviceInfoFormatting.fieldLabel("machine_model", chinese: true) == "机型标识符")
        #expect(DeviceInfoFormatting.fieldLabel("_spdisplays_resolution", chinese: false) == "Resolution")
        #expect(DeviceInfoFormatting.fieldLabel("controller_firmwareVersion", chinese: false) == "Firmware")
        #expect(DeviceInfoFormatting.fieldLabel("USBKeyHardwareType", chinese: false) == "Hardware Type")
    }

    @Test func unknownKeysAreHumanized() {
        #expect(DeviceInfoFormatting.fieldLabel("number_processors", chinese: false) == "Processors")
        #expect(DeviceInfoFormatting.fieldLabel("some_unknown_key", chinese: false) == "Some Unknown Key")
        #expect(DeviceInfoFormatting.fieldLabel("someUnknownKey", chinese: false) == "Some Unknown Key")
        #expect(DeviceInfoFormatting.fieldLabel("spdisplays_vendor", chinese: false) == "Vendor")
    }

    @Test func vendorTokensAreTranslated() {
        #expect(DeviceInfoFormatting.rawValue(.scalar("spdisplays_yes"), rawKey: "spdisplays_main", chinese: false) == "Yes")
        #expect(DeviceInfoFormatting.rawValue(.scalar("spdisplays_yes"), rawKey: "spdisplays_main", chinese: true) == "是")
        #expect(DeviceInfoFormatting.rawValue(.scalar("attrib_on"), rawKey: "controller_state", chinese: false) == "On")
        #expect(DeviceInfoFormatting.rawValue(.scalar("spairport_security_mode_wpa2_personal"), rawKey: "spairport_security_mode", chinese: false) == "WPA2 Personal")
        #expect(DeviceInfoFormatting.rawValue(.scalar("coreaudio_device_type_bluetooth"), rawKey: "coreaudio_device_transport", chinese: true) == "蓝牙")
        #expect(DeviceInfoFormatting.rawValue(.scalar("ssd"), rawKey: "medium_type", chinese: true) == "固态硬盘")
    }

    @Test func unknownPrefixedTokenIsHumanizedButUserTextIsNot() {
        #expect(DeviceInfoFormatting.rawValue(.scalar("spdisplays_some_new_mode"), rawKey: "mode", chinese: false) == "Some New Mode")
        #expect(DeviceInfoFormatting.rawValue(.scalar("Will's AirPods"), rawKey: "_name", chinese: false) == "Will's AirPods")
        #expect(DeviceInfoFormatting.rawValue(.scalar("/System/Library/Fonts/Supplemental/X.ttf"), rawKey: "path", chinese: false) == "/System/Library/Fonts/Supplemental/X.ttf")
    }

    @Test func pixelResolutionGetsSpacesAroundTheMultiplicationSign() {
        #expect(DeviceInfoFormatting.rawValue(
            .scalar("2560x1664Retina"),
            rawKey: "spdisplays_pixelresolution",
            chinese: false
        ) == "2560 × 1664 Retina")
        #expect(DeviceInfoFormatting.rawValue(
            .scalar("1710 x 1112 @ 60.00Hz"),
            rawKey: "_spdisplays_resolution",
            chinese: false
        ) == "1710 x 1112 @ 60.00Hz")
    }

    @Test func numbersGetContextualUnits() {
        #expect(DeviceInfoFormatting.rawValue(.number(48000), rawKey: "coreaudio_device_srate", chinese: false) == "48 kHz")
        #expect(DeviceInfoFormatting.rawValue(.number(44100), rawKey: "coreaudio_device_srate", chinese: false) == "44.1 kHz")
        #expect(DeviceInfoFormatting.rawValue(.number(864), rawKey: "spairport_network_rate", chinese: false) == "864 Mbps")
        #expect(DeviceInfoFormatting.rawValue(.number(90), rawKey: "sppower_battery_state_of_charge", chinese: false) == "90%")
    }

    @Test func byteCountsUseDecimalUnits() {
        #expect(DeviceInfoFormatting.rawValue(.bytes(275235905536), rawKey: "free_space_in_bytes", chinese: false) == "275.2 GB")
        #expect(DeviceInfoFormatting.rawValue(.bytes(494332366848), rawKey: "size_in_bytes", chinese: false) == "494.3 GB")
        #expect(DeviceInfoFormatting.rawValue(.bytes(999), rawKey: "size_in_bytes", chinese: false) == "999 B")
        #expect(DeviceInfoFormatting.rawValue(.bytes(0), rawKey: "size_in_bytes", chinese: false) == "0 B")
    }

    @Test func booleansAndEmptyValues() {
        #expect(DeviceInfoFormatting.rawValue(.boolean(true), rawKey: "enabled", chinese: false) == "Yes")
        #expect(DeviceInfoFormatting.rawValue(.boolean(false), rawKey: "enabled", chinese: true) == "否")
        #expect(DeviceInfoFormatting.rawValue(.scalar("  "), rawKey: "info", chinese: false) == "\u{2014}")
        #expect(DeviceInfoFormatting.rawValue(.list([]), rawKey: "signed_by", chinese: false) == "None")
    }

    @Test func datesFormatWithTheSelectedUILanguage() {
        let date = Date(timeIntervalSince1970: 1_781_521_405)
        let english = DeviceInfoFormatting.rawValue(.date(date), rawKey: "install_date", chinese: false)
        let chinese = DeviceInfoFormatting.rawValue(.date(date), rawKey: "install_date", chinese: true)
        #expect(english.contains("2026"))
        #expect(chinese.contains("2026"))
        #expect(english != chinese)
    }

    @Test func titlesAreReadable() {
        #expect(DeviceInfoFormatting.title(.literal("hardware_overview"), chinese: false) == "Hardware Overview")
        #expect(DeviceInfoFormatting.title(.literal("hardware_overview"), chinese: true) == "硬件概览")
        #expect(DeviceInfoFormatting.title(.key("spdisplays_ndrvs"), chinese: false) == "Displays")
        #expect(DeviceInfoFormatting.title(.literal("Color LCD"), chinese: false) == "Color LCD")
        #expect(DeviceInfoFormatting.title(.index(3), chinese: false) == "Item 3")
    }
}

struct DeviceInfoSearchTests {
    private func report() throws -> DeviceReport {
        let json = #"""
        {"SPHardwareDataType":[
            {"_name":"hardware_overview","machine_name":"MacBook Air","chip_type":"Apple M5",
             "physical_memory":"16 GB","serial_number":"SN123","machine_model":"Mac17,3"},
            {"_name":"Other Mac","machine_name":"Mac mini","chip_type":"Apple M2",
             "physical_memory":"8 GB","serial_number":"SN999","machine_model":"Mac14,3"}
        ]}
        """#
        return try SystemProfilerReportBuilder.build(category: .hardware, json: Data(json.utf8))
    }

    @Test func matchingParentKeepsTheWholeItem() throws {
        let items = try report().items.compactMap { $0.filtered(by: "MacBook", chinese: false) }
        #expect(items.count == 1)
        // `_name` became the title, so five rows remain.
        #expect(items.first?.fields.count == 5)
    }

    @Test func matchesFieldLabelsInTheSelectedLanguage() throws {
        let items = try report().items.compactMap { $0.filtered(by: "内存", chinese: true) }
        #expect(items.count == 2)

        let english = try report().items.compactMap { $0.filtered(by: "Memory", chinese: false) }
        #expect(english.count == 2)
    }

    @Test func matchesValuesAndMissesEmptyResults() throws {
        #expect(try report().items.compactMap { $0.filtered(by: "Mac14,3", chinese: false) }.count == 1)
        #expect(try report().items.compactMap { $0.filtered(by: "Windows", chinese: false) }.isEmpty)
    }

    @Test func emptyQueryKeepsEverything() throws {
        #expect(try report().items.compactMap { $0.filtered(by: "   ", chinese: false) }.count == 2)
    }
}

struct DeviceCategoryTests {
    @Test func everyCategoryMapsToAUniqueProfilerDataType() {
        let dataTypes = DeviceCategory.allCases.map(\.dataType)
        #expect(Set(dataTypes).count == dataTypes.count)
        #expect(dataTypes.allSatisfy { $0.hasPrefix("SP") })
    }

    @Test func everySidebarGroupHasCategories() {
        for group in DeviceCategoryGroup.allCases {
            #expect(!DeviceCategory.categories(in: group).isEmpty)
        }
    }
}
