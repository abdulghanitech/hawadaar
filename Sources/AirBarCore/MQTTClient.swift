import Foundation
import Network

/// Minimal MQTT-over-TLS client. Callbacks are delivered on the main queue.
public final class MQTTClient {
    public enum State { case disconnected, connecting, connected }

    public var onStateChange: ((State) -> Void)?
    public var onMessage: ((String, Data) -> Void)?
    /// Called when the broker rejects the credentials (CONNACK code 4 or 5), e.g. an expired token.
    public var onAuthRejected: (() -> Void)?

    private let host: String
    private let port: UInt16
    private let keepAlive: UInt16 = 60
    private let queue = DispatchQueue(label: "AirBar.MQTT")
    private var connection: NWConnection?
    private var decoder = MQTTPacket.Decoder()
    private var pingTimer: DispatchSourceTimer?
    private var nextPacketId: UInt16 = 1
    private var topics: [String] = []
    /// When the broker last sent anything; pings keep this fresh on a healthy connection.
    private var lastReceived = Date()

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    public func connect(clientId: String, username: String, password: String, subscribe topics: [String]) {
        queue.async { [self] in
            teardown()
            self.topics = topics
            notify(.connecting)
            let conn = NWConnection(host: .init(host), port: .init(rawValue: port)!, using: .tls)
            connection = conn
            conn.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.send(MQTTPacket.connect(clientId: clientId, username: username,
                                                 password: password, keepAlive: self.keepAlive))
                    self.receive()
                case .failed, .cancelled:
                    self.closeWithNotice()
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    public func disconnect() {
        queue.async { [self] in
            send(MQTTPacket.disconnect)
            teardown()
            notify(.disconnected)
        }
    }

    public func publish(topic: String, payload: Data) {
        queue.async { [self] in send(MQTTPacket.publish(topic: topic, payload: payload)) }
    }

    // MARK: - Internals

    private func teardown() {
        pingTimer?.cancel()
        pingTimer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        decoder.reset()
    }

    private func closeWithNotice() {
        teardown()
        notify(.disconnected)
    }

    private func notify(_ state: State) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.lastReceived = Date()
                for packet in self.decoder.append(data) { self.handle(packet) }
            }
            if isComplete || error != nil {
                self.closeWithNotice()
                return
            }
            self.receive()
        }
    }

    private func handle(_ packet: MQTTPacket.Incoming) {
        switch packet {
        case .connAck(0):
            startPing()
            if !topics.isEmpty {
                send(MQTTPacket.subscribe(packetId: nextPacketId, topics: topics))
                nextPacketId &+= 1
            }
            notify(.connected)
        case .connAck(let code):
            closeWithNotice()
            if code == 4 || code == 5 {
                DispatchQueue.main.async { self.onAuthRejected?() }
            }
        case .publish(let topic, let payload):
            DispatchQueue.main.async { self.onMessage?(topic, payload) }
        default:
            break
        }
    }

    private func startPing() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = DispatchTimeInterval.seconds(Int(keepAlive) / 2)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // A connection can die silently (e.g. across sleep); without a ping response
            // within the keep-alive period, drop it so the owner reconnects.
            if Date().timeIntervalSince(self.lastReceived) > TimeInterval(self.keepAlive) {
                self.closeWithNotice()
            } else {
                self.send(MQTTPacket.pingRequest)
            }
        }
        timer.resume()
        pingTimer = timer
    }
}
