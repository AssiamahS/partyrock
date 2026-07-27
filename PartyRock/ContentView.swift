import SwiftUI

struct ContentView: View {
    @StateObject private var player = PlayerWebViewStore()
    @StateObject private var api = SetlistAPI()
    @State private var urlText = ""
    @State private var showSettings = false
    @AppStorage("serverURL") private var serverURL = "https://saints-macbook-air.tail40af16.ts.net"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search or paste a YouTube link", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.webSearch)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { player.load(urlString: urlText) }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            PlayerWebView(store: player)

            statusBar

            HStack(spacing: 10) {
                Button {
                    setlistCurrent()
                } label: {
                    Label("Setlist It", systemImage: "list.number")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(api.phase == .resolving || api.phase == .shazaming || api.phase == .downloading)

                Button {
                    player.load(urlString: "https://m.youtube.com/results?search_query=amapiano+mix+2026")
                } label: {
                    Label("Amapiano", systemImage: "music.note")
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("Mac server (Tailscale)") {
                        TextField("https://…", text: $serverURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                .navigationTitle("Settings")
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if api.phase != .idle {
            HStack {
                if api.phase == .downloading || api.phase == .shazaming || api.phase == .resolving {
                    ProgressView()
                }
                Text(api.statusLine)
                    .font(.footnote)
                    .lineLimit(2)
                Spacer()
                Button(api.phase == .done || api.phase == .failed ? "Clear" : "Cancel") {
                    api.cancel()
                }
                .font(.footnote)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial)
        }
    }

    private func setlistCurrent() {
        player.fetchVideoURL { href in
            guard let href else {
                api.statusLine = "Open a video first, then hit Setlist It."
                api.phase = .failed
                return
            }
            var name = player.pageTitle
                .replacingOccurrences(of: " - YouTube", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = "PartyRock Set" }
            api.setlistIt(videoURL: href, setName: name)
        }
    }
}
