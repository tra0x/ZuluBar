import SwiftUI

@main
struct ZuluBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings {} // keeps SwiftUI lifecycle happy, no windows
    }
}
