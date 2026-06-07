import Foundation

struct ClaudeAccountStatus {
    var isInstalled = false
    var isLoggedIn = false
    var authMethod = ""
    var version = ""
    var subscriptionType = ""

    var displayText: String {
        if !isInstalled { return "未安装" }
        if !isLoggedIn { return "Claude Code 未登录" }
        if authMethod.localizedCaseInsensitiveContains("api") { return "API Key 已连接" }
        if !subscriptionType.isEmpty {
            return "Claude \(subscriptionType.capitalized) 已连接"
        }
        return "Claude 已连接"
    }
}

final class ClaudeAccountReader {
    func readStatus() async -> ClaudeAccountStatus {
        await Task.detached(priority: .utility) {
            guard let executable = self.claudeExecutable else {
                return ClaudeAccountStatus()
            }
            let versionResult = self.run(executable, arguments: ["--version"])
            let authResult = self.run(executable, arguments: ["auth", "status"])
            guard let data = authResult.output.data(using: .utf8),
                  let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ClaudeAccountStatus(
                    isInstalled: true,
                    version: self.parseVersion(versionResult.output)
                )
            }
            return ClaudeAccountStatus(
                isInstalled: true,
                isLoggedIn: auth["loggedIn"] as? Bool ?? false,
                authMethod: auth["authMethod"] as? String ?? "",
                version: self.parseVersion(versionResult.output),
                subscriptionType: auth["subscriptionType"] as? String ?? ""
            )
        }.value
    }

    func readLimits() async -> UsageLimits? {
        await Task.detached(priority: .utility) {
            guard let token = self.readAccessToken(),
                  let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                let primary = self.parseWindow(object["five_hour"], name: "5小时")
                let secondary = self.parseWindow(object["seven_day"], name: "7天")
                guard primary != nil || secondary != nil else { return nil }
                return UsageLimits(primary: primary, secondary: secondary)
            } catch {
                return nil
            }
        }.value
    }

    private var claudeExecutable: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directCandidates = [
            home.appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        if let direct = directCandidates.first(where: FileManager.default.isExecutableFile) {
            return direct
        }

        let desktopRoot = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: desktopRoot,
            includingPropertiesForKeys: nil
        ) else { return nil }
        return versions
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .map { $0.appendingPathComponent("claude.app/Contents/MacOS/claude").path }
            .first(where: FileManager.default.isExecutableFile)
    }

    private func parseVersion(_ output: String) -> String {
        output.split(separator: " ").first.map(String.init) ?? ""
    }

    private func readAccessToken() -> String? {
        let result = run("/usr/bin/security", arguments: [
            "find-generic-password", "-s", "Claude Code-credentials", "-w"
        ])
        guard result.status == 0,
              let data = result.output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["accessToken"] as? String
    }

    private func parseWindow(_ value: Any?, name: String) -> RateLimitWindow? {
        guard let value = value as? [String: Any],
              let utilization = (value["utilization"] as? NSNumber)?.doubleValue else { return nil }
        let resetsAt = (value["resets_at"] as? String).flatMap(parseDate)
        return RateLimitWindow(name: name, usedPercent: utilization, resetsAt: resetsAt)
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func run(_ executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return (
                process.terminationStatus,
                String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            )
        } catch {
            return (-1, "")
        }
    }
}
