import SwiftUI

enum ThemeID: String, CaseIterable, Identifiable {
    case retroFuturistic
    case plainLight
    case plainDark
    case dirtyDishes

    var id: String { rawValue }
}

struct AppTheme: Equatable {
    var id: ThemeID
    var displayName: String

    var colorScheme: ColorScheme

    var backgroundTop: Color
    var backgroundBottom: Color
    var surface: Color
    var elevatedSurface: Color

    var textPrimary: Color
    var textSecondary: Color
    var accent: Color

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension AppTheme {
    static func forID(_ id: ThemeID) -> AppTheme {
        switch id {
        case .retroFuturistic:
            return AppTheme(
                id: id,
                displayName: "RetroFuturistic",
                colorScheme: .dark,
                backgroundTop: Color(red: 0.06, green: 0.09, blue: 0.14),
                backgroundBottom: Color(red: 0.02, green: 0.03, blue: 0.06),
                surface: Color.white.opacity(0.06),
                elevatedSurface: Color.white.opacity(0.10),
                textPrimary: Color.white,
                textSecondary: Color.white.opacity(0.74),
                accent: Color(red: 0.38, green: 0.88, blue: 0.92)
            )
        case .plainLight:
            return AppTheme(
                id: id,
                displayName: "Plain Light",
                colorScheme: .light,
                backgroundTop: Color(red: 0.98, green: 0.98, blue: 0.99),
                backgroundBottom: Color(red: 0.95, green: 0.95, blue: 0.97),
                surface: Color.black.opacity(0.04),
                elevatedSurface: Color.black.opacity(0.06),
                textPrimary: Color.black,
                textSecondary: Color.black.opacity(0.68),
                accent: Color(red: 0.05, green: 0.45, blue: 0.95)
            )
        case .plainDark:
            return AppTheme(
                id: id,
                displayName: "Plain Dark",
                colorScheme: .dark,
                backgroundTop: Color(red: 0.10, green: 0.10, blue: 0.11),
                backgroundBottom: Color(red: 0.04, green: 0.04, blue: 0.05),
                surface: Color.white.opacity(0.06),
                elevatedSurface: Color.white.opacity(0.10),
                textPrimary: Color.white,
                textSecondary: Color.white.opacity(0.72),
                accent: Color(red: 0.90, green: 0.55, blue: 0.15)
            )
        case .dirtyDishes:
            // Catppuccin Mocha inspired, lavender-forward.
            return AppTheme(
                id: id,
                displayName: "DirtyDishes",
                colorScheme: .dark,
                backgroundTop: Color(red: 0.11, green: 0.10, blue: 0.15),
                backgroundBottom: Color(red: 0.06, green: 0.06, blue: 0.10),
                surface: Color.white.opacity(0.06),
                elevatedSurface: Color.white.opacity(0.10),
                textPrimary: Color(red: 0.94, green: 0.92, blue: 0.98),
                textSecondary: Color(red: 0.78, green: 0.75, blue: 0.88),
                accent: Color(red: 0.78, green: 0.72, blue: 0.96)
            )
        }
    }
}
