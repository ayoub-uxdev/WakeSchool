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
///
/// Quand ni compression ni chiffrement ne sont actifs, PRONOTE conserve l'objet JSON.
/// Dès qu'une des deux transformations est active, PRONOTE attend une chaîne hexadécimale.
enum PronoteDataSec {
    case jsonObject(Any)
    case encodedHex(String)
}

/// Codec minimal du protocole PRONOTE 2.15.x.
///
/// Pipeline :
/// JSON UTF-8 -> DEFLATE brut -> AES-CBC -> hexadécimal.
/// La compression, lorsqu'elle est activée, précède toujours le chiffrement.
enum PronoteCodec {

    static func jsonData(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw PronoteCodecError.invalidJSON
        }
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [])
        } catch {
            throw PronoteCodecError.invalidJSON
        }
    }

    static func jsonObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw PronoteCodecError.invalidJSON
        }
    }

    /// Compression DEFLATE brute (RFC 1951), telle qu'attendue par PRONOTE.
    /// Apple documente COMPRESSION_ZLIB comme un flux raw DEFLATE.
    static func deflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        return try process(data, operation: COMPRESSION_STREAM_ENCODE)
    }

    /// Décompression d'un flux DEFLATE brut.
    static func inflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        return try process(data, operation: COMPRESSION_STREAM_DECODE)
    }

    private static func process(_ data: Data,
                                operation: compression_stream_operation) throws -> Data {
        var stream = compression_stream(
            dst_ptr: nil,
            dst_size: 0,
            src_ptr: nil,
            src_size: 0,
            state: nil
        )

        guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            throw operation == COMPRESSION_STREAM_ENCODE
                ? PronoteCodecError.compressionFailed
                : PronoteCodecError.decompressionFailed
        }
        defer {
            compression_stream_destroy(&stream)
        }

        let outputCapacity = 64 * 1024
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: outputCapacity)
        let finalize = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)

        return try data.withUnsafeBytes { rawInput in
            guard let input = rawInput.bindMemory(to: UInt8.self).baseAddress else {
                throw operation == COMPRESSION_STREAM_ENCODE
                    ? PronoteCodecError.compressionFailed
                    : PronoteCodecError.decompressionFailed
            }

            stream.src_ptr = input
            stream.src_size = data.count

            var status: compression_status = COMPRESSION_STATUS_OK
            repeat {
                // Keep the destination pointer valid for the whole process call.
                status = buffer.withUnsafeMutableBytes { rawOutput in
                    stream.dst_ptr = rawOutput.bindMemory(to: UInt8.self).baseAddress!
                    stream.dst_size = outputCapacity
                    return compression_stream_process(&stream, finalize)
                }

                let produced = outputCapacity - stream.dst_size
                if produced > 0 {
                    output.append(buffer, count: produced)
                }

                if status == COMPRESSION_STATUS_ERROR {
                    throw operation == COMPRESSION_STREAM_ENCODE
                        ? PronoteCodecError.compressionFailed
                        : PronoteCodecError.decompressionFailed
                }
            } while status == COMPRESSION_STATUS_OK

            guard status == COMPRESSION_STATUS_END else {
                throw operation == COMPRESSION_STREAM_ENCODE
                    ? PronoteCodecError.compressionFailed
                    : PronoteCodecError.decompressionFailed
            }
            return output
        }
    }


    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    static func data(fromHex string: String) throws -> Data {
        guard string.count.isMultiple(of: 2) else {
            throw PronoteCodecError.invalidHex
        }

        let bytes = Array(string.utf8)
        var output = Data()
        output.reserveCapacity(bytes.count / 2)

        for index in stride(from: 0, to: bytes.count, by: 2) {
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
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    /// Prépare la valeur `dataSec` exacte à placer dans le JSON HTTP.
    static func encodeDataSec(_ object: Any,
                              compressed: Bool,
                              encrypted: Bool,
                              key: Data,
                              iv: Data) throws -> PronoteDataSec {
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
            do {
                payload = try PronoteCrypto.aesCBCEncrypt(payload, key: key, iv: iv)
            } catch {
                throw error
            }
        }
        return .encodedHex(hex(payload))
    }

    /// Décode une chaîne `dataSec` hexadécimale reçue après compression/chiffrement.
    static func decodeDataSec(_ hexString: String,
                              compressed: Bool,
                              encrypted: Bool,
                              key: Data,
                              iv: Data) throws -> Any {
        guard compressed || encrypted else {
            throw PronoteCodecError.invalidHex
        }

        var payload = try data(fromHex: hexString)
        if encrypted {
            do {
                payload = try PronoteCrypto.aesCBCDecrypt(payload, key: key, iv: iv)
            } catch {
                throw error
            }
        }
        if compressed {
            payload = try inflate(payload)
        }
        return try jsonObject(from: payload)
    }
}
