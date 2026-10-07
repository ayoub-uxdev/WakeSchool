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

    // MARK: - Raw DEFLATE

    static func deflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        return try process(
            data,
            operation: COMPRESSION_STREAM_ENCODE
        )
    }

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

        var stream = compression_stream()

        let initializationStatus = withUnsafeMutablePointer(to: &stream) {
            compression_stream_init(
                $0,
                operation,
                COMPRESSION_ZLIB
            )
        }

        guard initializationStatus != COMPRESSION_STATUS_ERROR else {
            if operation == COMPRESSION_STREAM_ENCODE {
                throw PronoteCodecError.compressionFailed
            } else {
                throw PronoteCodecError.decompressionFailed
            }
        }

        defer {
            withUnsafeMutablePointer(to: &stream) {
                compression_stream_destroy($0)
            }
        }

        let bufferSize = 64 * 1024
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: bufferSize
        )

        defer {
            outputBuffer.deallocate()
        }

        var result = Data()

        let sourceResult = data.withUnsafeBytes {
            rawBuffer -> Data? in

            guard let sourcePointer = rawBuffer.bindMemory(
                to: UInt8.self
            ).baseAddress else {
                return Data()
            }

            stream.src_ptr = sourcePointer
            stream.src_size = data.count

            while true {

                stream.dst_ptr = outputBuffer
                stream.dst_size = bufferSize

                let status = compression_stream_process(
                    &stream,
                    Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                )

                let bytesWritten = bufferSize - stream.dst_size

                if bytesWritten > 0 {
                    result.append(
                        outputBuffer,
                        count: bytesWritten
                    )
                }

                if status == COMPRESSION_STATUS_END {
                    return result
                }

                if status == COMPRESSION_STATUS_ERROR {
                    return nil
                }

                if stream.src_size == 0 && bytesWritten == 0 {
                    return nil
                }
            }
        }

        guard let sourceResult else {
            if operation == COMPRESSION_STREAM_ENCODE {
                throw PronoteCodecError.compressionFailed
            } else {
                throw PronoteCodecError.decompressionFailed
            }
        }

        return sourceResult
    }

    // MARK: - Hex

    static func hex(_ data: Data) -> String {
        data.map {
            String(format: "%02X", $0)
        }
        .joined()
    }

    static func data(fromHex string: String) throws -> Data {
        let cleaned = string.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard cleaned.count.isMultiple(of: 2) else {
            throw PronoteCodecError.invalidHex
        }

        var data = Data()
        data.reserveCapacity(cleaned.count / 2)

        var index = cleaned.startIndex

        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(
                index,
                offsetBy: 2
            )

            let byteString = String(
                cleaned[index..<nextIndex]
            )

            guard let byte = UInt8(
                byteString,
                radix: 16
            ) else {
                throw PronoteCodecError.invalidHex
            }

            data.append(byte)
            index = nextIndex
        }

        return data
    }

    // MARK: - PRONOTE dataSec

    static func encodeRequestDataSec(
        object: Any,
        compressed: Bool,
        encrypted: Bool,
        key: Data,
        iv: Data
    ) throws -> PronoteDataSec {

        var payload = try jsonData(object)

        if compressed {
            payload = try deflate(payload)
        }

        if encrypted {
            payload = try PronoteCrypto.aesEncrypt(
                payload,
                key: key,
                iv: iv
            )
        }

        return .encodedHex(hex(payload))
    }

    static func decodeResponseDataSec(
        _ dataSec: Any,
        compressed: Bool,
        encrypted: Bool,
        key: Data,
        iv: Data
    ) throws -> Any {

        guard let hexString = dataSec as? String else {
            if let dictionary = dataSec as? [String: Any] {
                if let nested = dictionary["dataSec"] {
                    return try decodeResponseDataSec(
                        nested,
                        compressed: compressed,
                        encrypted: encrypted,
                        key: key,
                        iv: iv
                    )
                }

                if let data = dictionary["data"] {
                    return data
                }
            }

            return dataSec
        }

        var payload = try data(fromHex: hexString)

        if encrypted {
            payload = try PronoteCrypto.aesDecrypt(
                payload,
                key: key,
                iv: iv
            )
        }

        if compressed {
            payload = try inflate(payload)
        }

        return try jsonObject(from: payload)
    }
}