import XCTest
@testable import AishowCore

final class DetectTests: XCTestCase {
    /// このファイル(#filePath)からの相対パスでフィクスチャディレクトリを解決する。
    /// Bundle.module は使わない(発注書の指示どおり)。
    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AishowCoreTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures/context")
    }

    private func loadPack(_ name: String) throws -> ContextPack {
        let url = Self.fixturesDirectory.appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContextPack.self, from: data)
    }

    func testWebsiteFormByURLPath() throws {
        let pack = try loadPack("01_website_form_by_path.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .websiteForm)
        XCTAssertEqual(site.workflow, .websiteForm)
        XCTAssertEqual(site.domain, "acme.com")
    }

    func testWebsiteFormByTextarea() throws {
        let pack = try loadPack("02_website_form_by_textarea.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .websiteForm)
        XCTAssertEqual(site.workflow, .websiteForm)
        XCTAssertEqual(site.domain, "acme.com")
    }

    func testBrowserGeneral() throws {
        let pack = try loadPack("03_browser_general.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .browser)
        XCTAssertEqual(site.workflow, .translate)
        XCTAssertEqual(site.domain, "acme.com")
    }

    func testLinkedInProfile() throws {
        let pack = try loadPack("04_linkedin_profile.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .linkedin)
        XCTAssertEqual(site.workflow, .linkedinDM)
        XCTAssertEqual(site.domain, "linkedin.com")
    }

    func testLinkedInMessaging() throws {
        let pack = try loadPack("05_linkedin_messaging.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .linkedin)
        XCTAssertEqual(site.workflow, .linkedinDM)
    }

    /// 誤判定防止: `host.contains("linkedin.com")` だと `evil-linkedin.com` のような偽ドメインも
    /// 拾ってしまうため、`host == "linkedin.com" || host.hasSuffix(".linkedin.com")` の厳密比較にした。
    func testSpoofedLinkedInDomainIsNotDetected() {
        let pack = ContextPack(app: "Safari", url: "https://evil-linkedin.com/in/janedoe/")
        let site = detect(pack)
        XCTAssertNotEqual(site.kind, .linkedin)
        XCTAssertNotEqual(site.workflow, .linkedinDM)
    }

    func testSlackChat() throws {
        let pack = try loadPack("06_slack_chat.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .chat)
        XCTAssertEqual(site.workflow, .casualEN)
        XCTAssertNil(site.domain)
    }

    func testGmailByHost() throws {
        let pack = try loadPack("07_gmail_by_host.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .mail)
        XCTAssertEqual(site.workflow, .emailEN)
        XCTAssertEqual(site.domain, "mail.google.com")
    }

    func testMailApp() throws {
        let pack = try loadPack("08_mail_app.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .mail)
        XCTAssertEqual(site.workflow, .emailEN)
    }

    func testGeneralNonBrowserApp() throws {
        let pack = try loadPack("09_general_non_browser_app.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .general)
        XCTAssertEqual(site.workflow, .translate)
    }

    func testWebsiteFormDemoPath() throws {
        let pack = try loadPack("10_website_form_demo_path.json")
        let site = detect(pack)
        XCTAssertEqual(site.kind, .websiteForm)
        XCTAssertEqual(site.workflow, .websiteForm)
        XCTAssertEqual(site.domain, "acme.com")
    }
}
