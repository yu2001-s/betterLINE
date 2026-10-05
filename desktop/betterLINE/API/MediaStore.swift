import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Owner-only disk cache under ~/Library/Caches: decrypted chat media keyed by
/// message id, and public CDN images (avatars, stickers) keyed by URL hash.
actor MediaStore {
	static let shared = MediaStore()

	nonisolated let root: URL
	private nonisolated let mediaDir: URL
	private nonisolated let publicDir: URL
	private var inflight: [String: Task<URL, Error>] = [:]
	private let limitBytes: Int64 = 2 << 30
	/// This store is the cache; URLSession's own would keep a second copy.
	private static let cdn: URLSession = {
		let c = URLSessionConfiguration.default
		c.urlCache = nil
		return URLSession(configuration: c)
	}()

	init() {
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		root = caches.appending(path: Bundle.main.bundleIdentifier ?? "com.example.betterline")
		mediaDir = root.appending(path: "media")
		publicDir = root.appending(path: "public")
		for dir in [root, mediaDir, publicDir] {
			try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		}
	}

	/// A message's media on disk, downloading it once.
	func file(for message: Message, api: LineAPI) async throws -> URL {
		if let local = message.localFile { return local }
		if let cached = cachedFile(for: message.id) { return cached }
		if let running = inflight[message.id] { return try await running.value }
		let task = Task<URL, Error> {
			let download = try await api.downloadMedia(message)
			let name = Self.fileName(for: message, download: download)
			let dir = mediaDir.appending(path: message.id)
			try? FileManager.default.removeItem(at: dir)
			try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
			let target = dir.appending(path: name)
			try FileManager.default.moveItem(at: download.file, to: target)
			try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
			return target
		}
		inflight[message.id] = task
		defer { inflight[message.id] = nil }
		let url = try await task.value
		evictIfNeeded()
		return url
	}

	/// A file this app just sent, so its own message never downloads it back.
	func adopt(_ file: URL, as messageId: String) {
		let dir = mediaDir.appending(path: messageId)
		guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else { return }
		let target = dir.appending(path: file.lastPathComponent)
		try? FileManager.default.copyItem(at: file, to: target)
		try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
	}

	nonisolated func cachedFile(for messageId: String) -> URL? {
		let dir = mediaDir.appending(path: messageId)
		guard let name = try? FileManager.default.contentsOfDirectory(atPath: dir.path).first(where: { !$0.hasPrefix(".") }) else {
			return nil
		}
		return dir.appending(path: name)
	}

	/// Public CDN content (profile pictures, stickers).
	func publicData(_ url: URL) async throws -> Data {
		let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
		let file = publicDir.appending(path: key)
		if let data = try? Data(contentsOf: file) { return data }
		let (data, response) = try await Self.cdn.data(from: url)
		guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
		try? data.write(to: file, options: .atomic)
		return data
	}

	func totalSize() -> Int64 {
		Self.size(of: root)
	}

	func clear() {
		for dir in [mediaDir, publicDir] {
			for item in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
				try? FileManager.default.removeItem(at: item)
			}
		}
	}

	/// Drops the least recently written media once the cache passes its limit.
	private func evictIfNeeded() {
		let fm = FileManager.default
		guard let dirs = try? fm.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
		var entries = dirs.map { dir in
			(dir, Self.size(of: dir), (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
		}
		var total = entries.reduce(0) { $0 + $1.1 }
		guard total > limitBytes else { return }
		entries.sort { $0.2 < $1.2 }
		for (dir, size, _) in entries where total > limitBytes {
			try? fm.removeItem(at: dir)
			total -= size
		}
	}

	private static func size(of dir: URL) -> Int64 {
		let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
		guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: Array(keys)) else { return 0 }
		var total: Int64 = 0
		for case let url as URL in walker {
			let values = try? url.resourceValues(forKeys: keys)
			if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
		}
		return total
	}

	private static func fileName(for message: Message, download: DownloadedMedia) -> String {
		// linejs sometimes names downloads "undefined".
		let usable = { (name: String?) -> String? in
			guard let name, !name.isEmpty else { return nil }
			let stem = (name as NSString).deletingPathExtension
			return ["undefined", "null"].contains(stem) ? nil : name
		}
		let raw = usable(message.media?.fileName) ?? usable(download.fileName) ?? message.id
		var name = raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
		if (name as NSString).pathExtension.isEmpty {
			let ext = download.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? Self.defaultExtension(message.kind)
			name += ".\(ext)"
		}
		return name
	}

	private static func defaultExtension(_ kind: MessageKind) -> String {
		switch kind {
		case .image: "jpg"
		case .video: "mp4"
		case .audio: "m4a"
		default: "bin"
		}
	}
}

/// Decoded, downsampled images in memory, shared by every view.
@MainActor
final class ImagePipeline {
	static let shared = ImagePipeline()

	private let memory = NSCache<NSString, NSImage>()
	private var inflight: [String: Task<NSImage?, Never>] = [:]
	/// Width / height of media images, so bubbles keep their size between loads.
	private(set) var aspects: [String: CGFloat] = [:]

	init() {
		memory.totalCostLimit = 300 << 20
	}

	func cached(_ key: String) -> NSImage? {
		memory.object(forKey: key as NSString)
	}

	/// `key` names the source; each size of it is cached separately, so a small
	/// thumbnail (an attachment chip) is never handed to a large view (a bubble).
	func image(key source: String, maxPixel: CGFloat, load: @escaping @Sendable () async throws -> URL) async -> NSImage? {
		let key = "\(source)@\(Int(maxPixel))"
		if let hit = cached(key) { return hit }
		if let running = inflight[key] { return await running.value }
		let task = Task<NSImage?, Never> {
			guard let file = try? await load() else { return nil }
			return await Self.decode(file: file, maxPixel: maxPixel)
		}
		inflight[key] = task
		let image = await task.value
		inflight[key] = nil
		if let image {
			store(image, key: key)
		}
		return image
	}

	func publicImage(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
		let key = "pub:\(url.absoluteString):\(Int(maxPixel))"
		if let hit = cached(key) { return hit }
		if let running = inflight[key] { return await running.value }
		let task = Task<NSImage?, Never> {
			guard let data = try? await MediaStore.shared.publicData(url) else { return nil }
			return await Self.decode(data: data, maxPixel: maxPixel)
		}
		inflight[key] = task
		let image = await task.value
		inflight[key] = nil
		if let image { store(image, key: key) }
		return image
	}

	func mediaImage(_ message: Message, api: LineAPI, maxPixel: CGFloat) async -> NSImage? {
		let image = await image(key: "media:\(message.id)", maxPixel: maxPixel) {
			try await MediaStore.shared.file(for: message, api: api)
		}
		if let image, image.size.height > 0 {
			aspects[message.id] = image.size.width / image.size.height
		}
		return image
	}

	/// First frame of a downloaded video.
	func videoThumbnail(_ message: Message, file: URL) async -> NSImage? {
		let key = "video:\(message.id)"
		if let hit = cached(key) { return hit }
		let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
		generator.appliesPreferredTrackTransform = true
		generator.maximumSize = CGSize(width: 640, height: 640)
		guard let (cg, _) = try? await generator.image(at: .zero) else { return nil }
		let image = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
		store(image, key: key)
		if cg.height > 0 { aspects[message.id] = CGFloat(cg.width) / CGFloat(cg.height) }
		return image
	}

	private func store(_ image: NSImage, key: String) {
		let cost = Int(image.size.width * image.size.height * 4)
		memory.setObject(image, forKey: key as NSString, cost: cost)
	}

	private nonisolated static func decode(file: URL, maxPixel: CGFloat) async -> NSImage? {
		guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
		return thumbnail(source, maxPixel: maxPixel)
	}

	private nonisolated static func decode(data: Data, maxPixel: CGFloat) async -> NSImage? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
		return thumbnail(source, maxPixel: maxPixel)
	}

	private nonisolated static func thumbnail(_ source: CGImageSource, maxPixel: CGFloat) -> NSImage? {
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceThumbnailMaxPixelSize: maxPixel,
			kCGImageSourceShouldCacheImmediately: true,
		]
		guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
		return NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
	}
}
