import Foundation

enum PronoteCodecError: Error, Equatable {
    case invalidJSON
    case compressionFailed
    case decompressionFailed
    case invalidHex
}

enum PronoteDataSec {
    case jsonObject(Any)
    case encodedHex(String)
}

enum PronoteCodec {

    // MARK: - JSON

    static func jsonData(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw PronoteCodecError.invalidJSON
        }

        do {
            return try JSONSerialization.data(
                withJSONObject: object,
                options: []
            )
        } catch {
            throw PronoteCodecError.invalidJSON
        }
    }

    static func jsonObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(
                with: data,
                options: []
            )
        } catch {
            throw PronoteCodecError.invalidJSON
        }
    }

    // MARK: - Compression

    /// Pawnote compresses the hexadecimal UTF-8 representation with raw DEFLATE.
    static func deflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        var capacity = max(1024, data.count * 2)
        while capacity <= 64 * 1024 * 1024 {
            var destination = Data(count: capacity)
            var encodedSize = Int32(capacity)
            let status = data.withUnsafeBytes { source in
                destination.withUnsafeMutableBytes { target in
                    pronote_deflate_raw(
                        source.bindMemory(to: UInt8.self).baseAddress,
                        Int32(data.count),
                        target.bindMemory(to: UInt8.self).baseAddress,
                        &encodedSize
                    )
                }
            }
            if status == 1 {
                destination.count = Int(encodedSize)
                return destination
            }
            guard status == 0 else {
                throw PronoteCodecError.compressionFailed
            }
            capacity *= 2
        }
        throw PronoteCodecError.compressionFailed
    }

    /// Inflates Pawnote's raw DEFLATE stream containing hexadecimal JSON.
    static func inflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        var capacity = max(4096, data.count * 4)
        while capacity <= 64 * 1024 * 1024 {
            var destination = Data(count: capacity)
            var decodedSize = Int32(capacity)
            let status = data.withUnsafeBytes { source in
                destination.withUnsafeMutableBytes { target in
                    pronote_inflate_raw(
                        source.bindMemory(to: UInt8.self).baseAddress,
                        Int32(data.count),
                        target.bindMemory(to: UInt8.self).baseAddress,
                        &decodedSize
                    )
                }
            }
            if status == 1 {
                destination.count = Int(decodedSize)
                guard let hexString = String(data: destination, encoding: .ascii) else {
                    throw PronoteCodecError.invalidHex
                }
                return try Self.data(fromHex: hexString)
            }
            guard status == 0 else {
                throw PronoteCodecError.decompressionFailed
            }
            capacity *= 2
        }
        throw PronoteCodecError.decompressionFailed
    }

    // MARK: - Hex

    static func hex(_ data: Data) -> String {
        data.map {
            String(format: "%02X", $0)
        }.joined()
    }

    static func data(fromHex string: String) throws -> Data {
        guard string.count.isMultiple(of: 2) else {
            throw PronoteCodecError.invalidHex
        }

        let bytes = Array(string.utf8)

        var output = Data()
        output.reserveCapacity(bytes.count / 2)

        for index in stride(
            from: 0,
            to: bytes.count,
            by: 2
        ) {
            guard let high = nibble(bytes[index]),
                  let low = nibble(bytes[index + 1])
            else {
                throw PronoteCodecError.invalidHex
            }

            output.append(
                (high << 4) | low
            )
        }

        return output
    }

    private static func nibble(
        _ byte: UInt8
    ) -> UInt8? {

        switch byte {

        case 48...57:
            return byte - 48

        case 65...70:
            return byte - 55

        case 97...102:
            return byte - 87

        default:
            return nil
        }
    }

    // MARK: - dataSec

    static func encodeDataSec(
        _ object: Any,
        compressed: Bool,
        encrypted: Bool,
        key: Data,
        iv: Data
    ) throws -> PronoteDataSec {

        guard compressed || encrypted else {

            guard JSONSerialization.isValidJSONObject(
                object
            ) else {
                throw PronoteCodecError.invalidJSON
            }

            return .jsonObject(object)
        }

        var payload = try jsonData(object)

        if compressed {
            payload = Data(hex(payload).utf8)
            payload = try deflate(payload)
        }

        if encrypted {
            payload = try PronoteCrypto.aesCBCEncrypt(
                payload,
                key: key,
                iv: iv
            )
        }

        return .encodedHex(
            hex(payload)
        )
    }

    static func decodeDataSec(
        _ hexString: String,
        compressed: Bool,
        encrypted: Bool,
        key: Data,
        iv: Data
    ) throws -> Any {

        guard compressed || encrypted else {
            throw PronoteCodecError.invalidHex
        }

        var payload = try data(
            fromHex: hexString
        )

        if encrypted {
            payload = try PronoteCrypto.aesCBCDecrypt(
                payload,
                key: key,
                iv: iv
            )
        }

        if compressed {
            payload = try inflate(payload)
        }

        return try jsonObject(
            from: payload
        )
    }
}