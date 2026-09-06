import SwiftUI

enum CalmilesTypography {
    static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .default)
    static let callout = Font.system(.callout, design: .default)
    static let caption = Font.system(.caption, design: .default)
    static let metric = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
}
