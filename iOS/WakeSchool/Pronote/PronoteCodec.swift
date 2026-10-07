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

    // MARK: - DEFLATE

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

        let destinationCapacity = max(64 * 1024, data.count * 2)

        var output = Data()

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
            throw operation == COMPRESSION_STREAM_ENCODE
                ? PronoteCodecError.compressionFailed
                : PronoteCodecError.decompressionFailed
        }

        defer {
            compression_stream_destroy(&stream)
        }

        var buffer = [UInt8](
            repeating: 0,
            count: destinationCapacity
        )

        let result: Data = try data.withUnsafeBytes { inputBuffer in

            guard let inputPointer = inputBuffer.bindMemory(
                to: UInt8.self
            ).baseAddress else {
                throw operation == COMPRESSION_STREAM_ENCODE
                    ? PronoteCodecError.compressionFailed
                    : PronoteCodecError.decompressionFailed
            }

            stream.src_ptr = inputPointer
            stream.src_size = data.count

            var resultData = Data()

            while true {

                let produced: Int = buffer.withUnsafeMutableBytes {
                    destinationBuffer in

                    guard let destinationPointer =
                        destinationBuffer.bindMemory(
                            to: UInt8.self
                        ).baseAddress
                    else {
                        return -1
                    }

                    stream.dst_ptr = destinationPointer
                    stream.dst_size = destinationCapacity

                    let status = compression_stream_process(
                        &stream,
                        COMPRESSION_STREAM_FINALIZE
                    )

                    let written =
                        destinationCapacity - stream.dst_size

                    if written > 0 {
                        resultData.append(
                            buffer,
                            count: written
                        )
                    }

                    if status == COMPRESSION_STATUS_ERROR {
                        return -1
                    }

                    if status == COMPRESSION_STATUS_END {
                        return -2
                    }

                    return written
                }

                if produced == -1 {
                    throw operation == COMPRESSION_STREAM_ENCODE
                        ? PronoteCodecError.compressionFailed
                        : PronoteCodecError.decompressionFailed
                }

                if produced == -2 {
                    break
                }
            }

            return resultData
        }

        output.append(result)

        return output
    }

    // MARK: - HEX

    static func hex(_ data: Data) -> String {
        data.map {
            String(format: "%02X", $0)
        }
        .joined()
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

            guard
                let high = nibble(bytes[index]),
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

    // MARK: - PRONOTE dataSec encoding

    static func encodeRequestDataSec(
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

            /*
             PRONOTE/pronotepy request behaviour:
             JSON -> UTF8 -> HEX text -> raw DEFLATE
            */

            let jsonHex = hex(payload).lowercased()

            payload = try deflate(
                Data(jsonHex.utf8)
            )
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

    // MARK: - PRONOTE dataSec decoding

    static func decodeResponseDataSec(
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

            payload = try inflate(
                payload
            )
        }

        /*
         Response compression is JSON UTF8 after DEFLATE.
        */

        return try jsonObject(
            from: payload
        )
    }

    // MARK: - Compatibility aliases

    static func encodeDataSec(
        _ object: Any,
        compressed: Bool,
        encrypted: Bool,
        key: Data,
        iv: Data
    ) throws -> PronoteDataSec {

        try encodeRequestDataSec(
            object,
            compressed: compressed,
            encrypted: encrypted,
            key: key,
            iv: iv
        )
    }

    static func decodeDataSec(
        _ hexString: String,
        compressed: Bool,
        encrypted: Bool,
        key: Data,
        iv: Data
    ) throws -> Any {

        try decodeResponseDataSec(
            hexString,
            compressed: compressed,
            encrypted: encrypted,
            key: key,
            iv: iv
        )
    }
}