//
//  DebugKernelPanel.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import SwiftUI

struct DebugKernelPanel: View {
    @ObservedObject var manager: DarkSwordManager
    let palette: AppPalette
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 10) {
            DebugRow(
                title: AppStrings.deviceTitle(language),
                value: manager.supportStatus.deviceIdentifier,
                palette: palette
            )
            DebugRow(
                title: AppStrings.ios,
                value: manager.supportStatus.osVersion,
                palette: palette
            )
            DebugRow(
                title: AppStrings.kernelBase,
                value: manager.kernelBaseText,
                palette: palette
            )
            DebugRow(
                title: AppStrings.kernelSlide,
                value: manager.kernelSlideText,
                palette: palette
            )
            DebugRow(
                title: AppStrings.remoteCall,
                value: AppStrings.remoteCallStatus(
                    connected: manager.remoteConnected,
                    process: manager.connectedProcess,
                    language: language
                ),
                palette: palette
            )
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

private struct DebugRow: View {
    let title: String
    let value: String
    let palette: AppPalette

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundColor(palette.secondaryText)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}
