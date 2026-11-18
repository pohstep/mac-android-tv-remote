import Foundation

public enum AtvFeature {
    public static let ping: UInt32 = 1 << 0
    public static let key: UInt32 = 1 << 1
    public static let ime: UInt32 = 1 << 2
    public static let power: UInt32 = 1 << 5
    public static let volume: UInt32 = 1 << 6
    public static let appLink: UInt32 = 1 << 9
    public static let active: UInt32 = ping | key | ime | power | volume | appLink
}

public enum AtvDirection {
    public static let shortPress: UInt32 = 3
}

public enum AtvRemoteMessage {
    public static func key(code: Int, direction: UInt32 = AtvDirection.shortPress) -> Data {
        let body = Proto.field(1, value: UInt64(code)) + Proto.field(2, value: UInt64(direction))
        return Proto.field(10, bytes: body)
    }

    public static func text(_ text: String, imeCounter: Int, fieldCounter: Int) -> Data {
        let end = max(text.utf8.count - 1, 0)
        let object = Proto.field(1, value: UInt64(end)) + Proto.field(2, value: UInt64(end)) + Proto.field(3, text: text)
        let edit = Proto.field(1, value: 1) + Proto.field(2, bytes: object)
        let batch = Proto.field(1, value: UInt64(imeCounter))
            + Proto.field(2, value: UInt64(fieldCounter))
            + Proto.field(3, bytes: edit)
        return Proto.field(21, bytes: batch)
    }

    public static func launch(link: String) -> Data {
        let body = Proto.field(1, text: link)
        return Proto.field(90, bytes: body)
    }

    public static func appLink(for package: String) -> String {
        if package.contains("://") { return package }
        return "market://launch?id=\(package)"
    }

    public static func configure(features: UInt32 = AtvFeature.active) -> Data {
        let info = Proto.field(3, value: 1)
            + Proto.field(4, text: "1")
            + Proto.field(5, text: AtvPairingMessage.serviceName)
            + Proto.field(6, text: "1.0.0")
        let body = Proto.field(1, value: UInt64(features)) + Proto.field(2, bytes: info)
        return Proto.field(1, bytes: body)
    }

    public static func setActive(features: UInt32 = AtvFeature.active) -> Data {
        Proto.field(2, bytes: Proto.field(1, value: UInt64(features)))
    }

    public static func pingResponse(_ value: UInt64) -> Data {
        Proto.field(9, bytes: Proto.field(1, value: value))
    }

    public static func framedKey(_ button: AndroidKey) -> Data {
        Proto.frame(key(code: button.code))
    }
}

public struct AtvRemoteState: Equatable {
    public var imeCounter: Int
    public var fieldCounter: Int
    public var started: Bool?
    public var volumeLevel: Int?
    public var volumeMax: Int?
    public var muted: Bool?
    public var currentApp: String?

    public init() {
        imeCounter = 0
        fieldCounter = 0
        started = nil
        volumeLevel = nil
        volumeMax = nil
        muted = nil
        currentApp = nil
    }

    public mutating func reply(to payload: Data) -> Data? {
        let fields = ProtoFields.parse(payload)
        if let configure = fields.message(1) {
            _ = configure
            return AtvRemoteMessage.configure()
        }
        if fields.message(2) != nil {
            return AtvRemoteMessage.setActive()
        }
        if let ping = fields.message(8) {
            let value = ProtoFields.parse(ping).uint64(1) ?? 0
            return AtvRemoteMessage.pingResponse(value)
        }
        if let batch = fields.message(21) {
            let parsed = ProtoFields.parse(batch)
            if let counter = parsed.uint64(1) { imeCounter = Int(counter) }
            if let counter = parsed.uint64(2) { fieldCounter = Int(counter) }
            return nil
        }
        if let volume = fields.message(50) {
            let parsed = ProtoFields.parse(volume)
            if let max = parsed.uint64(6) { volumeMax = Int(max) }
            if let level = parsed.uint64(7) { volumeLevel = Int(level) }
            muted = parsed.uint64(8) == 1
            return nil
        }
        if let start = fields.message(40) {
            started = ProtoFields.parse(start).uint64(1) == 1
            return nil
        }
        if let inject = fields.message(20) {
            let app = ProtoFields.parse(inject).message(1)
            if let app, let package = ProtoFields.parse(app).message(12) {
                currentApp = String(data: package, encoding: .utf8)
            }
            return nil
        }
        return nil
    }
}
