import SwiftUI

/// Groups used by the Device Information sidebar. The categories themselves
/// mirror `system_profiler -listDataTypes`; the groups are only a navigation
/// layer over those data types.
enum DeviceCategoryGroup: String, CaseIterable, Identifiable, Sendable {
    case machine
    case storage
    case network
    case media
    case software
    case system

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .machine: "Machine"
        case .storage: "Storage & Expansion"
        case .network: "Network"
        case .media: "Media & Devices"
        case .software: "Software"
        case .system: "System & Security"
        }
    }
}

/// One `system_profiler` data type (for example `SPHardwareDataType`).
///
/// The raw value *is* the argument handed to `system_profiler -json`, so the
/// category list cannot drift from the data it asks for.
enum DeviceCategory: String, CaseIterable, Identifiable, Sendable {
    case hardware = "SPHardwareDataType"
    case software = "SPSoftwareDataType"
    case displays = "SPDisplaysDataType"
    case memory = "SPMemoryDataType"
    case power = "SPPowerDataType"

    case storage = "SPStorageDataType"
    case nvme = "SPNVMeDataType"
    case pci = "SPPCIDataType"
    case usb = "SPUSBHostDataType"
    case thunderbolt = "SPThunderboltDataType"
    case cardReader = "SPCardReaderDataType"

    case network = "SPNetworkDataType"
    case wifi = "SPAirPortDataType"
    case ethernet = "SPEthernetDataType"
    case bluetooth = "SPBluetoothDataType"
    case firewall = "SPFirewallDataType"
    case networkLocations = "SPNetworkLocationDataType"

    case audio = "SPAudioDataType"
    case camera = "SPCameraDataType"
    case printers = "SPPrintersDataType"

    case applications = "SPApplicationsDataType"
    case extensions = "SPExtensionsDataType"
    case fonts = "SPFontsDataType"
    case frameworks = "SPFrameworksDataType"
    case installHistory = "SPInstallHistoryDataType"
    case configurationProfiles = "SPConfigurationProfileDataType"

    case accessibility = "SPUniversalAccessDataType"
    case secureElement = "SPSecureElementDataType"
    case smartCards = "SPSmartCardsDataType"
    case international = "SPInternationalDataType"
    case diagnostics = "SPDiagnosticsDataType"

    var id: String { rawValue }

    /// The value passed to `system_profiler`.
    var dataType: String { rawValue }

    var group: DeviceCategoryGroup {
        switch self {
        case .hardware, .software, .displays, .memory, .power:
            return .machine
        case .storage, .nvme, .pci, .usb, .thunderbolt, .cardReader:
            return .storage
        case .network, .wifi, .ethernet, .bluetooth, .firewall, .networkLocations:
            return .network
        case .audio, .camera, .printers:
            return .media
        case .applications, .extensions, .fonts, .frameworks, .installHistory, .configurationProfiles:
            return .software
        case .accessibility, .secureElement, .smartCards, .international, .diagnostics:
            return .system
        }
    }

    static func categories(in group: DeviceCategoryGroup) -> [DeviceCategory] {
        allCases.filter { $0.group == group }
    }

    /// Localization key, also used as the English display name.
    var titleKey: String {
        switch self {
        case .hardware: "Hardware"
        case .software: "Software"
        case .displays: "Displays"
        case .memory: "Memory"
        case .power: "Power"
        case .storage: "Storage"
        case .nvme: "NVMe"
        case .pci: "PCI"
        case .usb: "USB"
        case .thunderbolt: "Thunderbolt"
        case .cardReader: "Card Reader"
        case .network: "Network"
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .bluetooth: "Bluetooth"
        case .firewall: "Firewall"
        case .networkLocations: "Network Locations"
        case .audio: "Audio"
        case .camera: "Camera"
        case .printers: "Printers"
        case .applications: "Applications"
        case .extensions: "Extensions"
        case .fonts: "Fonts"
        case .frameworks: "Frameworks"
        case .installHistory: "Install History"
        case .configurationProfiles: "Configuration Profiles"
        case .accessibility: "Accessibility"
        case .secureElement: "Secure Element"
        case .smartCards: "Smart Cards"
        case .international: "International"
        case .diagnostics: "Diagnostics"
        }
    }

    var icon: String {
        switch self {
        case .hardware: "desktopcomputer"
        case .software: "gearshape.2"
        case .displays: "display"
        case .memory: "memorychip"
        case .power: "bolt.fill"
        case .storage: "internaldrive"
        case .nvme: "internaldrive"
        case .pci: "square.grid.3x1.below.line.grid.1x2"
        case .usb: "cable.connector"
        case .thunderbolt: "bolt.horizontal.circle"
        case .cardReader: "sdcard"
        case .network: "network"
        case .wifi: "wifi"
        case .ethernet: "cable.connector.horizontal"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .firewall: "shield.lefthalf.filled"
        case .networkLocations: "mappin.and.ellipse"
        case .audio: "hifispeaker.2"
        case .camera: "camera"
        case .printers: "printer"
        case .applications: "app.badge"
        case .extensions: "puzzlepiece.extension"
        case .fonts: "textformat"
        case .frameworks: "shippingbox"
        case .installHistory: "clock.arrow.circlepath"
        case .configurationProfiles: "doc.badge.gearshape"
        case .accessibility: "figure.stand"
        case .secureElement: "lock.shield"
        case .smartCards: "creditcard"
        case .international: "globe"
        case .diagnostics: "stethoscope"
        }
    }

    var tint: Color {
        switch self {
        case .hardware: .blue
        case .software: .purple
        case .displays: .teal
        case .memory: .indigo
        case .power: .orange
        case .storage: .indigo
        case .nvme: .indigo
        case .pci: .purple
        case .usb: .teal
        case .thunderbolt: .yellow
        case .cardReader: .orange
        case .network: .green
        case .wifi: .green
        case .ethernet: .mint
        case .bluetooth: .blue
        case .firewall: .red
        case .networkLocations: .cyan
        case .audio: .pink
        case .camera: .purple
        case .printers: .brown
        case .applications: .blue
        case .extensions: .purple
        case .fonts: .pink
        case .frameworks: .indigo
        case .installHistory: .teal
        case .configurationProfiles: .orange
        case .accessibility: .green
        case .secureElement: .red
        case .smartCards: .orange
        case .international: .cyan
        case .diagnostics: .teal
        }
    }

    /// Human-friendly ordering for the fields macOS emits. Unknown keys sort
    /// alphabetically after these, so output is stable between launches.
    var preferredKeyOrder: [String] {
        switch self {
        case .hardware:
            ["machine_name", "chip_type", "machine_model", "model_number", "physical_memory",
             "serial_number", "activation_lock_status", "number_processors", "platform_UUID",
             "provisioning_UDID", "boot_rom_version", "os_loader_version"]
        case .software:
            ["os_version", "kernel_version", "boot_volume", "boot_mode", "local_host_name",
             "user_name", "uptime", "system_integrity", "secure_vm"]
        case .displays:
            ["sppci_model", "spdisplays_vendor", "sppci_cores", "spdisplays_mtlgpufamilysupport",
             "sppci_device_type", "sppci_bus", "spdisplays_ndrvs"]
        case .memory:
            ["SPMemoryDataType", "dimm_type", "dimm_manufacturer"]
        case .power:
            ["sppower_battery_state_of_charge", "sppower_battery_is_charging",
             "sppower_battery_fully_charged", "sppower_battery_at_warn_level",
             "sppower_battery_health", "sppower_battery_cycle_count",
             "sppower_battery_health_maximum_capacity", "sppower_battery_charger_connected",
             "Current Power Source", "LowPowerMode", "System Sleep Timer", "Display Sleep Timer",
             "Disk Sleep Timer", "Hibernate Mode", "Wake On LAN", "Sleep On Power Button",
             "PrioritizeNetworkReachabilityOverSleep", "ReduceBrightness"]
        case .storage:
            ["file_system", "mount_point", "bsd_name", "size_in_bytes", "free_space_in_bytes",
             "volume_uuid", "writable", "ignore_ownership", "physical_drive"]
        case .nvme:
            ["device_model", "bsd_name", "detachable_drive", "is_internal_disk", "protocol",
             "medium_type", "smart_status", "partition_map_type"]
        case .network:
            ["type", "hardware", "interface", "spnetwork_service_order", "MAC Address",
             "ip_address", "ConfigMethod", "ServerAddresses", "Ethernet", "IPv4", "IPv6",
             "Proxies", "DNS", "dhcp"]
        case .wifi:
            ["spairport_status_information", "spairport_current_network_information",
             "spairport_wireless_card_type", "spairport_supported_phymodes",
             "spairport_supported_channels", "spairport_airport_interfaces",
             "spairport_software_information", "spairport_airport_other_local_wireless_networks"]
        case .bluetooth:
            ["controller_chipset", "controller_address", "controller_state", "controller_transport",
             "controller_firmwareVersion", "controller_vendorID", "controller_productID",
             "controller_supportedServices", "device_connected", "device_not_connected"]
        case .usb:
            ["USBKeyHardwareType", "USBKeyLocationID", "Driver"]
        case .thunderbolt:
            ["device_name_key", "vendor_name_key", "current_speed_key", "receptacle_status_key",
             "receptacle_id_key", "link_status_key", "route_string_key"]
        case .audio:
            ["coreaudio_device_manufacturer", "coreaudio_device_transport", "coreaudio_device_srate",
             "coreaudio_device_input", "coreaudio_device_output",
             "coreaudio_default_audio_input_device", "coreaudio_default_audio_output_device",
             "coreaudio_default_audio_system_device"]
        case .camera:
            ["spcamera_model-id", "spcamera_unique-id"]
        case .applications:
            ["version", "obtained_from", "arch_kind", "lastModified", "path", "signed_by", "info"]
        case .extensions:
            ["spext_version", "version", "spext_loaded", "spext_loadable", "spext_bundleid",
             "spext_signed_by", "spext_lastModified", "spext_architectures", "spext_path",
             "spext_has64BitIntelCode", "spext_hasAllDependencies"]
        case .fonts:
            ["family", "style", "fullname", "type", "enabled", "valid", "path", "typefaces",
             "vendor", "version", "designer", "copyright"]
        case .frameworks:
            ["version", "private_framework", "obtained_from", "lastModified", "path"]
        case .installHistory:
            ["install_version", "install_date", "package_source"]
        case .configurationProfiles:
            ["spconfigprofile_install_date", "spconfigprofile_install_source",
             "spconfigprofile_profile_identifier", "spconfigprofile_version",
             "spconfigprofile_verification_state", "spconfigprofile_RemovalDisallowed"]
        case .accessibility:
            ["voiceover", "zoomMode", "scrollZoom", "cursor_mag", "display", "contrast",
             "sticky_keys", "slow_keys", "mouse_keys", "keyboardZoom", "flash_screen"]
        case .international:
            ["user_locale", "user_language_code", "user_country_code", "user_calendar",
             "user_preferred_interface_languages", "user_current_input_source",
             "user_assistant_language", "user_assistant_voice_language",
             "user_assistant_voice_gender", "user_uses_metric_system"]
        case .smartCards, .secureElement:
            []
        case .pci, .cardReader, .firewall, .networkLocations, .printers, .diagnostics, .ethernet:
            []
        }
    }

    /// Keys that the collapsed "many items" list can use as a one-line
    /// subtitle when they exist.
    var summaryRowKeys: [String] {
        switch self {
        case .applications: ["version", "path"]
        case .extensions: ["spext_version", "version", "spext_path"]
        case .fonts: ["path", "family", "type"]
        case .frameworks: ["version", "path"]
        case .installHistory: ["install_version", "install_date"]
        case .configurationProfiles: ["spconfigprofile_version", "spconfigprofile_profile_identifier"]
        default: ["version", "family", "path", "type", "status"]
        }
    }
}
