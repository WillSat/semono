import Foundation

/// All display formatting for the Device Information window. Raw keys and
/// values stay in the cached report; this is the single place where they are
/// turned into localized, human-readable text.
enum DeviceInfoFormatting {

    // MARK: Titles

    static func title(_ title: InfoTitle?, chinese: Bool) -> String? {
        switch title {
        case .none:
            return nil
        case .literal(let value):
            return literal(value, chinese: chinese)
        case .key(let key):
            return fieldLabel(key, chinese: chinese)
        case .index(let index):
            return chinese ? "项目 \(index)" : "Item \(index)"
        }
    }

    /// A `_name` is either a system identifier (`hardware_overview`) or a
    /// user-facing device name ("Color LCD"). Only the former is rewritten.
    private static func literal(_ value: String, chinese: Bool) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let label = identifierLabels[trimmed.lowercased()] {
            return chinese ? label.zh : label.en
        }
        if trimmed.contains("_"), !trimmed.contains(" ") {
            return humanizeKey(trimmed)
        }
        return trimmed
    }

    // MARK: Field labels

    static func fieldLabel(_ key: String, chinese: Bool) -> String {
        if let label = keyLabels[key] {
            return chinese ? label.zh : label.en
        }
        if let label = keyLabelsLowercased[key.lowercased()] {
            return chinese ? label.zh : label.en
        }
        return humanizeKey(key)
    }

    /// Long identifiers (paths, UUIDs, payloads) read better in a monospaced
    /// face and without proportional tracking.
    static func isTechnicalField(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return lowered.contains("uuid")
            || lowered.contains("path")
            || lowered.contains("address")
            || lowered.contains("serial")
            || lowered.contains("payload")
            || lowered.contains("services")
            || lowered.contains("bundleid")
            || lowered.contains("unique")
            || lowered.contains("signed_by")
            || lowered.contains("identifier")
            || lowered.contains("load_address")
    }

    // MARK: Values

    static func value(_ field: InfoField, chinese: Bool) -> String {
        rawValue(field.value, rawKey: field.rawKey, chinese: chinese)
    }

    static func rawValue(_ value: InfoValue, rawKey: String, chinese: Bool) -> String {
        switch value {
        case .scalar(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return emDash }
            if rawKey == "_name" {
                return self.title(.literal(trimmed), chinese: chinese) ?? trimmed
            }
            if let translated = token(trimmed, chinese: chinese) { return translated }
            if rawKey.contains("pixelresolution"), let resolution = pixelResolution(trimmed) {
                return resolution
            }
            if let prettified = prettifyIdentifier(trimmed) { return prettified }
            return raw
        case .number(let number):
            if rawKey == "coreaudio_device_srate" {
                return sampleRate(number)
            }
            if rawKey == "spairport_network_rate" {
                return "\(plainNumber(number)) Mbps"
            }
            if rawKey == "sppower_battery_state_of_charge" {
                return "\(plainNumber(number))%"
            }
            if rawKey.lowercased().contains("rssi") {
                return "\(plainNumber(number)) dBm"
            }
            return plainNumber(number)
        case .boolean(let value):
            return value ? (chinese ? "是" : "Yes") : (chinese ? "否" : "No")
        case .bytes(let bytes):
            return byteCount(bytes)
        case .date(let date):
            return dateText(date, chinese: chinese)
        case .list(let values):
            guard !values.isEmpty else { return chinese ? "无" : "None" }
            return values.map { item in
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return emDash }
                return token(trimmed, chinese: chinese) ?? trimmed
            }.joined(separator: ", ")
        }
    }

    static func updatedText(_ date: Date, chinese: Bool, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds >= 0, seconds < 60 {
            return chinese ? "刚刚" : "Just now"
        }
        return dateText(date, chinese: chinese)
    }

    // MARK: Numbers and units

    private static func plainNumber(_ number: Double) -> String {
        if number == number.rounded(), abs(number) < Double(Int64.max) {
            return String(Int64(number))
        }
        return String(format: "%.2f", number)
    }

    /// `spdisplays_pixelresolution` is reported as `2560x1664Retina`.
    private static func pixelResolution(_ text: String) -> String? {
        let width = text.prefix(while: { $0.isNumber })
        guard !width.isEmpty else { return nil }
        var remainder = text.dropFirst(width.count)
        guard remainder.first == "x" || remainder.first == "X" else { return nil }
        remainder = remainder.dropFirst()
        let height = remainder.prefix(while: { $0.isNumber })
        guard !height.isEmpty else { return nil }
        let suffix = remainder.dropFirst(height.count).trimmingCharacters(in: .whitespaces)
        let base = "\(width) × \(height)"
        return suffix.isEmpty ? base : "\(base) \(suffix)"
    }

    private static func sampleRate(_ hertz: Double) -> String {
        if hertz >= 1000 {
            let kilo = hertz / 1000
            if kilo == kilo.rounded() {
                return "\(Int(kilo)) kHz"
            }
            return String(format: "%.1f kHz", kilo)
        }
        return "\(plainNumber(hertz)) Hz"
    }

    private static func byteCount(_ bytes: Int64) -> String {
        let magnitude = Double(abs(bytes))
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = magnitude
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let sign = bytes < 0 ? "-" : ""
        if unit == 0 {
            return "\(sign)\(Int(value)) B"
        }
        return sign + String(format: "%.1f %@", value, units[unit])
    }

    private static func dateText(_ date: Date, chinese: Bool) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(Locale(identifier: chinese ? "zh_CN" : "en_US"))
        return date.formatted(style)
    }

    // MARK: Token humanization

    private static let knownValuePrefixes = [
        "spdisplays_", "spairport_", "sppower_battery_", "sppower_", "spaudio_",
        "coreaudio_device_type_", "coreaudio_", "spcamera_", "spext_", "sppci_",
        "spnetworklocation_", "spnetwork_", "spfirewall_", "attrib_", "value_",
        "package_source_", "arch_", "receptacle_", "voice_gender_", "pairport_",
    ]

    /// Rewrites vendor tokens that are not in the explicit table. Only strings
    /// with a known system prefix are touched, so device names, paths, UUIDs
    /// and user text are left exactly as reported.
    private static func prettifyIdentifier(_ value: String) -> String? {
        let lowered = value.lowercased()
        guard let prefix = knownValuePrefixes.first(where: { lowered.hasPrefix($0) }) else {
            return nil
        }
        var remainder = String(value.dropFirst(prefix.count))
        while remainder.hasPrefix("_") { remainder.removeFirst() }
        guard !remainder.isEmpty else { return nil }
        return humanizeKey(remainder)
    }

    private static func token(_ value: String, chinese: Bool) -> String? {
        let lowered = value.lowercased()
        if let label = valueTokens[lowered] {
            return chinese ? label.zh : label.en
        }
        switch lowered {
        case "yes", "true", "on":
            return chinese ? "是" : "Yes"
        case "no", "false", "off":
            return chinese ? "否" : "No"
        case "enabled", "attrib_on", "value_yes":
            return chinese ? "已启用" : "Enabled"
        case "disabled", "attrib_off", "value_no":
            return chinese ? "已停用" : "Disabled"
        case "none":
            return chinese ? "无" : "None"
        case "unknown":
            return chinese ? "未知" : "Unknown"
        default:
            return nil
        }
    }

    // MARK: Key humanization

    private static let labelPrefixes = [
        "spdisplays", "sppower_battery", "sppower", "spnetworklocation", "spnetwork",
        "spairport", "spaudio", "coreaudio", "spcamera", "spext", "spconfigprofile",
        "spfirewall", "sppci", "spbattery",
    ]

    static func humanizeKey(_ key: String) -> String {
        var value = key
        while value.hasPrefix("_") { value.removeFirst() }

        for prefix in labelPrefixes {
            if value.lowercased().hasPrefix(prefix), value.count > prefix.count {
                value = String(value.dropFirst(prefix.count))
                while value.hasPrefix("_") || value.hasPrefix("-") { value.removeFirst() }
                break
            }
        }

        value = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        value = splitCamelCase(value)
        value = value.split(separator: " ").map(String.init).joined(separator: " ")

        let words = value.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return key }

        let minorWords: Set<String> = ["of", "and", "the", "in", "to", "for", "on", "with", "at", "by", "from", "per"]
        return words.enumerated().map { index, word in
            let lowered = word.lowercased()
            if let acronym = acronyms[lowered] { return acronym }
            if index > 0, minorWords.contains(lowered) { return lowered }
            if word.count == 2 || word.count == 3, word == word.uppercased() { return word }
            if word.contains(where: { $0.isUppercase }), word.contains(where: { $0.isLowercase }) {
                return word
            }
            if word.allSatisfy({ !$0.isLetter }) { return word }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// Inserts a space at a lower→upper boundary and at the end of an acronym
    /// run ("USBKey" → "USB Key", "numberProcessors" → "number Processors").
    private static func splitCamelCase(_ input: String) -> String {
        let characters = Array(input)
        var output = ""
        var uppercaseRun = 0
        for index in characters.indices {
            let character = characters[index]
            if character.isUppercase {
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let afterLowercase = previous?.isLowercase == true || previous?.isNumber == true
                let afterAcronym = previous?.isUppercase == true
                    && next?.isLowercase == true
                    && uppercaseRun >= 2
                if index > 0, !output.hasSuffix(" "), afterLowercase || afterAcronym {
                    output.append(" ")
                }
                uppercaseRun += 1
            } else {
                uppercaseRun = 0
            }
            output.append(character)
        }
        return output
    }

    private static let acronyms: [String: String] = [
        "id": "ID", "uuid": "UUID", "udid": "UDID", "url": "URL", "uri": "URI",
        "ip": "IP", "ipv4": "IPv4", "ipv6": "IPv6", "dns": "DNS", "dhcp": "DHCP",
        "mac": "MAC", "cpu": "CPU", "gpu": "GPU", "ram": "RAM", "rom": "ROM",
        "usb": "USB", "pci": "PCI", "pcie": "PCIe", "nvme": "NVMe", "sata": "SATA",
        "sas": "SAS", "scsi": "SCSI", "ssd": "SSD", "hdd": "HDD", "os": "OS",
        "rssi": "RSSI", "ssid": "SSID", "bssid": "BSSID", "mcs": "MCS",
        "phy": "PHY", "fw": "FW", "hw": "HW", "mw": "MW", "io": "IO", "ecc": "ECC",
        "dimm": "DIMM", "acpi": "ACPI", "xpc": "XPC", "ap": "AP", "tb": "TB",
        "wpa": "WPA", "wpa2": "WPA2", "wpa3": "WPA3", "owe": "OWE", "sim": "SIM",
        "eid": "EID", "uid": "UID", "gps": "GPS", "hdr": "HDR", "drm": "DRM",
        "sd": "SD", "ac": "AC", "dc": "DC", "led": "LED", "rgb": "RGB",
        "imei": "IMEI", "spi": "SPI", "ups": "UPS", "vram": "VRAM", "hfp": "HFP",
    ]

    // MARK: Localization tables

    private struct Label {
        let en: String
        let zh: String
    }

    private static let keyLabels: [String: Label] = [
        "_name": Label(en: "Name", zh: "名称"),
        "_items": Label(en: "Items", zh: "项目"),
        "_properties": Label(en: "Properties", zh: "属性"),

        "machine_name": Label(en: "Model Name", zh: "机型名称"),
        "chip_type": Label(en: "Chip", zh: "芯片"),
        "machine_model": Label(en: "Model Identifier", zh: "机型标识符"),
        "model_number": Label(en: "Model Number", zh: "型号"),
        "physical_memory": Label(en: "Memory", zh: "内存"),
        "serial_number": Label(en: "Serial Number", zh: "序列号"),
        "activation_lock_status": Label(en: "Activation Lock", zh: "激活锁"),
        "number_processors": Label(en: "Processors", zh: "处理器"),
        "platform_UUID": Label(en: "Platform UUID", zh: "平台 UUID"),
        "provisioning_UDID": Label(en: "Provisioning UDID", zh: "预置 UDID"),
        "boot_rom_version": Label(en: "Boot ROM Version", zh: "启动 ROM 版本"),
        "os_loader_version": Label(en: "OS Loader Version", zh: "系统载入器版本"),

        "os_version": Label(en: "macOS Version", zh: "macOS 版本"),
        "kernel_version": Label(en: "Kernel Version", zh: "内核版本"),
        "boot_volume": Label(en: "Startup Disk", zh: "启动磁盘"),
        "boot_mode": Label(en: "Boot Mode", zh: "启动模式"),
        "local_host_name": Label(en: "Computer Name", zh: "电脑名称"),
        "user_name": Label(en: "User", zh: "用户"),
        "uptime": Label(en: "Uptime", zh: "运行时间"),
        "system_integrity": Label(en: "System Integrity Protection", zh: "系统完整性保护"),
        "secure_vm": Label(en: "Secure Virtual Memory", zh: "安全虚拟内存"),

        "sppci_model": Label(en: "Chipset Model", zh: "芯片组型号"),
        "spdisplays_vendor": Label(en: "Vendor", zh: "厂商"),
        "sppci_cores": Label(en: "Cores", zh: "核心数"),
        "spdisplays_mtlgpufamilysupport": Label(en: "Metal Support", zh: "Metal 支持"),
        "sppci_device_type": Label(en: "Device Type", zh: "设备类型"),
        "sppci_bus": Label(en: "Bus", zh: "总线"),
        "spdisplays_ndrvs": Label(en: "Displays", zh: "显示器"),
        "_spdisplays_resolution": Label(en: "Resolution", zh: "分辨率"),
        "spdisplays_pixels": Label(en: "Pixels", zh: "像素"),
        "_spdisplays_pixels": Label(en: "Pixels", zh: "像素"),
        "spdisplays_pixelresolution": Label(en: "Pixel Resolution", zh: "像素分辨率"),
        "spdisplays_display_type": Label(en: "Display Type", zh: "显示器类型"),
        "spdisplays_connection_type": Label(en: "Connection", zh: "连接方式"),
        "spdisplays_ambient_brightness": Label(en: "Ambient Brightness", zh: "环境亮度"),
        "spdisplays_main": Label(en: "Main Display", zh: "主显示器"),
        "spdisplays_mirror": Label(en: "Mirror", zh: "镜像"),
        "spdisplays_online": Label(en: "Online", zh: "在线"),
        "_spdisplays_display-product-id": Label(en: "Product ID", zh: "产品 ID"),
        "_spdisplays_display-vendor-id": Label(en: "Vendor ID", zh: "厂商 ID"),
        "_spdisplays_display-serial-number": Label(en: "Serial Number", zh: "序列号"),
        "_spdisplays_displayID": Label(en: "Display ID", zh: "显示器 ID"),
        "_spdisplays_display-week": Label(en: "Production Week", zh: "生产周"),
        "_spdisplays_display-year": Label(en: "Production Year", zh: "生产年份"),

        "SPMemoryDataType": Label(en: "Memory Size", zh: "内存容量"),
        "dimm_type": Label(en: "Type", zh: "类型"),
        "dimm_manufacturer": Label(en: "Manufacturer", zh: "制造商"),

        "sppower_battery_state_of_charge": Label(en: "Charge Level", zh: "电量"),
        "sppower_battery_is_charging": Label(en: "Charging", zh: "正在充电"),
        "sppower_battery_fully_charged": Label(en: "Fully Charged", zh: "已充满"),
        "sppower_battery_at_warn_level": Label(en: "Low Battery Warning", zh: "低电量警告"),
        "sppower_battery_health": Label(en: "Battery Health", zh: "电池健康"),
        "sppower_battery_cycle_count": Label(en: "Cycle Count", zh: "循环次数"),
        "sppower_battery_health_maximum_capacity": Label(en: "Maximum Capacity", zh: "最大容量"),
        "sppower_battery_charger_connected": Label(en: "Power Adapter", zh: "电源适配器"),
        "sppower_battery_charge_info": Label(en: "Charge Information", zh: "充电信息"),
        "sppower_battery_health_info": Label(en: "Battery Health", zh: "电池健康"),
        "sppower_battery_model_info": Label(en: "Battery Model", zh: "电池型号"),
        "sppower_battery_cell_revision": Label(en: "Cell Revision", zh: "电芯版本"),
        "sppower_battery_device_name": Label(en: "Device Name", zh: "设备名称"),
        "sppower_battery_firmware_version": Label(en: "Firmware Version", zh: "固件版本"),
        "sppower_battery_hardware_revision": Label(en: "Hardware Revision", zh: "硬件版本"),
        "sppower_battery_pack_lot_code": Label(en: "Pack Lot Code", zh: "电池包批次"),
        "sppower_battery_pcb_lot_code": Label(en: "PCB Lot Code", zh: "电路板批次"),
        "sppower_battery_serial_number": Label(en: "Serial Number", zh: "序列号"),
        "sppower_ups_installed": Label(en: "UPS Installed", zh: "已安装 UPS"),
        "AC Power": Label(en: "AC Power", zh: "交流电源"),
        "Battery Power": Label(en: "Battery Power", zh: "电池电源"),
        "LowPowerMode": Label(en: "Low Power Mode", zh: "低电量模式"),
        "Current Power Source": Label(en: "Current Power Source", zh: "当前电源"),
        "System Sleep Timer": Label(en: "System Sleep Timer", zh: "系统睡眠计时器"),
        "Display Sleep Timer": Label(en: "Display Sleep Timer", zh: "显示器睡眠计时器"),
        "Disk Sleep Timer": Label(en: "Disk Sleep Timer", zh: "磁盘睡眠计时器"),
        "Hibernate Mode": Label(en: "Hibernate Mode", zh: "休眠模式"),
        "Wake On LAN": Label(en: "Wake for Network Access", zh: "网络唤醒"),
        "Sleep On Power Button": Label(en: "Sleep on Power Button", zh: "按下电源键睡眠"),
        "PrioritizeNetworkReachabilityOverSleep": Label(en: "Prioritize Network Reachability", zh: "优先保持网络连接"),
        "ReduceBrightness": Label(en: "Reduce Brightness", zh: "降低亮度"),

        "file_system": Label(en: "File System", zh: "文件系统"),
        "mount_point": Label(en: "Mount Point", zh: "挂载点"),
        "bsd_name": Label(en: "BSD Name", zh: "BSD 名称"),
        "size_in_bytes": Label(en: "Capacity", zh: "容量"),
        "free_space_in_bytes": Label(en: "Available", zh: "可用空间"),
        "volume_uuid": Label(en: "Volume UUID", zh: "卷 UUID"),
        "writable": Label(en: "Writable", zh: "可写"),
        "ignore_ownership": Label(en: "Ignore Ownership", zh: "忽略所有权"),
        "physical_drive": Label(en: "Physical Drive", zh: "物理磁盘"),
        "is_internal_disk": Label(en: "Internal", zh: "内置"),
        "media_name": Label(en: "Media Name", zh: "介质名称"),
        "medium_type": Label(en: "Medium", zh: "介质类型"),
        "partition_map_type": Label(en: "Partition Map", zh: "分区映射"),
        "smart_status": Label(en: "SMART Status", zh: "SMART 状态"),
        "device_model": Label(en: "Device Model", zh: "设备型号"),
        "device_name": Label(en: "Device Name", zh: "设备名称"),
        "device_revision": Label(en: "Device Revision", zh: "设备修订版"),
        "device_serial": Label(en: "Device Serial Number", zh: "设备序列号"),
        "detachable_drive": Label(en: "Detachable", zh: "可拆卸"),
        "removable_media": Label(en: "Removable Media", zh: "可移除介质"),
        "spnvme_trim_support": Label(en: "TRIM Support", zh: "TRIM 支持"),
        "iocontent": Label(en: "Content", zh: "内容"),
        "volumes": Label(en: "Volumes", zh: "卷"),
        "protocol": Label(en: "Protocol", zh: "协议"),
        "size": Label(en: "Size", zh: "大小"),

        "hardware": Label(en: "Hardware", zh: "硬件"),
        "interface": Label(en: "Interface", zh: "接口"),
        "ip_address": Label(en: "IP Address", zh: "IP 地址"),
        "spnetwork_service_order": Label(en: "Service Order", zh: "服务顺序"),
        "ConfigMethod": Label(en: "Configuration", zh: "配置方式"),
        "ServerAddresses": Label(en: "DNS Servers", zh: "DNS 服务器"),
        "ExceptionsList": Label(en: "Exceptions", zh: "例外"),
        "MediaOptions": Label(en: "Media Options", zh: "介质选项"),
        "MediaSubType": Label(en: "Media Subtype", zh: "介质子类型"),
        "MAC Address": Label(en: "MAC Address", zh: "MAC 地址"),
        "Addresses": Label(en: "Addresses", zh: "地址"),
        "ARPResolvedIPAddress": Label(en: "ARP Resolved IP", zh: "ARP 解析 IP"),
        "ARPResolvedHardwareAddress": Label(en: "ARP Resolved Hardware Address", zh: "ARP 解析硬件地址"),
        "InterfaceName": Label(en: "Interface Name", zh: "接口名称"),
        "ConfirmedInterfaceName": Label(en: "Confirmed Interface Name", zh: "已确认接口名称"),
        "PrefixLength": Label(en: "Prefix Length", zh: "前缀长度"),
        "SubnetMasks": Label(en: "Subnet Masks", zh: "子网掩码"),
        "NetworkSignature": Label(en: "Network Signature", zh: "网络签名"),
        "NetworkSignatureHash": Label(en: "Network Signature Hash", zh: "网络签名哈希"),
        "Ethernet": Label(en: "Ethernet", zh: "以太网"),
        "IPv4": Label(en: "IPv4", zh: "IPv4"),
        "IPv6": Label(en: "IPv6", zh: "IPv6"),
        "Proxies": Label(en: "Proxies", zh: "代理"),
        "DNS": Label(en: "DNS", zh: "DNS"),
        "dhcp": Label(en: "DHCP", zh: "DHCP"),
        "FTPPassive": Label(en: "FTP Passive", zh: "FTP 被动模式"),
        "HTTPEnable": Label(en: "HTTP Proxy", zh: "HTTP 代理"),
        "HTTPSEnable": Label(en: "HTTPS Proxy", zh: "HTTPS 代理"),
        "SOCKSEnable": Label(en: "SOCKS Proxy", zh: "SOCKS 代理"),
        "HTTPProxy": Label(en: "HTTP Server", zh: "HTTP 服务器"),
        "HTTPSProxy": Label(en: "HTTPS Server", zh: "HTTPS 服务器"),
        "SOCKSProxy": Label(en: "SOCKS Server", zh: "SOCKS 服务器"),
        "HTTPPort": Label(en: "HTTP Port", zh: "HTTP 端口"),
        "HTTPSPort": Label(en: "HTTPS Port", zh: "HTTPS 端口"),
        "SOCKSPort": Label(en: "SOCKS Port", zh: "SOCKS 端口"),
        "AdditionalRoutes": Label(en: "Additional Routes", zh: "附加路由"),
        "DestinationAddress": Label(en: "Destination Address", zh: "目标地址"),
        "SubnetMask": Label(en: "Subnet Mask", zh: "子网掩码"),
        "Router": Label(en: "Router", zh: "路由器"),
        "dhcp_domain_name_servers": Label(en: "DNS Servers", zh: "DNS 服务器"),
        "dhcp_lease_duration": Label(en: "Lease Duration", zh: "租约时长"),
        "dhcp_message_type": Label(en: "Message Type", zh: "消息类型"),
        "dhcp_routers": Label(en: "Router", zh: "路由器"),
        "dhcp_server_identifier": Label(en: "DHCP Server", zh: "DHCP 服务器"),
        "dhcp_subnet_mask": Label(en: "Subnet Mask", zh: "子网掩码"),
        "spnetworklocation_isActive": Label(en: "Active", zh: "已启用"),
        "spnetworklocation_services": Label(en: "Services", zh: "服务"),

        "spairport_airport_interfaces": Label(en: "AirPort Interfaces", zh: "AirPort 接口"),
        "spairport_airport_other_local_wireless_networks": Label(en: "Other Networks", zh: "其他网络"),
        "spairport_current_network_information": Label(en: "Current Network", zh: "当前网络"),
        "spairport_software_information": Label(en: "Software Information", zh: "软件信息"),
        "spairport_status_information": Label(en: "Status", zh: "状态"),
        "spairport_wireless_card_type": Label(en: "Wireless Card", zh: "无线网卡"),
        "spairport_supported_phymodes": Label(en: "Supported Modes", zh: "支持模式"),
        "spairport_supported_channels": Label(en: "Supported Channels", zh: "支持信道"),
        "spairport_network_channel": Label(en: "Channel", zh: "信道"),
        "spairport_network_country_code": Label(en: "Country Code", zh: "国家代码"),
        "spairport_network_mcs": Label(en: "MCS Index", zh: "MCS 索引"),
        "spairport_network_phymode": Label(en: "PHY Mode", zh: "PHY 模式"),
        "spairport_network_rate": Label(en: "Transmit Rate", zh: "传输速率"),
        "spairport_network_type": Label(en: "Network Type", zh: "网络类型"),
        "spairport_security_mode": Label(en: "Security", zh: "安全性"),
        "spairport_signal_noise": Label(en: "Signal / Noise", zh: "信号 / 噪声"),
        "spairport_corewlan_version": Label(en: "CoreWLAN Version", zh: "CoreWLAN 版本"),
        "spairport_corewlankit_version": Label(en: "CoreWLANKit Version", zh: "CoreWLANKit 版本"),
        "spairport_diagnostics_version": Label(en: "Diagnostics Version", zh: "诊断版本"),
        "spairport_extra_version": Label(en: "Extra Version", zh: "扩展版本"),
        "spairport_family_version": Label(en: "Family Version", zh: "系列版本"),
        "spairport_profiler_version": Label(en: "Profiler Version", zh: "系统信息版本"),
        "spairport_utility_version": Label(en: "Utility Version", zh: "实用工具版本"),
        "spairport_caps_airdrop": Label(en: "AirDrop", zh: "AirDrop"),
        "spairport_caps_autounlock": Label(en: "Auto Unlock", zh: "自动解锁"),
        "spairport_caps_wow": Label(en: "Wake on Wireless", zh: "无线唤醒"),
        "spairport_wireless_country_code": Label(en: "Country Code", zh: "国家代码"),
        "spairport_wireless_firmware_version": Label(en: "Wireless Firmware", zh: "无线固件版本"),
        "spairport_wireless_locale": Label(en: "Locale", zh: "区域"),
        "spairport_wireless_mac_address": Label(en: "MAC Address", zh: "MAC 地址"),

        "controller_address": Label(en: "Address", zh: "地址"),
        "controller_chipset": Label(en: "Chipset", zh: "芯片组"),
        "controller_discoverable": Label(en: "Discoverable", zh: "可被发现"),
        "controller_firmwareVersion": Label(en: "Firmware", zh: "固件"),
        "controller_productID": Label(en: "Product ID", zh: "产品 ID"),
        "controller_state": Label(en: "State", zh: "状态"),
        "controller_supportedServices": Label(en: "Supported Services", zh: "支持的服务"),
        "controller_transport": Label(en: "Transport", zh: "传输"),
        "controller_vendorID": Label(en: "Vendor ID", zh: "厂商 ID"),
        "device_connected": Label(en: "Connected Devices", zh: "已连接设备"),
        "device_not_connected": Label(en: "Not Connected", zh: "未连接设备"),
        "device_address": Label(en: "Address", zh: "地址"),
        "device_batteryLevelCase": Label(en: "Battery (Case)", zh: "电量（充电盒）"),
        "device_batteryLevelLeft": Label(en: "Battery (Left)", zh: "电量（左）"),
        "device_batteryLevelRight": Label(en: "Battery (Right)", zh: "电量（右）"),
        "device_caseVersion": Label(en: "Case Version", zh: "充电盒版本"),
        "device_firmwareVersion": Label(en: "Firmware", zh: "固件"),
        "device_minorType": Label(en: "Type", zh: "类型"),
        "device_productID": Label(en: "Product ID", zh: "产品 ID"),
        "device_rssi": Label(en: "RSSI", zh: "信号强度"),
        "device_serialNumber": Label(en: "Serial Number", zh: "序列号"),
        "device_serialNumberLeft": Label(en: "Serial Number (Left)", zh: "序列号（左）"),
        "device_serialNumberRight": Label(en: "Serial Number (Right)", zh: "序列号（右）"),
        "device_services": Label(en: "Services", zh: "服务"),
        "device_vendorID": Label(en: "Vendor ID", zh: "厂商 ID"),

        "USBKeyHardwareType": Label(en: "Hardware Type", zh: "硬件类型"),
        "USBKeyLocationID": Label(en: "Location ID", zh: "位置 ID"),
        "Driver": Label(en: "Driver", zh: "驱动程序"),
        "device_name_key": Label(en: "Device", zh: "设备"),
        "vendor_name_key": Label(en: "Vendor", zh: "厂商"),
        "current_speed_key": Label(en: "Speed", zh: "速度"),
        "receptacle_status_key": Label(en: "Status", zh: "状态"),
        "receptacle_id_key": Label(en: "Port", zh: "端口"),
        "link_status_key": Label(en: "Link Status", zh: "链路状态"),
        "route_string_key": Label(en: "Route", zh: "路由"),
        "domain_uuid_key": Label(en: "Domain UUID", zh: "域 UUID"),
        "switch_uid_key": Label(en: "Switch UID", zh: "交换机 UID"),
        "controller_properties": Label(en: "Controller Properties", zh: "控制器属性"),
        "receptacle_1_tag": Label(en: "Port 1", zh: "端口 1"),

        "coreaudio_device_manufacturer": Label(en: "Manufacturer", zh: "制造商"),
        "coreaudio_device_transport": Label(en: "Transport", zh: "传输"),
        "coreaudio_device_srate": Label(en: "Sample Rate", zh: "采样率"),
        "coreaudio_device_input": Label(en: "Input Channels", zh: "输入声道"),
        "coreaudio_device_output": Label(en: "Output Channels", zh: "输出声道"),
        "coreaudio_default_audio_input_device": Label(en: "Default Input", zh: "默认输入"),
        "coreaudio_default_audio_output_device": Label(en: "Default Output", zh: "默认输出"),
        "coreaudio_default_audio_system_device": Label(en: "Default System Device", zh: "默认系统设备"),
        "coreaudio_input_source": Label(en: "Input Source", zh: "输入来源"),
        "coreaudio_output_source": Label(en: "Output Source", zh: "输出来源"),

        "spcamera_model-id": Label(en: "Model", zh: "型号"),
        "spcamera_unique-id": Label(en: "Unique ID", zh: "唯一 ID"),

        "lastModified": Label(en: "Last Modified", zh: "上次修改"),
        "obtained_from": Label(en: "Source", zh: "来源"),
        "arch_kind": Label(en: "Architecture", zh: "架构"),
        "signed_by": Label(en: "Signed By", zh: "签名者"),
        "info": Label(en: "Info", zh: "信息"),
        "version": Label(en: "Version", zh: "版本"),
        "path": Label(en: "Location", zh: "位置"),

        "spext_architectures": Label(en: "Architectures", zh: "架构"),
        "spext_bundleid": Label(en: "Bundle ID", zh: "Bundle ID"),
        "spext_has64BitIntelCode": Label(en: "Intel Code", zh: "Intel 代码"),
        "spext_hasAllDependencies": Label(en: "Dependencies", zh: "依赖关系"),
        "spext_lastModified": Label(en: "Last Modified", zh: "上次修改"),
        "spext_load_address": Label(en: "Load Address", zh: "载入地址"),
        "spext_loadable": Label(en: "Loadable", zh: "可载入"),
        "spext_loaded": Label(en: "Loaded", zh: "已载入"),
        "spext_path": Label(en: "Location", zh: "位置"),
        "spext_signed_by": Label(en: "Signed By", zh: "签名者"),
        "spext_version": Label(en: "Version", zh: "版本"),
        "spext_description": Label(en: "Description", zh: "描述"),
        "spext_info": Label(en: "Info", zh: "信息"),

        "typefaces": Label(en: "Typefaces", zh: "字体样式"),
        "family": Label(en: "Family", zh: "字体家族"),
        "style": Label(en: "Style", zh: "样式"),
        "fullname": Label(en: "Full Name", zh: "全名"),
        "unique": Label(en: "Unique Name", zh: "唯一名称"),
        "outline": Label(en: "Outline", zh: "轮廓"),
        "valid": Label(en: "Valid", zh: "有效"),
        "enabled": Label(en: "Enabled", zh: "已启用"),
        "duplicate": Label(en: "Duplicate", zh: "重复"),
        "copy_protected": Label(en: "Copy Protected", zh: "防拷贝"),
        "embeddable": Label(en: "Embeddable", zh: "可嵌入"),
        "designer": Label(en: "Designer", zh: "设计者"),
        "vendor": Label(en: "Vendor", zh: "厂商"),
        "copyright": Label(en: "Copyright", zh: "版权"),
        "trademark": Label(en: "Trademark", zh: "商标"),
        "type": Label(en: "Type", zh: "类型"),
        "description": Label(en: "Description", zh: "描述"),

        "private_framework": Label(en: "Private", zh: "私有"),
        "install_date": Label(en: "Install Date", zh: "安装日期"),
        "install_version": Label(en: "Version", zh: "版本"),
        "package_source": Label(en: "Source", zh: "来源"),

        "spconfigprofile_install_date": Label(en: "Install Date", zh: "安装日期"),
        "spconfigprofile_install_source": Label(en: "Source", zh: "来源"),
        "spconfigprofile_profile_identifier": Label(en: "Profile ID", zh: "描述文件 ID"),
        "spconfigprofile_profile_uuid": Label(en: "Profile UUID", zh: "描述文件 UUID"),
        "spconfigprofile_version": Label(en: "Version", zh: "版本"),
        "spconfigprofile_verification_state": Label(en: "Verification", zh: "验证"),
        "spconfigprofile_RemovalDisallowed": Label(en: "Removal Disallowed", zh: "禁止移除"),
        "spconfigprofile_payload_data": Label(en: "Payload", zh: "负载"),
        "spconfigprofile_payload_identifier": Label(en: "Payload ID", zh: "负载 ID"),
        "spconfigprofile_payload_uuid": Label(en: "Payload UUID", zh: "负载 UUID"),
        "spconfigprofile_payload_version": Label(en: "Payload Version", zh: "负载版本"),

        "spfirewall_globalstate": Label(en: "Global State", zh: "全局状态"),
        "spfirewall_loggingenabled": Label(en: "Logging", zh: "日志记录"),
        "spfirewall_stealthenabled": Label(en: "Stealth Mode", zh: "隐身模式"),
        "Action": Label(en: "Action", zh: "操作"),
        "AuthenticationMethod": Label(en: "Authentication", zh: "认证方式"),
        "DesignatedRequirement": Label(en: "Designated Requirement", zh: "指定要求"),
        "DisconnectOnFastUserSwitch": Label(en: "Disconnect on Fast User Switch", zh: "快速用户切换时断开"),
        "DisconnectOnIdle": Label(en: "Disconnect on Idle", zh: "空闲时断开"),
        "DisconnectOnIdleTimer": Label(en: "Idle Timer", zh: "空闲计时器"),
        "DisconnectOnLogout": Label(en: "Disconnect on Logout", zh: "注销时断开"),
        "DisconnectOnSleep": Label(en: "Disconnect on Sleep", zh: "睡眠时断开"),
        "DisconnectOnWake": Label(en: "Disconnect on Wake", zh: "唤醒时断开"),
        "DisconnectOnWakeTimer": Label(en: "Wake Timer", zh: "唤醒计时器"),
        "IEEE80211": Label(en: "IEEE 802.11", zh: "IEEE 802.11"),
        "JoinMode": Label(en: "Join Mode", zh: "加入模式"),
        "NEProviderBundleIdentifier": Label(en: "Provider Bundle ID", zh: "提供程序 Bundle ID"),
        "OnDemandEnabled": Label(en: "On Demand", zh: "按需连接"),
        "OnDemandRules": Label(en: "On Demand Rules", zh: "按需规则"),
        "RemoteAddress": Label(en: "Remote Address", zh: "远程地址"),
        "URLStringProbe": Label(en: "URL Probe", zh: "URL 探测"),
        "VPN": Label(en: "VPN", zh: "VPN"),
        "bsd_device_name": Label(en: "BSD Device", zh: "BSD 设备"),
        "hardware_address": Label(en: "Hardware Address", zh: "硬件地址"),

        "contrast": Label(en: "Contrast", zh: "对比度"),
        "cursor_mag": Label(en: "Cursor Magnification", zh: "光标放大"),
        "display": Label(en: "Display", zh: "显示"),
        "flash_screen": Label(en: "Flash Screen", zh: "闪烁屏幕"),
        "keyboardZoom": Label(en: "Keyboard Zoom", zh: "键盘缩放"),
        "mouse_keys": Label(en: "Mouse Keys", zh: "鼠标键"),
        "scrollZoom": Label(en: "Scroll Zoom", zh: "滚动缩放"),
        "slow_keys": Label(en: "Slow Keys", zh: "慢速键"),
        "sticky_keys": Label(en: "Sticky Keys", zh: "粘滞键"),
        "voiceover": Label(en: "VoiceOver", zh: "VoiceOver"),
        "zoomMode": Label(en: "Zoom Mode", zh: "缩放模式"),

        "user_locale": Label(en: "Locale", zh: "区域"),
        "user_language_code": Label(en: "Language", zh: "语言"),
        "user_country_code": Label(en: "Country", zh: "国家/地区"),
        "user_calendar": Label(en: "Calendar", zh: "日历"),
        "user_preferred_interface_languages": Label(en: "Preferred Languages", zh: "首选语言"),
        "user_current_input_source": Label(en: "Input Source", zh: "输入法"),
        "user_assistant_language": Label(en: "Assistant Language", zh: "助理语言"),
        "user_assistant_voice_language": Label(en: "Assistant Voice Language", zh: "助理语音语言"),
        "user_assistant_voice_gender": Label(en: "Assistant Voice", zh: "助理语音"),
        "user_uses_metric_system": Label(en: "Metric System", zh: "公制"),
        "linguistic_data_assets_requested": Label(en: "Language Assets", zh: "语言资源"),
        "system_country": Label(en: "System Country", zh: "系统国家/地区"),
        "system_interface_languages": Label(en: "System Languages", zh: "系统语言"),
        "system_languages": Label(en: "System Languages", zh: "系统语言"),
        "system_locale": Label(en: "System Locale", zh: "系统区域"),
        "system_text_direction": Label(en: "Text Direction", zh: "文本方向"),
        "system_uses_metric_system": Label(en: "Metric System", zh: "公制"),
        "boot_kbd": Label(en: "Boot Keyboard", zh: "启动键盘"),
        "boot_locale": Label(en: "Boot Locale", zh: "启动区域"),

        "ctl_fw": Label(en: "Controller Firmware", zh: "控制器固件"),
        "ctl_hw": Label(en: "Controller Hardware", zh: "控制器硬件"),
        "ctl_info": Label(en: "Controller Info", zh: "控制器信息"),
        "ctl_mw": Label(en: "Controller Middleware", zh: "控制器中间件"),
        "se_device": Label(en: "Device", zh: "设备"),
        "se_fw": Label(en: "Firmware", zh: "固件"),
        "se_hw": Label(en: "Hardware", zh: "硬件"),
        "se_id": Label(en: "ID", zh: "ID"),
        "se_in_restricted_mode": Label(en: "Restricted Mode", zh: "受限模式"),
        "se_info": Label(en: "Info", zh: "信息"),
        "se_os_id": Label(en: "OS ID", zh: "系统 ID"),
        "se_os_version": Label(en: "OS Version", zh: "系统版本"),
        "se_plt": Label(en: "Platform", zh: "平台"),
        "se_prod_signed": Label(en: "Production Signed", zh: "量产签名"),

        "spfirewall_applications": Label(en: "Applications", zh: "应用程序"),
        "cupsversion": Label(en: "CUPS Version", zh: "CUPS 版本"),
        "status": Label(en: "Status", zh: "状态"),
        "byteSize": Label(en: "Size", zh: "大小"),
        "contents": Label(en: "Contents", zh: "内容"),
        "time": Label(en: "Time", zh: "时间"),
        "eventtype": Label(en: "Event", zh: "事件"),
        "scheduledby": Label(en: "Scheduled By", zh: "计划来源"),
        "appPID": Label(en: "Process ID", zh: "进程 ID"),
        "UserVisible": Label(en: "User Visible", zh: "用户可见"),
    ]

    private static let keyLabelsLowercased: [String: Label] = {
        var result: [String: Label] = [:]
        for (key, label) in keyLabels {
            result[key.lowercased()] = label
        }
        return result
    }()

    private static let identifierLabels: [String: Label] = [
        "hardware_overview": Label(en: "Hardware Overview", zh: "硬件概览"),
        "os_overview": Label(en: "Software Overview", zh: "软件概览"),
        "spbattery_information": Label(en: "Battery Information", zh: "电池信息"),
        "sppower_information": Label(en: "Power Settings", zh: "电源设置"),
        "sppower_hwconfig_information": Label(en: "Hardware Configuration", zh: "硬件配置"),
        "sppower_ac_charger_information": Label(en: "Power Adapter", zh: "电源适配器"),
        "sppower_events_info": Label(en: "Power Events", zh: "电源事件"),
        "sppower_scheduled_events_info": Label(en: "Scheduled Events", zh: "计划事件"),
        "spfirewall_settings": Label(en: "Firewall Settings", zh: "防火墙设置"),
        "user_settings": Label(en: "User Settings", zh: "用户设置"),
        "system_settings": Label(en: "System Settings", zh: "系统设置"),
        "recovery_os_settings": Label(en: "Recovery OS Settings", zh: "恢复系统设置"),
        "ua_info": Label(en: "Accessibility Settings", zh: "辅助功能设置"),
        "readers": Label(en: "Readers", zh: "读卡器"),
        "readers_drivers": Label(en: "Reader Drivers", zh: "读卡器驱动"),
        "smartcards_drivers": Label(en: "Smart Card Drivers", zh: "智能卡驱动"),
        "avail_smartcards_keychain": Label(en: "Available Smart Cards (Keychain)", zh: "可用智能卡（钥匙串）"),
        "avail_smartcards_token": Label(en: "Available Smart Cards (Token)", zh: "可用智能卡（令牌）"),
        "thunderboltusb4_bus_0": Label(en: "Thunderbolt / USB 4 Bus 0", zh: "雷雳 / USB 4 总线 0"),
        "thunderboltusb4_bus_1": Label(en: "Thunderbolt / USB 4 Bus 1", zh: "雷雳 / USB 4 总线 1"),
        "spairport_airport_interfaces": Label(en: "AirPort Interfaces", zh: "AirPort 接口"),
        "spairport_software_information": Label(en: "Software Information", zh: "软件信息"),
        "spairport_current_network_information": Label(en: "Current Network", zh: "当前网络"),
        "controller_properties": Label(en: "Controller Properties", zh: "控制器属性"),
        "coreaudio_device": Label(en: "Audio Devices", zh: "音频设备"),
        "device_connected": Label(en: "Connected Devices", zh: "已连接设备"),
        "device_not_connected": Label(en: "Not Connected", zh: "未连接设备"),
    ]

    private static let valueTokens: [String: Label] = [
        "spdisplays_yes": Label(en: "Yes", zh: "是"),
        "spdisplays_no": Label(en: "No", zh: "否"),
        "spdisplays_on": Label(en: "On", zh: "开"),
        "spdisplays_off": Label(en: "Off", zh: "关"),
        "spaudio_yes": Label(en: "Yes", zh: "是"),
        "spaudio_no": Label(en: "No", zh: "否"),
        "spext_yes": Label(en: "Yes", zh: "是"),
        "spext_no": Label(en: "No", zh: "否"),
        "value_yes": Label(en: "Yes", zh: "是"),
        "value_no": Label(en: "No", zh: "否"),
        "attrib_on": Label(en: "On", zh: "开"),
        "attrib_off": Label(en: "Off", zh: "关"),
        "package_source_apple": Label(en: "Apple", zh: "Apple"),
        "package_source_identified_developer": Label(en: "Identified Developer", zh: "已识别开发者"),
        "package_source_mac_app_store": Label(en: "Mac App Store", zh: "Mac App Store"),
        "apple": Label(en: "Apple", zh: "Apple"),
        "identified_developer": Label(en: "Identified Developer", zh: "已识别开发者"),
        "mac_app_store": Label(en: "Mac App Store", zh: "Mac App Store"),
        "arch_arm": Label(en: "Apple Silicon", zh: "Apple 芯片"),
        "arch_arm_i64": Label(en: "Universal", zh: "通用"),
        "arch_arm64": Label(en: "Apple Silicon", zh: "Apple 芯片"),
        "arch_i64": Label(en: "Intel", zh: "Intel"),
        "arch_x86_64": Label(en: "Intel", zh: "Intel"),
        "spdisplays_internal": Label(en: "Built-in", zh: "内置"),
        "spdisplays_external": Label(en: "External", zh: "外接"),
        "spdisplays_builtin": Label(en: "Built-in", zh: "内置"),
        "spdisplays_built-in-liquid-retina": Label(en: "Built-in Liquid Retina", zh: "内置 Liquid 视网膜"),
        "spdisplays_metal4": Label(en: "Metal 4", zh: "Metal 4"),
        "spdisplays_metal3": Label(en: "Metal 3", zh: "Metal 3"),
        "spdisplays_gpu": Label(en: "GPU", zh: "GPU"),
        "sppci_vendor_apple": Label(en: "Apple", zh: "Apple"),
        "spairport_status_connected": Label(en: "Connected", zh: "已连接"),
        "spairport_status_disconnected": Label(en: "Not Connected", zh: "未连接"),
        "spairport_status_inactive": Label(en: "Inactive", zh: "未启用"),
        "spairport_network_type_station": Label(en: "Station", zh: "工作站"),
        "spairport_network_type_ap": Label(en: "Access Point", zh: "接入点"),
        "spairport_security_mode_none": Label(en: "None", zh: "无"),
        "spairport_security_mode_wep": Label(en: "WEP", zh: "WEP"),
        "spairport_security_mode_wpa_personal": Label(en: "WPA Personal", zh: "WPA 个人级"),
        "spairport_security_mode_wpa2_personal": Label(en: "WPA2 Personal", zh: "WPA2 个人级"),
        "spairport_security_mode_wpa3_personal": Label(en: "WPA3 Personal", zh: "WPA3 个人级"),
        "spairport_security_mode_wpa2_enterprise": Label(en: "WPA2 Enterprise", zh: "WPA2 企业级"),
        "spairport_security_mode_wpa3_enterprise": Label(en: "WPA3 Enterprise", zh: "WPA3 企业级"),
        "spairport_security_mode_wpa3_transition": Label(en: "WPA3 Transition", zh: "WPA3 过渡模式"),
        "pairport_security_mode_wpa3_transition": Label(en: "WPA3 Transition", zh: "WPA3 过渡模式"),
        "spairport_security_mode_owe": Label(en: "OWE", zh: "OWE"),
        "spairport_security_mode_wpa2_wpa3_personal": Label(en: "WPA2/WPA3 Personal", zh: "WPA2/WPA3 个人级"),
        "spairport_caps_supported": Label(en: "Supported", zh: "支持"),
        "spairport_caps_unsupported": Label(en: "Not Supported", zh: "不支持"),
        "coreaudio_device_type_bluetooth": Label(en: "Bluetooth", zh: "蓝牙"),
        "coreaudio_device_type_usb": Label(en: "USB", zh: "USB"),
        "coreaudio_device_type_builtin": Label(en: "Built-in", zh: "内置"),
        "coreaudio_device_type_hdmi": Label(en: "HDMI", zh: "HDMI"),
        "coreaudio_device_type_displayport": Label(en: "DisplayPort", zh: "DisplayPort"),
        "coreaudio_device_type_airplay": Label(en: "AirPlay", zh: "AirPlay"),
        "coreaudio_device_type_unknown": Label(en: "Unknown", zh: "未知"),
        "spaudio_default": Label(en: "Default", zh: "默认"),
        "voice_gender_female": Label(en: "Female", zh: "女声"),
        "voice_gender_male": Label(en: "Male", zh: "男声"),
        "zoom_full_screen": Label(en: "Full Screen", zh: "全屏幕"),
        "black_on_white": Label(en: "Black on White", zh: "白底黑字"),
        "white_on_black": Label(en: "White on Black", zh: "黑底白字"),
        "gregorian": Label(en: "Gregorian", zh: "公历"),
        "normal_boot": Label(en: "Normal", zh: "正常"),
        "activation_lock_enabled": Label(en: "Enabled", zh: "已启用"),
        "integrity_enabled": Label(en: "Enabled", zh: "已启用"),
        "secure_vm_enabled": Label(en: "Enabled", zh: "已启用"),
        "ssd": Label(en: "SSD", zh: "固态硬盘"),
        "hdd": Label(en: "HDD", zh: "机械硬盘"),
        "ethernet": Label(en: "Ethernet", zh: "以太网"),
        "airport": Label(en: "Wi-Fi", zh: "Wi-Fi"),
        "wifi": Label(en: "Wi-Fi", zh: "Wi-Fi"),
        "bluetooth": Label(en: "Bluetooth", zh: "蓝牙"),
        "automatic": Label(en: "Automatic", zh: "自动"),
        "manual": Label(en: "Manual", zh: "手动"),
        "dhcp": Label(en: "DHCP", zh: "DHCP"),
        "autoselect": Label(en: "Auto-select", zh: "自动选择"),
        "guid_partition_map_type": Label(en: "GPT", zh: "GPT"),
        "spnvme_trim_support_yes": Label(en: "Yes", zh: "是"),
        "receptacle_no_devices_connected": Label(en: "No Devices Connected", zh: "未连接设备"),
        "unknown_partition_map_type": Label(en: "Unknown", zh: "未知"),
        "spfirewall_allow_all": Label(en: "Allow All", zh: "允许全部"),
        "spfirewall_block_all": Label(en: "Block All", zh: "阻止全部"),
        "spfirewall_globalstate_allow_all": Label(en: "Allow All", zh: "允许全部"),
        "spfirewall_globalstate_block_all": Label(en: "Block All", zh: "阻止全部"),
        "ieee80211": Label(en: "IEEE 802.11", zh: "IEEE 802.11"),
        "bridge": Label(en: "Bridge", zh: "网桥"),
        "no_info_found": Label(en: "No Information", zh: "无信息"),
        "not_applicable": Label(en: "Not Applicable", zh: "不适用"),
        "good": Label(en: "Good", zh: "良好"),
        "normal": Label(en: "Normal", zh: "正常"),
        "warning": Label(en: "Warning", zh: "警告"),
        "critical": Label(en: "Critical", zh: "严重"),
        "verified": Label(en: "Verified", zh: "已验证"),
    ]

    private static var emDash: String { "\u{2014}" }
}
