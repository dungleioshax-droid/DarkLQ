//
//  SharedUI.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import SwiftUI

struct AppBackground: View {
    let palette: AppPalette

    var body: some View {
        palette.background
            .ignoresSafeArea()
    }
}

struct DeveloperFooter: View {
    let palette: AppPalette

    var body: some View {
        Text(AppStrings.developerCredit)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundColor(palette.mutedText)
            .multilineTextAlignment(.center)
    }
}

struct StatusPill: View {
    let title: String
    let color: Color
    let palette: AppPalette

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(palette.pillBackground))
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    let palette: AppPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.black)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

struct DisconnectButtonStyle: ButtonStyle {
    let palette: AppPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.red)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.45), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
