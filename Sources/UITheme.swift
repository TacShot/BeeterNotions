import SwiftUI

enum UITheme {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let secondaryWindow = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let selection = Color.accentColor.opacity(0.12)
    static let subtleSelection = Color.primary.opacity(0.06)
    static let accent = Color.accentColor
}
