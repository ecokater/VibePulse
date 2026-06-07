import Foundation

struct CodexAccountStatus {
    var isInstalled = false
    var isLoggedIn = false
}

final class CodexAccountReader {
    func readStatus() async -> CodexAccountStatus {
        await Task.detached(priority: .utility) {
            guard let codex = self.codexExecutable else { return CodexAccountStatus() }
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: codex)
            process.arguments = ["login", "status"]
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                process.waitUntilExit()
                let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return CodexAccountStatus(
                    isInstalled: true,
                    isLoggedIn: process.terminationStatus == 0 && text.localizedCaseInsensitiveContains("logged in")
                )
            } catch {
                return CodexAccountStatus(isInstalled: true)
            }
        }.value
    }

    func readLimits() async -> UsageLimits? {
        await Task.detached(priority: .utility) {
            guard let codex = self.codexExecutable else { return nil }
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", self.command(codex: codex)]
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                return self.parseLimits(from: data)
            } catch {
                return nil
            }
        }.value
    }

    private var codexExecutable: String? {
        let bundled = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        let local = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        if FileManager.default.isExecutableFile(atPath: local) { return local }
        return nil
    }

    private func command(codex: String) -> String {
        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"vibepulse","version":"1.0"}}}"#
        let initialized = #"{"method":"initialized"}"#
        let limits = #"{"id":2,"method":"account/rateLimits/read"}"#
        return "(printf '%s\\n' '\(initialize)'; sleep 0.4; printf '%s\\n' '\(initialized)' '\(limits)'; sleep 3) | '\(codex)' app-server --stdio"
    }

    private func parseLimits(from data: Data) -> UsageLimits? {
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  (object["id"] as? NSNumber)?.intValue == 2,
                  let result = object["result"] as? [String: Any],
                  let limits = result["rateLimits"] as? [String: Any] else { continue }
            return UsageLimits(
                primary: parseWindow(limits["primary"], defaultName: "5小时"),
                secondary: parseWindow(limits["secondary"], defaultName: "7天")
            )
        }
        return nil
    }

    private func parseWindow(_ value: Any?, defaultName: String) -> RateLimitWindow? {
        guard let value = value as? [String: Any],
              let used = (value["usedPercent"] as? NSNumber)?.doubleValue,
              let reset = (value["resetsAt"] as? NSNumber)?.doubleValue else { return nil }
        let minutes = (value["windowDurationMins"] as? NSNumber)?.intValue
        let name = minutes == 300 ? "5小时" : minutes == 10_080 ? "7天" : defaultName
        return RateLimitWindow(name: name, usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset))
    }
}
