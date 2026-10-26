import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@_silgen_name("uncompress")
private func pngUncompress(
    _ dest: UnsafeMutablePointer<UInt8>?,
    _ destLen: UnsafeMutablePointer<UInt>?,
    _ source: UnsafePointer<UInt8>?,
    _ sourceLen: UInt
) -> Int32

/// PNG bytes from `screencap -p`. A black frame or a broken file is not shown.
public enum ScreenshotBytes {
    public static let blankSentence = "blank, the TV blocks screenshots for protected video"

    public enum Kind: Equatable {
        case picture
        case blank
        case broken
    }

    public static func kind(_ data: Data) -> Kind {
        guard data.count >= 8 else { return .broken }
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        if [UInt8](data.prefix(8)) != signature { return .broken }

        var index = data.index(data.startIndex, offsetBy: 8)
        var width = 0
        var height = 0
        var bitDepth = 0
        var colorType = 0
        var interlace = 0
        var idat = Data()
        var sawHeader = false
        var sawEnd = false

        while index < data.endIndex {
            guard let length = u32(data, index) else { return .broken }
            index = data.index(index, offsetBy: 4)
            guard let typeEnd = data.index(index, offsetBy: 4, limitedBy: data.endIndex) else { return .broken }
            let type = String(bytes: data[index..<typeEnd], encoding: .ascii) ?? ""
            index = typeEnd
            guard let dataEnd = data.index(index, offsetBy: length, limitedBy: data.endIndex),
                  data.index(dataEnd, offsetBy: 4, limitedBy: data.endIndex) != nil else { return .broken }
            let chunk = data[index..<dataEnd]
            index = data.index(dataEnd, offsetBy: 4)
            if type == "IHDR" {
                guard chunk.count >= 13, let w = u32(chunk, chunk.startIndex) else { return .broken }
                let hIndex = chunk.index(chunk.startIndex, offsetBy: 4)
                guard let h = u32(chunk, hIndex) else { return .broken }
                let fields = [UInt8](chunk)
                width = w
                height = h
                bitDepth = Int(fields[8])
                colorType = Int(fields[9])
                interlace = Int(fields[12])
                sawHeader = true
            } else if type == "IDAT" {
                idat.append(chunk)
            } else if type == "IEND" {
                sawEnd = true
                break
            }
        }

        guard sawHeader, sawEnd, width > 0, height > 0 else { return .broken }
        guard bitDepth == 8, interlace == 0, let channels = channelCount(colorType) else {
            return .picture
        }
        let stride = width * channels
        let expected = height * (stride + 1)
        guard expected > 0, expected <= 64 * 1024 * 1024, let raw = inflate(idat, expected: expected) else {
            return .broken
        }
        guard raw.count == expected else { return .broken }
        guard let black = pixelsAreBlack(raw, width: width, height: height, channels: channels, colorType: colorType) else {
            return .broken
        }
        return black ? .blank : .picture
    }

    private static func channelCount(_ colorType: Int) -> Int? {
        switch colorType {
        case 0: return 1
        case 2: return 3
        case 4: return 2
        case 6: return 4
        default: return nil
        }
    }

    /// Color samples only. An alpha channel is ignored, so a transparent black frame still counts as blank.
    private static func colorSamples(_ colorType: Int) -> Int {
        switch colorType {
        case 6: return 3
        case 4: return 1
        case 2: return 3
        default: return 1
        }
    }

    private static func pixelsAreBlack(_ raw: [UInt8], width: Int, height: Int, channels: Int, colorType: Int) -> Bool? {
        let stride = width * channels
        let samples = colorSamples(colorType)
        var prior = [UInt8](repeating: 0, count: stride)
        var cursor = 0
        for _ in 0..<height {
            let filter = raw[cursor]
            cursor += 1
            var row = [UInt8](repeating: 0, count: stride)
            for column in 0..<stride {
                let value = Int(raw[cursor + column])
                let left = column >= channels ? Int(row[column - channels]) : 0
                let up = Int(prior[column])
                let upLeft = column >= channels ? Int(prior[column - channels]) : 0
                let decoded: Int
                switch filter {
                case 0: decoded = value
                case 1: decoded = value + left
                case 2: decoded = value + up
                case 3: decoded = value + (left + up) / 2
                case 4: decoded = value + Int(paeth(left, up, upLeft))
                default: return nil
                }
                row[column] = UInt8(truncatingIfNeeded: decoded)
            }
            cursor += stride
            var column = 0
            while column < stride {
                for sample in 0..<samples where row[column + sample] != 0 {
                    return false
                }
                column += channels
            }
            prior = row
        }
        return true
    }

    private static func paeth(_ left: Int, _ up: Int, _ upLeft: Int) -> UInt8 {
        let estimate = left + up - upLeft
        let leftDistance = abs(estimate - left)
        let upDistance = abs(estimate - up)
        let upLeftDistance = abs(estimate - upLeft)
        if leftDistance <= upDistance && leftDistance <= upLeftDistance { return UInt8(left) }
        if upDistance <= upLeftDistance { return UInt8(up) }
        return UInt8(upLeft)
    }

    private static func inflate(_ data: Data, expected: Int) -> [UInt8]? {
        var dest = [UInt8](repeating: 0, count: expected)
        var destLen = UInt(expected)
        let status = dest.withUnsafeMutableBufferPointer { destBuffer -> Int32 in
            data.withUnsafeBytes { sourceBuffer -> Int32 in
                pngUncompress(
                    destBuffer.baseAddress,
                    &destLen,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                    UInt(data.count)
                )
            }
        }
        guard status == 0, Int(destLen) == expected else { return nil }
        return dest
    }

    private static func u32(_ data: Data, _ index: Data.Index) -> Int? {
        guard let end = data.index(index, offsetBy: 4, limitedBy: data.endIndex) else { return nil }
        let bytes = [UInt8](data[index..<end])
        return (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
    }
}
