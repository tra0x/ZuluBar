import SwiftUI

@main
struct ZuluBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {} // keeps SwiftUI lifecycle happy, no windows
    }
}
