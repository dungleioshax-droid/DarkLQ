//
//  AppStrings.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

import Foundation

enum AppLanguage: Equatable {
    case vietnamese
    case english
}

enum AppStrings {
    static let appTitle = "External DarkSword"
    static let developerCredit = "Develop by Le Tien Dat"
    static let bundleIdentifier = "Bundle ID"
    static let ios = "iOS"
    static let kernelBase = "Kernel base"
    static let kernelSlide = "Kernel slide"
    static let remoteCall = "RemoteCall"

    static func text(
        _ language: AppLanguage,
        vietnamese: String,
        english: String
    ) -> String {
        language == .vietnamese ? vietnamese : english
    }

    static func languageToggleCode(_ language: AppLanguage) -> String {
        language == .vietnamese ? "EN" : "VI"
    }

    static func languageToggleAccessibility(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Chuyển sang tiếng Anh",
            english: "Switch to Vietnamese"
        )
    }

    static func themeAccessibility(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Đổi giao diện", english: "Toggle theme")
    }

    static func logTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Nhật ký", english: "Log")
    }

    static func clearLogAccessibility(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Xóa log", english: "Clear log")
    }

    static func noLogs(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Chưa có log", english: "No logs")
    }

    static func exploitAction(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Tấn công thiết bị",
            english: "Exploit DarkSword"
        )
    }

    static func continueAction(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Tiếp tục", english: "Continue")
    }

    static func gamesTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Trò chơi", english: "Games")
    }

    static func disconnectAction(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Ngắt kết nối", english: "Disconnect")
    }

    static func gameLaunchFailureTitle(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Không mở được game",
            english: "Could not open game"
        )
    }

    static func gameLaunchDetails(
        error: String,
        bundleIdentifier: String,
        process: String,
        status: String,
        language: AppLanguage
    ) -> String {
        [
            error,
            "",
            "\(Self.bundleIdentifier): \(bundleIdentifier)",
            "\(text(language, vietnamese: "Tiến trình", english: "Process")): \(process)",
            "\(text(language, vietnamese: "Trạng thái", english: "Status")): \(aovStatus(status, language: language))",
        ].joined(separator: "\n")
    }

    static func kernelState(
        _ state: DarkSwordManager.KernelState,
        language: AppLanguage
    ) -> String {
        guard language == .vietnamese else { return state.rawValue }

        switch state {
        case .idle:
            return "Đang chờ"
        case .running:
            return "Đang tấn công"
        case .ready:
            return "Sẵn sàng"
        case .failed:
            return "Thất bại"
        }
    }

    static func gameCellStatus(
        _ status: String?,
        language: AppLanguage
    ) -> String? {
        status.map { aovStatus($0, language: language) }
    }

    static func aovStatus(
        _ status: String,
        language: AppLanguage
    ) -> String {
        guard language == .vietnamese else { return status }

        if status.hasPrefix("Connected to ") {
            return "Đã kết nối tới "
                + String(status.dropFirst("Connected to ".count))
        }

        switch status {
        case "Idle":
            return "Đang chờ"
        case "Opening":
            return "Đang mở"
        case "Waiting 3 seconds...":
            return "Đợi 3 giây..."
        case "Connecting...":
            return "Đang kết nối..."
        case "Disconnecting...":
            return "Đang ngắt kết nối..."
        case "Disconnected":
            return "Đã ngắt kết nối"
        case "Connect failed":
            return "Kết nối thất bại"
        case "Launch failed":
            return "Mở game thất bại"
        case "Not connected":
            return "Chưa kết nối"
        default:
            return status
        }
    }

    static func deviceTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Thiết bị", english: "Device")
    }

    static func remoteCallStatus(
        connected: Bool,
        process: String,
        language: AppLanguage
    ) -> String {
        guard connected else {
            return text(
                language,
                vietnamese: "Đã ngắt kết nối",
                english: "Disconnected"
            )
        }
        let title = text(
            language,
            vietnamese: "Đã kết nối",
            english: "Connected"
        )
        return "\(title) (\(process))"
    }
}
