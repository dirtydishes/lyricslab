import SwiftUI
import Combine

@MainActor
final class ThemeManager: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    @AppStorage("themeID") private var themeIDRaw: String = ThemeID.retroFuturistic.rawValue

    var themeID: ThemeID {
        get { ThemeID(rawValue: themeIDRaw) ?? .retroFuturistic }
        set {
            themeIDRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var theme: AppTheme {
        AppTheme.forID(themeID)
    }
}
