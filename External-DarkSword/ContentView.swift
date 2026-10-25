//
//  ContentView.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/3/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: DarkSwordManager
    @State private var isShowingGames = false
    @AppStorage("ui.prefersDarkTheme") private var prefersDarkTheme = true
    @AppStorage("ui.prefersVietnamese") private var prefersVietnamese = true

    private var palette: AppPalette {
        AppPalette(isDark: prefersDarkTheme)
    }

    private var language: AppLanguage {
        prefersVietnamese ? .vietnamese : .english
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(palette: palette)

                if isShowingGames {
                    GameListScreen(
                        manager: manager,
                        palette: palette,
                        language: language
                    )
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.98))
                    )
                } else {
                    ExploitScreen(
                        manager: manager,
                        palette: palette,
                        language: language,
                        onContinue: { isShowingGames = true }
                    )
                    .transition(.opacity)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if manager.isDebug {
                        NavigationLink {
                            LogScreen(
                                manager: manager,
                                palette: palette,
                                language: language
                            )
                        } label: {
                            Image(systemName: "doc.text")
                        }
                        .accessibilityLabel(AppStrings.logTitle(language))
                    }

                    Button {
                        prefersDarkTheme.toggle()
                    } label: {
                        Image(
                            systemName: prefersDarkTheme
                                ? "sun.max.fill" : "moon.fill"
                        )
                    }
                    .accessibilityLabel(AppStrings.themeAccessibility(language))

                    Button {
                        prefersVietnamese.toggle()
                    } label: {
                        Text(AppStrings.languageToggleCode(language))
                            .font(
                                .system(
                                    size: 12,
                                    weight: .heavy,
                                    design: .rounded
                                )
                            )
                            .foregroundColor(palette.primaryText)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(palette.iconBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(palette.border, lineWidth: 1)
                            )
                    }
                    .accessibilityLabel(
                        AppStrings.languageToggleAccessibility(language)
                    )
                }
            }
        }
        .tint(palette.accent)
        .preferredColorScheme(prefersDarkTheme ? .dark : .light)
        .animation(.easeInOut(duration: 0.2), value: isShowingGames)
    }
}
