import XCTest
@testable import WakeSchool

final class PronoteENTLoginWebViewTests: XCTestCase {
    func testLoginURLsStartAtInfoMobileAndContinueToMobileAccountPage() throws {
        let urls = try PronoteENTLoginWebView.loginURLs(
            from: "https://school.example/pronote/",
            accountKind: .student
        )

        XCTAssertEqual(
            urls.bootstrapURL.absoluteString,
            "https://school.example/pronote/InfoMobileApp.json?id=0D264427-EEFC-4810-A9E9-346942A862A4"
        )
        XCTAssertEqual(
            urls.mobileURL.absoluteString,
            "https://school.example/pronote/mobile.eleve.html?fd=1"
        )
    }

    func testLoginURLsNormalizeAnExistingMobilePage() throws {
        let urls = try PronoteENTLoginWebView.loginURLs(
            from: "https://school.example/pronote/mobile.parent.html?login=true",
            accountKind: .parent
        )

        XCTAssertEqual(
            urls.bootstrapURL.absoluteString,
            "https://school.example/pronote/InfoMobileApp.json?id=0D264427-EEFC-4810-A9E9-346942A862A4"
        )
        XCTAssertEqual(
            urls.mobileURL.absoluteString,
            "https://school.example/pronote/mobile.parent.html?fd=1"
        )
    }

    func testLoginURLsRejectUnencryptedHTTP() {
        XCTAssertThrowsError(
            try PronoteENTLoginWebView.loginURLs(
                from: "http://school.example/pronote/",
                accountKind: .student
            )
        )
    }
}
