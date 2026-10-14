import Foundation
import Testing
@testable import AirBarCore

struct AirConditionerTests {
    /// Payload fields as text, so string and number values compare uniformly.
    private func json(_ data: Data) -> [String: String] {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return object.mapValues { "\($0)" }
    }

    @Test func statusDecoding() {
        let status = ACStatus(raw: ["ps": "on", "actmp": "24.0", "acmd": "cool", "acfs": "quiet",
                                    "acvs": 3, "acem": "off", "acpm": "on", "acdc": "off", "rssi": -54])
        #expect(status.isOn)
        #expect(status.setpoint == 24)
        #expect(status.mode == .cool)
        #expect(status.fan == .quiet)
        #expect(status.verticalSwing == 3)
        #expect(!status.eco)
        #expect(status.powerful)
        #expect(!status.display)
        #expect(status.wifiSignal == -54)
    }

    @Test func unknownValuesFallBackToDefaults() {
        let status = ACStatus(raw: ["acmd": "turbo", "acfs": 7])
        #expect(status.mode == .auto)
        #expect(status.fan == .auto)
        #expect(status.setpoint == 24)
        #expect(status.roomTemperature == nil)
    }

    @Test func roomTemperaturePlainFormat() {
        #expect(ACStatus(raw: ["rmtmp": "25.5", "V": "2.15"]).roomTemperature == 25.5)
    }

    @Test func roomTemperaturePackedFormatOnFirmware302() throws {
        // "<fraction × 256>.<whole degrees>": 43/256 + 28 ≈ 28.17 °C
        let temperature = try #require(ACStatus(raw: ["rmtmp": "43.28", "V": "3.02"]).roomTemperature)
        #expect(abs(temperature - 28.168) < 0.001)
    }

    @Test func mergeOverridesFields() {
        var status = ACStatus(raw: ["ps": "off", "actmp": "24.0"])
        status.merge(["ps": "on"])
        #expect(status.isOn)
        #expect(status.setpoint == 24)
    }

    @Test func commandPayloadIncludesProtocolFields() {
        #expect(json(ACCommand.power(true).payload) == ["ki": "1", "cnt": "an", "sid": "1", "ps": "on"])
    }

    @Test func temperatureCommandIsClampedAndSentAsString() {
        #expect(json(ACCommand.temperature(35).payload)["actmp"] == "30")
        #expect(json(ACCommand.temperature(10).payload)["actmp"] == "16")
        #expect(json(ACCommand.temperature(22).payload)["actmp"] == "22")
    }

    @Test func ecoAndPowerfulAreMutuallyExclusive() {
        let eco = json(ACCommand.eco(true).payload)
        #expect(eco["acem"] == "on")
        #expect(eco["acpm"] == "off")
        #expect(eco["actmp"] == "26")
        let powerful = json(ACCommand.powerful(true).payload)
        #expect(powerful["acpm"] == "on")
        #expect(powerful["acem"] == "off")
    }

    @Test func verticalSwingIsNumericAndClamped() {
        #expect(json(ACCommand.verticalSwing(3).payload)["acvs"] == "3")
        #expect(json(ACCommand.verticalSwing(9).payload)["acvs"] == "5")
    }

    @Test(arguments: [
        ("98765 43210", "+919876543210"),     // country code added for Indian numbers
        ("098765-43210", "+919876543210"),    // trunk prefix 0
        ("919876543210", "+919876543210"),    // country code without +
        ("+91 98765 43210", "+919876543210"),
        ("+44 7700 900123", "+447700900123"), // other countries need +
    ])
    func mobileLogin(input: String, expected: String) {
        #expect(MirAIeAPI.loginIdentifier(for: input) == .mobile(expected))
    }

    @Test func emailLogin() {
        #expect(MirAIeAPI.loginIdentifier(for: " me@example.com ") == .email("me@example.com"))
    }

    @Test(arguments: ["", "98765", "987654321012345", "me@example", "abc", "+44 12"])
    func invalidLogin(input: String) {
        #expect(MirAIeAPI.loginIdentifier(for: input) == nil)
    }
}
