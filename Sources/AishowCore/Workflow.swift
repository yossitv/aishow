/// 開いているサイト / サービスの種別と、対応する workflow(呪文)。
/// 判定ロジック本体 `detect(_:)` は Step 2 で実装する。
public enum SiteKind: String, Codable, Sendable {
    case websiteForm = "website_form"
    case linkedin
    case chat
    case mail
    case browser
    case general
}

public enum Workflow: String, Codable, Sendable {
    case websiteForm = "website_form"
    case linkedinDM = "linkedin_dm"
    case casualEN = "casual_en"
    case emailEN = "email_en"
    case translate
}

public struct SiteDetection: Codable, Equatable, Sendable {
    public var domain: String?
    public var kind: SiteKind
    public var workflow: Workflow

    public init(domain: String?, kind: SiteKind, workflow: Workflow) {
        self.domain = domain
        self.kind = kind
        self.workflow = workflow
    }
}
