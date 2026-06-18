import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CollectView()
                .tabItem {
                    Label("Collect", systemImage: "tray.and.arrow.down")
                }
            DetectView()
                .tabItem {
                    Label("Detect", systemImage: "dot.radiowaves.left.and.right")
                }
        }
    }
}

#Preview {
    ContentView()
}
