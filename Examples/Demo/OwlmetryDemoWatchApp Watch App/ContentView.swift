import SwiftUI
import Owlmetry

struct ContentView: View {
    @State private var lastSent: String = "—"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Owlmetry Watch Demo")
                    .font(.headline)
                Text("last: \(lastSent)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("Fire event") {
                    Owl.track("watch_button_tap", attributes: ["source": "manual"])
                    lastSent = "single"
                }
                Button("Start workout (metric)") {
                    let op = Owl.startOperation("watch-workout")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        op.complete()
                    }
                    lastSent = "workout"
                }
                Button("Log error") {
                    Owl.error("watch_demo_error", attributes: ["scenario": "manual"])
                    lastSent = "error"
                }
                Button("Burst 25 events") {
                    for i in 0..<25 {
                        Owl.track("watch_burst", attributes: ["index": "\(i)"])
                    }
                    lastSent = "burst×25"
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
