import Foundation

/// Packages a single USD layer into a USDZ archive.
///
/// USDZ is an uncompressed zip whose file bytes start on a 64-byte boundary.
/// The layout matches `scripts/generate_assets.py`.
enum USDZPacker {
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = ((2026 - 1980) << 9) | (1 << 5) | 1

    static func pack(named name: String, data: Data) throws -> Data {
        guard data.count <= Int(UInt32.max) else {
            throw UserFacingError(message: "That USD file is too large to package.")
        }
        let nameBytes = Data(name.utf8)
        guard nameBytes.count <= Int(UInt16.max) else {
            throw UserFacingError(message: "That file name is too long.")
        }
        let extraLength = (64 - ((30 + nameBytes.count) % 64)) % 64
        let crc = crc32(data)
        var local = Data()
        local.appendUInt32(0x0403_4B50)
        local.appendUInt16(20)
        local.appendUInt16(0)
        local.appendUInt16(0)
        local.appendUInt16(dosTime)
        local.appendUInt16(dosDate)
        local.appendUInt32(crc)
        local.appendUInt32(UInt32(data.count))
        local.appendUInt32(UInt32(data.count))
        local.appendUInt16(UInt16(nameBytes.count))
        local.appendUInt16(UInt16(extraLength))
        local.append(nameBytes)
        local.append(Data(repeating: 0, count: extraLength))
        let payloadStart = local.count
        local.append(data)

        var central = Data()
        central.appendUInt32(0x0201_4B50)
        central.appendUInt16(20)
        central.appendUInt16(20)
        central.appendUInt16(0)
        central.appendUInt16(0)
        central.appendUInt16(dosTime)
        central.appendUInt16(dosDate)
        central.appendUInt32(crc)
        central.appendUInt32(UInt32(data.count))
        central.appendUInt32(UInt32(data.count))
        central.appendUInt16(UInt16(nameBytes.count))
        central.appendUInt16(0)
        central.appendUInt16(0)
        central.appendUInt16(0)
        central.appendUInt16(0)
        central.appendUInt32(0)
        central.appendUInt32(0)
        central.append(nameBytes)

        var eocd = Data()
        eocd.appendUInt32(0x0605_4B50)
        eocd.appendUInt16(0)
        eocd.appendUInt16(0)
        eocd.appendUInt16(1)
        eocd.appendUInt16(1)
        eocd.appendUInt32(UInt32(central.count))
        eocd.appendUInt32(UInt32(local.count))
        eocd.appendUInt16(0)

        var archive = Data()
        archive.append(local)
        archive.append(central)
        archive.append(eocd)
        guard payloadStart % 64 == 0 else {
            throw UserFacingError(message: "Could not prepare that USD file.")
        }
        return archive
    }

    static func internalName(for data: Data, pathExtension: String) -> String {
        if data.starts(with: Data("#usda".utf8)) || pathExtension.lowercased() == "usda" {
            return "model.usda"
        }
        return "model.usdc"
    }

    /// Standard IEEE CRC-32, the checksum ZIP stores for uncompressed entries.
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                if value & 1 == 1 {
                    value = (value >> 1) ^ 0xEDB8_8320
                } else {
                    value >>= 1
                }
            }
            return value
        }
    }()
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
