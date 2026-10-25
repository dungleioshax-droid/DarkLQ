//
//  AppPalette.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import SwiftUI

struct AppPalette {
    let isDark: Bool

    var background: Color {
        isDark
            ? Color(red: 0.035, green: 0.04, blue: 0.048)
            : Color(red: 0.94, green: 0.95, blue: 0.96)
    }

    var primaryText: Color {
        isDark ? .white : Color(red: 0.06, green: 0.075, blue: 0.095)
    }

    var secondaryText: Color {
        primaryText.opacity(isDark ? 0.62 : 0.58)
    }

    var mutedText: Color {
        primaryText.opacity(isDark ? 0.45 : 0.42)
    }

    var card: Color {
        isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.92)
    }

    var iconBackground: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    var border: Color {
        primaryText.opacity(isDark ? 0.13 : 0.1)
    }

    var pillBackground: Color {
        primaryText.opacity(isDark ? 0.08 : 0.07)
    }

    var accent: Color {
        Color(red: 0.24, green: 0.9, blue: 0.46)
    }
}
