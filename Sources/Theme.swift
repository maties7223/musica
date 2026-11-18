import SwiftUI
import Observation

/// Colores disponibles para la interfaz.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case pink, yellow, blue, green

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pink: return "Rosa"
        case .yellow: return "Amarillo"
        case .blue: return "Azul"
        case .green: return "Verde claro"
        }
    }

    var accent: Color {
        switch self {
        case .pink: return Color(red: 0.98, green: 0.24, blue: 0.42)
        case .yellow: return Color(red: 0.96, green: 0.70, blue: 0.04)
        case .blue: return Color(red: 0.12, green: 0.52, blue: 0.98)
        case .green: return Color(red: 0.25, green: 0.78, blue: 0.48)
        }
    }

    var accent2: Color {
        switch self {
        case .pink: return Color(red: 0.60, green: 0.30, blue: 0.96)
        case .yellow: return Color(red: 0.98, green: 0.45, blue: 0.10)
        case .blue: return Color(red: 0.00, green: 0.74, blue: 0.92)
        case .green: return Color(red: 0.10, green: 0.68, blue: 0.70)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Guarda el color elegido y avisa a las vistas cuando cambia.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var choice: ThemeChoice

    private init() {
        let saved = UserDefaults.standard.string(forKey: "themeChoice") ?? ""
        choice = ThemeChoice(rawValue: saved) ?? .pink
    }

    func select(_ new: ThemeChoice) {
        choice = new
        UserDefaults.standard.set(new.rawValue, forKey: "themeChoice")
    }
}

enum Theme {
    static var accent: Color { ThemeStore.shared.choice.accent }
    static var accent2: Color { ThemeStore.shared.choice.accent2 }
    static var gradient: LinearGradient { ThemeStore.shared.choice.gradient }
}
