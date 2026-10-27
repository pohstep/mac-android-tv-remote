import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@_silgen_name("zlibVersion")
private func zlibVersion() -> UnsafePointer<CChar>

@_silgen_name("inflateInit2_")
private func inflateInit2_(
    _ stream: UnsafeMutableRawPointer,
    _ windowBits: Int32,
    _ version: UnsafePointer<CChar>,
    _ streamSize: Int32
) -> Int32

@_silgen_name("inflate")
private func zlibInflate(_ stream: UnsafeMutableRawPointer, _ flush: Int32) -> Int32

@_silgen_name("inflateEnd")
private func inflateEnd(_ stream: UnsafeMutableRawPointer) -> Int32

/// Which raster inside an APK is worth showing. XML adaptive icons are skipped.
public enum ApkIcons {
    public static func matches(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard lower.contains("/res/") || lower.hasPrefix("res/") else { return false }
        guard lower.hasSuffix(".png") || lower.hasSuffix(".webp") else { return false }
        let file = lower.split(separator: "/").last.map(String.init) ?? lower
        let stem = file.split(separator: ".").dropLast().joined(separator: ".")
        let prefixes = ["ic_launcher", "app_icon", "tv_banner", "banner", "icon"]
        return prefixes.contains { stem.hasPrefix($0) }
    }

    /// xxxhdpi, then xxhdpi, then smaller buckets. Checked longest-first so xxhdpi is not read as xhdpi.
    public static func densityRank(_ path: String) -> Int {
        let lower = path.lowercased()
        if lower.contains("xxxhdpi") { return 5 }
        if lower.contains("xxhdpi") { return 4 }
        if lower.contains("xhdpi") { return 3 }
        if lower.contains("hdpi") { return 2 }
        if lower.contains("mdpi") || lower.contains("tvdpi") { return 1 }
        return 0
    }

    public static func best(paths: [String], byteCounts: [Int]) -> Int? {
        guard paths.count == byteCounts.count else { return nil }
        var winner: (index: Int, density: Int, bytes: Int)?
        for index in paths.indices where matches(paths[index]) {
            let density = densityRank(paths[index])
            let bytes = byteCounts[index]
            if let current = winner {
                let betterDensity = density > current.density
                let sameDensityLarger = density == current.density && bytes > current.bytes
                if betterDensity || sameDensityLarger {
                    winner = (index, density, bytes)
                }
            } else {
                winner = (index, density, bytes)
            }
        }
        return winner?.index
    }
}

/// Minimal ZIP reader for APK entries. Stored and raw deflate. No resource-table parser.
public enum ZipArchive {
    public static func icon(in data: Data) -> Data? {
        let bytes = [UInt8](data)
        var index = 0
        var paths: [String] = []
        var images: [Data] = []
        while index + 30 <= bytes.count {
            if bytes[index] != 0x50 || bytes[index + 1] != 0x4B || bytes[index + 2] != 0x03 || bytes[index + 3] != 0x04 {
                index += 1
                continue
            }
            let flag = int16(bytes, index + 6)
            let method = int16(bytes, index + 8)
            var compressed = int32(bytes, index + 18)
            var uncompressed = int32(bytes, index + 22)
            let nameLength = int16(bytes, index + 26)
            let extraLength = int16(bytes, index + 28)
            let nameStart = index + 30
            guard nameStart + nameLength + extraLength <= bytes.count else { break }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            let dataStart = nameStart + nameLength + extraLength
            if flag & 0x08 != 0 && compressed == 0 {
                guard let located = scanPayload(bytes, from: dataStart) else { break }
                compressed = located.size
                uncompressed = 0
            }
            if compressed == 0xFFFFFFFF || uncompressed == 0xFFFFFFFF { break }
            guard dataStart + compressed <= bytes.count else { break }
            if ApkIcons.matches(name), compressed <= 8 * 1024 * 1024, uncompressed <= 8 * 1024 * 1024 {
                let payload = Data(bytes[dataStart..<(dataStart + compressed)])
                if let raw = decode(method: method, compressed: payload, expected: uncompressed) {
                    paths.append(name)
                    images.append(raw)
                }
            }
            index = dataStart + compressed
            if flag & 0x08 != 0 {
                if index + 4 <= bytes.count,
                   bytes[index] == 0x50, bytes[index + 1] == 0x4B, bytes[index + 2] == 0x07, bytes[index + 3] == 0x08 {
                    index += 16
                } else {
                    index += 12
                }
            }
        }
        guard let chosen = ApkIcons.best(paths: paths, byteCounts: images.map(\.count)) else { return nil }
        return images[chosen]
    }

    static func decode(method: Int, compressed: Data, expected: Int) -> Data? {
        if method == 0 { return compressed }
        guard method == 8 else { return nil }
        return inflateRaw(compressed, expected: expected)
    }

    /// ZIP method 8 is raw deflate (window -15), not a zlib wrapper.
    static func inflateRaw(_ input: Data, expected: Int) -> Data? {
        guard !input.isEmpty, input.count <= Int(UInt32.max) else { return nil }
        let limit = 8 * 1024 * 1024
        let capacity = expected > 0 ? min(expected, limit) : min(max(input.count * 4, 64), limit)
        guard capacity > 0 else { return nil }
        var output = Data(count: capacity)
        var stream = ZStream()
        let status = withUnsafeMutablePointer(to: &stream) { pointer -> Int32 in
            let began = inflateInit2_(
                UnsafeMutableRawPointer(pointer),
                -15,
                zlibVersion(),
                Int32(MemoryLayout<ZStream>.size)
            )
            guard began == 0 else { return began }
            let result = input.withUnsafeBytes { rawIn -> Int32 in
                output.withUnsafeMutableBytes { rawOut -> Int32 in
                    guard let inBase = rawIn.bindMemory(to: UInt8.self).baseAddress,
                          let outBase = rawOut.bindMemory(to: UInt8.self).baseAddress else { return -2 }
                    pointer.pointee.nextIn = UnsafeMutablePointer(mutating: inBase)
                    pointer.pointee.availIn = UInt32(input.count)
                    pointer.pointee.nextOut = outBase
                    pointer.pointee.availOut = UInt32(capacity)
                    return zlibInflate(UnsafeMutableRawPointer(pointer), 4)
                }
            }
            let produced = Int(pointer.pointee.totalOut)
            _ = inflateEnd(UnsafeMutableRawPointer(pointer))
            if result == 1, produced > 0, expected == 0 || produced == expected {
                output.removeSubrange(produced..<output.count)
                return 1
            }
            return result == 1 ? -3 : result
        }
        return status == 1 ? output : nil
    }

    private static func scanPayload(_ bytes: [UInt8], from start: Int) -> (size: Int, next: Int)? {
        var cursor = start
        let end = min(bytes.count, start + 2 * 1024 * 1024)
        while cursor + 4 <= end {
            if bytes[cursor] == 0x50 && bytes[cursor + 1] == 0x4B && bytes[cursor + 2] == 0x03 && bytes[cursor + 3] == 0x04 {
                return (cursor - start, cursor)
            }
            cursor += 1
        }
        return nil
    }

    private static func int16(_ bytes: [UInt8], _ index: Int) -> Int {
        Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
    }

    private static func int32(_ bytes: [UInt8], _ index: Int) -> Int {
        Int(bytes[index])
            | (Int(bytes[index + 1]) << 8)
            | (Int(bytes[index + 2]) << 16)
            | (Int(bytes[index + 3]) << 24)
    }
}

/// LP64 layout of zlib's z_stream. Size is checked against inflateInit2_.
private struct ZStream {
    var nextIn: UnsafeMutablePointer<UInt8>?
    var availIn: UInt32 = 0
    var totalIn: UInt64 = 0
    var nextOut: UnsafeMutablePointer<UInt8>?
    var availOut: UInt32 = 0
    var totalOut: UInt64 = 0
    var msg: UnsafeMutablePointer<CChar>?
    var state: OpaquePointer?
    var zalloc: OpaquePointer?
    var zfree: OpaquePointer?
    var opaque: OpaquePointer?
    var dataType: Int32 = 0
    var adler: UInt64 = 0
    var reserved: UInt64 = 0
}

public enum AppIconCache {
    public static func fileName(package: String, versionCode: String) -> String {
        let safe = package.map { character -> Character in
            if character.isLetter || character.isNumber || character == "." || character == "_" || character == "-" {
                return character
            }
            return "_"
        }
        let digits = versionCode.filter(\.isNumber)
        let code = digits.isEmpty ? "0" : String(digits)
        return "\(String(safe))@\(code).png"
    }

    public static func existing(directory: URL, package: String, versionCode: String) -> URL? {
        let png = directory.appendingPathComponent(fileName(package: package, versionCode: versionCode))
        if FileManager.default.fileExists(atPath: png.path) { return png }
        let webp = png.deletingPathExtension().appendingPathExtension("webp")
        if FileManager.default.fileExists(atPath: webp.path) { return webp }
        return nil
    }

    public static func store(directory: URL, package: String, versionCode: String, bytes: Data) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = directory.appendingPathComponent(fileName(package: package, versionCode: versionCode))
        let destination: URL
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            destination = png.deletingPathExtension().appendingPathExtension("webp")
        } else {
            destination = png
        }
        try bytes.write(to: destination, options: .atomic)
        return destination
    }
}

public enum AppIconFetch {
    public static let maxApkBytes = 150 * 1024 * 1024
    public static let timeout: TimeInterval = 15

    public static func versionCode(in text: String) -> String {
        guard let range = text.range(of: #"versionCode=([0-9]+)"#, options: .regularExpression) else { return "0" }
        let token = String(text[range])
        return String(token.dropFirst("versionCode=".count))
    }

    /// `pm path` prints `package:/.../base.apk`. Prefer that file over split APKs.
    public static func baseApkPath(_ text: String) -> String? {
        var paths: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let path: String
            if let range = line.range(of: "package:") {
                path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("/") {
                path = line
            } else {
                continue
            }
            if path.hasSuffix(".apk") { paths.append(path) }
        }
        return paths.first { $0.contains("base.apk") } ?? paths.first
    }

    /// One package. The pulled APK is removed before this returns. Nil keeps the name tile.
    public static func fetch(package: String, serial: String, client: AdbClient, cacheDirectory: URL) -> URL? {
        guard PackageName.isValid(package) else { return nil }
        var client = client
        let started = Date()
        func budget() -> TimeInterval {
            max(1, timeout - Date().timeIntervalSince(started))
        }
        client.timeout = budget()
        let dump = (try? client.shell(["cmd", "package", "dump", package], serial: serial)) ?? ""
        let version = versionCode(in: dump)
        if let hit = AppIconCache.existing(directory: cacheDirectory, package: package, versionCode: version) {
            return hit
        }
        client.timeout = budget()
        guard let listing = try? client.shell(["pm", "path", package], serial: serial),
              let remote = baseApkPath(listing) else { return nil }
        client.timeout = budget()
        if let stat = try? client.shell(["stat", "-c", "%s", remote], serial: serial),
           let size = Int(stat.trimmingCharacters(in: .whitespacesAndNewlines)),
           size > maxApkBytes {
            return nil
        }
        let local = URL(fileURLWithPath: client.temporaryDirectory, isDirectory: true)
            .appendingPathComponent("zapbar-\(UUID().uuidString).apk")
        defer { try? FileManager.default.removeItem(at: local) }
        client.timeout = budget()
        guard let pulled = try? client.pullFile(
            remotePath: remote,
            localPath: local.path,
            serial: serial,
            timeout: budget()
        ), pulled.status == 0 else { return nil }
        guard let data = try? Data(contentsOf: local), !data.isEmpty, data.count <= maxApkBytes else { return nil }
        guard let icon = ZipArchive.icon(in: data) else { return nil }
        return try? AppIconCache.store(directory: cacheDirectory, package: package, versionCode: version, bytes: icon)
    }
}

/// At most one fetch in flight, and a failed package is tried at most once more this session.
public final class AppIconSchedule {
    public static let maxAttempts = 2

    public private(set) var inFlight: String?
    private var waiting: [String] = []
    private var attempts: [String: Int] = [:]

    public func enqueue(_ packages: [String]) {
        for package in packages {
            guard PackageName.isValid(package) else { continue }
            if attempts[package, default: 0] >= Self.maxAttempts { continue }
            if inFlight == package || waiting.contains(package) { continue }
            waiting.append(package)
        }
    }

    public func next() -> String? {
        if inFlight != nil { return nil }
        guard !waiting.isEmpty else { return nil }
        let package = waiting.removeFirst()
        inFlight = package
        return package
    }

    public func finish(_ package: String, success: Bool) {
        if inFlight == package { inFlight = nil }
        if success {
            attempts[package] = Self.maxAttempts
            waiting.removeAll { $0 == package }
            return
        }
        let count = attempts[package, default: 0] + 1
        attempts[package] = count
        if count < Self.maxAttempts, !waiting.contains(package) {
            waiting.append(package)
        }
    }
}
