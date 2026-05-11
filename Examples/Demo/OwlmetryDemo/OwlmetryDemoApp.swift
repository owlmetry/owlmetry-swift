import SwiftUI
import Owlmetry
import WatchConnectivity

@main
struct OwlmetryDemoApp: App {
    init() {
        do {
            try Owl.configure(
                endpoint: "http://localhost:4000",
                apiKey: "owl_client_demo_000000000000000000000000000000000000000000"
            )
        } catch {
            print("Owlmetry configuration failed: \(error)")
        }

        // Receive events forwarded from the paired Apple Watch demo.
        if WCSession.isSupported() {
            WCSession.default.delegate = WatchEventForwarder.shared
            WCSession.default.activate()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Static singleton — WCSession.delegate is weakly held, so the strong
// reference must outlive the App struct.
private final class WatchEventForwarder: NSObject, WCSessionDelegate {
    static let shared = WatchEventForwarder()

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Owl.handleWatchUserInfo(userInfo)
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
