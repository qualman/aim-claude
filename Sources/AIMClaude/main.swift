import SwiftUI

struct AIMClaudeApp: App {
    var body: some Scene {
        WindowGroup("AIM") {
            Text("AIM").frame(width: 200, height: 400)
        }
    }
}

MainActor.assumeIsolated { RenderMode.runIfRequested() }
AIMClaudeApp.main()
