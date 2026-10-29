//
//  ContentView.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/3/26.
//

import SwiftUI

enum AppTab: Int, CaseIterable {
    case dashboard = 0
    case games = 1
    case logs = 2
    case settings = 3

    func icon(isSelected: Bool) -> String {
        switch self {
        case .dashboard:
            return isSelected ? "bolt.shield.fill" : "bolt.shield"
        case .games:
            return isSelected ? "gamecontroller.fill" : "gamecontroller"
        case .logs:
            return isSelected ? "terminal.fill" : "terminal"
        case .settings:
            return isSelected ? "gearshape.fill" : "gearshape"
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .dashboard:
            return AppStrings.tabDashboard(language)
        case .games:
            return AppStrings.tabGames(language)
        case .logs:
            return AppStrings.tabLogs(language)
        case .settings:
            return AppStrings.tabSettings(language)
        }
    }
}

struct ContentView: View {
    @ObservedObject var manager: DarkSwordManager
    @AppStorage("ui.prefersDarkTheme") private var prefersDarkTheme = true
    @AppStorage("ui.prefersVietnamese") private var prefersVietnamese = true

    @State private var selectedTab: AppTab = .dashboard

    private var palette: AppPalette {
        AppPalette(isDark: prefersDarkTheme)
    }

    private var language: AppLanguage {
        prefersVietnamese ? .vietnamese : .english
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Ambient Glassmorphic Canvas
            AppBackground(palette: palette)

            // Main Tab Content
            Group {
                switch selectedTab {
                case .dashboard:
                    ExploitScreen(
                        manager: manager,
                        palette: palette,
                        language: language,
                        onContinue: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = .games
                            }
                        }
                    )
                case .games:
                    GameListScreen(
                        manager: manager,
                        palette: palette,
                        language: language
                    )
                case .logs:
                    LogScreen(
                        manager: manager,
                        palette: palette,
                        language: language
                    )
                case .settings:
                    SettingsScreen(
                        manager: manager,
                        palette: palette,
                        language: language,
                        prefersDarkTheme: $prefersDarkTheme,
                        prefersVietnamese: $prefersVietnamese
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MARK: - Floating Glass Bottom Tab Bar
            FloatingGlassTabBar(
                selectedTab: $selectedTab,
                manager: manager,
                palette: palette,
                language: language
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(prefersDarkTheme ? .dark : .light)
        .tint(palette.accent)
    }
}

// MARK: - Floating Glass Tab Bar Component
private struct FloatingGlassTabBar: View {
    @Binding var selectedTab: AppTab
    @ObservedObject var manager: DarkSwordManager
    let palette: AppPalette
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon(isSelected: isSelected))
                                .font(.system(size: 19, weight: isSelected ? .bold : .medium))
                                .foregroundColor(
                                    isSelected
                                        ? (palette.isDark ? .white : .black)
                                        : palette.secondaryText
                                )
                                .frame(height: 24)

                            // Status Indicator Badges
                            if tab == .games && manager.remoteConnected {
                                Circle()
                                    .fill(palette.success)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -2)
                            } else if tab == .logs && !manager.remoteError.isEmpty {
                                Circle()
                                    .fill(palette.danger)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -2)
                            }
                        }

                        Text(tab.title(language))
                            .font(.system(size: 10, weight: isSelected ? .heavy : .medium, design: .rounded))
                            .foregroundColor(
                                isSelected
                                    ? (palette.isDark ? .white : .black)
                                    : palette.mutedText
                            )
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        palette.isDark
                                            ? Color.white.opacity(0.18)
                                            : Color.white.opacity(0.92)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(palette.glassBorderHighlight, lineWidth: 1)
                                    )
                                    .shadow(
                                        color: palette.isDark ? Color.black.opacity(0.3) : Color.black.opacity(0.06),
                                        radius: 6,
                                        x: 0,
                                        y: 2
                                    )
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.glassCardRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(palette.glassBorderHighlight, lineWidth: 1.2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(palette.glassBorder, lineWidth: 0.8)
                )
                .shadow(color: palette.glassShadow, radius: 18, x: 0, y: 8)
        )
    }
}
