import Foundation

/// Talks to the setlist server on the Mac (Flask :8787) over Tailscale.
/// Flow mirrors the web UI: resolve → tracklist ? download : shazam → download.
final class SetlistAPI: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var statusLine: String = ""
    @Published var trackCount: Int = 0
    @Published var doneCount: Int = 0

    enum Phase: Equatable {
        case idle, resolving, shazaming, downloading, done, failed
    }

    var baseURL: String {
        UserDefaults.standard.string(forKey: "serverURL") ?? "http://saints-macbook-air.tail40af16.ts.net:8787"
    }

    private var pollTask: Task<Void, Never>?
    private var sourceURL: String = ""

    func setlistIt(videoURL: String, setName: String) {
        pollTask?.cancel()
        sourceURL = videoURL
        phase = .resolving
        statusLine = "Resolving tracklist…"
        pollTask = Task { await run(videoURL: videoURL, setName: setName) }
    }

    func cancel() {
        pollTask?.cancel()
        phase = .idle
        statusLine = ""
    }

    private func run(videoURL: String, setName: String) async {
        do {
            let resolved = try await post("/api/resolve", ["url": videoURL])
            let type = resolved["type"] as? String ?? ""
            if type == "tracklist", let tracks = resolved["tracks"] as? [[String: Any]], !tracks.isEmpty {
                try await download(setName: setName, tracks: tracks)
            } else if resolved["can_shazam"] as? Bool == true {
                try await shazamThenDownload(videoURL: videoURL, setName: setName)
            } else {
                await fail("No tracklist found and Shazam unavailable for this link.")
            }
        } catch is CancellationError {
        } catch {
            await fail("Error: \(error.localizedDescription)")
        }
    }

    private func shazamThenDownload(videoURL: String, setName: String) async throws {
        await set(.shazaming, "No published tracklist — Shazam-tagging the set…")
        let job = try await post("/api/shazam", ["url": videoURL])
        guard let id = job["id"] as? String else { throw err("shazam start failed") }
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            let st = try await get("/api/shazam/\(id)")
            let status = st["status"] as? String ?? ""
            let tracks = st["tracks"] as? [[String: Any]] ?? []
            await set(.shazaming, "Shazam: \(tracks.count) tracks so far…")
            if status == "done" {
                guard !tracks.isEmpty else { return await fail("Shazam found nothing usable.") }
                try await download(setName: setName, tracks: tracks)
                return
            }
            if status == "error" { return await fail(st["error"] as? String ?? "Shazam failed") }
        }
    }

    private func download(setName: String, tracks: [[String: Any]]) async throws {
        await MainActor.run {
            self.trackCount = tracks.count
            self.phase = .downloading
            self.statusLine = "Downloading \(tracks.count) tracks…"
        }
        let job = try await post("/api/download",
                                 ["name": setName, "tracks": tracks, "source_url": sourceURL])
        guard let id = job["id"] as? String else { throw err("download start failed") }
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            let st = try await get("/api/job/\(id)")
            let items = st["items"] as? [[String: Any]] ?? []
            let done = items.filter { ($0["status"] as? String) == "done" }.count
            let finished = (st["status"] as? String) != "running"
            await MainActor.run {
                self.doneCount = done
                self.statusLine = "Downloaded \(done)/\(items.count)…"
            }
            if finished {
                await set(.done, "Done — \(done)/\(items.count) tracks in the crate.")
                return
            }
        }
    }

    // MARK: - plumbing

    private func set(_ p: Phase, _ line: String) async {
        await MainActor.run { self.phase = p; self.statusLine = line }
    }

    private func fail(_ line: String) async {
        await MainActor.run { self.phase = .failed; self.statusLine = line }
    }

    private func err(_ s: String) -> NSError {
        NSError(domain: "PartyRock", code: 1, userInfo: [NSLocalizedDescriptionKey: s])
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + path) else { throw err("bad server URL") }
        var req = URLRequest(url: url, timeoutInterval: 300)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func get(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + path) else { throw err("bad server URL") }
        let (data, _) = try await URLSession.shared.data(from: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
