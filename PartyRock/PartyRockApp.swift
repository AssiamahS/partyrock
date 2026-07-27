import SwiftUI
import AVFoundation

@main
struct PartyRockApp: App {
    init() {
        // keep audio alive when the app is backgrounded / PiP'd
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
