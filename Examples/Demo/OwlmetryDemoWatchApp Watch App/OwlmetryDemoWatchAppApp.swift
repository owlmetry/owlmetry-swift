import SwiftUI
import Owlmetry

@main
struct OwlmetryDemoWatchApp_Watch_AppApp: App {
    init() {
        do {
            try Owl.configure(
                endpoint: "http://localhost:4000",
                apiKey: "owl_client_demo_000000000000000000000000000000000000000000"
            )
        } catch {
            print("Owlmetry configuration failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
