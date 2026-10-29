//
//  GameCard.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import SwiftUI

struct GameCard: View {
    let game: GameStatusInfo
    let statusText: String?
    let isBusy: Bool
    let isConnected: Bool
    let palette: AppPalette

    init(
        game: GameStatusInfo,
        statusText: String?,
        isBusy: Bool,
        isConnected: Bool = false,
        palette: AppPalette
    ) {
        self.game = game
        self.statusText = statusText
        self.isBusy = isBusy
        self.isConnected = isConnected
        self.palette = palette
    }

    var body: some View {
        GlassCard(palette: palette, cornerRadius: 20, isRaised: isConnected) {
            HStack(spacing: 16) {
                // Game Avatar in Rounded Glass Container
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.iconBackground)

                    if let avatar = AppImageCatalog.gameAvatar(for: game.bundleIdentifier) {
                        Image(uiImage: avatar)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(palette.accent)
                    }
                }
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isConnected ? palette.accent : palette.glassBorderHighlight,
                            lineWidth: isConnected ? 1.5 : 1
                        )
                )
                .shadow(
                    color: isConnected ? palette.accent.opacity(0.3) : Color.clear,
                    radius: 8,
                    x: 0,
                    y: 2
                )

                // Info Column
                VStack(alignment: .leading, spacing: 5) {
                    Text(game.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(palette.primaryText)

                    Text(game.bundleIdentifier)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.secondaryText)
                        .lineLimit(1)

                    if let statusText {
                        GlassBadge(
                            title: statusText,
                            color: isConnected ? palette.success : palette.accent,
                            palette: palette,
                            pulsing: isConnected || isBusy
                        )
                    }
                }

                Spacer(minLength: 8)

                // Action Indicator / Button
                ZStack {
                    Circle()
                        .fill(
                            isConnected
                                ? palette.success.opacity(0.18)
                                : palette.accent.opacity(palette.isDark ? 0.16 : 0.12)
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(
                                    isConnected ? palette.success.opacity(0.4) : palette.accent.opacity(0.35),
                                    lineWidth: 1
                                )
                        )

                    if isBusy {
                        ProgressView()
                            .tint(palette.accent)
                    } else {
                        Image(systemName: isConnected ? "checkmark.circle.fill" : "play.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(isConnected ? palette.success : palette.accent)
                    }
                }
            }
        }
    }
}
