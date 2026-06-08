import Foundation

struct UsageSnapshot {
    var today: Int = 0
    var week: Int = 0
    var month: Int = 0
    var todayCost = 0.0
    var weekCost = 0.0
    var monthCost = 0.0

    func formatted(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    func formattedCost(_ value: Double) -> String {
        value < 0.01 ? "≈$0.00" : String(format: "≈$%.2f", value)
    }
}

struct RateLimitWindow {
    let name: String
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }

    var resetText: String {
        guard let resetsAt else { return "暂无重置时间" }
        if resetsAt <= Date() { return "等待新数据" }
        return "重置 " + resetsAt.formatted(.relative(presentation: .named))
    }
}

struct UsageLimits {
    var primary: RateLimitWindow?
    var secondary: RateLimitWindow?

    var isAvailable: Bool {
        primary != nil || secondary != nil
    }

    static let unavailable = UsageLimits()
}

private struct UsageEntry {
    let date: Date
    let tokens: Int
    let cost: Double
}

final class UsageMetricsReader {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()
    private let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let ISO8601Formatter = ISO8601DateFormatter()

    func readCodex() -> UsageSnapshot {
        readPricedSessions(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) { data, modified in
            var entries: [UsageEntry] = []
            var model = "gpt-5.5"
            var previous: (input: Int, cached: Int, output: Int, total: Int)?
            for line in data.split(separator: 0x0A) {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let payload = object["payload"] as? [String: Any] else { continue }
                if object["type"] as? String == "turn_context", let value = payload["model"] as? String {
                    model = value
                }
                guard payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let usage = info["total_token_usage"] as? [String: Any] else { continue }
                let input = usage["input_tokens"] as? Int ?? 0
                let cached = usage["cached_input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                let total = usage["total_tokens"] as? Int ?? input + output
                // total_token_usage is cumulative; bill the per-event delta so each turn
                // lands in the day/week/month bucket where it actually happened.
                let base = previous ?? (0, 0, 0, 0)
                previous = (input, cached, output, total)
                let deltaInput = max(0, input - base.input)
                let deltaCached = max(0, cached - base.cached)
                let deltaOutput = max(0, output - base.output)
                let deltaTotal = max(0, total - base.total)
                guard deltaTotal > 0 else { continue }
                let price = self.codexPrice(for: model)
                let cost = Double(max(0, deltaInput - deltaCached)) * price.input
                    + Double(deltaCached) * price.cached
                    + Double(deltaOutput) * price.output
                let date = self.parseDate(object["timestamp"]) ?? modified
                entries.append(UsageEntry(date: date, tokens: deltaTotal, cost: cost / 1_000_000))
            }
            return entries
        }
    }

    func readCodexLimits() -> UsageLimits {
        readLatestLimits(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"))
    }

    func readClaudeLimits() -> UsageLimits {
        readLatestLimits(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"))
    }

    func readClaude() -> UsageSnapshot {
        var seen = Set<String>()
        return readPricedSessions(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) { data, modified in
            var entries: [UsageEntry] = []
            for line in data.split(separator: 0x0A) {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                // Session logs repeat the same assistant message across resumes and
                // sidechains; dedupe by message id + request id before counting.
                if let id = message["id"] as? String {
                    let key = id + "|" + (object["requestId"] as? String ?? "")
                    guard seen.insert(key).inserted else { continue }
                }
                let input = usage["input_tokens"] as? Int ?? 0
                let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                let tokens = input + cacheRead + cacheCreate + output
                guard tokens > 0 else { continue }
                let price = self.claudePrice(for: message["model"] as? String ?? "")
                var cost = Double(input) * price.input
                    + Double(cacheRead) * price.cacheRead
                    + Double(output) * price.output
                // 5-minute and 1-hour cache writes bill at different rates (1.25x vs 2x input).
                if let creation = usage["cache_creation"] as? [String: Any],
                   let write5m = creation["ephemeral_5m_input_tokens"] as? Int,
                   let write1h = creation["ephemeral_1h_input_tokens"] as? Int {
                    cost += Double(write5m) * price.cacheWrite5m + Double(write1h) * price.cacheWrite1h
                } else {
                    cost += Double(cacheCreate) * price.cacheWrite5m
                }
                let date = self.parseDate(object["timestamp"]) ?? modified
                entries.append(UsageEntry(date: date, tokens: tokens, cost: cost / 1_000_000))
            }
            return entries
        }
    }

    private func readPricedSessions(
        at root: URL,
        parser: (Data, Date) -> [UsageEntry]
    ) -> UsageSnapshot {
        var result = UsageSnapshot()
        let now = Date()
        let startToday = calendar.startOfDay(for: now)
        let startWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startToday
        let startMonth = calendar.dateInterval(of: .month, for: now)?.start ?? startToday
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified >= startMonth,
                  let data = try? Data(contentsOf: url) else { continue }
            for entry in parser(data, modified) where entry.tokens > 0 && entry.date >= startMonth {
                result.month += entry.tokens
                result.monthCost += entry.cost
                if entry.date >= startWeek {
                    result.week += entry.tokens
                    result.weekCost += entry.cost
                }
                if entry.date >= startToday {
                    result.today += entry.tokens
                    result.todayCost += entry.cost
                }
            }
        }
        return result
    }

    private func codexPrice(for model: String) -> (input: Double, cached: Double, output: Double) {
        // Per million tokens (input, cached input, output). gpt-5.5 verified against
        // OpenAI's published pricing: $5.00 / $0.50 / $30.00.
        if model.contains("5.5") { return (5.00, 0.50, 30.00) }
        if model.contains("5.4") { return (2.50, 0.25, 15.00) }
        if model.contains("5.2") { return (1.75, 0.175, 14.00) }
        if model.contains("5.1") || model == "gpt-5" { return (1.25, 0.125, 10.00) }
        return (5.00, 0.50, 30.00)
    }

    private func claudePrice(for model: String) -> (input: Double, cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double, output: Double) {
        // Per million tokens. Cache writes bill at 1.25x (5m) / 2x (1h) of input; reads at 0.1x.
        // Opus prices are for Opus 4.5+ ($5/$25); legacy Opus 3/4.0/4.1 were $15/$75.
        if model.localizedCaseInsensitiveContains("opus") { return (5.00, 6.25, 10.00, 0.50, 25.00) }
        if model.localizedCaseInsensitiveContains("haiku") { return (1.00, 1.25, 2.00, 0.10, 5.00) }
        return (3.00, 3.75, 6.00, 0.30, 15.00)
    }

    private func readLatestLimits(at root: URL) -> UsageLimits {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return .unavailable }

        var latestDate = Date.distantPast
        var latestLimits = UsageLimits.unavailable
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let data = try? Data(contentsOf: url) else { continue }
            for line in data.split(separator: 0x0A) {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let timestamp = parseDate(object["timestamp"]),
                      timestamp > latestDate,
                      let limits = extractLimits(from: object) else { continue }
                latestDate = timestamp
                latestLimits = limits
            }
        }
        return latestLimits
    }

    private func extractLimits(from object: [String: Any]) -> UsageLimits? {
        let payload = object["payload"] as? [String: Any]
        guard let rateLimits = (payload?["rate_limits"] as? [String: Any])
            ?? (object["rate_limits"] as? [String: Any]) else { return nil }
        let primary = parseWindow(rateLimits["primary"], defaultName: "5小时")
        let secondary = parseWindow(rateLimits["secondary"], defaultName: "7天")
        guard primary != nil || secondary != nil else { return nil }
        return UsageLimits(primary: primary, secondary: secondary)
    }

    private func parseWindow(_ value: Any?, defaultName: String) -> RateLimitWindow? {
        guard let value = value as? [String: Any],
              let used = (value["used_percent"] as? NSNumber)?.doubleValue,
              let reset = (value["resets_at"] as? NSNumber)?.doubleValue else { return nil }
        let minutes = (value["window_minutes"] as? NSNumber)?.intValue
        let name: String
        switch minutes {
        case 300: name = "5小时"
        case 10_080: name = "7天"
        default: name = defaultName
        }
        return RateLimitWindow(name: name, usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset))
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return fractionalISO8601Formatter.date(from: string)
            ?? ISO8601Formatter.date(from: string)
    }
}
