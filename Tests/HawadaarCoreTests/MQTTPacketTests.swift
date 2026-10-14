import Foundation
import Testing
@testable import HawadaarCore

struct MQTTPacketTests {
    @Test func connectPacket() {
        let packet = MQTTPacket.connect(clientId: "c", username: "u", password: "p", keepAlive: 60)
        #expect([UInt8](packet) == [
            0x10, 19,                                  // CONNECT, remaining length
            0x00, 0x04, 0x4D, 0x51, 0x54, 0x54,        // "MQTT"
            0x04, 0xC2, 0x00, 0x3C,                    // level 4, flags, keep-alive 60
            0x00, 0x01, 0x63,                          // client id "c"
            0x00, 0x01, 0x75,                          // username "u"
            0x00, 0x01, 0x70,                          // password "p"
        ])
    }

    @Test func subscribePacket() {
        let packet = MQTTPacket.subscribe(packetId: 7, topics: ["a/b"])
        #expect([UInt8](packet) == [0x82, 8, 0x00, 0x07, 0x00, 0x03, 0x61, 0x2F, 0x62, 0x00])
    }

    @Test func publishUsesMultiByteLengthForLargePayloads() {
        let packet = MQTTPacket.publish(topic: "t", payload: Data(repeating: 0x41, count: 200))
        // remaining length = 2 + 1 + 200 = 203 → 0xCB 0x01
        #expect([UInt8](packet.prefix(3)) == [0x30, 0xCB, 0x01])
        #expect(packet.count == 3 + 203)
    }

    @Test func decoderRoundTripsPublish() {
        var decoder = MQTTPacket.Decoder()
        let payload = Data(#"{"ps":"on"}"#.utf8)
        let packets = decoder.append(MQTTPacket.publish(topic: "home/ac/status", payload: payload))
        #expect(packets == [.publish(topic: "home/ac/status", payload: payload)])
    }

    @Test func decoderHandlesSplitAndMergedFrames() {
        var decoder = MQTTPacket.Decoder()
        let stream = Data([0x20, 0x02, 0x00, 0x00])
            + MQTTPacket.publish(topic: "x", payload: Data("hi".utf8))
            + Data([0xD0, 0x00])
        var packets: [MQTTPacket.Incoming] = []
        for byte in stream { packets += decoder.append(Data([byte])) } // worst case: one byte at a time
        #expect(packets == [.connAck(returnCode: 0), .publish(topic: "x", payload: Data("hi".utf8)), .pingResponse])
    }

    @Test func decoderSkipsPacketIdOnQoS1Publish() {
        var decoder = MQTTPacket.Decoder()
        let body = MQTTPacket.string("t") + Data([0x00, 0x05]) + Data("ok".utf8)
        #expect(decoder.append(MQTTPacket.packet(0x32, body)) == [.publish(topic: "t", payload: Data("ok".utf8))])
    }

    @Test func rejectedConnAck() {
        var decoder = MQTTPacket.Decoder()
        #expect(decoder.append(Data([0x20, 0x02, 0x00, 0x05])) == [.connAck(returnCode: 5)])
    }
}
