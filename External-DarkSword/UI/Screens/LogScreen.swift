//
//  LogScreen.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import SwiftUI
import UIKit

struct LogScreen: View {
    @ObservedObject var manager: DarkSwordManager
    let palette: AppPalette
    let language: AppLanguage

    @State private var selectedFilter: LogFilter = .all
    @State private var showCopiedToast = false

    enum LogFilter: String, CaseIterable {
        case all
        case kernel
        case games
        case errors

        func localizedTitle(_ language: AppLanguage) -> String {
            switch self {
            case .all:
                return AppStrings.filterAll(language)
            case .kernel:
                return AppStrings.filterKernel(language)
            case .games:
                return AppStrings.filterGames(language)
            case .errors:
                return AppStrings.filterErrors(language)
            }
        }
    }

    private var logLines: [String] {
        manager.logText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var filteredLines: [String] {
        switch selectedFilter {
        case .all:
            return logLines
        case .kernel:
            return logLines.filter { line in
                let lower = line.lowercased()
                return lower.contains("kernel") || lower.contains("kfd") || lower.contains("task") || lower.contains("slide") || lower.contains("base")
            }
        case .games:
            return logLines.filter { line in
                let lower = line.lowercased()
                return lower.contains("aov") || lower.contains("freefire") || lower.contains("kgvn") || lower.contains("hook") || lower.contains("esp")
            }
        case .errors:
            return logLines.filter { line in
                let lower = line.lowercased()
                return lower.contains("error") || lower.contains("fail") || lower.contains("exception") || lower.contains("warn")
            }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                headerAreaView
                terminalCardView
            }

            if showCopiedToast {
                toastView
            }
        }
    }

    private var headerAreaView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(palette.accent)

                        Text(AppStrings.logTitle(language))
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(palette.primaryText)
                    }

                    Text("\(filteredLines.count) \(AppStrings.text(language, vietnamese: "dòng ghi nhận", english: "recorded lines"))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.mutedText)
                }

                Spacer()

                HStack(spacing: 8) {
                    copyButton
                    clearButton
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)

            filterChipsRow
        }
    }

    private var copyButton: some View {
        Button(action: copyLogsToClipboard) {
            ZStack {
                Circle()
                    .fill(palette.glassCard)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(palette.glassBorder, lineWidth: 1))

                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(palette.accent)
            }
        }
        .buttonStyle(.plain)
        .disabled(manager.logText.isEmpty)
        .accessibilityLabel(AppStrings.copyLogAccessibility(language))
    }

    private var clearButton: some View {
        Button(action: manager.clearLog) {
            ZStack {
                Circle()
                    .fill(palette.glassCard)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(palette.glassBorder, lineWidth: 1))

                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(manager.logText.isEmpty ? palette.mutedText : palette.danger)
            }
        }
        .buttonStyle(.plain)
        .disabled(manager.logText.isEmpty)
        .accessibilityLabel(AppStrings.clearLogAccessibility(language))
    }

    private var filterChipsRow: some View {
        HStack(spacing: 6) {
            ForEach(LogFilter.allCases, id: \.self) { filter in
                let isSelected = selectedFilter == filter
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.localizedTitle(language))
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(isSelected ? (palette.isDark ? .white : .black) : palette.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? (palette.isDark ? Color.white.opacity(0.18) : Color.white.opacity(0.95)) : palette.glassCardSubtle)
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? palette.glassBorderStrong : palette.glassBorder, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var terminalCardView: some View {
        GlassCard(palette: palette, cornerRadius: 20) {
            ScrollView {
                if filteredLines.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                            logLineRow(index: index, line: line)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 96)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(palette.mutedText)

            Text(AppStrings.noLogs(language))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(palette.mutedText)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private func logLineRow(index: Int, line: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(format: "%03d", index + 1))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(palette.mutedText.opacity(0.6))
                .frame(width: 26, alignment: .trailing)

            Text(line)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundColor(lineColor(for: line))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var toastView: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(palette.success)
                Text(AppStrings.copiedToast(language))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .overlay(Capsule().stroke(palette.glassBorderHighlight, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 108)
        }
    }

    private func copyLogsToClipboard() {
        UIPasteboard.general.string = manager.logText
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.25)) {
                showCopiedToast = false
            }
        }
    }

    private func lineColor(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fail") || lower.contains("crash") {
            return palette.danger
        } else if lower.contains("success") || lower.contains("ready") || lower.contains("connected") {
            return palette.success
        } else if lower.contains("warn") {
            return palette.warning
        } else if lower.contains("kernel") || lower.contains("kfd") || lower.contains("hook") {
            return palette.accent
        } else {
            return palette.primaryText.opacity(0.88)
        }
    }
}
