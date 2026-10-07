import XCTest
@testable import WakeSchool

final class PronoteHTTPTransportTests: XCTestCase {
    func testParsesTypicalPronoteOnloadParameters() throws {
        let html = """
        <html><body onload="try { Start ({h:'2052117',sCrA:true,sCoA:true,a:3,d:true}) } catch (e) { messageErreur (e) }"></body></html>
        """
        let result = try PronoteHTTPTransport.parseSessionParameters(from: html)
        XCTAssertEqual(result.sessionID, "2052117")
        XCTAssertEqual(result.spaceID, 3)
        XCTAssertTrue(result.skipRequestEncryption)
        XCTAssertTrue(result.skipRequestCompression)
        XCTAssertFalse(result.requestsAreEncrypted)
        XCTAssertFalse(result.requestsAreCompressed)
    }

    func testParsesEncryptedAndCompressedFlags() throws {
        let html = #"<body onload='Start ({h:"12345", sCrA:false, sCoA:false, a:3})'>"#
        let result = try PronoteHTTPTransport.parseSessionParameters(from: html)
        XCTAssertEqual(result.sessionID, "12345")
        XCTAssertEqual(result.spaceID, 3)
        XCTAssertFalse(result.skipRequestEncryption)
        XCTAssertFalse(result.skipRequestCompression)
        XCTAssertTrue(result.requestsAreEncrypted)
        XCTAssertTrue(result.requestsAreCompressed)
    }

    func testNestedObjectDoesNotBreakParsing() throws {
        let html = #"<body onload="Start ({h:'42',sCrA:false,sCoA:true,a:3,d:true,extra:{foo:'bar'}})">"#
        let result = try PronoteHTTPTransport.parseSessionParameters(from: html)
        XCTAssertEqual(result.sessionID, "42")
        XCTAssertEqual(result.spaceID, 3)
    }

    func testMissingStartFails() {
        let html = #"<body onload="hello()">"#
        XCTAssertThrowsError(try PronoteHTTPTransport.parseSessionParameters(from: html)) { error in
            XCTAssertEqual(error as? PronoteTransportError, .sessionParametersNotFound)
        }
    }

    func testMissingParameterFails() {
        let html = #"<body onload="Start ({h:'42',sCrA:true,sCoA:true})">"#
        XCTAssertThrowsError(try PronoteHTTPTransport.parseSessionParameters(from: html)) { error in
            XCTAssertEqual(error as? PronoteTransportError, .invalidSessionParameter("a"))
        }
    }
}
