//
//  AppPalette.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import SwiftUI

struct AppPalette {
    let isDark: Bool

    // MARK: - Base Colors
    var background: Color {
        isDark
            ? Color(red: 0.04, green: 0.05, blue: 0.07)
            : Color(red: 0.94, green: 0.95, blue: 0.98)
    }

    var primaryText: Color {
        isDark ? .white : Color(red: 0.08, green: 0.09, blue: 0.14)
    }

    var secondaryText: Color {
        primaryText.opacity(isDark ? 0.72 : 0.68)
    }

    var mutedText: Color {
        primaryText.opacity(isDark ? 0.45 : 0.42)
    }

    // MARK: - Glassmorphism System
    var glassCard: Color {
        isDark
            ? Color.white.opacity(0.065)
            : Color.white.opacity(0.75)
    }

    var glassCardSubtle: Color {
        isDark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.50)
    }

    var glassCardRaised: Color {
        isDark
            ? Color(red: 0.11, green: 0.13, blue: 0.19).opacity(0.85)
            : Color.white.opacity(0.88)
    }

    var glassBorder: Color {
        isDark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    var glassBorderStrong: Color {
        isDark
            ? Color.white.opacity(0.24)
            : Color.black.opacity(0.15)
    }

    var glassBorderHighlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isDark ? 0.35 : 0.80),
                Color.white.opacity(isDark ? 0.04 : 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var glassHighlight: Color {
        Color.white.opacity(isDark ? 0.22 : 0.65)
    }

    var glassShadow: Color {
        isDark
            ? Color.black.opacity(0.40)
            : Color(red: 0.10, green: 0.15, blue: 0.25).opacity(0.08)
    }

    // MARK: - Accents & Vibrant Tones
    var accent: Color {
        Color(red: 0.18, green: 0.82, blue: 0.98) // Electric Cyan
    }

    var accentGreen: Color {
        Color(red: 0.22, green: 0.90, blue: 0.55) // Neon Mint
    }

    var accentPurple: Color {
        Color(red: 0.68, green: 0.44, blue: 1.0) // Soft Purple
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.82, blue: 0.98),
                Color(red: 0.22, green: 0.90, blue: 0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var purpleGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.68, green: 0.44, blue: 1.0),
                Color(red: 0.92, green: 0.40, blue: 0.78)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var success: Color {
        Color(red: 0.22, green: 0.90, blue: 0.55)
    }

    var warning: Color {
        Color(red: 1.0, green: 0.72, blue: 0.22)
    }

    var danger: Color {
        Color(red: 1.0, green: 0.35, blue: 0.45)
    }

    var dangerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.38, blue: 0.48),
                Color(red: 0.90, green: 0.20, blue: 0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Compatibility Properties
    var card: Color { glassCard }
    var iconBackground: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    var border: Color { glassBorder }
    var pillBackground: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
}
