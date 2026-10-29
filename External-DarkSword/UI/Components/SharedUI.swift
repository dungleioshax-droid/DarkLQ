//
//  SharedUI.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import SwiftUI

// MARK: - Ambient Glassmorphic Background
struct AppBackground: View {
    let palette: AppPalette

    var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            // Glowing Ambient Light Orbs for Frosted Depth
            GeometryReader { geometry in
                let size = geometry.size
                let isDark = palette.isDark

                // Top-Right Cyan/Blue Glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.18, green: 0.78, blue: 0.98).opacity(isDark ? 0.16 : 0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size.width * 0.45
                        )
                    )
                    .frame(width: size.width * 0.9, height: size.width * 0.9)
                    .offset(x: size.width * 0.35, y: -size.height * 0.08)
                    .blur(radius: 60)

                // Center-Left Purple/Violet Glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.65, green: 0.40, blue: 1.0).opacity(isDark ? 0.14 : 0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size.width * 0.5
                        )
                    )
                    .frame(width: size.width, height: size.width)
                    .offset(x: -size.width * 0.4, y: size.height * 0.25)
                    .blur(radius: 70)

                // Bottom-Right Mint/Emerald Glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.20, green: 0.90, blue: 0.58).opacity(isDark ? 0.12 : 0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size.width * 0.4
                        )
                    )
                    .frame(width: size.width * 0.8, height: size.width * 0.8)
                    .offset(x: size.width * 0.25, y: size.height * 0.65)
                    .blur(radius: 65)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Reusable Glass Card Container
struct GlassCard<Content: View>: View {
    let palette: AppPalette
    var cornerRadius: CGFloat = 20
    var isRaised: Bool = false
    let content: () -> Content

    init(
        palette: AppPalette,
        cornerRadius: CGFloat = 20,
        isRaised: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.palette = palette
        self.cornerRadius = cornerRadius
        self.isRaised = isRaised
        self.content = content
    }

    var body: some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isRaised ? palette.glassCardRaised : palette.glassCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.glassBorderHighlight, lineWidth: 1.2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.glassBorder, lineWidth: 0.8)
                    )
                    .shadow(
                        color: palette.glassShadow,
                        radius: isRaised ? 16 : 10,
                        x: 0,
                        y: isRaised ? 8 : 4
                    )
            )
    }
}

// MARK: - Glass Status Badge
struct GlassBadge: View {
    let title: String
    var icon: String? = nil
    var color: Color
    let palette: AppPalette
    var pulsing: Bool = false

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            if pulsing {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulsing ? 1.3 : 0.85)
                    .opacity(isPulsing ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(palette.isDark ? 0.14 : 0.12))
                .overlay(
                    Capsule()
                        .stroke(color.opacity(palette.isDark ? 0.35 : 0.28), lineWidth: 1)
                )
        )
    }
}

// MARK: - Glass Segmented Control
struct GlassSegmentedPicker: View {
    let options: [String]
    @Binding var selectedIndex: Int
    let palette: AppPalette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<options.count, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        selectedIndex = index
                    }
                } label: {
                    Text(options[index])
                        .font(.system(size: 13, weight: selectedIndex == index ? .bold : .medium, design: .rounded))
                        .foregroundColor(selectedIndex == index ? (palette.isDark ? .white : .black) : palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                if selectedIndex == index {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            palette.isDark
                                                ? Color.white.opacity(0.18)
                                                : Color.white.opacity(0.95)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(palette.glassBorderHighlight, lineWidth: 1)
                                        )
                                        .shadow(color: palette.glassShadow, radius: 4, x: 0, y: 2)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.glassCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.glassBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Glass Section Header
struct GlassSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    let palette: AppPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(palette.accent)
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(palette.primaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.mutedText)
            }
        }
    }
}

// MARK: - Developer Attribution Footer
struct DeveloperFooter: View {
    let palette: AppPalette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(palette.accent)

            Text(AppStrings.developerCredit)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(palette.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(palette.glassCard)
                .overlay(
                    Capsule()
                        .stroke(palette.glassBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Compatibility Button Styles & Views
struct StatusPill: View {
    let title: String
    let color: Color
    let palette: AppPalette

    var body: some View {
        GlassBadge(title: title, color: color, palette: palette)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    let palette: AppPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.black)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.accentGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(
                        color: palette.accent.opacity(palette.isDark ? 0.38 : 0.24),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

struct DisconnectButtonStyle: ButtonStyle {
    let palette: AppPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(palette.danger)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.danger.opacity(palette.isDark ? 0.12 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(palette.danger.opacity(0.4), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
