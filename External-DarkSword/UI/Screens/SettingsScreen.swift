//
//  SettingsScreen.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var manager: DarkSwordManager
    let palette: AppPalette
    let language: AppLanguage
    @Binding var prefersDarkTheme: Bool
    @Binding var prefersVietnamese: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Title
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.settingsTitle(language))
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(palette.primaryText)

                    Text("Customization, preferences and system information")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 16)

                // MARK: - Appearance Section
                VStack(alignment: .leading, spacing: 10) {
                    GlassSectionHeader(
                        title: AppStrings.appearanceSection(language),
                        icon: "paintpalette.fill",
                        palette: palette
                    )
                    .padding(.horizontal, 22)

                    GlassCard(palette: palette, cornerRadius: 20) {
                        VStack(spacing: 14) {
                            // Theme Selector
                            HStack {
                                HStack(spacing: 10) {
                                    Image(systemName: prefersDarkTheme ? "moon.stars.fill" : "sun.max.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(palette.accent)

                                    Text(AppStrings.text(language, vietnamese: "Chủ đề giao diện", english: "App Theme"))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(palette.primaryText)
                                }

                                Spacer()

                                GlassSegmentedPicker(
                                    options: [
                                        AppStrings.themeDarkGlass(language),
                                        AppStrings.themeLightGlass(language)
                                    ],
                                    selectedIndex: Binding(
                                        get: { prefersDarkTheme ? 0 : 1 },
                                        set: { prefersDarkTheme = ($0 == 0) }
                                    ),
                                    palette: palette
                                )
                                .frame(maxWidth: 210)
                            }

                            Divider().background(palette.glassBorder)

                            // Language Selector
                            HStack {
                                HStack(spacing: 10) {
                                    Image(systemName: "globe.asia.australia.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(palette.accentPurple)

                                    Text(AppStrings.languageSection(language))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(palette.primaryText)
                                }

                                Spacer()

                                GlassSegmentedPicker(
                                    options: [
                                        "Tiếng Việt",
                                        "English"
                                    ],
                                    selectedIndex: Binding(
                                        get: { prefersVietnamese ? 0 : 1 },
                                        set: { prefersVietnamese = ($0 == 0) }
                                    ),
                                    palette: palette
                                )
                                .frame(maxWidth: 210)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }

                // MARK: - Advanced Kernel & RemoteCall Section
                VStack(alignment: .leading, spacing: 10) {
                    GlassSectionHeader(
                        title: AppStrings.advancedSection(language),
                        icon: "terminal.fill",
                        palette: palette
                    )
                    .padding(.horizontal, 22)

                    GlassCard(palette: palette, cornerRadius: 20) {
                        VStack(spacing: 14) {
                            // MIG Filter Bypass Toggle
                            Toggle(isOn: $manager.useMigFilterBypass) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(AppStrings.migBypassTitle(language))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(palette.primaryText)

                                    Text(AppStrings.migBypassDesc(language))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(palette.mutedText)
                                }
                            }
                            .tint(palette.accent)

                            Divider().background(palette.glassBorder)

                            // Target Process
                            HStack {
                                Text(AppStrings.targetProcessTitle(language))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(palette.secondaryText)
                                Spacer()
                                Text(manager.targetProcess)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(palette.primaryText)
                            }

                            Divider().background(palette.glassBorder)

                            // Overlay Socket Clients
                            HStack {
                                Text(AppStrings.socketClientsTitle(language))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(palette.secondaryText)
                                Spacer()
                                GlassBadge(
                                    title: "\(manager.overlaySocketClientCount) Online",
                                    color: manager.overlaySocketClientCount > 0 ? palette.success : palette.secondaryText,
                                    palette: palette
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }

                // MARK: - About & Developer Card
                VStack(alignment: .leading, spacing: 10) {
                    GlassSectionHeader(
                        title: AppStrings.aboutAppSection(language),
                        icon: "info.circle.fill",
                        palette: palette
                    )
                    .padding(.horizontal, 22)

                    GlassCard(palette: palette, cornerRadius: 22) {
                        VStack(spacing: 16) {
                            // App Logo Emblem
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                palette.accent.opacity(palette.isDark ? 0.30 : 0.15),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 40
                                        )
                                    )
                                    .frame(width: 80, height: 80)

                                Circle()
                                    .stroke(palette.accent.opacity(0.35), lineWidth: 1.2)
                                    .frame(width: 60, height: 60)

                                Image(systemName: "bolt.shield.fill")
                                    .font(.system(size: 26, weight: .black))
                                    .foregroundStyle(palette.accentGradient)
                            }

                            VStack(spacing: 4) {
                                Text(AppStrings.appTitle)
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundColor(palette.primaryText)

                                Text("High-Performance Kernel Tool & Sideloaded Mod")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(palette.mutedText)
                            }

                            Divider().background(palette.glassBorder)

                            // Specs & Metadata List
                            VStack(spacing: 8) {
                                AboutRow(
                                    title: AppStrings.versionTitle(language),
                                    value: "v1.2.0 (Glass Edition)",
                                    palette: palette
                                )
                                AboutRow(
                                    title: AppStrings.architectureTitle(language),
                                    value: "arm64e (iOS 17.0 - 18.7.1 & 26.0.x)",
                                    palette: palette
                                )
                                AboutRow(
                                    title: AppStrings.devName(language),
                                    value: "Le Tien Dat",
                                    palette: palette
                                )
                            }

                            DeveloperFooter(palette: palette)
                                .padding(.top, 4)
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

private struct AboutRow: View {
    let title: String
    let value: String
    let palette: AppPalette

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(palette.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(palette.primaryText)
        }
    }
}
