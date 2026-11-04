import Foundation

/// An app the user can add to their Composio project. `verified` apps are known to be accepted by Composio;
/// others are offered too, and are dropped automatically if Composio does not recognize them.
struct CatalogApp: Identifiable, Hashable, Sendable {
    let slug: String
    let name: String
    let category: String
    let symbol: String
    var verified = false
    var id: String { slug }
}

enum ComposioCatalog {
    static let categories = ["Productivity", "Communication", "Code", "Design", "Business", "Social"]
    static let recommended = ["gmail", "googlecalendar", "googledrive", "notion", "slack", "github"]

    static let apps: [CatalogApp] = [
        CatalogApp(slug: "gmail", name: "Gmail", category: "Communication", symbol: "envelope.fill", verified: true),
        CatalogApp(slug: "slack", name: "Slack", category: "Communication", symbol: "number", verified: true),
        CatalogApp(slug: "outlook", name: "Outlook", category: "Communication", symbol: "envelope.badge.fill"),
        CatalogApp(slug: "discord", name: "Discord", category: "Communication", symbol: "bubble.left.and.bubble.right.fill"),
        CatalogApp(slug: "zoom", name: "Zoom", category: "Communication", symbol: "video.fill"),
        CatalogApp(slug: "googlecalendar", name: "Google Calendar", category: "Productivity", symbol: "calendar", verified: true),
        CatalogApp(slug: "googledrive", name: "Google Drive", category: "Productivity", symbol: "externaldrive.fill", verified: true),
        CatalogApp(slug: "notion", name: "Notion", category: "Productivity", symbol: "doc.text.fill", verified: true),
        CatalogApp(slug: "googledocs", name: "Google Docs", category: "Productivity", symbol: "doc.richtext.fill"),
        CatalogApp(slug: "googlesheets", name: "Google Sheets", category: "Productivity", symbol: "tablecells.fill"),
        CatalogApp(slug: "asana", name: "Asana", category: "Productivity", symbol: "checkmark.circle.fill"),
        CatalogApp(slug: "trello", name: "Trello", category: "Productivity", symbol: "rectangle.split.3x1.fill"),
        CatalogApp(slug: "todoist", name: "Todoist", category: "Productivity", symbol: "checklist"),
        CatalogApp(slug: "clickup", name: "ClickUp", category: "Productivity", symbol: "list.bullet.rectangle.fill"),
        CatalogApp(slug: "airtable", name: "Airtable", category: "Productivity", symbol: "square.grid.2x2.fill"),
        CatalogApp(slug: "dropbox", name: "Dropbox", category: "Productivity", symbol: "shippingbox.fill"),
        CatalogApp(slug: "calendly", name: "Calendly", category: "Productivity", symbol: "clock.fill"),
        CatalogApp(slug: "github", name: "GitHub", category: "Code", symbol: "chevron.left.forwardslash.chevron.right", verified: true),
        CatalogApp(slug: "linear", name: "Linear", category: "Code", symbol: "line.3.horizontal.decrease.circle.fill", verified: true),
        CatalogApp(slug: "gitlab", name: "GitLab", category: "Code", symbol: "arrow.triangle.branch"),
        CatalogApp(slug: "bitbucket", name: "Bitbucket", category: "Code", symbol: "externaldrive.connected.to.line.below.fill"),
        CatalogApp(slug: "jira", name: "Jira", category: "Code", symbol: "ticket.fill"),
        CatalogApp(slug: "sentry", name: "Sentry", category: "Code", symbol: "ladybug.fill"),
        CatalogApp(slug: "vercel", name: "Vercel", category: "Code", symbol: "triangle.fill"),
        CatalogApp(slug: "supabase", name: "Supabase", category: "Code", symbol: "bolt.fill"),
        CatalogApp(slug: "datadog", name: "Datadog", category: "Code", symbol: "chart.bar.fill"),
        CatalogApp(slug: "figma", name: "Figma", category: "Design", symbol: "paintpalette.fill", verified: true),
        CatalogApp(slug: "canva", name: "Canva", category: "Design", symbol: "paintbrush.fill"),
        CatalogApp(slug: "miro", name: "Miro", category: "Design", symbol: "rectangle.on.rectangle.angled.fill"),
        CatalogApp(slug: "hubspot", name: "HubSpot", category: "Business", symbol: "person.2.fill"),
        CatalogApp(slug: "salesforce", name: "Salesforce", category: "Business", symbol: "cloud.fill"),
        CatalogApp(slug: "stripe", name: "Stripe", category: "Business", symbol: "creditcard.fill"),
        CatalogApp(slug: "shopify", name: "Shopify", category: "Business", symbol: "cart.fill"),
        CatalogApp(slug: "zendesk", name: "Zendesk", category: "Business", symbol: "lifepreserver.fill"),
        CatalogApp(slug: "mailchimp", name: "Mailchimp", category: "Business", symbol: "megaphone.fill"),
        CatalogApp(slug: "twitter", name: "X (Twitter)", category: "Social", symbol: "at"),
        CatalogApp(slug: "reddit", name: "Reddit", category: "Social", symbol: "text.bubble.fill"),
        CatalogApp(slug: "youtube", name: "YouTube", category: "Social", symbol: "play.rectangle.fill"),
        CatalogApp(slug: "linkedin", name: "LinkedIn", category: "Social", symbol: "briefcase.fill")
    ]

    static func app(_ slug: String) -> CatalogApp? { apps.first { $0.slug == slug } }
    static var verifiedSlugs: Set<String> { Set(apps.filter(\.verified).map(\.slug)) }

    /// Case-insensitive search over name, slug and category, optionally limited to one category.
    static func filter(_ list: [CatalogApp] = apps, query: String, category: String?) -> [CatalogApp] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return list.filter { app in
            (category == nil || app.category == category)
                && words.allSatisfy { app.name.lowercased().contains($0) || app.slug.contains($0) || app.category.lowercased().contains($0) }
        }
    }

    /// Splits a request into what Composio should be asked for when an extra app is not accepted: only known-good apps remain.
    static func fallback(for requested: [String]) -> (use: [String], skipped: [String])? {
        let use = requested.filter { verifiedSlugs.contains($0) }
        guard !use.isEmpty, use.count < requested.count else { return nil }
        return (use, requested.filter { !verifiedSlugs.contains($0) })
    }
}
