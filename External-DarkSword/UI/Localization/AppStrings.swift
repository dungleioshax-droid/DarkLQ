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

    // MARK: - Navigation Tabs
    static func tabDashboard(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Khai thác", english: "Exploit")
    }

    static func tabGames(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Trò chơi", english: "Games")
    }

    static func tabLogs(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Nhật ký", english: "Logs")
    }

    static func tabSettings(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Cài đặt", english: "Settings")
    }

    // MARK: - Toggles & Controls
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

    // MARK: - Dashboard / Exploit Screen
    static func exploitAction(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Tấn công thiết bị",
            english: "Exploit DarkSword"
        )
    }

    static func exploitRunning(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Đang tấn công kernel...",
            english: "Exploiting kernel..."
        )
    }

    static func continueAction(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Xem danh sách game", english: "View Games")
    }

    static func kernelMetricsTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Thông số Kernel", english: "Kernel Metrics")
    }

    static func deviceTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Thiết bị", english: "Device")
    }

    static func deviceStatusTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Trạng thái thiết bị", english: "Device Status")
    }

    static func keepAliveTitle(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Chạy ngầm liên tục (Keep-Alive)",
            english: "Background Keep-Alive"
        )
    }

    static func keepAliveDesc(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Giữ ứng dụng luôn hoạt động để duy trì hook overlay",
            english: "Keeps app alive in background to maintain overlay hooks"
        )
    }

    static func activeSessionTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Phiên kết nối hoạt động", english: "Active Connection Session")
    }

    static func viewGameControls(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Mở bảng điều khiển Game", english: "Open Game Panel")
    }

    // MARK: - Games Screen
    static func gamesTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Trò chơi hỗ trợ", english: "Supported Games")
    }

    static func gamesSubtitle(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Tự động khởi động và liên kết mod với ứng dụng",
            english: "Launch and automatically inject mod overlay"
        )
    }

    static func aovRenderModeTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Chế độ Render AoV", english: "AoV Render Mode")
    }

    static func renderInternal(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Internal Hook", english: "Internal Hook")
    }

    static func renderSpringboard(_ language: AppLanguage) -> String {
        text(language, vietnamese: "SpringBoard Overlay", english: "SpringBoard Overlay")
    }

    static func launchGameAction(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Mở game & Hook", english: "Launch & Hook")
    }

    static func gameOpeningAction(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Đang mở...", english: "Opening...")
    }

    static func connected(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Đã kết nối", english: "Connected")
    }

    static func disconnected(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Đã ngắt kết nối", english: "Disconnected")
    }

    static func disconnectAction(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Ngắt kết nối", english: "Disconnect")
    }

    static func tuningFeaturesTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Tùy chỉnh tính năng trong game", english: "In-Game Feature Tuning")
    }

    static func espOverlay(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Hiển thị ESP", english: "ESP Overlay")
    }

    static func hackMap(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Bản đồ nhỏ (Hack Map)", english: "Mini-Map Hack")
    }

    static func espSnaplines(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Đường kẻ (Snaplines)", english: "Snaplines")
    }

    static func espBoxes(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Khung hộp (2D Box)", english: "2D Box")
    }

    static func espHealth(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Thanh máu (HP)", english: "Health Bar")
    }

    static func espName(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Tên người chơi", english: "Player Name")
    }

    static func espDistance(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Khoảng cách (Distance)", english: "Distance")
    }

    static func cameraHeightTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Góc nhìn Camera", english: "Camera Height")
    }

    // MARK: - Logs Screen
    static func logTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Nhật ký hệ thống", english: "System Console")
    }

    static func clearLogAccessibility(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Xóa toàn bộ log", english: "Clear all logs")
    }

    static func copyLogAccessibility(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Sao chép log", english: "Copy logs")
    }

    static func copiedToast(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Đã sao chép vào bộ nhớ tạm!", english: "Copied to clipboard!")
    }

    static func noLogs(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Chưa có bản ghi nhật ký nào",
            english: "No console logs recorded yet"
        )
    }

    static func filterAll(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Tất cả", english: "All")
    }

    static func filterKernel(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Kernel", english: "Kernel")
    }

    static func filterGames(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Game", english: "Game")
    }

    static func filterErrors(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Lỗi", english: "Error")
    }

    // MARK: - Settings Screen
    static func settingsTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Cài đặt & Giới thiệu", english: "Settings & About")
    }

    static func appearanceSection(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Giao diện hiển thị", english: "Appearance")
    }

    static func themeDarkGlass(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Kính tối (Dark Glass)", english: "Dark Glass")
    }

    static func themeLightGlass(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Kính sáng (Light Glass)", english: "Light Glass")
    }

    static func languageSection(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Ngôn ngữ", english: "Language")
    }

    static func advancedSection(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Khai thác & Kết nối", english: "Kernel & Connection")
    }

    static func migBypassTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Vượt qua MIG Filter", english: "MIG Filter Bypass")
    }

    static func migBypassDesc(_ language: AppLanguage) -> String {
        text(
            language,
            vietnamese: "Bỏ qua bộ lọc cổng MIG để tăng tỷ lệ thành công của RemoteCall",
            english: "Bypass MIG port filtering to improve RemoteCall reliability"
        )
    }

    static func targetProcessTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Tiến trình mục tiêu", english: "Target Process")
    }

    static func socketClientsTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Overlay Clients kết nối", english: "Connected Overlay Clients")
    }

    static func aboutAppSection(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Về ứng dụng DarkSword", english: "About DarkSword")
    }

    static func versionTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Phiên bản", english: "Version")
    }

    static func architectureTitle(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Kiến trúc hỗ trợ", english: "Architecture")
    }

    static func devName(_ language: AppLanguage) -> String {
        text(language, vietnamese: "Tác giả phát triển", english: "Lead Developer")
    }

    // MARK: - Alert & Status Helpers
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
