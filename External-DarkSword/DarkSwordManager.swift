//
//  DarkSwordManager.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/3/26.
//

import Darwin
import Foundation
import UIKit

struct DarkSwordSupportStatus {
    let osVersion: String
    let deviceIdentifier: String
    let debuggerAttached: Bool
    let isSupported: Bool
    let reason: String

    var stateText: String {
        isSupported ? "Supported" : "Blocked"
    }

    static func current() -> DarkSwordSupportStatus {
        let osVersion = UIDevice.current.systemVersion
        let deviceIdentifier = Self.machineIdentifier()
        let version = Version(osVersion)
        let supportedOS =
            (version >= Version(17, 0, 0) && version <= Version(18, 7, 1))
            || (version >= Version(26, 0, 0) && version < Version(26, 1, 0))
        let excludedChip = Self.isExcludedA19OrM5Device(deviceIdentifier)
        let debuggerAttached = Self.isDebuggerAttached()

        if !supportedOS {
            return DarkSwordSupportStatus(
                osVersion: osVersion,
                deviceIdentifier: deviceIdentifier,
                debuggerAttached: debuggerAttached,
                isSupported: false,
                reason: "Only iOS 17.0-18.7.1 and iOS 26.0.x are supported."
            )
        }

        if excludedChip {
            return DarkSwordSupportStatus(
                osVersion: osVersion,
                deviceIdentifier: deviceIdentifier,
                debuggerAttached: debuggerAttached,
                isSupported: false,
                reason: "A19 and M5 devices are not supported."
            )
        }

        if debuggerAttached {
            return DarkSwordSupportStatus(
                osVersion: osVersion,
                deviceIdentifier: deviceIdentifier,
                debuggerAttached: true,
                isSupported: false,
                reason:
                    "DarkSword and RemoteCall are not available while a debugger is attached. Launch the sideloaded app directly from the Home Screen."
            )
        }

        return DarkSwordSupportStatus(
            osVersion: osVersion,
            deviceIdentifier: deviceIdentifier,
            debuggerAttached: false,
            isSupported: true,
            reason: "Ready for DarkSword."
        )
    }

    private static func isExcludedA19OrM5Device(_ identifier: String) -> Bool {
        identifier.hasPrefix("iPhone18,") || identifier.hasPrefix("iPad17,")
    }

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        var machine = systemInfo.machine
        return withUnsafeBytes(of: &machine) { buffer in
            let pointer = buffer.bindMemory(to: CChar.self).baseAddress
            return pointer.map { String(cString: $0) } ?? "unknown"
        }
    }

    private static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }

        let tracedFlag: Int32 = 0x0000_0800
        return (info.kp_proc.p_flag & tracedFlag) != 0
    }

    private struct Version: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        init(_ major: Int, _ minor: Int, _ patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        init(_ text: String) {
            let parts = text.split(separator: ".").map { Int($0) ?? 0 }
            self.major = parts.indices.contains(0) ? parts[0] : 0
            self.minor = parts.indices.contains(1) ? parts[1] : 0
            self.patch = parts.indices.contains(2) ? parts[2] : 0
        }

        static func < (lhs: Version, rhs: Version) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }
    }
}

struct GameStatusInfo: Identifiable {
    let name: String
    let bundleIdentifier: String
    let processName: String
    let isInstalled: Bool
    let isRunning: Bool

    var id: String { bundleIdentifier }
}

final class DarkSwordManager: ObservableObject {
    enum KernelState: String {
        case idle = "Idle"
        case running = "Running"
        case ready = "Ready"
        case failed = "Failed"
    }

    private enum DefaultsKey {
        static let targetProcess = "remote.targetProcess"
        static let useMigFilterBypass = "remote.useMigFilterBypass"
        static let aovProcess = "aov.process"
        static let aovESPEnabled = "aov.esp.enabled"
        static let aovHackMapEnabled = "aov.hackMap.enabled"
        static let aovShowsLine = "aov.esp.showsLine"
        static let aovShowsBox = "aov.esp.showsBox"
        static let aovShowsHealth = "aov.esp.showsHealth"
        static let aovShowsName = "aov.esp.showsName"
        static let aovShowsDistance = "aov.esp.showsDistance"
        static let aovCameraHeight = "aov.camera.height"
        static let aovRenderMode = "aov.render.mode"
        static let freeFireProcess = "freefire.process"
        static let freeFireESPEnabled = "freefire.esp.enabled"
        static let freeFireShowsLine = "freefire.esp.showsLine"
        static let freeFireShowsBox = "freefire.esp.showsBox"
        static let freeFireShowsHealth = "freefire.esp.showsHealth"
        static let freeFireShowsName = "freefire.esp.showsName"
        static let freeFireShowsDistance = "freefire.esp.showsDistance"
    }

    private enum DefaultsFallback {
        static let targetProcess = "kgvn"
        static let useMigFilterBypass = true
        static let aovProcess = "kgvn"
        static let aovESPEnabled = false
        static let aovHackMapEnabled = false
        static let aovShowsLine = false
        static let aovShowsBox = false
        static let aovShowsHealth = false
        static let aovShowsName = false
        static let aovShowsDistance = false
        static let aovCameraHeight = 1.0
        static let aovRenderMode = "springboard"
        static let freeFireProcess = "FreeFire"
        static let freeFireESPEnabled = false
        static let freeFireShowsLine = false
        static let freeFireShowsBox = false
        static let freeFireShowsHealth = false
        static let freeFireShowsName = false
        static let freeFireShowsDistance = false
    }

    private static let aovCameraHeightMinValue: Double = 1
    private static let aovCameraHeightMaxValue: Double = 10

    private static func resolvedAoVCameraHeight() -> Double {
        let value = AppUserDefaults.double(
            forKey: DefaultsKey.aovCameraHeight,
            fallbackValue: DefaultsFallback.aovCameraHeight
        )
        guard value.isFinite else { return DefaultsFallback.aovCameraHeight }
        return min(
            max(value, aovCameraHeightMinValue),
            aovCameraHeightMaxValue
        )
    }

    @Published var kernelState: KernelState = .idle
    @Published var progress: Double = 0
    @Published var kernelBaseText = "-"
    @Published var kernelSlideText = "-"
    @Published var targetProcess = AppUserDefaults.string(
        forKey: DefaultsKey.targetProcess,
        fallbackValue: DefaultsFallback.targetProcess
    ) {
        didSet {
            AppUserDefaults.setString(
                targetProcess,
                forKey: DefaultsKey.targetProcess
            )
        }
    }
    @Published var useMigFilterBypass = AppUserDefaults.bool(
        forKey: DefaultsKey.useMigFilterBypass,
        fallbackValue: DefaultsFallback.useMigFilterBypass
    ) {
        didSet {
            AppUserDefaults.setBool(
                useMigFilterBypass,
                forKey: DefaultsKey.useMigFilterBypass
            )
        }
    }
    @Published var remoteConnected = false
    @Published var connectedProcess = ""
    @Published var remoteError = ""
    @Published var symbolName = "getpid"
    @Published var argumentText = ""
    @Published var timeoutText = "5"
    @Published var lastCallResult = "-"
    @Published var isBusy = false
    @Published var logText = ""
    @Published private(set) var supportStatus = DarkSwordSupportStatus.current()
    @Published private(set) var offsetsInitialized = false
    @Published private(set) var kernelSymbolOffsetsReady = false
    @Published private(set) var selfProcessReady = false
    @Published var isKeepAliveEnabled = false
    @Published private(set) var overlaySocketClientCount = 0
    @Published private(set) var gameStatusVersion = 0
    @Published private(set) var isOpeningAoV = false

    @Published var aovProcess = AppUserDefaults.string(
        forKey: DefaultsKey.aovProcess,
        fallbackValue: DefaultsFallback.aovProcess
    ) {
        didSet {
            AppUserDefaults.setString(
                aovProcess,
                forKey: DefaultsKey.aovProcess
            )
        }
    }
    @Published var aovScanResult = "-"
    @Published var aovProbeResult = "-"
    @Published var aovStatus = "Idle"
    @Published var aovRenderMode = AppUserDefaults.string(
        forKey: DefaultsKey.aovRenderMode,
        fallbackValue: DefaultsFallback.aovRenderMode
    ) {
        didSet {
            AppUserDefaults.setString(
                aovRenderMode,
                forKey: DefaultsKey.aovRenderMode
            )
        }
    }

    @Published var aovESPEnabled = AppUserDefaults.bool(
        forKey: DefaultsKey.aovESPEnabled,
        fallbackValue: DefaultsFallback.aovESPEnabled
    ) {
        didSet {
            AppUserDefaults.setBool(
                aovESPEnabled,
                forKey: DefaultsKey.aovESPEnabled
            )
            syncAoVESPOptions()
        }
    }
    @Published var aovHackMapEnabled = AppUserDefaults.bool(
        forKey: DefaultsKey.aovHackMapEnabled,
        fallbackValue: DefaultsFallback.aovHackMapEnabled
    ) {
        didSet {
            AppUserDefaults.setBool(
                aovHackMapEnabled,
                forKey: DefaultsKey.aovHackMapEnabled
            )
            syncAoVESPOptions()
        }
    }
    @Published var aovShowsLine = AppUserDefaults.bool(
        forKey: DefaultsKey.aovShowsLine,
        fallbackValue: DefaultsFallback.aovShowsLine
    ) {
        didSet {
            AppUserDefaults.setBool(
                aovShowsLine,
                forKey: DefaultsKey.aovShowsLine
            )
            syncAoVESPOptions()
        }
    }
    @Published var aovShowsBox = AppUserDefaults.bool(
        forKey: DefaultsKey.aovShowsBox,
        fallbackValue: DefaultsFallback.aovShowsBox
    ) {
        didSet {
            AppUserDefaults.setBool(
                aovShowsBox,
                forKey: DefaultsKey.aovShowsBox
            )
            syncAoVESPOptions()
        }
    }
    @Published var aovShowsHealth = AppUserDefaults.bool(
        forKey: DefaultsKey.aovShowsHealth,
        fallbackValue: DefaultsFallback.aovShowsHealth
    ) {
        didSet {
            AppUserDefaults.setBool(
                aovShowsHealth,
                forKey: DefaultsKey.aovShowsHealth
            )
            syncAoVESPOptions()
        }
    }
    @Published var aovShowsName = AppUserDefaults.bool(
        forKey: DefaultsKey.aovShowsName,
        fallbackValue: DefaultsFallback.aovShowsName
    ) {
        didSet {
            AppUserDefaults.setBool(
                aovShowsName,
                forKey: DefaultsKey.aovShowsName
            )
            syncAoVESPOptions()
        }
    }
    @Published var aovShowsDistance = AppUserDefaults.bool(
        forKey: DefaultsKey.aovShowsDistance,
        fallbackValue: DefaultsFallback.aovShowsDistance
    ) {
        didSet {
            AppUserDefaults.setBool(
                aovShowsDistance,
                forKey: DefaultsKey.aovShowsDistance
            )
            syncAoVESPOptions()
        }
    }
    @Published var aovCameraHeight: Double =
        DarkSwordManager.resolvedAoVCameraHeight()
    {
        didSet {
            AppUserDefaults.setDouble(
                aovCameraHeight,
                forKey: DefaultsKey.aovCameraHeight
            )
            syncAoVESPOptions()
        }
    }

    let aovCameraHeightMin: Double = DarkSwordManager.aovCameraHeightMinValue
    let aovCameraHeightMax: Double = DarkSwordManager.aovCameraHeightMaxValue

    let aovBundleIdentifier = "com.garena.game.kgvn"

    var isSupportedDevice: Bool {
        supportStatus.isSupported
    }

    var isExploitReady: Bool {
        supportStatus.isSupported && kernelState == .ready
            && kernelSymbolOffsetsReady && selfProcessReady
    }

    var isToolingAvailable: Bool {
        isExploitReady
    }

    var isDebug: Bool {
        g_isDebug
    }

    var canContinueToGames: Bool {
        kernelState == .ready && isExploitReady
    }

    var isConnectedToAoV: Bool {
        let process = aovProcess.trimmingCharacters(in: .whitespacesAndNewlines)
        return remoteConnected && connectedProcess == process
    }

    var aovGameCellStatus: String? {
        if isOpeningAoV {
            return "Opening"
        }
        return nil
    }

    @Published private(set) var isOpeningFreeFire = false

    @Published var freeFireProcess = AppUserDefaults.string(
        forKey: DefaultsKey.freeFireProcess,
        fallbackValue: DefaultsFallback.freeFireProcess
    ) {
        didSet {
            AppUserDefaults.setString(
                freeFireProcess,
                forKey: DefaultsKey.freeFireProcess
            )
        }
    }
    @Published var freeFireScanResult = "-"
    @Published var freeFireStatus = "Idle"

    @Published var freeFireESPEnabled = AppUserDefaults.bool(
        forKey: DefaultsKey.freeFireESPEnabled,
        fallbackValue: DefaultsFallback.freeFireESPEnabled
    ) {
        didSet {
            AppUserDefaults.setBool(
                freeFireESPEnabled,
                forKey: DefaultsKey.freeFireESPEnabled
            )
            syncFreeFireESPOptions()
        }
    }
    @Published var freeFireShowsLine = AppUserDefaults.bool(
        forKey: DefaultsKey.freeFireShowsLine,
        fallbackValue: DefaultsFallback.freeFireShowsLine
    ) {
        didSet {
            AppUserDefaults.setBool(
                freeFireShowsLine,
                forKey: DefaultsKey.freeFireShowsLine
            )
            syncFreeFireESPOptions()
        }
    }
    @Published var freeFireShowsBox = AppUserDefaults.bool(
        forKey: DefaultsKey.freeFireShowsBox,
        fallbackValue: DefaultsFallback.freeFireShowsBox
    ) {
        didSet {
            AppUserDefaults.setBool(
                freeFireShowsBox,
                forKey: DefaultsKey.freeFireShowsBox
            )
            syncFreeFireESPOptions()
        }
    }
    @Published var freeFireShowsHealth = AppUserDefaults.bool(
        forKey: DefaultsKey.freeFireShowsHealth,
        fallbackValue: DefaultsFallback.freeFireShowsHealth
    ) {
        didSet {
            AppUserDefaults.setBool(
                freeFireShowsHealth,
                forKey: DefaultsKey.freeFireShowsHealth
            )
            syncFreeFireESPOptions()
        }
    }
    @Published var freeFireShowsName = AppUserDefaults.bool(
        forKey: DefaultsKey.freeFireShowsName,
        fallbackValue: DefaultsFallback.freeFireShowsName
    ) {
        didSet {
            AppUserDefaults.setBool(
                freeFireShowsName,
                forKey: DefaultsKey.freeFireShowsName
            )
            syncFreeFireESPOptions()
        }
    }
    @Published var freeFireShowsDistance = AppUserDefaults.bool(
        forKey: DefaultsKey.freeFireShowsDistance,
        fallbackValue: DefaultsFallback.freeFireShowsDistance
    ) {
        didSet {
            AppUserDefaults.setBool(
                freeFireShowsDistance,
                forKey: DefaultsKey.freeFireShowsDistance
            )
            syncFreeFireESPOptions()
        }
    }

    var freeFireBundleIdentifier: String {
        if isApplicationInstalled(bundleIdentifier: "com.dts.freefiremax") &&
            !isApplicationInstalled(bundleIdentifier: "com.dts.freefireth") {
            return "com.dts.freefiremax"
        }
        return "com.dts.freefireth"
    }

    // The overlay menu is shared by both games, so resolve which game is
    // currently connected before syncing or applying menu options.
    private var activeOverlayGame: String {
        let process = connectedProcess.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if process.lowercased().contains("freefire") || process.lowercased().contains("ffmax") {
            return "freefire"
        }
        if !process.isEmpty, process == aovProcess {
            return "aov"
        }
        if freeFireManager != nil && aovManager == nil {
            return "freefire"
        }
        if aovManager != nil && freeFireManager == nil {
            return "aov"
        }
        if !process.isEmpty {
            return "aov"
        }
        if freeFireManager != nil {
            return "freefire"
        }
        return "aov"
    }

    var isConnectedToFreeFire: Bool {
        let process = resolvedFreeFireProcessName()
        return remoteConnected && connectedProcess == process
    }

    var freeFireGameCellStatus: String? {
        if isOpeningFreeFire {
            return "Opening"
        }
        return nil
    }

    private var remoteCall: RemoteCall?
    private var springboardRemoteCall: RemoteCall?
    private var aovManager: AoVManager?
    private var freeFireManager: FreeFireManager?
    private let workerQueue = DispatchQueue(
        label: "external.darksword.worker",
        qos: .userInitiated
    )
    private static weak var activeManager: DarkSwordManager?
    private static let kernelRunLock = NSLock()
    private static var isKernelRunClaimed = false
    private static let offsetsLock = NSLock()
    private static var sharedOffsetsInitialized = false

    private func ensureSpringBoardRemoteCall() -> RemoteCall? {
        if let existing = springboardRemoteCall, existing.trojanMem != 0 {
            return existing
        }

        let mig = useMigFilterBypass
        DispatchQueue.main.async {
            self.appendLog("Connecting RemoteCall to SpringBoard for external overlay...")
        }
        let sbInstance = RemoteCall(process: "SpringBoard", useMigFilterBypass: mig)
        if let sbInstance, sbInstance.trojanMem != 0 {
            springboardRemoteCall = sbInstance
            DispatchQueue.main.async {
                self.appendLog("RemoteCall connected to SpringBoard (pid=\(sbInstance.pid)).")
            }
            return sbInstance
        } else {
            let error = RemoteCall.lastInitError() ?? "unknown error"
            DispatchQueue.main.async {
                self.appendLog("SpringBoard RemoteCall connection warning: \(error).")
            }
            return nil
        }
    }

    init() {
        DarkSwordManager.activeManager = self
        configureOverlaySocketCallbacks()
        ds_set_log_callback { message in
            guard let message else { return }
            DarkSwordManager.activeManager?.appendLog(String(cString: message))
        }
        ds_set_progress_callback { progress in
            DispatchQueue.main.async {
                DarkSwordManager.activeManager?.progress = progress
            }
        }

        prepareOffsetsIfNeeded()
        kernelSymbolOffsetsReady =
            emergencyfixfunctiontobereplacedlateronquestionmark()
        if !kernelSymbolOffsetsReady {
            appendLog(
                "Kernel symbol offsets are not resolved yet. They will be resolved before DarkSword runs."
            )
        }

        if supportStatus.debuggerAttached {
            appendLog(
                "Debugger detected. This launch context is blocked to match External DarkSword's RemoteCall requirements."
            )
        }

        if ds_is_ready() {
            kernelState = .ready
            refreshKernelInfo()
            _ = refreshSelfProcessState(logIfUnavailable: false)
            startKeepAlive()
        }
    }

    deinit {
        if remoteCall != nil {
            _ = remoteCall?.destroy()
        }
        if springboardRemoteCall != nil {
            _ = springboardRemoteCall?.destroy()
        }
    }

    func initializeDarkSword() {
        guard !isBusy else { return }
        guard Self.claimKernelRun() else {
            appendLog("DarkSword is already running in this process.")
            return
        }
        guard allowSupportedAction("DarkSword initialization") else {
            Self.releaseKernelRun()
            return
        }
        guard prepareOffsetsIfNeeded() else {
            Self.releaseKernelRun()
            return
        }

        if ds_is_ready() {
            let processReady = refreshSelfProcessState(logIfUnavailable: false)
            kernelState =
                kernelSymbolOffsetsReady && processReady ? .ready : .failed
            refreshKernelInfo()
            appendLog("DarkSword is already ready.")
            Self.releaseKernelRun()
            return
        }

        isBusy = true
        kernelState = .running
        progress = 0
        appendLog("Starting DarkSword...")

        workerQueue.async { [weak self] in
            guard let self else {
                Self.releaseKernelRun()
                return
            }
            defer { Self.releaseKernelRun() }
            let symbolsReady = self.resolveKernelSymbolOffsetsIfNeeded()
            guard symbolsReady else {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.kernelState = .failed
                    self.stopKeepAlive()
                    self.remoteError =
                        "Kernel symbol offsets are required for process lookup."
                    self.appendLog(
                        "DarkSword blocked: kernel symbol offsets could not be resolved."
                    )
                }
                return
            }

            let result = ds_run()
            let ready = ds_is_ready()
            let base = ds_get_kernel_base()
            let slide = ds_get_kernel_slide()

            DispatchQueue.main.async {
                self.isBusy = false
                self.progress = ready ? 1 : self.progress
                self.kernelBaseText = Self.hex(base)
                self.kernelSlideText = Self.hex(slide)
                let processReady =
                    self.refreshSelfProcessState(logIfUnavailable: ready)
                self.kernelState =
                    result == 0 && ready && processReady ? .ready : .failed

                if self.kernelState == .ready {
                    self.startKeepAlive()
                }

                self.appendLog(
                    "DarkSword finished with result \(result), ready=\(ready)."
                )
            }
        }
    }

    func connectRemoteCall(processName: String? = nil) {
        guard !isBusy else { return }
        guard allowSupportedAction("RemoteCall connect") else { return }
        guard allowToolingAction("RemoteCall connect") else { return }
        let process = (processName ?? targetProcess).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !process.isEmpty else {
            remoteError = "Process name is empty."
            return
        }

        isBusy = true
        remoteError = ""
        connectedProcess = ""
        let mig = useMigFilterBypass
        appendLog("Connecting RemoteCall to \(process) (migBypass=\(mig))...")

        workerQueue.async { [weak self] in
            guard let self else { return }

            let isAoVProcess =
                process
                == self.aovProcess.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            let isFreeFireProcess =
                process
                == self.resolvedFreeFireProcessName()
                || process.lowercased().contains("freefire")

            var sbInstance: RemoteCall? = nil
            if isAoVProcess && self.aovRenderMode == "springboard" {
                DispatchQueue.main.async {
                    self.aovStatus = "Connecting SpringBoard..."
                }
                sbInstance = self.ensureSpringBoardRemoteCall()
                if sbInstance == nil {
                    DispatchQueue.main.async {
                        self.appendLog(
                            "Warning: SpringBoard RemoteCall unavailable; falling back to internal overlay if needed."
                        )
                    }
                }
            }

            let kaddr = process.withCString { procbyname($0) }
            if kaddr == 0 {
                DispatchQueue.main.async {
                    self.remoteCall = nil
                    self.remoteConnected = false
                    self.connectedProcess = ""
                    self.remoteError = "Unable to find process: \(process)"
                    self.isBusy = false
                    if isAoVProcess {
                        self.aovStatus = "Connect failed"
                        self.isOpeningAoV = false
                    }
                    if isFreeFireProcess {
                        self.freeFireStatus = "Connect failed"
                        self.isOpeningFreeFire = false
                    }
                    self.appendLog(
                        "RemoteCall failed: process \"\(process)\" not found (procbyname)."
                    )
                    self.broadcastOverlayState()
                }
                return
            }

            let pid = ds_kread32(kaddr + UInt64(off_proc_p_pid))
            DispatchQueue.main.async {
                self.appendLog(
                    "RemoteCall target resolved: pid=\(pid) kaddr=\(Self.hex(kaddr))"
                )
            }

            let instance = RemoteCall(
                process: process,
                useMigFilterBypass: mig
            )
            let error = RemoteCall.lastInitError() ?? ""
            let connected = instance != nil && error.isEmpty

            DispatchQueue.main.async {
                self.remoteCall = connected ? instance : nil
                self.remoteConnected = connected
                self.connectedProcess = connected ? process : ""
                self.remoteError =
                    connected
                    ? ""
                    : (error.isEmpty ? "RemoteCall init returned nil" : error)
                self.isBusy = false

                if connected {
                    if let instance, isAoVProcess {
                        let manager = AoVManager(
                            remoteCall: instance,
                            overlayRemoteCall: sbInstance
                        )
                        self.aovManager = manager
                        let modeDesc = (sbInstance != nil) ? "External SpringBoard" : "Internal"
                        self.aovStatus = "Connected to \(process) (\(modeDesc))"
                        self.isOpeningAoV = false
                        self.syncAoVESPOptions()
                        manager.runLoop()
                    } else if let instance, isFreeFireProcess {
                        let manager = FreeFireManager(remoteCall: instance)
                        self.freeFireManager = manager
                        self.freeFireStatus = "Connected to \(process)"
                        self.isOpeningFreeFire = false
                        self.syncFreeFireESPOptions()
                        manager.diagnosticsHandler = { [weak self] message in
                            self?.appendDiagnostics(message)
                        }
                        manager.runLoop()
                    } else {
                        self.aovStatus = "Connected to \(process)"
                        self.freeFireStatus = "Connected to \(process)"
                    }
                } else {
                    if isAoVProcess {
                        self.aovStatus = "Connect failed"
                        self.isOpeningAoV = false
                    }
                    if isFreeFireProcess {
                        self.freeFireStatus = "Connect failed"
                        self.isOpeningFreeFire = false
                    }
                }

                self.appendLog(
                    connected
                        ? "RemoteCall connected to \(process)."
                        : "RemoteCall failed: \(self.remoteError)"
                )
                self.broadcastOverlayState()
            }
        }
    }

    func disconnectRemoteCall() {
        guard !isBusy else { return }
        guard let remoteCall else { return }

        isBusy = true
        aovStatus = "Disconnecting..."
        freeFireStatus = "Disconnecting..."
        appendLog("Disconnecting RemoteCall...")
        aovManager?.stopLoop()
        freeFireManager?.stopLoop()

        workerQueue.async { [weak self] in
            guard let self else { return }
            usleep(50_000)
            let result = remoteCall.destroy()
            if let sb = self.springboardRemoteCall {
                _ = sb.destroy()
                self.springboardRemoteCall = nil
            }
            DispatchQueue.main.async {
                self.aovManager = nil
                self.freeFireManager = nil
                self.remoteCall = nil
                self.springboardRemoteCall = nil
                self.remoteConnected = false
                self.connectedProcess = ""
                self.isOpeningAoV = false
                self.isOpeningFreeFire = false
                self.aovStatus = "Disconnected"
                self.freeFireStatus = "Disconnected"
                self.isBusy = false
                self.appendLog("RemoteCall destroy result: \(result).")
                self.broadcastOverlayState()
            }
        }
    }

    func runRemoteCall() {
        guard !isBusy else { return }
        guard allowSupportedAction("RemoteCall") else { return }
        guard allowToolingAction("RemoteCall") else { return }
        guard let remoteCall else {
            remoteError = "RemoteCall is not connected."
            return
        }

        let symbol = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symbol.isEmpty else {
            remoteError = "Symbol name is empty."
            return
        }

        let timeout =
            Int32(timeoutText.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? 5
        let parsedArgs: [UInt64]
        do {
            parsedArgs = try parseArguments(argumentText)
        } catch {
            remoteError = error.localizedDescription
            return
        }

        guard
            let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol)
        else {
            remoteError = "Cannot resolve local symbol: \(symbol)."
            return
        }
        let pointerAddress = UInt(bitPattern: pointer)
        let argCount = UInt(parsedArgs.count)

        isBusy = true
        remoteError = ""
        appendLog(
            "Calling \(symbol)(\(parsedArgs.map(Self.hex).joined(separator: ", ")))..."
        )

        workerQueue.async { [weak self] in
            var args = parsedArgs
            let result: UInt
            result = symbol.withCString { symbolCString in
                args.withUnsafeMutableBufferPointer { buffer in
                    let functionPointer = UnsafeMutableRawPointer(
                        bitPattern: pointerAddress
                    )
                    return remoteCall.doStable(
                        withTimeout: timeout,
                        functionName: UnsafeMutablePointer(
                            mutating: symbolCString
                        ),
                        functionPointer: functionPointer,
                        args: buffer.baseAddress,
                        argCount: argCount
                    )
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                self.lastCallResult = Self.hex(UInt64(result))
                self.appendLog("RemoteCall result: \(self.lastCallResult).")
            }
        }
    }

    func clearLog() {
        logText = ""
    }

    func scanAoVProcess() {
        guard !isBusy else { return }
        guard allowSupportedAction("Liên Quân scan") else { return }
        guard allowToolingAction("Liên Quân scan") else { return }

        let process = aovProcess.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !process.isEmpty else {
            remoteError = "Liên Quân process name is empty."
            aovStatus = "Name empty"
            return
        }

        isBusy = true
        remoteError = ""
        aovStatus = "Scanning..."
        appendLog("Scanning processes for \"\(process)\"...")

        workerQueue.async { [weak self] in
            guard let self else { return }
            let kaddr = process.withCString { procbyname($0) }
            var line: String?
            if kaddr != 0 {
                let pid = ds_kread32(kaddr + UInt64(off_proc_p_pid))
                line = "pid=\(pid) name=\(process) kaddr=\(Self.hex(kaddr))"
            }

            DispatchQueue.main.async {
                self.isBusy = false
                if let line {
                    self.aovScanResult = line
                    self.aovStatus = "Found"
                    self.appendLog("Liên Quân scan (1):\n\(line)")
                } else {
                    self.aovScanResult = "Not found for \"\(process)\""
                    self.aovStatus = "Process missing"
                    self.appendLog("Liên Quân scan: no matching process.")
                }
            }
        }
    }

    func connectAoVRemoteCall() {
        let process = aovProcess.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !process.isEmpty else {
            remoteError = "Liên Quân process name is empty."
            aovStatus = "Name empty"
            return
        }
        aovStatus = "Connecting..."
        connectRemoteCall(processName: process)
    }

    func resolvedFreeFireProcessName() -> String {
        let configured = freeFireProcess.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !configured.isEmpty && isProcessRunning(configured) {
            return configured
        }
        for candidate in [
            "FreeFire", "freefire", "FreeFireTH", "freefireth",
            "FreeFireMAX", "freefiremax", "FreeFireMax", "FFMAX", "ffmax",
            "com.dts.freefireth", "com.dts.freefiremax"
        ] {
            if isProcessRunning(candidate) {
                return candidate
            }
        }
        return configured.isEmpty ? "FreeFire" : configured
    }

    func connectFreeFireRemoteCall() {
        let process = resolvedFreeFireProcessName()
        guard !process.isEmpty else {
            remoteError = "Free Fire process name is empty."
            freeFireStatus = "Name empty"
            return
        }
        freeFireStatus = "Connecting..."
        connectRemoteCall(processName: process)
    }

    private func syncAoVESPOptions() {
        guard let aovManager else { return }
        aovManager.isESPEnabled = aovESPEnabled
        aovManager.isHackMapEnabled = aovHackMapEnabled
        aovManager.showsLine = aovShowsLine
        aovManager.showsBox = aovShowsBox
        aovManager.showsHealth = aovShowsHealth
        aovManager.showsName = aovShowsName
        aovManager.showsDistance = aovShowsDistance
        aovManager.cameraHeight = aovCameraHeight
        if !aovESPEnabled {
            aovManager.clearOverlayTargets()
        }
        broadcastOverlayState()
    }

    private func syncFreeFireESPOptions() {
        guard let freeFireManager else { return }
        freeFireManager.isESPEnabled = freeFireESPEnabled
        freeFireManager.showsLine = freeFireShowsLine
        freeFireManager.showsBox = freeFireShowsBox
        freeFireManager.showsHealth = freeFireShowsHealth
        freeFireManager.showsName = freeFireShowsName
        freeFireManager.showsDistance = freeFireShowsDistance
        if !freeFireESPEnabled {
            freeFireManager.clearOverlayTargets()
        }
        broadcastOverlayState()
    }

    func openAoVAndConnect() {
        guard !isBusy else { return }
        guard allowSupportedAction("Liên Quân Open & Connect") else { return }
        guard allowToolingAction("Liên Quân Open & Connect") else { return }

        let process = aovProcess.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !process.isEmpty else {
            remoteError = "Liên Quân process name is empty."
            aovStatus = "Name empty"
            return
        }

        if remoteConnected && connectedProcess != process {
            disconnectRemoteCallThenOpenAoV(process: process)
            return
        }

        openAoVAndConnectAfterRemoteReady(
            process: process,
            shouldConnectAfterLaunch: !remoteConnected
        )
    }

    private func disconnectRemoteCallThenOpenAoV(process: String) {
        guard let remoteCall else {
            openAoVAndConnectAfterRemoteReady(
                process: process,
                shouldConnectAfterLaunch: true
            )
            return
        }

        isBusy = true
        remoteError = ""
        isOpeningAoV = true
        aovScanResult = "Disconnecting \(connectedProcess)..."
        aovStatus = "Opening"
        broadcastOverlayState()
        appendLog(
            "Disconnecting \(connectedProcess), then opening \(aovBundleIdentifier)..."
        )
        aovManager?.stopLoop()
        freeFireManager?.stopLoop()

        workerQueue.async { [weak self] in
            guard let self else { return }
            usleep(50_000)
            let result = remoteCall.destroy()
            if let sb = self.springboardRemoteCall {
                _ = sb.destroy()
                self.springboardRemoteCall = nil
            }
            DispatchQueue.main.async {
                self.aovManager = nil
                self.freeFireManager = nil
                self.remoteCall = nil
                self.springboardRemoteCall = nil
                self.remoteConnected = false
                self.connectedProcess = ""
                self.appendLog("RemoteCall destroy result: \(result).")
                self.openAoVAndConnectAfterRemoteReady(
                    process: process,
                    shouldConnectAfterLaunch: true
                )
            }
        }
    }

    private func openAoVAndConnectAfterRemoteReady(
        process: String,
        shouldConnectAfterLaunch: Bool
    ) {
        isBusy = true
        remoteError = ""
        isOpeningAoV = true
        aovScanResult = "Opening \(aovBundleIdentifier)..."
        aovStatus = "Opening"
        broadcastOverlayState()
        appendLog(
            "Opening \(aovBundleIdentifier), then connecting to \(process) in 3 seconds..."
        )

        guard launchApplication(bundleIdentifier: aovBundleIdentifier) else {
            isBusy = false
            isOpeningAoV = false
            aovStatus = "Launch failed"
            aovScanResult = "Unable to launch \(aovBundleIdentifier)"
            remoteError = "LSApplicationWorkspace could not launch Liên Quân."
            broadcastOverlayState()
            appendLog("Liên Quân launch failed.")
            return
        }

        if !shouldConnectAfterLaunch {
            isBusy = false
            isOpeningAoV = false
            aovStatus = "Connected to \(process)"
            aovScanResult = "Opened \(aovBundleIdentifier)"
            broadcastOverlayState()
            appendLog("Liên Quân opened while RemoteCall is already connected.")
            return
        }

        aovStatus = "Waiting 3 seconds..."
        broadcastOverlayState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            guard !self.remoteConnected else {
                self.isBusy = false
                self.isOpeningAoV = false
                self.broadcastOverlayState()
                return
            }

            self.isBusy = false
            self.aovStatus = "Connecting..."
            self.broadcastOverlayState()
            self.appendLog(
                "Liên Quân launch delay finished; connecting RemoteCall."
            )
            self.connectAoVRemoteCall()
        }
    }

    func openFreeFireAndConnect() {
        guard !isBusy else { return }
        guard allowSupportedAction("Free Fire Open & Connect") else { return }
        guard allowToolingAction("Free Fire Open & Connect") else { return }

        let process = resolvedFreeFireProcessName()
        guard !process.isEmpty else {
            remoteError = "Free Fire process name is empty."
            freeFireStatus = "Name empty"
            return
        }

        if isProcessRunning(process) || isProcessRunning("FreeFire") || isProcessRunning("freefireth") {
            connectFreeFireRemoteCall()
            return
        }

        if remoteConnected && connectedProcess != process {
            disconnectRemoteCallThenOpenFreeFire(process: process)
            return
        }

        openFreeFireAndConnectAfterRemoteReady(
            process: process,
            shouldConnectAfterLaunch: !remoteConnected
        )
    }

    private func disconnectRemoteCallThenOpenFreeFire(process: String) {
        guard let remoteCall else {
            openFreeFireAndConnectAfterRemoteReady(
                process: process,
                shouldConnectAfterLaunch: true
            )
            return
        }

        isBusy = true
        remoteError = ""
        isOpeningFreeFire = true
        freeFireScanResult = "Disconnecting \(connectedProcess)..."
        freeFireStatus = "Opening"
        broadcastOverlayState()
        appendLog(
            "Disconnecting \(connectedProcess), then opening \(freeFireBundleIdentifier)..."
        )
        aovManager?.stopLoop()
        freeFireManager?.stopLoop()

        workerQueue.async { [weak self] in
            guard let self else { return }
            usleep(50_000)
            let result = remoteCall.destroy()
            DispatchQueue.main.async {
                self.aovManager = nil
                self.freeFireManager = nil
                self.remoteCall = nil
                self.remoteConnected = false
                self.connectedProcess = ""
                self.appendLog("RemoteCall destroy result: \(result).")
                self.openFreeFireAndConnectAfterRemoteReady(
                    process: process,
                    shouldConnectAfterLaunch: true
                )
            }
        }
    }

    private func openFreeFireAndConnectAfterRemoteReady(
        process: String,
        shouldConnectAfterLaunch: Bool
    ) {
        isBusy = true
        remoteError = ""
        isOpeningFreeFire = true
        freeFireScanResult = "Opening \(freeFireBundleIdentifier)..."
        freeFireStatus = "Opening"
        broadcastOverlayState()
        appendLog(
            "Opening \(freeFireBundleIdentifier), then connecting to \(process) in 10 seconds..."
        )

        guard launchApplication(bundleIdentifier: freeFireBundleIdentifier) else {
            isBusy = false
            isOpeningFreeFire = false
            freeFireStatus = "Launch failed"
            freeFireScanResult = "Unable to launch \(freeFireBundleIdentifier)"
            remoteError = "LSApplicationWorkspace could not launch Free Fire."
            broadcastOverlayState()
            appendLog("Free Fire launch failed.")
            return
        }

        if !shouldConnectAfterLaunch {
            isBusy = false
            isOpeningFreeFire = false
            freeFireStatus = "Connected to \(process)"
            freeFireScanResult = "Opened \(freeFireBundleIdentifier)"
            broadcastOverlayState()
            appendLog("Free Fire opened while RemoteCall is already connected.")
            return
        }

        freeFireStatus = "Waiting 10 seconds..."
        broadcastOverlayState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            guard !self.remoteConnected else {
                self.isBusy = false
                self.isOpeningFreeFire = false
                self.broadcastOverlayState()
                return
            }

            self.isBusy = false
            self.freeFireStatus = "Connecting..."
            self.broadcastOverlayState()
            self.appendLog(
                "Free Fire launch delay finished; connecting RemoteCall."
            )
            self.connectFreeFireRemoteCall()
        }
    }

    private func launchApplication(bundleIdentifier: String) -> Bool {
        let defaultWorkspace = NSSelectorFromString("defaultWorkspace")
        guard
            let workspaceClass = NSClassFromString("LSApplicationWorkspace")
                as? NSObject.Type,
            workspaceClass.responds(to: defaultWorkspace),
            let workspace = workspaceClass.perform(defaultWorkspace)?
                .takeUnretainedValue() as? NSObject
        else {
            appendLog("LSApplicationWorkspace is unavailable.")
            return false
        }

        for selectorName in [
            "openApplicationWithBundleID:",
            "openApplicationWithBundleIdentifier:",
            "openApplication:",
        ] {
            let selector = NSSelectorFromString(selectorName)
            guard workspace.responds(to: selector) else { continue }
            _ = workspace.perform(selector, with: bundleIdentifier as NSString)
            return true
        }

        appendLog("LSApplicationWorkspace has no supported open selector.")
        return false
    }

    func aovGameStatus() -> GameStatusInfo {
        GameStatusInfo(
            name: "Liên Quân Mobile",
            bundleIdentifier: aovBundleIdentifier,
            processName: aovProcess,
            isInstalled: isApplicationInstalled(
                bundleIdentifier: aovBundleIdentifier
            ),
            isRunning: isProcessRunning(aovProcess)
        )
    }

    func freeFireGameStatus() -> GameStatusInfo {
        let process = resolvedFreeFireProcessName()
        let bundleId = freeFireBundleIdentifier
        return GameStatusInfo(
            name: bundleId.contains("max") ? "Free Fire MAX" : "Free Fire",
            bundleIdentifier: bundleId,
            processName: process,
            isInstalled: isApplicationInstalled(
                bundleIdentifier: bundleId
            ) || isApplicationInstalled(bundleIdentifier: "com.dts.freefireth")
              || isApplicationInstalled(bundleIdentifier: "com.dts.freefiremax"),
            isRunning: isProcessRunning(process)
                || isProcessRunning("FreeFire")
                || isProcessRunning("freefireth")
                || isProcessRunning("FreeFireMAX")
                || isProcessRunning("freefiremax")
        )
    }

    func refreshGameStatuses() {
        gameStatusVersion += 1
    }

    func isApplicationInstalled(bundleIdentifier: String) -> Bool {
        applicationInstallStatus(bundleIdentifier: bundleIdentifier) ?? true
    }

    private func applicationInstallStatus(bundleIdentifier: String) -> Bool? {
        let defaultWorkspace = NSSelectorFromString("defaultWorkspace")
        guard
            let workspaceClass = NSClassFromString("LSApplicationWorkspace")
                as? NSObject.Type,
            workspaceClass.responds(to: defaultWorkspace),
            let workspace = workspaceClass.perform(defaultWorkspace)?
                .takeUnretainedValue() as? NSObject
        else {
            return nil
        }

        let proxySelectors = [
            "applicationProxyForIdentifier:",
            "applicationProxyForBundleIdentifier:",
            "applicationForIdentifier:",
            "applicationForBundleIdentifier:",
        ]
        for selectorName in proxySelectors {
            let selector = NSSelectorFromString(selectorName)
            guard workspace.responds(to: selector) else { continue }
            if workspace.perform(selector, with: bundleIdentifier as NSString)
                != nil
            {
                return true
            }
        }

        let allInstalledApplications = NSSelectorFromString(
            "allInstalledApplications"
        )
        guard
            workspace.responds(to: allInstalledApplications),
            let applications = workspace.perform(allInstalledApplications)?
                .takeUnretainedValue() as? [NSObject]
        else {
            return nil
        }

        return applications.contains {
            applicationProxy($0, matchesBundleIdentifier: bundleIdentifier)
        }
    }

    private func applicationProxy(
        _ proxy: NSObject,
        matchesBundleIdentifier bundleIdentifier: String
    ) -> Bool {
        for selectorName in [
            "applicationIdentifier",
            "bundleIdentifier",
            "bundleIdentifierString",
        ] {
            let selector = NSSelectorFromString(selectorName)
            guard
                proxy.responds(to: selector),
                let value = proxy.perform(selector)?.takeUnretainedValue()
                    as? String
            else {
                continue
            }
            if value == bundleIdentifier {
                return true
            }
        }
        return false
    }

    func isProcessRunning(_ process: String) -> Bool {
        guard ds_is_ready() else { return false }
        let trimmed = process.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.withCString { procbyname($0) } != 0
    }

    private func configureOverlaySocketCallbacks() {
        let server = OverlayWebSocketServer.shared()
        server.messageHandler = { [weak self] message in
            DispatchQueue.main.async {
                self?.handleOverlaySocketMessage(message)
            }
        }
        server.connectionHandler = { [weak self] count in
            DispatchQueue.main.async {
                self?.overlaySocketClientCount = Int(count)
                self?.broadcastOverlayState()
            }
        }
    }

    private func handleOverlaySocketMessage(_ message: String) {
        guard let data = message.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let type = object["type"] as? String
        else {
            return
        }

        switch type {
        case "hello", "ready", "requestState":
            broadcastOverlayState()
            aovManager?.refreshOverlayLayout()
            freeFireManager?.refreshOverlayLayout()
        case "setMenuVisible":
            guard let visibleValue = object["visible"],
                let visible = boolValue(visibleValue)
            else {
                return
            }
            aovManager?.setOverlayMenuVisible(visible)
            freeFireManager?.setOverlayMenuVisible(visible)
        case "toggleMenu":
            aovManager?.toggleOverlayMenu()
            freeFireManager?.toggleOverlayMenu()
        case "setFloatButtonPosition":
            guard let xValue = object["xRatio"],
                let yValue = object["yRatio"],
                let xRatio = doubleValue(xValue),
                let yRatio = doubleValue(yValue)
            else {
                return
            }
            aovManager?.setOverlayFloatButtonPositionX(
                CGFloat(xRatio),
                y: CGFloat(yRatio)
            )
            freeFireManager?.setOverlayFloatButtonPositionX(
                CGFloat(xRatio),
                y: CGFloat(yRatio)
            )
        case "viewport":
            aovManager?.refreshOverlayLayout()
            freeFireManager?.refreshOverlayLayout()
        case "setOption":
            guard let key = object["key"] as? String,
                let value = object["value"]
            else {
                return
            }
            if applyOverlayOption(key: key, value: value) {
                broadcastOverlayState()
            }
        case "patchOptions", "setOptions":
            let options =
                object["options"] as? [String: Any]
                ?? object["state"] as? [String: Any]
                ?? [:]
            var didChange = false
            for (key, value) in options {
                didChange =
                    applyOverlayOption(key: key, value: value) || didChange
            }
            if didChange {
                broadcastOverlayState()
            }
        default:
            return
        }
    }

    @discardableResult
    private func applyOverlayOption(key: String, value: Any) -> Bool {
        let game = activeOverlayGame
        switch key {
        case "aovESPEnabled":
            guard let bool = boolValue(value) else { return false }
            aovESPEnabled = bool
            return true
        case "freeFireESPEnabled":
            guard let bool = boolValue(value) else { return false }
            freeFireESPEnabled = bool
            return true
        case "espEnabled", "esp":
            guard let bool = boolValue(value) else { return false }
            if game == "freefire" {
                freeFireESPEnabled = bool
            } else {
                aovESPEnabled = bool
            }
            return true
        case "aovHackMapEnabled":
            guard let bool = boolValue(value) else { return false }
            aovHackMapEnabled = bool
            return true
        case "aovRenderMode", "renderMode":
            if let str = value as? String, !str.isEmpty {
                aovRenderMode = str.lowercased()
                return true
            }
            return false
        case "hackMapEnabled", "hackMap", "map":
            guard game != "freefire", let bool = boolValue(value),
                bool != aovHackMapEnabled
            else {
                return false
            }
            aovHackMapEnabled = bool
            return true
        case "aovShowsLine":
            guard let bool = boolValue(value) else { return false }
            aovShowsLine = bool
            return true
        case "freeFireShowsLine":
            guard let bool = boolValue(value) else { return false }
            freeFireShowsLine = bool
            return true
        case "showsLine", "line":
            guard let bool = boolValue(value) else { return false }
            if game == "freefire" {
                freeFireShowsLine = bool
            } else {
                aovShowsLine = bool
            }
            return true
        case "aovShowsBox":
            guard let bool = boolValue(value) else { return false }
            aovShowsBox = bool
            return true
        case "freeFireShowsBox":
            guard let bool = boolValue(value) else { return false }
            freeFireShowsBox = bool
            return true
        case "showsBox", "box":
            guard let bool = boolValue(value) else { return false }
            if game == "freefire" {
                freeFireShowsBox = bool
            } else {
                aovShowsBox = bool
            }
            return true
        case "aovShowsHealth":
            guard let bool = boolValue(value) else { return false }
            aovShowsHealth = bool
            return true
        case "freeFireShowsHealth":
            guard let bool = boolValue(value) else { return false }
            freeFireShowsHealth = bool
            return true
        case "showsHealth", "health":
            guard let bool = boolValue(value) else { return false }
            if game == "freefire" {
                freeFireShowsHealth = bool
            } else {
                aovShowsHealth = bool
            }
            return true
        case "aovShowsName":
            guard let bool = boolValue(value) else { return false }
            aovShowsName = bool
            return true
        case "freeFireShowsName":
            guard let bool = boolValue(value) else { return false }
            freeFireShowsName = bool
            return true
        case "showsName", "name":
            guard let bool = boolValue(value) else { return false }
            if game == "freefire" {
                freeFireShowsName = bool
            } else {
                aovShowsName = bool
            }
            return true
        case "aovShowsDistance":
            guard let bool = boolValue(value) else { return false }
            aovShowsDistance = bool
            return true
        case "freeFireShowsDistance":
            guard let bool = boolValue(value) else { return false }
            freeFireShowsDistance = bool
            return true
        case "showsDistance", "distance":
            guard let bool = boolValue(value) else { return false }
            if game == "freefire" {
                freeFireShowsDistance = bool
            } else {
                aovShowsDistance = bool
            }
            return true
        case "aovCameraHeight":
            guard let double = doubleValue(value) else { return false }
            return applyAoVCameraHeight(double)
        case "cameraHeight":
            guard game != "freefire", let double = doubleValue(value) else {
                return false
            }
            return applyAoVCameraHeight(double)
        default:
            return false
        }
    }

    private func applyAoVCameraHeight(_ value: Double) -> Bool {
        let clamped = min(
            max(value, Self.aovCameraHeightMinValue),
            Self.aovCameraHeightMaxValue
        )
        guard abs(clamped - aovCameraHeight) > 0.001 else { return false }
        aovCameraHeight = clamped
        NotificationCenter.default.post(
            name: NSNotification.Name.CameraHeightDidChange,
            object: nil,
            userInfo: nil
        )
        return true
    }

    private func boolValue(_ value: Any) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func doubleValue(_ value: Any) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func broadcastOverlayState() {
        let game = activeOverlayGame
        let isFreeFire = game == "freefire"
        let state: [String: Any] = [
            "debug": g_isDebug,
            "game": game,
            "espEnabled": isFreeFire ? freeFireESPEnabled : aovESPEnabled,
            "hackMapEnabled": aovHackMapEnabled,
            "showsLine": isFreeFire ? freeFireShowsLine : aovShowsLine,
            "showsBox": isFreeFire ? freeFireShowsBox : aovShowsBox,
            "showsHealth": isFreeFire ? freeFireShowsHealth : aovShowsHealth,
            "showsName": isFreeFire ? freeFireShowsName : aovShowsName,
            "showsDistance": isFreeFire
                ? freeFireShowsDistance : aovShowsDistance,
            "cameraHeight": aovCameraHeight,
            "cameraHeightMin": Self.aovCameraHeightMinValue,
            "cameraHeightMax": Self.aovCameraHeightMaxValue,
            "aovRenderMode": aovRenderMode,
            "aovESPEnabled": aovESPEnabled,
            "aovShowsLine": aovShowsLine,
            "aovShowsBox": aovShowsBox,
            "aovShowsHealth": aovShowsHealth,
            "aovShowsName": aovShowsName,
            "aovShowsDistance": aovShowsDistance,
            "freeFireESPEnabled": freeFireESPEnabled,
            "freeFireShowsLine": freeFireShowsLine,
            "freeFireShowsBox": freeFireShowsBox,
            "freeFireShowsHealth": freeFireShowsHealth,
            "freeFireShowsName": freeFireShowsName,
            "freeFireShowsDistance": freeFireShowsDistance,
            "remoteConnected": remoteConnected,
            "connectedProcess": connectedProcess,
            "aovStatus": aovStatus,
            "freeFireStatus": freeFireStatus,
            "socketClients": overlaySocketClientCount,
        ]
        let payload: [String: Any] = [
            "type": "state",
            "state": state,
        ]
        guard JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(withJSONObject: payload)
        else {
            return
        }

        OverlayWebSocketServer.shared().broadcastTextData(data)
    }

    func probeAoVGetpid() {
        guard !isBusy else { return }
        guard allowSupportedAction("Liên Quân getpid") else { return }
        guard allowToolingAction("Liên Quân getpid") else { return }
        guard let remoteCall else {
            remoteError = "Connect RemoteCall to kgvn first."
            aovStatus = "Not connected"
            return
        }

        guard
            let pointer = dlsym(
                UnsafeMutableRawPointer(bitPattern: -2),
                "getpid"
            )
        else {
            remoteError = "Cannot resolve local getpid."
            return
        }

        isBusy = true
        aovStatus = "Calling getpid..."
        appendLog("Liên Quân demo: remote getpid()...")

        let pointerAddress = UInt(bitPattern: pointer)
        workerQueue.async { [weak self] in
            guard let self else { return }
            let result = "getpid".withCString { symbolCString in
                remoteCall.doStable(
                    withTimeout: 10,
                    functionName: UnsafeMutablePointer(mutating: symbolCString),
                    functionPointer: UnsafeMutableRawPointer(
                        bitPattern: pointerAddress
                    ),
                    args: nil,
                    argCount: 0
                )
            }

            DispatchQueue.main.async {
                self.isBusy = false
                self.aovProbeResult =
                    "getpid => \(result) (\(Self.hex(UInt64(result))))"
                self.aovStatus = "Probe OK"
                self.lastCallResult = Self.hex(UInt64(result))
                self.appendLog("Liên Quân demo: \(self.aovProbeResult)")
            }
        }
    }

    func probeAoVProcessName() {
        guard !isBusy else { return }
        guard allowSupportedAction("Liên Quân processName") else { return }
        guard allowToolingAction("Liên Quân processName") else { return }
        guard let remoteCall else {
            remoteError = "Connect RemoteCall to kgvn first."
            aovStatus = "Not connected"
            return
        }

        isBusy = true
        aovStatus = "Calling NSProcessInfo..."
        appendLog("Liên Quân demo: remote NSProcessInfo.processName...")

        workerQueue.async { [weak self] in
            guard let self else { return }

            let processInfoClass = remote_getClass(remoteCall, "NSProcessInfo")
            let processInfoSel = remote_sel(remoteCall, "processInfo")
            let processNameSel = remote_sel(remoteCall, "processName")
            let utf8Sel = remote_sel(remoteCall, "UTF8String")

            var summary = "class=\(Self.hex(processInfoClass))"
            var processName = "(unavailable)"

            if processInfoClass != 0, processInfoSel != 0 {
                let info = remote_msg(
                    remoteCall,
                    processInfoClass,
                    processInfoSel,
                    0,
                    0,
                    0,
                    0
                )
                summary += " info=\(Self.hex(info))"
                if info != 0, processNameSel != 0 {
                    let nameObj = remote_msg(
                        remoteCall,
                        info,
                        processNameSel,
                        0,
                        0,
                        0,
                        0
                    )
                    summary += " nameObj=\(Self.hex(nameObj))"
                    if nameObj != 0, utf8Sel != 0 {
                        let cstr = remote_msg(
                            remoteCall,
                            nameObj,
                            utf8Sel,
                            0,
                            0,
                            0,
                            0
                        )
                        if cstr != 0 {
                            var bytes = [UInt8](repeating: 0, count: 64)
                            let ok = bytes.withUnsafeMutableBytes { buffer in
                                remoteCall.remoteRead(
                                    cstr,
                                    to: buffer.baseAddress,
                                    size: UInt64(buffer.count - 1)
                                )
                            }
                            if ok {
                                processName = String(cString: bytes)
                            }
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                self.isBusy = false
                self.aovProbeResult =
                    "processName => \(processName)\n\(summary)"
                self.aovStatus =
                    processName == "(unavailable)"
                    ? "Probe partial" : "Probe OK"
                self.appendLog("Liên Quân demo: \(self.aovProbeResult)")
            }
        }
    }

    private func refreshKernelInfo() {
        kernelBaseText = Self.hex(ds_get_kernel_base())
        kernelSlideText = Self.hex(ds_get_kernel_slide())
    }

    // MARK: - Keep Alive

    func startKeepAlive() {
        guard !kaEnabled else { return }

        toggleKeepAlive(logger: { [weak self] msg in self?.appendLog(msg) })
        isKeepAliveEnabled = kaEnabled
    }

    func stopKeepAlive() {
        guard kaEnabled else { return }

        toggleKeepAlive(logger: { [weak self] msg in self?.appendLog(msg) })
        isKeepAliveEnabled = kaEnabled
    }

    @discardableResult
    private func refreshSelfProcessState(logIfUnavailable: Bool) -> Bool {
        let proc = proc_self()
        let task = task_self()
        selfProcessReady = proc != 0 && task != 0
        if !selfProcessReady && logIfUnavailable {
            appendLog(
                "Warning: self proc/task lookup is unavailable. RemoteCall may fail in this launch context."
            )
        }
        return selfProcessReady
    }

    @discardableResult
    private func prepareOffsetsIfNeeded() -> Bool {
        supportStatus = DarkSwordSupportStatus.current()
        guard supportStatus.isSupported else {
            remoteError = supportStatus.reason
            return false
        }

        Self.offsetsLock.lock()
        defer { Self.offsetsLock.unlock() }

        if offsetsInitialized || Self.sharedOffsetsInitialized {
            offsetsInitialized = true
            return true
        }

        appendLog("Initializing kernel offsets...")
        init_offsets()
        offsets_init()
        Self.sharedOffsetsInitialized = true
        offsetsInitialized = true
        appendLog("Kernel offsets initialized.")
        return true
    }

    private static func claimKernelRun() -> Bool {
        kernelRunLock.lock()
        defer { kernelRunLock.unlock() }
        guard !isKernelRunClaimed else { return false }
        isKernelRunClaimed = true
        return true
    }

    private static func releaseKernelRun() {
        kernelRunLock.lock()
        isKernelRunClaimed = false
        kernelRunLock.unlock()
    }

    private func resolveKernelSymbolOffsetsIfNeeded() -> Bool {
        if emergencyfixfunctiontobereplacedlateronquestionmark() {
            DispatchQueue.main.async {
                self.kernelSymbolOffsetsReady = true
            }
            appendLog("Kernel symbol offsets resolved from cached kernelcache.")
            return true
        }

        appendLog("Kernel symbol offsets missing. Downloading kernelcache...")
        let resolved = dlkcache()
        DispatchQueue.main.async {
            self.kernelSymbolOffsetsReady = resolved
        }
        appendLog(
            resolved
                ? "Kernel symbol offsets resolved."
                : "Kernel symbol offsets failed to resolve."
        )
        return resolved
    }

    private func allowSupportedAction(_ actionName: String) -> Bool {
        supportStatus = DarkSwordSupportStatus.current()
        guard supportStatus.isSupported else {
            remoteError = supportStatus.reason
            appendLog("\(actionName) blocked: \(supportStatus.reason)")
            return false
        }
        return true
    }

    private func allowToolingAction(_ actionName: String) -> Bool {
        guard isExploitReady else {
            let message =
                "Initialize DarkSword successfully before using tools."
            remoteError = message
            appendLog("\(actionName) blocked: \(message)")
            return false
        }
        return true
    }

    /// Free Fire ESP diagnostics stay visible in the Log screen even when the
    /// debug build flag is off, so an on-device run can be diagnosed.
    private func appendDiagnostics(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }

        DispatchQueue.main.async {
            logSwift("[FreeFire] \(trimmed)")
            if self.logText.isEmpty {
                self.logText = "[FreeFire] \(trimmed)"
            } else {
                self.logText += "\n[FreeFire] \(trimmed)"
            }

            let lines = self.logText.split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            if lines.count > 400 {
                self.logText = lines.suffix(300).joined(separator: "\n")
            }
        }
    }

    private func appendLog(_ line: String) {
        guard g_isDebug else { return }
        DispatchQueue.main.async {
            let trimmed = line.trimmingCharacters(in: .newlines)
            guard !trimmed.isEmpty else { return }
            logSwift("[DarkSword] \(trimmed)")
            if self.logText.isEmpty {
                self.logText = trimmed
            } else {
                self.logText += "\n" + trimmed
            }
        }
    }

    private func parseArguments(_ text: String) throws -> [UInt64] {
        let tokens =
            text
            .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
            .map(String.init)

        return try tokens.map { token in
            let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let radix = value.lowercased().hasPrefix("0x") ? 16 : 10
            let numberText = radix == 16 ? String(value.dropFirst(2)) : value
            guard let number = UInt64(numberText, radix: radix) else {
                throw NSError(
                    domain: "DarkSwordManager",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Invalid argument: \(token)"
                    ]
                )
            }
            return number
        }
    }

    private static func hex(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16, uppercase: false)
    }
}
