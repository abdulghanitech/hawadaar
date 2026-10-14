import Foundation

/// MirAIe cloud REST API. Endpoints and app constants follow the community MirAIe clients
/// (github.com/rkzofficial/miraie-ac, github.com/selvakk2k/miraie-ac-in).
public enum MirAIeAPI {
    public static let mqttHost = "mqtt.miraie.in"
    public static let mqttPort: UInt16 = 8883

    private static let clientId = "PBcMcfG19njNCL8AOgvRzIC8AjQa"
    private static let scope = "an_14214235325"
    private static let loginURL = URL(string: "https://auth.miraie.in/simplifi/v1/userManagement/login")!
    private static let homesURL = URL(string: "https://app.miraie.in/simplifi/v1/homeManagement/homes")!
    private static let devicesURL = "https://app.miraie.in/simplifi/v1/deviceManagement/devices/"

    public struct Session {
        public let accessToken: String
    }

    public struct Device: Identifiable, Hashable {
        public let id: String
        public let name: String
        public let topicBase: String
        public var controlTopic: String { topicBase + "/control" }
        public var statusTopic: String { topicBase + "/status" }
        public var connectionTopic: String { topicBase + "/connectionStatus" }

        public init(id: String, name: String, topicBase: String) {
            self.id = id
            self.name = name
            self.topicBase = topicBase
        }
    }

    public struct Home {
        public let id: String
        public let devices: [Device]
    }

    public enum APIError: LocalizedError {
        case signInFailed(String)
        case badResponse(String)

        public var errorDescription: String? {
            switch self {
            case .signInFailed(let message): return "Sign-in failed: \(message)"
            case .badResponse(let message): return message
            }
        }
    }

    public enum LoginIdentifier: Equatable {
        case email(String)
        /// E.164 number, e.g. "+919876543210".
        case mobile(String)

        var field: String {
            switch self {
            case .email: return "email"
            case .mobile: return "mobile"
            }
        }

        public var value: String {
            switch self {
            case .email(let value), .mobile(let value): return value
            }
        }
    }

    /// Interprets what the user typed as an email or a mobile number, or nil if it's neither yet.
    /// Indian numbers (MirAIe's home market) may be typed without the country code, as
    /// "98765 43210", "098765 43210" or "919876543210"; other countries need a leading "+".
    public static func loginIdentifier(for username: String) -> LoginIdentifier? {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("@") {
            return trimmed.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
                ? .email(trimmed) : nil
        }
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber || " +-()".contains($0) }) else { return nil }
        let digits = trimmed.filter(\.isNumber)
        if trimmed.hasPrefix("+") {
            return (8...15).contains(digits.count) ? .mobile("+" + digits) : nil
        }
        switch digits.count {
        case 10: return .mobile("+91" + digits)
        case 11 where digits.hasPrefix("0"): return .mobile("+91" + digits.dropFirst())
        case 12 where digits.hasPrefix("91"): return .mobile("+" + digits)
        default: return nil
        }
    }

    public static func signIn(username: String, password: String) async throws -> Session {
        guard let identifier = loginIdentifier(for: username) else {
            throw APIError.signInFailed("Enter a 10-digit mobile number or an email address.")
        }
        let body: [String: Any] = ["clientId": clientId, "scope": scope, "password": password,
                                   identifier.field: identifier.value]
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let token = json?["accessToken"] as? String else {
            throw APIError.signInFailed((json?["message"] as? String) ?? "HTTP \(status)")
        }
        return Session(accessToken: token)
    }

    public static func home(session: Session) async throws -> Home {
        guard let home = (try await get(homesURL, session: session) as? [[String: Any]])?.first,
              let homeId = home["homeId"] as? String else {
            throw APIError.badResponse("No home found on this MirAIe account.")
        }
        let devices = (home["spaces"] as? [[String: Any]] ?? []).flatMap { space in
            (space["devices"] as? [[String: Any]] ?? []).compactMap { device -> Device? in
                guard let id = device["deviceId"] as? String,
                      let topic = (device["topic"] as? [String])?.first else { return nil }
                return Device(id: id, name: device["deviceName"] as? String ?? "AC", topicBase: topic)
            }
        }
        return Home(id: homeId, devices: devices)
    }

    public static func status(deviceId: String, session: Session) async throws -> [String: Any] {
        try await get(URL(string: devicesURL + deviceId + "/mobile/status")!, session: session) as? [String: Any] ?? [:]
    }

    private static func get(_ url: URL, session: Session) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw APIError.badResponse("MirAIe server returned HTTP \(status)") }
        return try JSONSerialization.jsonObject(with: data)
    }
}
