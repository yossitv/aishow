import Foundation

/// ブラウザとみなすアプリ名の一覧。
private let browserAppNames: Set<String> = [
    "Google Chrome",
    "Arc",
    "Brave Browser",
    "Microsoft Edge",
    "Safari",
    "Chromium",
    "Vivaldi",
    "Firefox",
]

private let chatAppNames: Set<String> = [
    "Slack",
    "Discord",
    "Microsoft Teams",
    "Messages",
]

private let websiteFormPathKeywords = [
    "contact", "inquiry", "get-in-touch", "demo", "sales", "support", "talk-to",
]

/// URL 文字列から host を取り出し、`www.` を除いた domain を返す。
private func domain(from urlString: String?) -> String? {
    guard let urlString, let url = URL(string: urlString), let host = url.host else {
        return nil
    }
    if host.hasPrefix("www.") {
        return String(host.dropFirst(4))
    }
    return host
}

private func path(from urlString: String?) -> String {
    guard let urlString, let url = URL(string: urlString) else { return "" }
    return url.path.lowercased()
}

private func isBrowser(_ app: String) -> Bool {
    browserAppNames.contains(app)
}

/// `ContextPack` からサイト種別と workflow を判定する純粋関数。
/// 判定表(上から順、最初に当たったもの)は docs/steps/step-02-scan-detect.md を参照。
public func detect(_ pack: ContextPack) -> SiteDetection {
    let host = pack.url.flatMap { URL(string: $0)?.host?.lowercased() }
    let d = domain(from: pack.url)
    let p = path(from: pack.url)

    // linkedin
    if let host, host.contains("linkedin.com") {
        if p.hasPrefix("/in/") || p.hasPrefix("/messaging/") {
            return SiteDetection(domain: d, kind: .linkedin, workflow: .linkedinDM)
        }
    }

    // chat apps
    if chatAppNames.contains(pack.app) {
        return SiteDetection(domain: d, kind: .chat, workflow: .casualEN)
    }

    // mail
    if pack.app == "Mail" || host == "mail.google.com" {
        return SiteDetection(domain: d, kind: .mail, workflow: .emailEN)
    }

    // browser
    if isBrowser(pack.app) {
        let pathMatches = websiteFormPathKeywords.contains { p.contains($0) }
        if pathMatches || pack.hasFormTextarea {
            return SiteDetection(domain: d, kind: .websiteForm, workflow: .websiteForm)
        }
        return SiteDetection(domain: d, kind: .browser, workflow: .translate)
    }

    // other
    return SiteDetection(domain: d, kind: .general, workflow: .translate)
}
