//
//  LocalImageInliner.swift
//  PreviewHTML
//
//  Rendered Markdown's local images, inlined as data URIs so a sealed page can show them.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Rewrites the `<img src>` of rendered HTML that names a local file into a `data:` URI, so a web view
/// sealed off from the file system and the network still shows the project's own screenshots.
public enum LocalImageInliner {
    /// The largest image inlined, in bytes; a bigger one keeps its `src` (and so does not show).
    public static let byteCap = 8_000_000

    /// Data URIs already made, keyed by path and content stamp, so a live re-render re-reads only an
    /// image whose file changed. Bounded: one entry can be about 10.6 MB (the cap × base64's 4/3).
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.totalCostLimit = 64_000_000
        return cache
    }()

    /// `html` with every `<img src="…">` that names a readable local image (relative to `baseURL`, an
    /// absolute path, or a `file:` URL) replaced by its data URI. Remote, `data:` and protocol-relative
    /// sources, missing files and files over `byteCap` keep their `src`.
    public static func inline(_ html: String, baseURL: URL?, byteCap: Int = LocalImageInliner.byteCap) -> String {
        guard let baseURL, html.contains("<img "),
            let regex = try? NSRegularExpression(pattern: #"<img([^>]*?)src="([^"]*)"([^>]*)>"#)
        else { return html }
        let ns = html as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            last = NSMaxRange(match.range)
            let src = ns.substring(with: match.range(at: 2))
            let uri = fileURL(forSource: src, baseURL: baseURL).flatMap { dataURI(for: $0, byteCap: byteCap) } ?? src
            result += "<img\(ns.substring(with: match.range(at: 1)))src=\"\(uri)\"\(ns.substring(with: match.range(at: 3)))>"
        }
        return result + ns.substring(from: last)
    }

    /// The local file an image `src` names, or nil for a remote, `data:` or protocol-relative one. The
    /// attribute's HTML escapes are undone (`a&amp;b.png` is `a&b.png`), a `?query` or `#fragment` is
    /// dropped, and percent-encoding is decoded (`my%20shot.png` is `my shot.png`), as a browser would.
    static func fileURL(forSource src: String, baseURL: URL) -> URL? {
        let raw = src.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
        let lower = raw.lowercased()
        if ["http://", "https://", "data:", "//"].contains(where: lower.hasPrefix) { return nil }
        if lower.hasPrefix("file://") { return URL(string: raw) }
        let path = String(raw.prefix { $0 != "?" && $0 != "#" })
        let decoded = path.removingPercentEncoding ?? path
        guard !decoded.isEmpty else { return nil }
        return decoded.hasPrefix("/") ? URL(fileURLWithPath: decoded) : baseURL.appendingPathComponent(decoded)
    }

    /// The file as a `data:` URI, or nil when it cannot be read or is over `byteCap` — measured before
    /// it is read, so a huge file is never loaded only to be refused.
    private static func dataURI(for fileURL: URL, byteCap: Int) -> String? {
        let stamp = fileURL.contentStamp
        let key = "\(fileURL.path)|\(stamp ?? "-")|\(byteCap)" as NSString
        if stamp != nil, let cached = cache.object(forKey: key) { return cached as String }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? Int, size < byteCap,
            let data = try? Data(contentsOf: fileURL)
        else { return nil }
        let uri = "data:\(mimeType(forExtension: fileURL.pathExtension));base64,\(data.base64EncodedString())"
        if stamp != nil { cache.setObject(uri as NSString, forKey: key, cost: uri.utf16.count * 2) }
        return uri
    }

    /// The MIME type of an image file extension; `application/octet-stream` for one it does not know.
    public static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        case "bmp": "image/bmp"
        case "ico": "image/x-icon"
        case "avif": "image/avif"
        case "heic": "image/heic"
        default: "application/octet-stream"
        }
    }
}
