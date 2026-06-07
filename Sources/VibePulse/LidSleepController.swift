import Foundation

final class LidSleepController {
    private let helperPath = "/usr/local/libexec/awakebar-lid-sleep"
    private let sudoersPath = "/etc/sudoers.d/awakebar-lid-sleep"

    func isDisabled() -> Bool {
        let result = run("/usr/bin/pmset", arguments: ["-g"])
        return result.output.range(
            of: #"SleepDisabled\s+1"#,
            options: .regularExpression
        ) != nil
    }

    func setDisabled(_ disabled: Bool) async -> (enabled: Bool, error: String?) {
        await Task.detached(priority: .userInitiated) {
            let value = disabled ? "1" : "0"
            let result: (status: Int32, output: String, error: String)
            if self.isHelperInstalled {
                result = self.run("/usr/bin/sudo", arguments: ["-n", self.helperPath, value])
            } else {
                result = self.installHelperAndSet(value)
            }
            let enabled = self.isDisabled()
            guard result.status != 0 else { return (enabled, nil) }

            let cancelled = result.error.localizedCaseInsensitiveContains("User canceled")
                || result.error.contains("-128")
            return (enabled, cancelled ? "已取消首次管理员授权" : "无法修改合盖休眠设置")
        }.value
    }

    private var isHelperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: helperPath)
            && FileManager.default.fileExists(atPath: sudoersPath)
    }

    private func installHelperAndSet(_ value: String) -> (status: Int32, output: String, error: String) {
        let user = NSUserName()
        let helper = """
        #!/bin/sh
        case "$1" in
          0|1) exec /usr/bin/pmset -a disablesleep "$1" ;;
          *) exit 64 ;;
        esac
        """
        let sudoers = "\(user) ALL=(root) NOPASSWD: \(helperPath)\n"
        let helperBase64 = Data(helper.utf8).base64EncodedString()
        let sudoersBase64 = Data(sudoers.utf8).base64EncodedString()
        let command = """
        /bin/mkdir -p /usr/local/libexec; \
        /bin/echo \(helperBase64) | /usr/bin/base64 -D > /tmp/awakebar-lid-sleep; \
        /bin/echo \(sudoersBase64) | /usr/bin/base64 -D > /tmp/awakebar-lid-sleep.sudoers; \
        /usr/sbin/chown root:wheel /tmp/awakebar-lid-sleep /tmp/awakebar-lid-sleep.sudoers; \
        /bin/chmod 755 /tmp/awakebar-lid-sleep; \
        /bin/chmod 440 /tmp/awakebar-lid-sleep.sudoers; \
        /usr/sbin/visudo -cf /tmp/awakebar-lid-sleep.sudoers && \
        /usr/bin/install -o root -g wheel -m 755 /tmp/awakebar-lid-sleep \(helperPath) && \
        /usr/bin/install -o root -g wheel -m 440 /tmp/awakebar-lid-sleep.sudoers \(sudoersPath) && \
        \(helperPath) \(value) && \
        /bin/rm -f /tmp/awakebar-lid-sleep /tmp/awakebar-lid-sleep.sudoers
        """
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = #"do shell script "\#(escaped)" with administrator privileges"#
        return run("/usr/bin/osascript", arguments: ["-e", script])
    }

    private func run(_ executable: String, arguments: [String]) -> (status: Int32, output: String, error: String) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
            return (
                process.terminationStatus,
                String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            )
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }
}
