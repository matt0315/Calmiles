import Foundation

/// Canonical Botland Studio URLs used everywhere in-app.
enum StudioURLs {
    static let website = URL(string: "https://botland.studio")!
    static let privacy = URL(string: "https://botland.studio/privacy")!
    static let terms = URL(string: "https://botland.studio/terms")!
    static let supportEmail = URL(string: "mailto:support@botland.studio")!

    /// App Store product page. User-facing “share the app” actions use this, not the studio site.
    static let appStore = URL(string: "https://apps.apple.com/app/id6809109970")!

    /// Share sheet body for inviting friends to Calmiles.
    static let friendShareText = """
    I've been using Calmiles to track work mileage — calm, simple logging for freelancers. Check it out: https://apps.apple.com/app/id6809109970
    """
}
