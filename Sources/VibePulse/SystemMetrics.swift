import Darwin
import Foundation

struct SystemMetrics {
    var uptime = "0分钟"
    var cpuUsage = 0.0
    var memoryUsage = 0.0
    var memoryText = "0 GB / 0 GB"
    var batteryText = "未检测到电池"
    var batteryLevel = 0.0

    static let placeholder = SystemMetrics()
}

final class SystemMetricsReader {
    private var previousCPU: (used: UInt64, total: UInt64)?

    func read() -> SystemMetrics {
        let cpu = readCPU()
        let memory = readMemory()
        let battery = readBattery()
        return SystemMetrics(
            uptime: formatUptime(ProcessInfo.processInfo.systemUptime),
            cpuUsage: cpu,
            memoryUsage: memory.ratio,
            memoryText: String(format: "%.1f GB / %.1f GB", memory.used, memory.total),
            batteryText: battery.text,
            batteryLevel: battery.level
        )
    }

    private func readCPU() -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let used = UInt64(load.cpu_ticks.0 + load.cpu_ticks.1 + load.cpu_ticks.3)
        let total = used + UInt64(load.cpu_ticks.2)
        defer { previousCPU = (used, total) }
        guard let previousCPU, total > previousCPU.total else { return 0 }
        return Double(used - previousCPU.used) / Double(total - previousCPU.total)
    }

    private func readMemory() -> (used: Double, total: Double, ratio: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return (0, totalBytes / 1_073_741_824, 0) }
        let pageSize = Double(vm_kernel_page_size)
        let usedBytes = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        return (usedBytes / 1_073_741_824, totalBytes / 1_073_741_824, min(usedBytes / totalBytes, 1))
    }

    private func readBattery() -> (text: String, level: Double) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "batt"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let pattern = #"(\d+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output),
              let value = Double(output[range]) else {
            return ("未检测到电池", 0)
        }
        let charging = output.localizedCaseInsensitiveContains("charging")
            && !output.localizedCaseInsensitiveContains("discharging")
            && !output.localizedCaseInsensitiveContains("not charging")
        return ("\(Int(value))%\(charging ? " · 充电中" : "")", value / 100)
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / 1_440
        let hours = totalMinutes % 1_440 / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)天 \(hours)小时" }
        return "\(hours)小时 \(minutes)分"
    }
}
