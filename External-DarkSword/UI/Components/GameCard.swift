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
    let palette: AppPalette

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.iconBackground)

                if let avatar = AppImageCatalog.gameAvatar(
                    for: game.bundleIdentifier
                ) {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(palette.primaryText)
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(palette.border, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(game.name)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundColor(palette.primaryText)

                Text(game.bundleIdentifier)
                    .font(
                        .system(.caption, design: .monospaced).weight(.medium)
                    )
                    .foregroundColor(palette.secondaryText)
                    .lineLimit(1)

                if let statusText {
                    StatusPill(
                        title: statusText,
                        color: palette.accent,
                        palette: palette
                    )
                }
            }

            Spacer(minLength: 10)

            Image(systemName: isBusy ? "clock.fill" : "play.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(palette.accent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.border, lineWidth: 1)
                )
        )
    }
}
