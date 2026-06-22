import SwiftUI
import Supabase

// MARK: - MessageImageView
/// Loads chat-image files from Supabase Storage using the authenticated SDK
/// `download` API, so it works whether the bucket is public or private (as
/// long as the user has a SELECT policy on storage.objects).
///
/// Falls back to URLSession for any URL that isn't a Supabase Storage URL.
struct MessageImageView: View {
    let urlString: String
    var maxWidth : CGFloat = 200
    var maxHeight: CGFloat = 220

    @State private var image  : UIImage? = nil
    @State private var failed : Bool     = false
    @State private var loading: Bool     = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if failed {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .frame(minWidth: min(maxWidth, 120), minHeight: min(maxHeight, 90))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo").foregroundColor(.gray)
                            if maxWidth >= 140 {
                                Text("Tap to retry").font(.caption2).foregroundColor(.gray)
                            }
                        }
                    )
                    .onTapGesture { Task { await load(force: true) } }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .frame(minWidth: min(maxWidth, 120), minHeight: min(maxHeight, 120))
                    .overlay(ProgressView())
            }
        }
        .task(id: urlString) { await load(force: false) }
    }

    // MARK: load
    private func load(force: Bool) async {
        if loading { return }
        if !force, let cached = MessageImageCache.shared.get(urlString) {
            image = cached
            return
        }
        loading = true
        failed  = false
        defer { loading = false }

        // Path 1: Supabase Storage URL → use authenticated SDK download (works
        // for both public and private buckets, no URL-level auth needed).
        if let (bucket, path) = parseSupabaseStorageURL(urlString) {
            do {
                print("[MessageImageView] downloading via SDK: bucket=\(bucket) path=\(path)")
                let data = try await supabase.storage.from(bucket).download(path: path)
                guard let img = UIImage(data: data) else {
                    print("[MessageImageView] data is not a valid image (\(data.count) bytes)")
                    failed = true
                    return
                }
                MessageImageCache.shared.set(img, for: urlString)
                image = img
                return
            } catch {
                print("[MessageImageView] SDK download FAILED for \(bucket)/\(path) → \(error)")
                // Don't bail — fall through to URLSession as a last attempt.
            }
        }

        // Path 2: plain HTTPS URL → URLSession with bearer token if available.
        guard let url = URL(string: urlString) else {
            print("[MessageImageView] invalid URL string: \(urlString)")
            failed = true
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        if let token = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("[MessageImageView] HTTP \(http.statusCode) for \(urlString)")
                if let body = String(data: data, encoding: .utf8) {
                    print("[MessageImageView] body: \(body.prefix(400))")
                }
                failed = true
                return
            }
            guard let img = UIImage(data: data) else {
                print("[MessageImageView] non-image data (\(data.count) bytes) for \(urlString)")
                failed = true
                return
            }
            MessageImageCache.shared.set(img, for: urlString)
            image = img
        } catch {
            print("[MessageImageView] network error for \(urlString): \(error)")
            failed = true
        }
    }

    /// Returns `(bucket, path)` if `urlString` looks like a Supabase Storage URL.
    /// Matches both `/object/public/<bucket>/<path>` and `/object/sign/<bucket>/<path>`
    /// (and even unsigned `/object/<bucket>/<path>`).
    private func parseSupabaseStorageURL(_ s: String) -> (String, String)? {
        guard let url = URL(string: s) else { return nil }
        // path components are like: ["/", "storage", "v1", "object", "public", "<bucket>", "<...path>"]
        var parts = url.pathComponents
        if parts.first == "/" { parts.removeFirst() }
        guard let i = parts.firstIndex(of: "object") else { return nil }
        var rest = Array(parts.dropFirst(i + 1))
        // Drop the variant marker (public / sign / authenticated) if present.
        if let first = rest.first, first == "public" || first == "sign" || first == "authenticated" {
            rest.removeFirst()
        }
        guard let bucket = rest.first, rest.count > 1 else { return nil }
        let path = rest.dropFirst().joined(separator: "/")
        return (bucket, path)
    }
}

// MARK: - In-memory cache
final class MessageImageCache {
    static let shared = MessageImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.countLimit = 200 }

    func get(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}
