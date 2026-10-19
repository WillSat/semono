import Foundation

/// HUD color treatment. Dark is the original translucent black panel with
/// light text; light is a white panel with darker text and a deeper metric
/// palette for contrast.
enum HUDTheme: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}
