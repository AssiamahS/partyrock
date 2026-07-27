import SwiftUI

// MARK: - models (mirror /api/history on the setlist server)

struct SetSummary: Identifiable, Decodable {
    let id: String
    let name: String
    let status: String
    let started: Double?
    let finished: Double?
    let source_url: String?
    let total: Int
    let done: Int
    let crate: String?

    var crateName: String? {
        // "…/Subcrates/My Set.crate" → "My Set"
        guard let crate else { return nil }
        return crate.split(separator: "/").last.map {
            String($0).replacingOccurrences(of: ".crate", with: "")
        }
    }
}

struct SetTrack: Decodable {
    let n: Int?
    let artist: String?
    let title: String?
    let name: String?
    let t: Double?
    let status: String?
    let source: String?

    var display: String {
        if let artist, let title, !artist.isEmpty { return "\(artist) — \(title)" }
        if let title, !title.isEmpty { return title }
        return name ?? "Unknown"
    }

    var cue: String? {
        guard let t else { return nil }
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct SetDetail: Decodable {
    let id: String
    let name: String
    let status: String
    let source_url: String?
    let crate: CrateInfo?
    let items: [SetTrack]

    struct CrateInfo: Decodable {
        let path: String?
        let tracks: Int?
    }
}

// MARK: - store

@MainActor
final class LibraryStore: ObservableObject {
    @Published var sets: [SetSummary] = []
    @Published var loading = false
    @Published var error: String?

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "serverURL") ?? "https://saints-macbook-air.tail40af16.ts.net"
    }

    func refresh() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            guard let url = URL(string: baseURL + "/api/history") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Resp: Decodable { let sets: [SetSummary] }
            sets = try JSONDecoder().decode(Resp.self, from: data).sets
        } catch {
            self.error = error.localizedDescription
        }
    }

    func detail(id: String) async throws -> SetDetail {
        guard let url = URL(string: baseURL + "/api/history/\(id)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SetDetail.self, from: data)
    }
}

// MARK: - views

struct LibraryView: View {
    @StateObject private var store = LibraryStore()

    var body: some View {
        NavigationStack {
            Group {
                if let error = store.error {
                    ContentUnavailableView("Can't reach the Mac",
                                           systemImage: "wifi.exclamationmark",
                                           description: Text(error))
                } else if store.sets.isEmpty && !store.loading {
                    ContentUnavailableView("No sets yet",
                                           systemImage: "music.note.list",
                                           description: Text("Play a DJ set and hit Setlist It — every set you rip lands here."))
                } else {
                    List(store.sets) { set_ in
                        NavigationLink(value: set_.id) {
                            SetRow(summary: set_)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: String.self) { id in
                SetDetailView(id: id, store: store)
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
        }
    }
}

private struct SetRow: View {
    let summary: SetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.name)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 6) {
                if summary.status == "running" {
                    ProgressView().controlSize(.mini)
                    Text("\(summary.done)/\(summary.total) downloading…")
                } else {
                    Image(systemName: summary.done == summary.total
                          ? "checkmark.circle.fill" : "checkmark.circle.badge.xmark")
                        .foregroundStyle(summary.done == summary.total ? .green : .orange)
                    Text("\(summary.done)/\(summary.total) tracks")
                }
                if let crate = summary.crateName {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.purple)
                    Text("Serato: \(crate)")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let started = summary.started {
                Text(Date(timeIntervalSince1970: started), style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SetDetailView: View {
    let id: String
    @ObservedObject var store: LibraryStore
    @State private var detail: SetDetail?
    @State private var error: String?

    var body: some View {
        Group {
            if let detail {
                List {
                    if let path = detail.crate?.path {
                        crateSection(path: path)
                    }
                    Section("Tracks — set order") {
                        ForEach(Array(detail.items.enumerated()), id: \.offset) { i, track in
                            TrackRow(index: i, track: track)
                        }
                    }
                }
            } else if let error {
                ContentUnavailableView("Couldn't load set", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(detail?.name ?? "Set")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { detail = try await store.detail(id: id) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func crateSection(path: String) -> some View {
        Section {
            Label {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.purple)
            }
        } header: {
            Text("In your Serato crates")
        }
    }
}

private struct TrackRow: View {
    let index: Int
    let track: SetTrack

    var body: some View {
        HStack(spacing: 10) {
            Text("\(track.n ?? index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.display)
                    .font(.subheadline)
                    .lineLimit(2)
                if let cue = track.cue {
                    Text("in the set at \(cue)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            statusIcon
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch track.status ?? "" {
        case "done":
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
        case "downloading", "queued":
            ProgressView().controlSize(.small)
        case "skipped":
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case "not_found":
            Image(systemName: "questionmark.circle").foregroundStyle(.orange)
        default:
            Image(systemName: "xmark.circle").foregroundStyle(.red)
        }
    }
}
