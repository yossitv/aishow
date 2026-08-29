import XCTest
@testable import AishowCore

final class ContextPackTests: XCTestCase {
    func testRoundTripJSON() throws {
        let pack = ContextPack(
            app: "Google Chrome",
            windowTitle: "Contact Us — Acme",
            url: "https://www.acme.com/contact",
            focusedInput: true,
            hasFormTextarea: true,
            chant: "この会社に、うちの音声 SDK の話でコールドメッセージ",
            capturedAt: Date(timeIntervalSince1970: 1_787_000_000)
        )
        let data = try JSONEncoder().encode(pack)
        let decoded = try JSONDecoder().decode(ContextPack.self, from: data)
        XCTAssertEqual(decoded, pack)
    }

    func testWorkflowRawValuesMatchSpellFileNames() {
        // harness/spells/<workflow>.md と一致させる
        XCTAssertEqual(Workflow.websiteForm.rawValue, "website_form")
        XCTAssertEqual(Workflow.linkedinDM.rawValue, "linkedin_dm")
        XCTAssertEqual(Workflow.casualEN.rawValue, "casual_en")
        XCTAssertEqual(Workflow.emailEN.rawValue, "email_en")
        XCTAssertEqual(Workflow.translate.rawValue, "translate")
    }
}
