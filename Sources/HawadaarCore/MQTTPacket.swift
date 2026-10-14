import Foundation

/// Encoding and decoding for the subset of MQTT 3.1.1 that Hawadaar needs:
/// CONNECT, SUBSCRIBE, PUBLISH (QoS 0), PINGREQ and DISCONNECT.
public enum MQTTPacket {
    public static let pingRequest = Data([0xC0, 0x00])
    public static let disconnect = Data([0xE0, 0x00])

    public static func connect(clientId: String, username: String, password: String, keepAlive: UInt16) -> Data {
        var body = string("MQTT")
        body.append(contentsOf: [0x04, 0xC2]) // protocol level 4; username + password + clean session
        body.append(contentsOf: [UInt8(keepAlive >> 8), UInt8(keepAlive & 0xFF)])
        body.append(string(clientId))
        body.append(string(username))
        body.append(string(password))
        return packet(0x10, body)
    }

    public static func subscribe(packetId: UInt16, topics: [String]) -> Data {
        var body = Data([UInt8(packetId >> 8), UInt8(packetId & 0xFF)])
        for topic in topics {
            body.append(string(topic))
            body.append(0x00) // QoS 0
        }
        return packet(0x82, body)
    }

    public static func publish(topic: String, payload: Data) -> Data {
        packet(0x30, string(topic) + payload)
    }

    /// A packet received from the broker.
    public enum Incoming: Equatable {
        case connAck(returnCode: UInt8)
        case publish(topic: String, payload: Data)
        case subAck
        case pingResponse
        case other(type: UInt8)
    }

    /// Reassembles packets from a TCP byte stream, which may split or merge them arbitrarily.
    public struct Decoder {
        private var buffer = Data()

        public init() {}

        public mutating func append(_ data: Data) -> [Incoming] {
            buffer.append(data)
            var packets: [Incoming] = []
            while let (header, body, consumed) = nextFrame() {
                buffer = Data(buffer.dropFirst(consumed))
                packets.append(Self.parse(header: header, body: body))
            }
            return packets
        }

        public mutating func reset() { buffer.removeAll() }

        private func nextFrame() -> (UInt8, Data, Int)? {
            guard buffer.count >= 2 else { return nil }
            let bytes = [UInt8](buffer.prefix(5))
            var length = 0, multiplier = 1, index = 1
            while true {
                guard index < bytes.count, index <= 4 else { return nil }
                let byte = Int(bytes[index])
                length += (byte & 0x7F) * multiplier
                multiplier *= 128
                index += 1
                if byte & 0x80 == 0 { break }
            }
            guard buffer.count >= index + length else { return nil }
            let start = buffer.startIndex
            return (bytes[0], Data(buffer[(start + index)..<(start + index + length)]), index + length)
        }

        private static func parse(header: UInt8, body: Data) -> Incoming {
            let bytes = [UInt8](body)
            switch header >> 4 {
            case 2:
                return .connAck(returnCode: bytes.count >= 2 ? bytes[1] : 0xFF)
            case 3:
                guard bytes.count >= 2 else { return .other(type: 3) }
                let topicLength = Int(bytes[0]) << 8 | Int(bytes[1])
                guard bytes.count >= 2 + topicLength else { return .other(type: 3) }
                let topic = String(decoding: bytes[2..<(2 + topicLength)], as: UTF8.self)
                let hasPacketId = (header >> 1) & 0x03 > 0
                let payloadStart = min(bytes.count, 2 + topicLength + (hasPacketId ? 2 : 0))
                return .publish(topic: topic, payload: Data(bytes[payloadStart...]))
            case 9:
                return .subAck
            case 13:
                return .pingResponse
            default:
                return .other(type: header >> 4)
            }
        }
    }

    static func string(_ value: String) -> Data {
        let bytes = Data(value.utf8)
        return Data([UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)]) + bytes
    }

    static func packet(_ header: UInt8, _ body: Data) -> Data {
        var data = Data([header])
        var length = body.count
        repeat {
            var byte = UInt8(length % 128)
            length /= 128
            if length > 0 { byte |= 0x80 }
            data.append(byte)
        } while length > 0
        return data + body
    }
}
