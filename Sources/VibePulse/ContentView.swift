import AppKit
import SwiftUI

private enum Brand: String {
    case claude = "Claude"
    case codex = "Codex"
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 9) {
            awakeCard
            systemCard
            usageCard(
                brand: .claude,
                iconColor: .orange,
                title: "Claude Code",
                usage: model.claudeUsage,
                limits: model.claudeLimits,
                isConnected: model.claudeAccount.isLoggedIn
            )
            usageCard(
                brand: .codex,
                iconColor: .blue,
                title: "Codex",
                usage: model.codexUsage,
                limits: model.codexLimits,
                isConnected: model.codexAccount.isLoggedIn
            )
            footer
        }
        .padding(11)
        .frame(width: 374)
        .preferredColorScheme(model.appearance.colorScheme)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [.white.opacity(0.20), .clear, .blue.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
    }

    private var awakeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "cup.and.heat.waves.fill")
                    .font(.title3)
                Text("保持唤醒")
                    .font(.headline)
                Toggle("", isOn: $model.isAwake)
                    .labelsHidden()
                    .toggleStyle(.switch)
                Spacer()
                Picker("", selection: $model.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Image(systemName: appearanceIcon(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 104)
                .help("切换深色或浅色模式")
            }

            Picker("唤醒时长", selection: $model.selectedDuration) {
                ForEach(AwakeDuration.allCases) { duration in
                    Text(duration.rawValue).tag(duration)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Divider()
            HStack {
                Label("合盖不休眠", systemImage: "laptopcomputer")
                    .fontWeight(.medium)
                Spacer()
                if model.isUpdatingLidSleep {
                    ProgressView()
                        .controlSize(.small)
                }
                Toggle("", isOn: Binding(
                    get: { model.isLidSleepDisabled },
                    set: model.setLidSleepDisabled
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(model.isUpdatingLidSleep)
            }
            Text(model.lidSleepMessage ?? "合盖后继续运行，请保持设备通风。")
                .font(.caption)
                .foregroundStyle(model.lidSleepMessage == nil ? Color.secondary : Color.red)
        }
        .glassCard()
    }

    private var systemCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("系统状态", systemImage: "display")
                .font(.headline)
            HStack(spacing: 14) {
                VStack(spacing: 7) {
                    CompactMetric(icon: "power", label: "开机", value: model.metrics.uptime)
                    CompactMetric(icon: "cpu", label: "CPU", value: "\(Int(model.metrics.cpuUsage * 100))%")
                    CompactMetric(icon: "memorychip", label: "内存", value: model.metrics.memoryText)
                }
                VStack(spacing: 7) {
                    CompactMetric(icon: "battery.75percent", label: "电池", value: model.metrics.batteryText)
                    CompactMetric(icon: "network", label: "IP", value: model.ipLocation.ip)
                    CompactMetric(icon: "globe.asia.australia", label: "国家", value: model.ipLocation.countryDisplay)
                }
            }
        }
        .glassCard()
    }

    private func usageCard(
        brand: Brand,
        iconColor: Color,
        title: String,
        usage: UsageSnapshot,
        limits: UsageLimits,
        isConnected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                Text(title).font(.headline)
                } icon: {
                    BrandIcon(brand: brand)
                }
                Spacer()
                ConnectionBadge(isConnected: isConnected)
            }
            HStack {
                CompactUsage(label: "今日", value: usage.formatted(usage.today), cost: usage.formattedCost(usage.todayCost))
                CompactUsage(label: "本周", value: usage.formatted(usage.week), cost: usage.formattedCost(usage.weekCost))
                CompactUsage(label: "本月", value: usage.formatted(usage.month), cost: usage.formattedCost(usage.monthCost))
            }
            Divider()
            if limits.isAvailable {
                if let primary = limits.primary {
                    LimitRow(window: primary, accent: iconColor)
                }
                if let secondary = limits.secondary {
                    LimitRow(window: secondary, accent: iconColor)
                }
            } else {
                Text("暂未检测到 5小时 / 7天余额")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .glassCard()
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Text("开机自启").fontWeight(.medium)
                Toggle("", isOn: $model.launchAtLogin).labelsHidden()
                Spacer()
                Button {
                    model.refreshAll()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                Text(model.lastUpdated, style: .relative)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button(action: model.quit) {
                    Label("退出", systemImage: "power")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 3)
    }

    private func appearanceIcon(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

private struct ConnectionBadge: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isConnected ? Color.green : Color.white)
                .frame(width: 6, height: 6)
            Text(isConnected ? "已连接" : "未连接")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(isConnected ? Color.green : Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(isConnected ? 0.08 : 0.06), in: Capsule())
    }
}

private struct BrandIcon: View {
    let brand: Brand

    var body: some View {
        if let image = NSImage(contentsOf: resourceURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 21, height: 21)
        } else {
            Image(systemName: "app.fill")
                .frame(width: 21, height: 21)
        }
    }

    private var resourceURL: URL {
        Bundle.main.resourceURL!.appendingPathComponent("\(brand.rawValue).\(brand == .claude ? "svg" : "png")")
    }
}

private struct LimitRow: View {
    let window: RateLimitWindow
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(window.name)
                .fontWeight(.medium)
                .frame(width: 38, alignment: .leading)
            CompactLimitBar(value: window.remainingPercent / 100, accent: accent)
            Text("\(Int(window.remainingPercent))%")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 32, alignment: .trailing)
            Spacer(minLength: 4)
            Text(window.resetText)
                .foregroundStyle(.secondary)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

private struct CompactLimitBar: View {
    let value: Double
    let accent: Color

    private var clampedValue: Double {
        max(0, min(1, value))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.16))
                Capsule()
                    .fill(clampedValue < 0.2 ? Color.red : accent)
                    .frame(width: proxy.size.width * clampedValue)
            }
        }
        .frame(width: 92, height: 4)
        .accessibilityLabel("剩余额度")
        .accessibilityValue("\(Int(clampedValue * 100))%")
    }
}

private struct CompactMetric: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .frame(width: 15)
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompactUsage: View {
    let label: String
    let value: String
    let cost: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.caption)
            HStack(spacing: 4) {
                Text(value)
                    .fontWeight(.semibold)
                Text(cost)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    @ViewBuilder
    func glassCard() -> some View {
        if #available(macOS 26.0, *) {
            self
                .padding(11)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            self
                .padding(11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
