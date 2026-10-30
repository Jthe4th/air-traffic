import SwiftUI
import ImageIO
import OverheadKit

/// Caps simultaneous downloads so a screenful of map tiles doesn't hammer a free tile server.
actor DownloadGate {
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let limit = 6

    func acquire() async {
        if running < limit { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }
}

/// In-memory image cache with synchronous lookup, so a view (or a snapshot renderer) can ask
/// "is it loaded yet?" without async plumbing. Network caching is handled by URLCache underneath.
@MainActor
@Observable
public final class ImageStore {
    public static let shared = ImageStore()

    private var images: [URL: Image] = [:]
    @ObservationIgnored private var loading: Set<URL> = []
    @ObservationIgnored private var failed: [URL: Date] = [:]
    @ObservationIgnored private let gate = DownloadGate()

    public func image(for url: URL) -> Image? { images[url] }

    public func insert(_ image: Image, for url: URL) { images[url] = image }

    public func load(_ url: URL) async {
        if images[url] != nil || loading.contains(url) { return }
        if let when = failed[url], Date().timeIntervalSince(when) < 30 { return }
        loading.insert(url)
        defer { loading.remove(url) }

        var request = URLRequest(url: url)
        request.setValue(ClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        await gate.acquire()
        defer { Task { await gate.release() } }
        do {
            let (data, response) = try await HTTP.session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { failed[url] = Date(); return }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { failed[url] = Date(); return }
            let image = Image(decorative: cg, scale: 1)
            withAnimation(.easeOut(duration: 0.4)) { images[url] = image }
        } catch {
            // A tile scrolled away (cancelled) is not a failure; it should load normally if it returns.
            if !Task.isCancelled { failed[url] = Date() }
        }
        if images.count > 700 {   // crude bound; tiles re-fetch from URLCache
            for key in images.keys.prefix(images.count - 500) where key != url { images[key] = nil }
        }
    }

    public func prefetch(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls { group.addTask { await self.load(url) } }
        }
    }
}

struct CachedImage: View {
    let url: URL
    var contentMode: ContentMode = .fill
    /// False draws only what is already cached and never starts a download.
    var autoload = true

    var body: some View {
        ZStack {
            if let image = ImageStore.shared.image(for: url) {
                image.resizable().aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: url) { if autoload { await ImageStore.shared.load(url) } }
    }
}
