import HawadaarCore
import AppKit

@MainActor
final class ACStore: ObservableObject {
    enum Phase: Equatable { case signedOut, loading, ready, failed(String) }

    @Published private(set) var phase: Phase = .signedOut
    @Published private(set) var devices: [MirAIeAPI.Device] = []
    @Published private(set) var statuses: [String: ACStatus] = [:]
    @Published private(set) var online: [String: Bool] = [:]
    @Published private(set) var cloudConnected = false
    @Published var selectedId: String? {
        didSet { UserDefaults.standard.set(selectedId, forKey: "selectedDevice") }
    }

    var selected: MirAIeAPI.Device? { devices.first { $0.id == selectedId } ?? devices.first }
    var status: ACStatus { selected.flatMap { statuses[$0.id] } ?? ACStatus() }
    var isOnline: Bool { selected.flatMap { online[$0.id] } ?? false }
    /// Whether commands can reach the selected AC right now.
    var canControl: Bool { cloudConnected && isOnline }

    private var credentials: (username: String, password: String)?
    private var session: MirAIeAPI.Session?
    private var homeId = ""
    private let mqtt = MQTTClient(host: MirAIeAPI.mqttHost, port: MirAIeAPI.mqttPort)
    private let clientId = "hawadaar-\(UUID().uuidString.prefix(8).lowercased())"
    private var reconnectTask: Task<Void, Never>?

    init() {
        selectedId = UserDefaults.standard.string(forKey: "selectedDevice")
        mqtt.onMessage = { [weak self] topic, payload in self?.handle(topic: topic, payload: payload) }
        mqtt.onStateChange = { [weak self] state in self?.mqttStateChanged(state) }
        mqtt.onAuthRejected = { [weak self] in self?.session = nil }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAfterWake() }
        }
        if let saved = Keychain.load() {
            credentials = saved
            Task { await start() }
        }
    }

    // MARK: - Session

    func signIn(username: String, password: String) async {
        credentials = (username, password)
        await start()
        if phase == .ready { Keychain.save(username: username, password: password) }
    }

    func signOut() {
        reconnectTask?.cancel()
        mqtt.disconnect()
        Keychain.delete()
        credentials = nil
        session = nil
        devices = []
        statuses = [:]
        online = [:]
        phase = .signedOut
    }

    func start() async {
        guard let credentials else { phase = .signedOut; return }
        phase = .loading
        do {
            let session = try await MirAIeAPI.signIn(username: credentials.username, password: credentials.password)
            let home = try await MirAIeAPI.home(session: session)
            guard !home.devices.isEmpty else { throw MirAIeAPI.APIError.badResponse("No ACs found on this MirAIe account.") }
            self.session = session
            homeId = home.id
            devices = home.devices
            for device in devices {
                let raw = (try? await MirAIeAPI.status(deviceId: device.id, session: session)) ?? [:]
                statuses[device.id] = ACStatus(raw: raw)
                online[device.id] = raw["onlineStatus"] as? String == "true"
            }
            phase = .ready
            writeDebugDump()
            connectMQTT()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// After sleep the token may have expired and the MQTT connection is likely dead:
    /// sign in again, reload every AC's status and reconnect, without leaving the panel.
    private func refreshAfterWake() async {
        guard phase == .ready, let credentials else { return }
        reconnectTask?.cancel()
        // Wi-Fi typically needs a few seconds to come back after wake.
        try? await Task.sleep(for: .seconds(3))
        guard let session = try? await MirAIeAPI.signIn(username: credentials.username, password: credentials.password) else {
            mqttStateChanged(.disconnected) // falls back to the regular retry loop
            return
        }
        self.session = session
        for device in devices {
            if let raw = try? await MirAIeAPI.status(deviceId: device.id, session: session) {
                statuses[device.id] = ACStatus(raw: raw)
                online[device.id] = raw["onlineStatus"] as? String == "true"
            }
        }
        connectMQTT()
    }

    private func connectMQTT() {
        guard let session else { return }
        let topics = devices.flatMap { [$0.statusTopic, $0.connectionTopic] }
        mqtt.connect(clientId: clientId, username: homeId, password: session.accessToken, subscribe: topics)
    }

    private func mqttStateChanged(_ state: MQTTClient.State) {
        cloudConnected = state == .connected
        guard state == .disconnected, credentials != nil, phase == .ready else { return }
        // Reconnect after a pause, signing in again if the broker rejected the token.
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, let credentials = self.credentials else { return }
            if self.session == nil {
                self.session = try? await MirAIeAPI.signIn(username: credentials.username, password: credentials.password)
            }
            self.connectMQTT()
        }
    }

    // MARK: - Incoming

    private func handle(topic: String, payload: Data) {
        guard let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              let device = devices.first(where: { topic.hasPrefix($0.topicBase + "/") }) else { return }
        if topic == device.connectionTopic {
            let isOnline = "\(json["onlineStatus"] ?? "")" == "true"
            if online[device.id] != isOnline {
                ConnectionLog.write("\(device.name) went \(isOnline ? "online" : "offline")")
            }
            online[device.id] = isOnline
        } else {
            statuses[device.id, default: ACStatus()].merge(json)
            online[device.id] = true
            writeDebugDump()
        }
    }

    // MARK: - Commands

    func send(_ command: ACCommand) {
        guard let device = selected, canControl else { return }
        mqtt.publish(topic: device.controlTopic, payload: command.payload)
        // Optimistic update; the AC confirms with a status message.
        statuses[device.id, default: ACStatus()].merge(command.fields)
    }

    // MARK: - Diagnostics

    /// Status of every AC as JSON, for bug reports. Contains no credentials or tokens.
    func diagnostics() -> String {
        let report: [[String: Any]] = devices.map { device in
            ["name": device.name, "online": online[device.id] ?? false, "status": statuses[device.id]?.raw ?? [:]]
        }
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }

    /// With `defaults write tech.abdulghani.hawadaar DebugStatusDump -bool true`, mirrors
    /// `diagnostics()` to ~/Library/Logs/Hawadaar-status.json on every update.
    private func writeDebugDump() {
        guard UserDefaults.standard.bool(forKey: "DebugStatusDump") else { return }
        try? Data(diagnostics().utf8).write(to: ConnectionLog.directory.appending(path: "Hawadaar-status.json"))
    }
}

/// Records when ACs drop off and come back, to ~/Library/Logs/Hawadaar.log.
enum ConnectionLog {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs")
    static let url = directory.appending(path: "Hawadaar.log")

    static func write(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withSpaceBetweenDateAndTime]
        formatter.timeZone = .current
        let line = Data("\(formatter.string(from: Date())) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
