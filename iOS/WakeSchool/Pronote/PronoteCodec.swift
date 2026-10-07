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

/// Codec minimal du protocole PRONOTE 2.15.x.
///
/// Pipeline :
/// JSON UTF-8 -> DEFLATE brut -> AES-CBC -> hexadécimal.
enum PronoteCodec {

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

    /// Compression DEFLATE brute.
    static func deflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        return try process(
            data,
            operation: COMPRESSION_STREAM_ENCODE
        )
    }

    /// Décompression DEFLATE brute.
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

        let outputCapacity = 64 * 1024
        var output = Data()

        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: outputCapacity
        )
        defer {
            outputBuffer.deallocate()
        }

        return try data.withUnsafeBytes { rawInput in

            guard let inputPointer = rawInput.bindMemory(
                to: UInt8.self
            ).baseAddress else {
                throw operation == COMPRESSION_STREAM_ENCODE
                    ? PronoteCodecError.compressionFailed
                    : PronoteCodecError.decompressionFailed
            }

            var stream = compression_stream(
                dst_ptr: outputBuffer,
                dst_size: outputCapacity,
                src_ptr: inputPointer,
                src_size: data.count,
                state: nil
            )

            let initStatus = compression_stream_init(
                &stream,
                operation,
                COMPRESSION_ZLIB
            )

            guard initStatus != COMPRESSION_STATUS_ERROR else {
                throw operation == COMPRESSION_STREAM_ENCODE
                    ? PronoteCodecError.compressionFailed
                    : PronoteCodecError.decompressionFailed
            }

            defer {
                compression_stream_destroy(&stream)
            }

            let finalize = Int32(
                COMPRESSION_STREAM_FINALIZE.rawValue
            )

            while true {

                stream.dst_ptr = outputBuffer
                stream.dst_size = outputCapacity

                let status = compression_stream_process(
                    &stream,
                    finalize
                )

                let produced = outputCapacity - stream.dst_size

                if produced > 0 {
                    output.append(
                        outputBuffer,
                        count: produced
                    )
                }

                if status == COMPRESSION_STATUS_END {
                    return output
                }

                if status == COMPRESSION_STATUS_ERROR {
                    throw operation == COMPRESSION_STREAM_ENCODE
                        ? PronoteCodecError.compressionFailed
                        : PronoteCodecError.decompressionFailed
                }

                if stream.src_size == 0 && produced == 0 {
                    throw operation == COMPRESSION_STREAM_ENCODE
                        ? PronoteCodecError.compressionFailed
                        : PronoteCodecError.decompressionFailed
                }
            }
        }
    }

    static func hex(_ data: Data) -> String {
        data
            .map { String(format: "%02X", $0) }
            .joined()
    }

    static func data(fromHex string: String) throws -> Data {
        let cleaned = string.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard cleaned.count.isMultiple(of: 2) else {
            throw PronoteCodecError.invalidHex
        }

        let bytes = Array(cleaned.utf8)

        var output = Data()
        output.reserveCapacity(bytes.count / 2)

        for index in stride(
            from: 0,
            to: bytes.count,
            by: 2
        ) {
            guard let high = nibble(bytes[index]),
                  let low = nibble(bytes[index + 1]) else {
                throw PronoteCodecError.invalidHex
            }

            output.append((high << 4) | low)
        }

        return output
    }

    private static func nibble(_ byte: UInt8) -> UInt8? {
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

    /// Prépare la valeur `dataSec` à placer dans le JSON HTTP.
    static func encodeDataSec(
        _ object: Any,
        compressed: Bool,
        encrypted: Bool,
        key: Data,
        iv: Data
    ) throws -> PronoteDataSec {

        guard compressed || encrypted else {
            guard JSONSerialization.isValidJSONObject(object) else {
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

    /// Décode une chaîne `dataSec` hexadécimale.
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