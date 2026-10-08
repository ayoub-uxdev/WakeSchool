import Foundation
import Compression

/// Erreurs de la couche d'encodage `dataSec` de PRONOTE.
enum PronoteCodecError: Error, Equatable {
    case invalidJSON
    case compressionFailed
    case decompressionFailed
    case invalidHex
}

/// Représentation de `dataSec` avant insertion dans le corps HTTP.
enum PronoteDataSec {
    case jsonObject(Any)
    case encodedHex(String)
}

/// Codec du protocole PRONOTE.
///
/// Pipeline :
///
/// JSON UTF-8
/// → DEFLATE
/// → AES-CBC
/// → hexadécimal
///
/// La compression est effectuée avant le chiffrement.
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

    /// Compression DEFLATE via Compression.framework.
    static func deflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        return try process(
            data,
            operation: COMPRESSION_STREAM_ENCODE
        )
    }

    /// Décompression via Compression.framework.
    static func inflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        return try process(
            data,
            operation: COMPRESSION_STREAM_DECODE
        )
    }

    private static func process(
        _ data: Data,
        operation: compression_stream_operation
    ) throws -> Data {

        // Xcode 27 / SDK iOS 27 expose explicitement cet initialiseur.
        var stream = compression_stream(
            dst_ptr: nil,
            dst_size: 0,
            src_ptr: nil,
            src_size: 0,
            state: nil
        )

        let initStatus = compression_stream_init(
            &stream,
            operation,
            COMPRESSION_ZLIB
        )

        guard initStatus != COMPRESSION_STATUS_ERROR else {
            if operation == COMPRESSION_STREAM_ENCODE {
                throw PronoteCodecError.compressionFailed
            } else {
                throw PronoteCodecError.decompressionFailed
            }
        }

        defer {
            compression_stream_destroy(&stream)
        }

        let outputCapacity = 64 * 1024
        var output = Data()
        var outputBuffer = [UInt8](
            repeating: 0,
            count: outputCapacity
        )

        return try data.withUnsafeBytes { rawInput in

            guard let inputPointer =
                    rawInput.bindMemory(
                        to: UInt8.self
                    ).baseAddress
            else {
                if operation == COMPRESSION_STREAM_ENCODE {
                    throw PronoteCodecError.compressionFailed
                } else {
                    throw PronoteCodecError.decompressionFailed
                }
            }

            stream.src_ptr = inputPointer
            stream.src_size = data.count

            var status: compression_status = COMPRESSION_STATUS_OK

            repeat {

                let produced: Int = outputBuffer.withUnsafeMutableBytes {
                    rawOutput in

                    guard let outputPointer =
                            rawOutput.bindMemory(
                                to: UInt8.self
                            ).baseAddress
                    else {
                        return -1
                    }

                    stream.dst_ptr = outputPointer
                    stream.dst_size = outputCapacity

                    status = compression_stream_process(
                        &stream,
                        Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                    )

                    return outputCapacity - stream.dst_size
                }

                guard produced >= 0 else {
                    if operation == COMPRESSION_STREAM_ENCODE {
                        throw PronoteCodecError.compressionFailed
                    } else {
                        throw PronoteCodecError.decompressionFailed
                    }
                }

                if produced > 0 {
                    output.append(
                        outputBuffer,
                        count: produced
                    )
                }

                if status == COMPRESSION_STATUS_ERROR {
                    if operation == COMPRESSION_STREAM_ENCODE {
                        throw PronoteCodecError.compressionFailed
                    } else {
                        throw PronoteCodecError.decompressionFailed
                    }
                }

            } while status == COMPRESSION_STATUS_OK

            guard status == COMPRESSION_STATUS_END else {
                if operation == COMPRESSION_STREAM_ENCODE {
                    throw PronoteCodecError.compressionFailed
                } else {
                    throw PronoteCodecError.decompressionFailed
                }
            }

            return output
        }
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