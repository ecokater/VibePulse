import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

enum AwakeDuration: String, CaseIterable, Identifiable {
    case forever = "永久"
    case oneHour = "1小时"
    case twoHours = "2小时"
    case fourHours = "4小时"

    var id: Self { self }

    var seconds: TimeInterval? {
        switch self {
        case .forever: nil
        case .oneHour: 3_600
        case .twoHours: 7_200
        case .fourHours: 14_400
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var id: Self { self }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var isAwake = false {
        didSet { updateAwakeProcess() }
    }
    @Published var selectedDuration: AwakeDuration = .forever {
        didSet {
            if isAwake { updateAwakeProcess() }
        }
    }
    @Published var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }
    @Published var launchAtLogin = false {
        didSet { updateLaunchAtLogin() }
    }
    @Published var isLidSleepDisabled = false
    @Published var isUpdatingLidSleep = false
    @Published var lidSleepMessage: String?
    @Published var metrics = SystemMetrics.placeholder
    @Published var claudeUsage = UsageSnapshot()
    @Published var codexUsage = UsageSnapshot()
    @Published var claudeAccount = ClaudeAccountStatus()
    @Published var codexAccount = CodexAccountStatus()
    @Published var claudeLimits = UsageLimits.unavailable
    @Published var codexLimits = UsageLimits.unavailable
    @Published var ipLocation = IPLocation.loading
    @Published var lastUpdated = Date()
    @Published var lastAccountRefresh: Date?

    private var caffeinate: Process?
    private var refreshTimer: Timer?
    private var accountRefreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var awakeTimer: Timer?
    private var isInitializing = true
    private var isRefreshingCodexAccount = false
    private var isRefreshingClaudeAccount = false
    private var hasLiveCodexLimits = false
    private var hasLiveClaudeLimits = false
    private let metricsReader = SystemMetricsReader()
    private let usageReader = UsageMetricsReader()
    private let ipLocationReader = IPLocationReader()
    private let codexAccountReader = CodexAccountReader()
    private let claudeAccountReader = ClaudeAccountReader()
    private let lidSleepController = LidSleepController()

    init() {
        appearance = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isLidSleepDisabled = lidSleepController.isDisabled()
        isInitializing = false
        applyAppearance()
        refresh()
        refreshIP()
        refreshCodexAccount()
        refreshClaudeAccount()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        accountRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshOfficialAccounts() }
        }
        accountRefreshTimer?.tolerance = 30
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshOfficialAccounts() }
        }
    }

    func refresh() {
        metrics = metricsReader.read()
        claudeUsage = usageReader.readClaude()
        codexUsage = usageReader.readCodex()
        if !hasLiveClaudeLimits {
            claudeLimits = usageReader.readClaudeLimits()
        }
        if !hasLiveCodexLimits {
            codexLimits = usageReader.readCodexLimits()
        }
        lastUpdated = Date()
    }

    func refreshAll() {
        refresh()
        isLidSleepDisabled = lidSleepController.isDisabled()
        refreshIP(force: true)
        refreshOfficialAccounts()
    }

    func setLidSleepDisabled(_ disabled: Bool) {
        guard !isUpdatingLidSleep else { return }
        isUpdatingLidSleep = true
        lidSleepMessage = nil
        Task {
            let result = await lidSleepController.setDisabled(disabled)
            isLidSleepDisabled = result.enabled
            lidSleepMessage = result.error
            isUpdatingLidSleep = false
        }
    }

    private func refreshCodexAccount() {
        guard !isRefreshingCodexAccount else { return }
        isRefreshingCodexAccount = true
        Task {
            codexAccount = await codexAccountReader.readStatus()
            if let limits = await codexAccountReader.readLimits() {
                hasLiveCodexLimits = true
                codexLimits = limits
            }
            isRefreshingCodexAccount = false
            markAccountRefreshFinished()
        }
    }

    private func refreshClaudeAccount() {
        guard !isRefreshingClaudeAccount else { return }
        isRefreshingClaudeAccount = true
        Task {
            claudeAccount = await claudeAccountReader.readStatus()
            if let limits = await claudeAccountReader.readLimits() {
                hasLiveClaudeLimits = true
                claudeLimits = limits
            }
            isRefreshingClaudeAccount = false
            markAccountRefreshFinished()
        }
    }

    private func refreshOfficialAccounts() {
        refreshCodexAccount()
        refreshClaudeAccount()
    }

    private func markAccountRefreshFinished() {
        if !isRefreshingCodexAccount && !isRefreshingClaudeAccount {
            lastAccountRefresh = Date()
        }
    }

    private func refreshIP(force: Bool = false) {
        if force { ipLocation = .loading }
        Task {
            ipLocation = await ipLocationReader.read(force: force)
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func applyAppearance() {
        let selectedAppearance = appearance.appKitAppearance
        NSApplication.shared.appearance = selectedAppearance
        for window in NSApplication.shared.windows {
            window.appearance = selectedAppearance
        }
    }

    private func updateAwakeProcess() {
        caffeinate?.terminate()
        caffeinate = nil
        awakeTimer?.invalidate()
        awakeTimer = nil

        guard isAwake else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d", "-i"]
        try? process.run()
        caffeinate = process

        if let seconds = selectedDuration.seconds {
            awakeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.isAwake = false }
            }
        }
    }

    private func updateLaunchAtLogin() {
        guard !isInitializing else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
