import Foundation

public enum ACMode: String, CaseIterable, Identifiable {
    case cool, auto, dry, fan, heat
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .cool: return "snowflake"
        case .auto: return "a.circle"
        case .dry: return "drop"
        case .fan: return "fan"
        case .heat: return "sun.max"
        }
    }
    /// Fan-only mode has no temperature setpoint.
    public var usesSetpoint: Bool { self != .fan }
}

public enum FanSpeed: String, CaseIterable, Identifiable {
    case auto, quiet, low, medium, high
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// One AC's state, decoded from MirAIe status fields. Unknown fields are kept in `raw`.
public struct ACStatus {
    public static let temperatureRange = 16...30

    public var raw: [String: Any]

    public init(raw: [String: Any] = [:]) { self.raw = raw }

    public var isOn: Bool { raw["ps"] as? String == "on" }
    public var setpoint: Int { Int((double("actmp") ?? 24).rounded()) }
    public var mode: ACMode { (raw["acmd"] as? String).flatMap(ACMode.init) ?? .auto }
    public var fan: FanSpeed { (raw["acfs"] as? String).flatMap(FanSpeed.init) ?? .auto }
    /// Vertical louver: 0 is auto swing, 1 (nearly horizontal) to 5 (pointing down) are fixed.
    public var verticalSwing: Int { int("acvs") ?? 0 }
    public var eco: Bool { raw["acem"] as? String == "on" }
    public var powerful: Bool { raw["acpm"] as? String == "on" }
    public var display: Bool { raw["acdc"] as? String != "off" }
    /// Signal strength the AC reports for its own Wi-Fi connection, in dBm.
    public var wifiSignal: Int? { int("rssi") }
    public var firmware: String? { (raw["V"] as? String).flatMap { $0.isEmpty ? nil : $0 } }

    /// Room temperature in °C. Firmware 3.02+ packs sub-degree precision as "<fraction/256>.<degrees>".
    public var roomTemperature: Double? {
        guard let value = raw["rmtmp"].map({ "\($0)" }), !value.isEmpty else { return nil }
        let version = (firmware ?? "").split(separator: ".").compactMap { Int($0.filter(\.isNumber)) }
        let packed = version.count >= 2 && (version[0], version[1]) >= (3, 2)
        let parts = value.split(separator: ".")
        if packed, parts.count == 2, let fraction = Double(parts[0]), let degrees = Double(parts[1]), degrees > 0 {
            return degrees + fraction / 256
        }
        return Double(value)
    }

    public mutating func merge(_ fields: [String: Any]) {
        raw.merge(fields) { _, new in new }
    }

    private func double(_ key: String) -> Double? {
        if let number = raw[key] as? NSNumber { return number.doubleValue }
        return (raw[key] as? String).flatMap(Double.init)
    }

    private func int(_ key: String) -> Int? {
        double(key).map { Int($0) }
    }
}

/// A control command, published as JSON to the AC's `<topic>/control` MQTT topic.
public enum ACCommand: Equatable {
    case power(Bool)
    case temperature(Int)
    case mode(ACMode)
    case fan(FanSpeed)
    case verticalSwing(Int)
    case display(Bool)
    case eco(Bool)
    case powerful(Bool)

    /// The status fields this command changes.
    public var fields: [String: Any] {
        switch self {
        case .power(let on): return ["ps": on ? "on" : "off"]
        case .temperature(let value):
            let clamped = min(ACStatus.temperatureRange.upperBound, max(ACStatus.temperatureRange.lowerBound, value))
            return ["actmp": String(clamped)]
        case .mode(let mode): return ["acmd": mode.rawValue]
        case .fan(let speed): return ["acfs": speed.rawValue]
        case .verticalSwing(let position): return ["acvs": min(5, max(0, position))]
        case .display(let on): return ["acdc": on ? "on" : "off"]
        // Eco and Powerful are mutually exclusive; the MirAIe app sets 26 °C when enabling Eco.
        case .eco(true): return ["acem": "on", "acpm": "off", "actmp": "26"]
        case .eco(false): return ["acem": "off"]
        case .powerful(true): return ["acpm": "on", "acem": "off"]
        case .powerful(false): return ["acpm": "off"]
        }
    }

    public var payload: Data {
        var message: [String: Any] = ["ki": 1, "cnt": "an", "sid": "1"]
        message.merge(fields) { _, new in new }
        return (try? JSONSerialization.data(withJSONObject: message, options: .sortedKeys)) ?? Data()
    }

    public static func == (lhs: ACCommand, rhs: ACCommand) -> Bool {
        lhs.payload == rhs.payload
    }
}
