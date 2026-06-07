import Foundation

struct IPLocation {
    var ip = "检测中…"
    var country = "检测中…"
    var countryCode = ""

    var flag: String {
        countryCode.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127_397 + Int($0.value))
        }.map(String.init).joined()
    }

    var countryDisplay: String {
        flag.isEmpty ? country : "\(flag) \(country)"
    }

    static let loading = IPLocation()
    static let unavailable = IPLocation(ip: "检测失败", country: "未知", countryCode: "")
}

private struct IPWhoResponse: Decodable {
    let success: Bool
    let ip: String?
    let country: String?
    let countryCode: String?

    enum CodingKeys: String, CodingKey {
        case success, ip, country
        case countryCode = "country_code"
    }
}

final class IPLocationReader {
    private var cached: IPLocation?
    private var cachedAt: Date?
    private let cacheDuration: TimeInterval = 30 * 60

    func read(force: Bool = false) async -> IPLocation {
        if !force,
           let cached,
           let cachedAt,
           Date().timeIntervalSince(cachedAt) < cacheDuration {
            return cached
        }

        guard let url = URL(string: "https://ipwho.is/") else { return .unavailable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return cached ?? .unavailable
            }
            let result = try JSONDecoder().decode(IPWhoResponse.self, from: data)
            guard result.success, let ip = result.ip, let code = result.countryCode else {
                return cached ?? .unavailable
            }
            let localizedCountry = Locale.current.localizedString(forRegionCode: code)
                ?? result.country
                ?? code
            let location = IPLocation(ip: ip, country: localizedCountry, countryCode: code)
            cached = location
            cachedAt = Date()
            return location
        } catch {
            return cached ?? .unavailable
        }
    }
}
