import XCTest
@testable import WakeSchool

final class PronoteHTTPTransportTests: XCTestCase {
    func testParsesLegacySessionParameters() throws {
        let html = """
        <a>>PRONOTE 2024.3.8</a>
        <body onload="try { Start ({h:'2052117',sCrA:true,sCoA:true,a:3,d:true}) } catch (e) { messageErreur (e) }"></body>
        """

        let result = try PronoteHTTPTransport.parseSessionParameters(from: html)

        XCTAssertEqual(result.sessionID, "2052117")
        XCTAssertEqual(result.spaceID, 3)
        XCTAssertTrue(result.skipRequestEncryption)
        XCTAssertTrue(result.skipRequestCompression)
        XCTAssertFalse(result.requestsAreEncrypted)
        XCTAssertFalse(result.requestsAreCompressed)
    }

    func testParsesModernSessionParametersAndInvertsEncryptionFlags() throws {
        let html = #"""
        <a>>PRONOTE 2026.2.7</a>
        <script>window.addEventListener("load", () => {try{Start ({"h":12345,"CrA":true,"CoA":false,"a":6});}});</script>
        """#

        let result = try PronoteHTTPTransport.parseSessionParameters(from: html)

        XCTAssertEqual(result.sessionID, "12345")
        XCTAssertEqual(result.spaceID, 6)
        XCTAssertFalse(result.skipRequestEncryption)
        XCTAssertTrue(result.skipRequestCompression)
        XCTAssertTrue(result.requestsAreEncrypted)
        XCTAssertFalse(result.requestsAreCompressed)
        XCTAssertEqual(result.version, [2026, 2, 7])
    }

    func testParsesMobileAppBootstrapMarkup() throws {
        let html = #"""
        <a>>PRONOTE 2026.2.7</a>
        <script>
        window.addEventListener("load", () => {try{Start ({"h":4873407,"d":true,"a":6});} catch (e) {IE.sendLogFailStart (4873407, e)}});
        </script>
        """#

        let result = try PronoteHTTPTransport.parseSessionParameters(from: html)

        XCTAssertEqual(result.sessionID, "4873407")
        XCTAssertEqual(result.spaceID, 6)
        XCTAssertTrue(result.skipRequestEncryption)
        XCTAssertTrue(result.skipRequestCompression)
    }

    func testNestedObjectDoesNotBreakSessionParameterParsing() throws {
        let html = #"""
        <a>>PRONOTE 2026.2.7</a>
        <body onload="Start ({h:'42',CrA:false,CoA:true,a:3,d:true,extra:{foo:'bar'}})">
        """#

        let result = try PronoteHTTPTransport.parseSessionParameters(from: html)

        XCTAssertEqual(result.sessionID, "42")
        XCTAssertEqual(result.spaceID, 3)
        XCTAssertFalse(result.skipRequestEncryption)
        XCTAssertFalse(result.skipRequestCompression)
    }

    func testMissingStartFails() {
        let html = #"<a>>PRONOTE 2026.2.7</a><body onload="hello()">"#

        XCTAssertThrowsError(
            try PronoteHTTPTransport.parseSessionParameters(from: html)
        ) { error in
            XCTAssertEqual(
                error as? PronoteTransportError,
                .sessionParametersNotFound
            )
        }
    }

    func testMissingSessionParameterFails() {
        let html = #"<a>>PRONOTE 2026.2.7</a><body onload="Start ({h:'42',CrA:true,CoA:true})">"#

        XCTAssertThrowsError(
            try PronoteHTTPTransport.parseSessionParameters(from: html)
        ) { error in
            XCTAssertEqual(
                error as? PronoteTransportError,
                .invalidSessionParameter("a")
            )
        }
    }

    func testNormalizeDirectURLAddsMobileBootstrapFlagsAndAccountPath() throws {
        let url = try PronoteHTTPTransport.normalizeDirectURL(
            "https://example.test/pronote/eleve.html?old=1",
            accountKind: .parent
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://example.test/pronote/mobile.parent.html?old=1&fd=1&login=true"
        )
    }

    func testBootstrapUsesRootURLForFunctionRequests() throws {
        let html = #"<a>>PRONOTE 2026.2.7</a><body onload="Start ({h:'42',CrA:true,CoA:true,a:6})">"#
        let directURL = try XCTUnwrap(
            URL(string: "https://example.test/pronote/mobile.eleve.html?fd=1&login=true")
        )

        let result = try PronoteHTTPTransport.parseSessionParameters(
            from: html,
            directURL: directURL
        )

        XCTAssertEqual(
            result.rootURL.absoluteString,
            "https://example.test/pronote/"
        )
        XCTAssertEqual(
            PronoteHTTPTransport.appelfonctionURL(
                rootURL: result.rootURL,
                spaceID: result.spaceID,
                sessionID: result.sessionID,
                order: "ABC"
            ).absoluteString,
            "https://example.test/pronote/appelfonction/6/42/ABC"
        )
    }
}
