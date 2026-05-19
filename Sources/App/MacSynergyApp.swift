import SwiftUI

@main
struct MacSynergyApp: App {
    // Inject the App Delegate to handle windowing and global shortcuts natively
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We use the Settings scene to prevent SwiftUI from spawning a default window on launch.
        // This is a native and robust technique for menu-bar and floating overlay applications.
        Settings {
            EmptyView()
        }
    }
}
