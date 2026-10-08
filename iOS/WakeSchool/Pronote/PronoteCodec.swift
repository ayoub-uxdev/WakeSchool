import Foundation
import Compression

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

    /// Compression ZLIB/DEFLATE utilisée par PRONOTE.
    static func deflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        let destinationCapacity = max(
            1024,
            data.count * 2
        )

        var destination = Data(
            count: destinationCapacity
        )

        let encodedSize: Int = data.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in

                guard let sourcePointer =
                        sourceBuffer.bindMemory(
                            to: UInt8.self
                        ).baseAddress,

                      let destinationPointer =
                        destinationBuffer.bindMemory(
                            to: UInt8.self
                        ).baseAddress
                else {
                    return 0
                }

                return compression_encode_buffer(
                    destinationPointer,
                    destinationCapacity,
                    sourcePointer,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard encodedSize > 0 else {
            throw PronoteCodecError.compressionFailed
        }

        destination.count = encodedSize
        return destination
    }

    /// Décompression ZLIB/DEFLATE utilisée par PRONOTE.
    ///
    /// La taille du résultat n'étant pas connue à l'avance,
    /// on agrandit progressivement le buffer.
    static func inflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        var destinationCapacity = max(
            4096,
            data.count * 4
        )

        let maximumCapacity = 64 * 1024 * 1024

        while destinationCapacity <= maximumCapacity {

            var destination = Data(
                count: destinationCapacity
            )

            let decodedSize: Int = data.withUnsafeBytes { sourceBuffer in
                destination.withUnsafeMutableBytes { destinationBuffer in

                    guard let sourcePointer =
                            sourceBuffer.bindMemory(
                                to: UInt8.self
                            ).baseAddress,

                          let destinationPointer =
                            destinationBuffer.bindMemory(
                                to: UInt8.self
                            ).baseAddress
                    else {
                        return 0
                    }

                    return compression_decode_buffer(
                        destinationPointer,
                        destinationCapacity,
                        sourcePointer,
                        data.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }

            if decodedSize > 0 {
                destination.count = decodedSize
                return destination
            }

            destinationCapacity *= 2
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