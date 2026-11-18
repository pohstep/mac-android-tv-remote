import Foundation

struct AdbInteger: Equatable {
    private var limbs: [UInt32]

    init() {
        limbs = [0]
    }

    init(bigEndian data: Data) {
        var bytes = [UInt8](data)
        while bytes.count % 4 != 0 {
            bytes.insert(0, at: 0)
        }
        var built: [UInt32] = []
        built.reserveCapacity(bytes.count / 4)
        var index = bytes.count
        while index > 0 {
            index -= 4
            let value = (UInt32(bytes[index]) << 24)
                | (UInt32(bytes[index + 1]) << 16)
                | (UInt32(bytes[index + 2]) << 8)
                | UInt32(bytes[index + 3])
            built.append(value)
        }
        limbs = built
        trim()
    }

    func littleEndian(width: Int) -> Data {
        Data(bigEndian(width: width).reversed())
    }

    func bigEndian(width: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: width)
        for (offset, limb) in limbs.enumerated() {
            let base = width - (offset + 1) * 4
            guard base >= 0 else { continue }
            bytes[base] = UInt8((limb >> 24) & 0xff)
            bytes[base + 1] = UInt8((limb >> 16) & 0xff)
            bytes[base + 2] = UInt8((limb >> 8) & 0xff)
            bytes[base + 3] = UInt8(limb & 0xff)
        }
        return Data(bytes)
    }

    static func one() -> AdbInteger {
        AdbInteger(limbs: [1])
    }

    func adding(_ other: AdbInteger) -> AdbInteger {
        let count = max(limbs.count, other.limbs.count)
        var result = [UInt32](repeating: 0, count: count + 1)
        var carry: UInt64 = 0
        for index in 0..<count {
            let left = index < limbs.count ? UInt64(limbs[index]) : 0
            let right = index < other.limbs.count ? UInt64(other.limbs[index]) : 0
            let sum = left + right + carry
            result[index] = UInt32(sum & 0xffff_ffff)
            carry = sum >> 32
        }
        result[count] = UInt32(carry)
        return AdbInteger(limbs: result)
    }

    func subtracting(_ other: AdbInteger) -> AdbInteger {
        var result = limbs
        if result.count < other.limbs.count {
            result.append(contentsOf: repeatElement(0, count: other.limbs.count - result.count))
        }
        var borrow: UInt64 = 0
        for index in 0..<result.count {
            let right = index < other.limbs.count ? UInt64(other.limbs[index]) : 0
            let left = UInt64(result[index])
            if left >= right + borrow {
                result[index] = UInt32(left - right - borrow)
                borrow = 0
            } else {
                result[index] = UInt32((left + (1 << 32)) - right - borrow)
                borrow = 1
            }
        }
        return AdbInteger(limbs: result)
    }

    func compare(_ other: AdbInteger) -> ComparisonResult {
        let left = trimmed()
        let right = other.trimmed()
        if left.limbs.count != right.limbs.count {
            return left.limbs.count < right.limbs.count ? .orderedAscending : .orderedDescending
        }
        var index = left.limbs.count
        while index > 0 {
            index -= 1
            if left.limbs[index] != right.limbs[index] {
                return left.limbs[index] < right.limbs[index] ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    func bitLength() -> Int {
        let value = trimmed()
        guard let top = value.limbs.last else { return 0 }
        if top == 0 { return 0 }
        return (value.limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    func bit(_ index: Int) -> Bool {
        let limb = index / 32
        guard limb < limbs.count else { return false }
        return (limbs[limb] >> (index % 32)) & 1 == 1
    }

    func mod(_ modulus: AdbInteger) -> AdbInteger {
        var remainder = trimmed()
        let divisor = modulus.trimmed()
        if remainder.compare(divisor) == .orderedAscending { return remainder }
        let shift = remainder.bitLength() - divisor.bitLength()
        var current = divisor.shiftedLeft(by: shift)
        var steps = shift
        while true {
            if remainder.compare(current) != .orderedAscending {
                remainder = remainder.subtracting(current)
            }
            if steps == 0 { break }
            current = current.shiftedRight1()
            steps -= 1
        }
        return remainder
    }

    func addingMod(_ other: AdbInteger, modulus: AdbInteger) -> AdbInteger {
        var sum = adding(other)
        if sum.compare(modulus) != .orderedAscending {
            sum = sum.subtracting(modulus)
        }
        if sum.compare(modulus) != .orderedAscending {
            sum = sum.subtracting(modulus)
        }
        return sum
    }

    func multiplyingMod(_ other: AdbInteger, modulus: AdbInteger) -> AdbInteger {
        var result = AdbInteger()
        var doubled = self.mod(modulus)
        let bits = other.bitLength()
        if bits == 0 { return result }
        for index in 0..<bits {
            if other.bit(index) {
                result = result.addingMod(doubled, modulus: modulus)
            }
            doubled = doubled.addingMod(doubled, modulus: modulus)
        }
        return result
    }

    func exponentiating(_ exponent: AdbInteger, modulus: AdbInteger) -> AdbInteger {
        var result = AdbInteger.one()
        var base = self.mod(modulus)
        let bits = exponent.bitLength()
        if bits == 0 { return result }
        for index in 0..<bits {
            if exponent.bit(index) {
                result = result.multiplyingMod(base, modulus: modulus)
            }
            base = base.multiplyingMod(base, modulus: modulus)
        }
        return result
    }

    func lowWord() -> UInt32 {
        limbs.first ?? 0
    }

    private init(limbs: [UInt32]) {
        self.limbs = limbs
        trim()
    }

    private func trimmed() -> AdbInteger {
        var copy = self
        copy.trim()
        return copy
    }

    private mutating func trim() {
        while limbs.count > 1 && limbs.last == 0 {
            limbs.removeLast()
        }
        if limbs.isEmpty { limbs = [0] }
    }

    private func shiftedLeft(by bits: Int) -> AdbInteger {
        guard bits > 0 else { return self }
        let words = bits / 32
        let remain = bits % 32
        var result = [UInt32](repeating: 0, count: limbs.count + words + 1)
        var carry: UInt32 = 0
        for index in 0..<limbs.count {
            let value = limbs[index]
            result[index + words] = (value << remain) | carry
            carry = remain == 0 ? 0 : value >> (32 - remain)
        }
        result[limbs.count + words] = carry
        return AdbInteger(limbs: result)
    }

    private func shiftedRight1() -> AdbInteger {
        var result = [UInt32](repeating: 0, count: limbs.count)
        var carry: UInt32 = 0
        var index = limbs.count
        while index > 0 {
            index -= 1
            let value = limbs[index]
            result[index] = (value >> 1) | carry
            carry = (value & 1) << 31
        }
        return AdbInteger(limbs: result)
    }
}
