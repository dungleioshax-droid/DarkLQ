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

    private let timer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        let _ = manager.gameStatusVersion
        let aovGame = manager.aovGameStatus()
        let freeFireGame = manager.freeFireGameStatus()

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(AppStrings.gamesTitle(language))
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(palette.primaryText)
                    .padding(.horizontal, 22)
                    .padding(.top, 28)

                if manager.isDebug {
                    DebugKernelPanel(
                        manager: manager,
                        palette: palette,
                        language: language
                    )
                    .padding(.horizontal, 22)
                }

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
                        statusText: AppStrings.gameCellStatus(
                            manager.aovGameCellStatus,
                            language: language
                        ),
                        isBusy: manager.isBusy,
                        palette: palette
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)

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
                        statusText: AppStrings.gameCellStatus(
                            manager.freeFireGameCellStatus,
                            language: language
                        ),
                        isBusy: manager.isBusy,
                        palette: palette
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 8) {
                    if manager.remoteConnected {
                        Text(
                            AppStrings.remoteCallStatus(
                                connected: true,
                                process: manager.connectedProcess,
                                language: language
                            )
                        )
                        .font(
                            .system(.footnote, design: .monospaced).weight(.bold)
                        )
                        .foregroundColor(palette.accent)
                    } else {
                        if manager.aovStatus != "Idle" {
                            Text(
                                "AoV: \(AppStrings.aovStatus(manager.aovStatus, language: language))"
                            )
                            .font(
                                .system(.footnote, design: .monospaced).weight(.bold)
                            )
                            .foregroundColor(palette.secondaryText)
                        }
                        if manager.freeFireStatus != "Idle" {
                            Text(
                                "Free Fire: \(AppStrings.aovStatus(manager.freeFireStatus, language: language))"
                            )
                            .font(
                                .system(.footnote, design: .monospaced).weight(.bold)
                            )
                            .foregroundColor(palette.secondaryText)
                        }
                        if manager.aovStatus == "Idle" && manager.freeFireStatus == "Idle" {
                            Text(
                                AppStrings.aovStatus(
                                    manager.aovStatus,
                                    language: language
                                )
                            )
                            .font(
                                .system(.footnote, design: .monospaced).weight(.bold)
                            )
                            .foregroundColor(palette.secondaryText)
                        }
                    }

                    if !manager.remoteError.isEmpty {
                        Text(manager.remoteError)
                            .font(.footnote)
                            .foregroundColor(.red.opacity(0.92))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, manager.remoteConnected ? 96 : 42)
            }
        }
        .scrollIndicators(.visible)
        .alert(
            AppStrings.gameLaunchFailureTitle(language),
            isPresented: $isShowingLaunchAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchAlertMessage)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if manager.remoteConnected {
                    Button(action: manager.disconnectRemoteCall) {
                        Label(
                            AppStrings.disconnectAction(language),
                            systemImage: "xmark.circle.fill"
                        )
                        .font(.system(size: 16, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(DisconnectButtonStyle(palette: palette))
                    .disabled(manager.isBusy)
                    .padding(.horizontal, 24)
                }

                DeveloperFooter(palette: palette)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            .background(palette.background)
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
