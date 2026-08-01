import SwiftUI

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh"
}

@MainActor
final class LocaleManager: ObservableObject {
    static let shared = LocaleManager()

    @AppStorage("appLanguage") var appLanguage: String = LocaleManager.detectSystemLanguage()

    static func detectSystemLanguage() -> String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang == "zh" ? "zh" : "en"
    }

    var currentLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .english
    }

    func localized(_ key: String) -> String {
        guard currentLanguage == .chinese else { return key }
        return Self.zh[key] ?? key
    }

    private static let zh: [String: String] = [
        "Display": "显示",
        "Window": "窗口",
        "Opacity": "不透明度",
        "Font": "字体",
        "Font Scale": "字体缩放",
        "Show in Fullscreen": "全屏显示",
        "Block Display": "块状显示",
        "Columns": "面板列",
        "Compute (CPU/GPU/PWR)": "计算 (CPU/GPU/PWR)",
        "Memory (MEM/PRS/SWAP)": "内存 (MEM/PRS/SWAP)",
        "Storage (DR/DW/THM)": "存储 (DR/DW/THM)",
        "Network (NET/UP/DN)": "网络 (NET/UP/DN)",
        "Menu Bar": "菜单栏",
        "Refresh:": "刷新间隔:",
        "Refresh": "刷新",
        "Launch at Login": "开机启动",
        "General": "通用",
        "Settings...": "设置...",
        "Quit Semono": "退出 Semono",
        "Language": "语言",
        "English": "English",
        "中文": "中文",
        "Adaptive Sleep": "智能休眠",
        "Sleep Sensitivity": "休眠灵敏度",
        "Hysteresis": "迟滞",
        "Sleep when the last 5 CPU samples stay within the sensitivity; wake when they exceed sensitivity + hysteresis.": "最近 5 次样本的 CPU 变化极差 ≤ 灵敏度时休眠，超过 灵敏度+迟滞 时唤醒。休眠期间刷新间隔自动变为 10 秒。",
        "Per Core": "每核",
        "Settings apply immediately": "设置即时生效",
        "Semono Settings": "Semono 设置",
        "Semono Monitor": "Semono 监控",
        "Restore Defaults": "恢复默认设置",
        "Reset": "重置",

        "CPU": "CPU",
        "GPU": "GPU",
        "Memory": "内存",
        "Storage": "存储",
        "Network": "网络",
        "Other": "其他",

        "CPU Usage": "CPU 使用率",
        "GPU Usage": "GPU 使用率",
        "Power Draw": "功耗",
        "Memory Usage": "内存使用率",
        "Swap Usage": "交换",
        "Memory Pressure": "内存压力",
        "Disk Read": "磁盘读取",
        "Disk Write": "磁盘写入",
        "Thermal State": "温度状态",
        "Network Down": "下载",
        "Network Up": "上传",
        "WiFi RSSI": "WiFi 信号",
        "Frequency": "频率",

        "Nominal": "正常",
        "Moderate": "中等",
        "Heavy": "严重",
        "Critical": "危急",
    ]
}
