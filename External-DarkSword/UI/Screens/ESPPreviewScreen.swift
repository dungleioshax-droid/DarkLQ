//
//  ESPPreviewScreen.swift
//  External-DarkSword
//
//  Created by DLX07 on 11/1/26.
//

import SwiftUI
import UIKit

struct ESPPreviewScreen: View {
    @ObservedObject var manager: DarkSwordManager
    let palette: AppPalette
    let language: AppLanguage

    @State private var selectedGameIndex = 0 // 0: AoV, 1: Free Fire
    @State private var simulatedDistance: Double = 28.0

    // Bindings to DarkSwordManager properties depending on selected game
    private var isAoV: Bool {
        selectedGameIndex == 0
    }

    private var showsLine: Binding<Bool> {
        Binding(
            get: { isAoV ? manager.aovShowsLine : manager.freeFireShowsLine },
            set: {
                if isAoV {
                    manager.aovShowsLine = $0
                } else {
                    manager.freeFireShowsLine = $0
                }
            }
        )
    }

    private var showsBox: Binding<Bool> {
        Binding(
            get: { isAoV ? manager.aovShowsBox : manager.freeFireShowsBox },
            set: {
                if isAoV {
                    manager.aovShowsBox = $0
                } else {
                    manager.freeFireShowsBox = $0
                }
            }
        )
    }

    private var showsHealth: Binding<Bool> {
        Binding(
            get: { isAoV ? manager.aovShowsHealth : manager.freeFireShowsHealth },
            set: {
                if isAoV {
                    manager.aovShowsHealth = $0
                } else {
                    manager.freeFireShowsHealth = $0
                }
            }
        )
    }

    private var showsName: Binding<Bool> {
        Binding(
            get: { isAoV ? manager.aovShowsName : manager.freeFireShowsName },
            set: {
                if isAoV {
                    manager.aovShowsName = $0
                } else {
                    manager.freeFireShowsName = $0
                }
            }
        )
    }

    private var showsDistance: Binding<Bool> {
        Binding(
            get: { isAoV ? manager.aovShowsDistance : manager.freeFireShowsDistance },
            set: {
                if isAoV {
                    manager.aovShowsDistance = $0
                } else {
                    manager.freeFireShowsDistance = $0
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppStrings.espPreviewTitle(language))
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(palette.primaryText)

                            Text(AppStrings.espPreviewSubtitle(language))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(palette.mutedText)
                        }

                        Spacer()

                        // Target Game Switcher Badge
                        GlassBadge(
                            title: isAoV ? "Liên Quân" : "Free Fire",
                            color: isAoV ? palette.accent : palette.accentPurple,
                            palette: palette
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)

                // Game Selector Segmented Control
                VStack(alignment: .leading, spacing: 8) {
                    GlassSegmentedPicker(
                        options: [
                            "Liên Quân Mobile",
                            "Free Fire"
                        ],
                        selectedIndex: $selectedGameIndex,
                        palette: palette
                    )
                    .padding(.horizontal, 18)
                }

                // MARK: - Simulation Stage / Canvas
                VStack(spacing: 12) {
                    GlassCard(palette: palette, cornerRadius: 24, isRaised: true) {
                        VStack(spacing: 0) {
                            // Viewport Canvas Header
                            HStack {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("LIVE VIEWPORT")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(palette.secondaryText)
                                }

                                Spacer()

                                Text("FPS: 60 • RES: 1080P")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(palette.mutedText)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                            Divider().background(palette.glassBorder)

                            // Interactive Viewport Arena
                            GeometryReader { geometry in
                                ZStack {
                                    // Tactical Grid & Viewport Ambience
                                    TacticalGridBackground(palette: palette)

                                    // Snapline from screen top center to character
                                    if showsLine.wrappedValue {
                                        Path { path in
                                            let start = CGPoint(x: geometry.size.width / 2, y: 0)
                                            let target = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.44)
                                            path.move(to: start)
                                            path.addLine(to: target)
                                        }
                                        .stroke(
                                            Color(red: 1.0, green: 0.22, blue: 0.32),
                                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                                        )
                                        .shadow(color: Color(red: 1.0, green: 0.22, blue: 0.32).opacity(0.8), radius: 4)

                                        // Contact Point Dot
                                        Circle()
                                            .fill(Color(red: 1.0, green: 0.22, blue: 0.32))
                                            .frame(width: 5, height: 5)
                                            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.44)
                                    }

                                    // Simulated Character Target with ESP Overlays
                                    VStack(spacing: 4) {
                                        // 1. Distance Tag (Yellow HUD)
                                        if showsDistance.wrappedValue {
                                            Text(String(format: "[ %.0fm ]", simulatedDistance))
                                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                                .foregroundColor(Color(red: 1.0, green: 0.95, blue: 0.25))
                                                .shadow(color: Color.black.opacity(0.9), radius: 2, x: 1, y: 1)
                                        }

                                        // 2. Player Name Tag
                                        if showsName.wrappedValue {
                                            Text(isAoV ? "[Địch] Valhein" : "[Địch] Kelly_07")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .shadow(color: Color.black.opacity(0.9), radius: 2, x: 1, y: 1)
                                        }

                                        // 3. Health Bar
                                        if showsHealth.wrappedValue {
                                            HStack(spacing: 2) {
                                                GeometryReader { hpGeo in
                                                    ZStack(alignment: .leading) {
                                                        RoundedRectangle(cornerRadius: 2)
                                                            .fill(Color.black.opacity(0.75))

                                                        RoundedRectangle(cornerRadius: 2)
                                                            .fill(
                                                                LinearGradient(
                                                                    colors: [Color.green, Color.yellow],
                                                                    startPoint: .leading,
                                                                    endPoint: .trailing
                                                                )
                                                            )
                                                            .frame(width: hpGeo.size.width * 0.82)
                                                    }
                                                }
                                                .frame(width: 76, height: 5)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .stroke(Color.black.opacity(0.8), lineWidth: 0.8)
                                                )

                                                Text(isAoV ? "3.4k" : "180")
                                                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                                    .foregroundColor(.white)
                                                    .shadow(color: .black, radius: 1)
                                            }
                                        }

                                        // 4. Character Figure + 2D Bounding Box
                                        ZStack {
                                            // Character Silhouette & Stance
                                            CharacterDummyGraphic(isAoV: isAoV, palette: palette)
                                                .frame(width: 80, height: 130)

                                            // 2D ESP Bounding Box
                                            if showsBox.wrappedValue {
                                                ESPBoundingBoxView()
                                                    .frame(width: 88, height: 138)
                                            }
                                        }
                                    }
                                    // Scale character smoothly based on distance
                                    .scaleEffect(max(0.65, min(1.25, 1.4 - (simulatedDistance / 100.0) * 0.75)))
                                    .animation(.spring(response: 0.28, dampingFraction: 0.75), value: simulatedDistance)
                                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.58)
                                }
                            }
                            .frame(height: 310)
                            .clipped()

                            Divider().background(palette.glassBorder)

                            // Distance Slider Control
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(AppStrings.espCanvasDistance(language))
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(palette.secondaryText)

                                    Spacer()

                                    Text(String(format: "%.0f mét", simulatedDistance))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(palette.accent)
                                }

                                Slider(value: $simulatedDistance, in: 10...90, step: 1)
                                    .tint(palette.accent)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 18)
                }

                // MARK: - Toggle Controls Panel
                VStack(alignment: .leading, spacing: 10) {
                    GlassSectionHeader(
                        title: AppStrings.tuningFeaturesTitle(language),
                        icon: "slider.horizontal.3",
                        palette: palette
                    )
                    .padding(.horizontal, 22)

                    GlassCard(palette: palette, cornerRadius: 20) {
                        VStack(spacing: 12) {
                            FeatureToggleRow(
                                title: AppStrings.espBoxes(language),
                                isOn: showsBox,
                                palette: palette
                            )
                            FeatureToggleRow(
                                title: AppStrings.espSnaplines(language),
                                isOn: showsLine,
                                palette: palette
                            )
                            FeatureToggleRow(
                                title: AppStrings.espHealth(language),
                                isOn: showsHealth,
                                palette: palette
                            )
                            FeatureToggleRow(
                                title: AppStrings.espName(language),
                                isOn: showsName,
                                palette: palette
                            )
                            FeatureToggleRow(
                                title: AppStrings.espDistance(language),
                                isOn: showsDistance,
                                palette: palette
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                }

                Spacer(minLength: 96) // Space for bottom tab bar
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - ESP Bounding Box Component (Game Overlay Style)
private struct ESPBoundingBoxView: View {
    private let boxColor = Color(red: 1.0, green: 0.22, blue: 0.32)

    var body: some View {
        ZStack {
            // Full semi-transparent border
            RoundedRectangle(cornerRadius: 4)
                .stroke(boxColor.opacity(0.85), lineWidth: 1.5)
                .shadow(color: boxColor.opacity(0.6), radius: 3)

            // Accent Corner Brackets for authentic game ESP look
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let len: CGFloat = 12

                Path { path in
                    // Top-Left
                    path.move(to: CGPoint(x: 0, y: len))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: len, y: 0))

                    // Top-Right
                    path.move(to: CGPoint(x: w - len, y: 0))
                    path.addLine(to: CGPoint(x: w, y: 0))
                    path.addLine(to: CGPoint(x: w, y: len))

                    // Bottom-Left
                    path.move(to: CGPoint(x: 0, y: h - len))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: len, y: h))

                    // Bottom-Right
                    path.move(to: CGPoint(x: w - len, y: h))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: w, y: h - len))
                }
                .stroke(boxColor, lineWidth: 2.2)
            }
        }
    }
}

// MARK: - Character Dummy Visual Graphic
private struct CharacterDummyGraphic: View {
    let isAoV: Bool
    let palette: AppPalette

    private var auraColor: Color {
        (isAoV ? palette.accent : palette.accentPurple).opacity(0.25)
    }

    private var visorColor: Color {
        isAoV ? palette.accent : Color.red
    }

    var body: some View {
        ZStack {
            // Tactical Body Aura
            Capsule()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [auraColor, Color.clear]),
                        center: .center,
                        startRadius: 5,
                        endRadius: 55
                    )
                )
                .frame(width: 80, height: 120)

            // Stylized Tactical Character Silhouette
            VStack(spacing: 2) {
                // Head / Helmet
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [palette.primaryText.opacity(0.85), palette.secondaryText.opacity(0.6)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        // Visor Glow
                        RoundedRectangle(cornerRadius: 2)
                            .fill(visorColor)
                            .frame(width: 14, height: 4)
                            .offset(y: -1)
                    )

                // Torso & Tactical Armor
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [palette.secondaryText.opacity(0.75), palette.glassBorderHighlight.opacity(0.5)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 38, height: 48)
                    .overlay(
                        VStack(spacing: 3) {
                            Rectangle()
                                .fill(palette.accent.opacity(0.6))
                                .frame(width: 20, height: 2)
                            Image(systemName: isAoV ? "shield.fill" : "cross.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(palette.primaryText.opacity(0.7))
                        }
                    )

                // Legs / Stance
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.secondaryText.opacity(0.7))
                        .frame(width: 12, height: 44)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.secondaryText.opacity(0.7))
                        .frame(width: 12, height: 44)
                }
            }
            .shadow(color: Color.black.opacity(0.5), radius: 6, x: 0, y: 4)
        }
    }
}

// MARK: - Tactical Viewport Grid Background
private struct TacticalGridBackground: View {
    let palette: AppPalette

    var body: some View {
        ZStack {
            // Dark Arena Canvas
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.10, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Radar Circle Concentric Rings
            Circle()
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                .frame(width: 180, height: 180)

            Circle()
                .stroke(Color.white.opacity(0.03), lineWidth: 1)
                .frame(width: 280, height: 280)

            // Center Crosshair
            Path { path in
                path.move(to: CGPoint(x: 20, y: 155))
                path.addLine(to: CGPoint(x: 340, y: 155))
            }
            .stroke(Color.white.opacity(0.03), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}
