//
//  LogScreen.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import SwiftUI

struct LogScreen: View {
    @ObservedObject var manager: DarkSwordManager
    let palette: AppPalette
    let language: AppLanguage

    var body: some View {
        ScrollView {
            Text(
                manager.logText.isEmpty
                    ? AppStrings.noLogs(language)
                    : manager.logText
            )
            .font(.system(.footnote, design: .monospaced))
            .foregroundColor(palette.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .padding(16)
            .textSelection(.enabled)
        }
        .background(AppBackground(palette: palette))
        .navigationTitle(AppStrings.logTitle(language))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            DeveloperFooter(palette: palette)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(palette.background)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: manager.clearLog) {
                    Image(systemName: "trash")
                }
                .disabled(manager.logText.isEmpty)
                .accessibilityLabel(AppStrings.clearLogAccessibility(language))
            }
        }
    }
}
