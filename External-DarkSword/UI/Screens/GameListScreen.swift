//
//  GameListScreen.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import Combine
import SwiftUI

struct GameListScreen: View {
    @ObservedObject var manager: DarkSwordManager
    let palette: AppPalette
    let language: AppLanguage

    @State private var isShowingLaunchAlert = false
    @State private var launchAlertMessage = ""
    @State private var isWaitingForGameActionResult = false
    @State private var lastAttemptedGame = "aov"
    @State private var isAoVFeaturesExpanded = false
    @State private var isFreeFireFeaturesExpanded = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let _ = manager.gameStatusVersion
        let aovGame = manager.aovGameStatus()
        let freeFireGame = manager.freeFireGameStatus()
        let isAoVConnected = manager.remoteConnected
            && manager.connectedProcess.lowercased().contains(manager.aovProcess.lowercased())
        let isFreeFireConnected = manager.remoteConnected
            && manager.connectedProcess.lowercased().contains(manager.freeFireProcess.lowercased())

        ScrollView {
            VStack(spacing: 20) {
                // Header Title
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppStrings.gamesTitle(language))
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(palette.primaryText)

                            Text(AppStrings.gamesSubtitle(language))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(palette.mutedText)
                        }

                        Spacer()

                        if manager.remoteConnected {
                            GlassBadge(
                                title: AppStrings.connected(language),
                                color: palette.success,
                                palette: palette,
                                pulsing: true
                            )
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)

                // MARK: - Active Connection Banner with Disconnect Button
                if manager.remoteConnected {
                    GlassCard(palette: palette, cornerRadius: 20, isRaised: true) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(palette.success)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppStrings.remoteCallStatus(
                                    connected: true,
                                    process: manager.connectedProcess,
                                    language: language
                                ))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryText)

                                Text("RemoteCall Hook Active")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(palette.success)
                            }

                            Spacer()

                            Button(action: manager.disconnectRemoteCall) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text(AppStrings.disconnectAction(language))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(DisconnectButtonStyle(palette: palette))
                            .disabled(manager.isBusy)
                        }
                    }
                    .padding(.horizontal, 18)
                }

                // MARK: - AoV Render Mode Selector
                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionHeader(
                        title: AppStrings.aovRenderModeTitle(language),
                        icon: "display",
                        palette: palette
                    )
                    .padding(.horizontal, 22)

                    GlassSegmentedPicker(
                        options: [
                            AppStrings.renderInternal(language),
                            AppStrings.renderSpringboard(language)
                        ],
                        selectedIndex: Binding(
                            get: { manager.aovRenderMode == "springboard" ? 1 : 0 },
                            set: { manager.aovRenderMode = ($0 == 1 ? "springboard" : "internal") }
                        ),
                        palette: palette
                    )
                    .padding(.horizontal, 18)
                }

                // MARK: - Arena of Valor Card & Drawer
                VStack(spacing: 10) {
                    // Main AoV Card
                    Button {
                        lastAttemptedGame = "aov"
                        isWaitingForGameActionResult = true
                        manager.openAoVAndConnect()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showLaunchErrorIfNeeded()
                        }
                    } label: {
                        GameCard(
                            game: aovGame,
                            statusText: AppStrings.gameCellStatus(manager.aovGameCellStatus, language: language),
                            isBusy: manager.isOpeningAoV || (manager.isBusy && lastAttemptedGame == "aov"),
                            isConnected: isAoVConnected,
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)

                    // Expandable AoV Features Control
                    GlassCard(palette: palette, cornerRadius: 18) {
                        VStack(spacing: 12) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isAoVFeaturesExpanded.toggle()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(palette.accent)

                                    Text(AppStrings.tuningFeaturesTitle(language))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(palette.primaryText)

                                    Spacer()

                                    Image(systemName: isAoVFeaturesExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(palette.secondaryText)
                                }
                            }
                            .buttonStyle(.plain)

                            if isAoVFeaturesExpanded {
                                Divider().background(palette.glassBorder)

                                // Toggles List
                                VStack(spacing: 10) {
                                    FeatureToggleRow(
                                        title: AppStrings.espOverlay(language),
                                        isOn: $manager.aovESPEnabled,
                                        palette: palette
                                    )
                                    FeatureToggleRow(
                                        title: AppStrings.hackMap(language),
                                        isOn: $manager.aovHackMapEnabled,
                                        palette: palette
                                    )
                                    FeatureToggleRow(
                                        title: AppStrings.espSnaplines(language),
                                        isOn: $manager.aovShowsLine,
                                        palette: palette
                                    )
                                    FeatureToggleRow(
                                        title: AppStrings.espBoxes(language),
                                        isOn: $manager.aovShowsBox,
                                        palette: palette
                                    )
                                    FeatureToggleRow(
                                        title: AppStrings.espHealth(language),
                                        isOn: $manager.aovShowsHealth,
                                        palette: palette
                                    )
                                    FeatureToggleRow(
                                        title: AppStrings.espDistance(language),
                                        isOn: $manager.aovShowsDistance,
                                        palette: palette
                                    )

                                    // Camera Height Slider
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(AppStrings.cameraHeightTitle(language))
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundColor(palette.secondaryText)
                                            Spacer()
                                            Text(String(format: "%.1fx", manager.aovCameraHeight))
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(palette.accent)
                                        }

                                        Slider(value: $manager.aovCameraHeight, in: 1.0...2.5, step: 0.1)
                                            .tint(palette.accent)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)

                // MARK: - Free Fire Card & Drawer
                VStack(spacing: 10) {
                    // Main Free Fire Card
                    Button {
                        lastAttemptedGame = "freefire"
                        isWaitingForGameActionResult = true
                        manager.openFreeFireAndConnect()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showLaunchErrorIfNeeded()
                        }
                    } label: {
                        GameCard(
                            game: freeFireGame,
                            statusText: AppStrings.gameCellStatus(manager.freeFireGameCellStatus, language: language),
                            isBusy: manager.isOpeningFreeFire || (manager.isBusy && lastAttemptedGame == "freefire"),
                            isConnected: isFreeFireConnected,
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)

                    // Expandable Free Fire Features Control
                    GlassCard(palette: palette, cornerRadius: 18) {
                        VStack(spacing: 12) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isFreeFireFeaturesExpanded.toggle()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(palette.accent)

                                    Text(AppStrings.tuningFeaturesTitle(language))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(palette.primaryText)

                                    Spacer()

                                    Image(systemName: isFreeFireFeaturesExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(palette.secondaryText)
                                }
                            }
                            .buttonStyle(.plain)

                            if isFreeFireFeaturesExpanded {
                                Divider().background(palette.glassBorder)

                                VStack(spacing: 10) {
                                    FeatureToggleRow(
                                        title: AppStrings.espOverlay(language),
                                        isOn: $manager.freeFireESPEnabled,
                                        palette: palette
                                    )
                                    FeatureToggleRow(
                                        title: AppStrings.espSnaplines(language),
                                        isOn: $manager.freeFireShowsLine,
                                        palette: palette
                                    )
                                    FeatureToggleRow(
                                        title: AppStrings.espBoxes(language),
                                        isOn: $manager.freeFireShowsBox,
                                        palette: palette
                                    )
                                    FeatureToggleRow(
                                        title: AppStrings.espHealth(language),
                                        isOn: $manager.freeFireShowsHealth,
                                        palette: palette
                                    )
                                    FeatureToggleRow(
                                        title: AppStrings.espDistance(language),
                                        isOn: $manager.freeFireShowsDistance,
                                        palette: palette
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)

                // Error Message if any
                if !manager.remoteError.isEmpty {
                    GlassCard(palette: palette, cornerRadius: 16) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(palette.danger)
                            Text(manager.remoteError)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(palette.danger)
                        }
                    }
                    .padding(.horizontal, 18)
                }

                Spacer(minLength: 96) // Space for floating bottom tab bar
            }
        }
        .scrollIndicators(.hidden)
        .alert(
            AppStrings.gameLaunchFailureTitle(language),
            isPresented: $isShowingLaunchAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchAlertMessage)
        }
        .onReceive(timer) { _ in
            manager.refreshGameStatuses()
        }
        .onChange(of: manager.remoteError) { _ in
            showLaunchErrorIfNeeded()
        }
        .onChange(of: manager.remoteConnected) { connected in
            if connected {
                isWaitingForGameActionResult = false
            }
        }
    }

    private func showLaunchErrorIfNeeded() {
        guard isWaitingForGameActionResult else { return }
        guard !manager.remoteError.isEmpty else { return }
        if lastAttemptedGame == "freefire" {
            launchAlertMessage = AppStrings.gameLaunchDetails(
                error: manager.remoteError,
                bundleIdentifier: manager.freeFireBundleIdentifier,
                process: manager.freeFireProcess,
                status: manager.freeFireStatus,
                language: language
            )
        } else {
            launchAlertMessage = AppStrings.gameLaunchDetails(
                error: manager.remoteError,
                bundleIdentifier: manager.aovBundleIdentifier,
                process: manager.aovProcess,
                status: manager.aovStatus,
                language: language
            )
        }
        isWaitingForGameActionResult = false
        isShowingLaunchAlert = true
    }
}

// MARK: - Feature Toggle Row
private struct FeatureToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let palette: AppPalette

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(palette.primaryText)
        }
        .tint(palette.accent)
    }
}
