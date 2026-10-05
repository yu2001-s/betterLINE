import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a local file into what LINE accepts: the media kind, a duration for
/// video and audio, and JPEG for image formats other LINE clients cannot show.
enum Upload {
	static let maxBytes: Int64 = 100 << 20

	struct Prepared: Sendable {
		var file: URL
		var kind: MessageKind
		var name: String
		var durationMs: Int?
	}

	static func kind(of url: URL) -> MessageKind {
		guard let type = UTType(filenameExtension: url.pathExtension) else { return .file }
		if type.conforms(to: .image), !type.conforms(to: .svg), type != .pdf { return .image }
		if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
		if type.conforms(to: .audio) { return .audio }
		return .file
	}

	static func size(of url: URL) -> Int64 {
		Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
	}

	static func prepare(_ url: URL, kind: MessageKind) async throws -> Prepared {
		switch kind {
		case .image:
			let type = UTType(filenameExtension: url.pathExtension)
			if let type, [.jpeg, .png, .gif].contains(type) {
				return Prepared(file: url, kind: .image, name: url.lastPathComponent)
			}
			let jpeg = try convertToJPEG(url)
			return Prepared(file: jpeg, kind: .image, name: jpeg.lastPathComponent)
		case .video, .audio:
			let duration = try? await AVURLAsset(url: url).load(.duration)
			let ms = duration.map { Int($0.seconds * 1000) }.flatMap { $0 > 0 ? $0 : nil }
			return Prepared(file: url, kind: kind, name: url.lastPathComponent, durationMs: ms)
		default:
			return Prepared(file: url, kind: .file, name: url.lastPathComponent)
		}
	}

	private static func convertToJPEG(_ url: URL) throws -> URL {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
			let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
			throw CocoaError(.fileReadCorruptFile)
		}
		let out = scratchDirectory().appending(path: url.deletingPathExtension().lastPathComponent + ".jpg")
		guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
			throw CocoaError(.fileWriteUnknown)
		}
		let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
		var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
		if let orientation = props[kCGImagePropertyOrientation] { options[kCGImagePropertyOrientation] = orientation }
		CGImageDestinationAddImage(dest, image, options as CFDictionary)
		guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
		return out
	}

	/// Saves pasted image data (screenshots, copied images) as a PNG to send.
	static func writePasted(_ image: NSImage) -> URL? {
		guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
			let png = rep.representation(using: .png, properties: [:]) else { return nil }
		let stamp = DateFormatter()
		stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
		let url = scratchDirectory().appending(path: "貼上的圖片 \(stamp.string(from: Date())).png")
		do {
			try png.write(to: url)
			return url
		} catch {
			return nil
		}
	}

	/// Saves dropped or pasted image data, keeping its format when it has one.
	static func writeImageData(_ data: Data, type: UTType?) -> URL? {
		guard let type, [UTType.png, .jpeg, .gif].contains(type), let ext = type.preferredFilenameExtension else {
			return NSImage(data: data).flatMap(writePasted)
		}
		let stamp = DateFormatter()
		stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
		let url = scratchDirectory().appending(path: "圖片 \(stamp.string(from: Date())).\(ext)")
		return (try? data.write(to: url)).map { url }
	}

	private static func scratchDirectory() -> URL {
		let dir = FileManager.default.temporaryDirectory.appending(path: "betterLINE-\(UUID().uuidString.prefix(8))")
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		return dir
	}
}

/// What on a pasteboard should become an attachment instead of text: copied
/// files, or a copied image (a screenshot, "Copy Image" in a browser).
enum Clipboard {
	static let imageTypes: [NSPasteboard.PasteboardType] = [
		.tiff, .png,
		NSPasteboard.PasteboardType(UTType.jpeg.identifier),
		NSPasteboard.PasteboardType(UTType.heic.identifier),
		NSPasteboard.PasteboardType(UTType.gif.identifier),
	]

	static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
		pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
	}

	/// An image counts only when it is what was copied: there is no text, or the
	/// image comes before the text in the source's own order of preference.
	static func hasImage(_ pasteboard: NSPasteboard) -> Bool {
		let types = pasteboard.types ?? []
		guard let image = types.firstIndex(where: imageTypes.contains) else { return false }
		guard let text = types.firstIndex(of: .string) else { return true }
		return image < text
	}

	static func hasAttachment(_ pasteboard: NSPasteboard) -> Bool {
		!fileURLs(pasteboard).isEmpty || hasImage(pasteboard)
	}

	/// The attachments to add, or nil when this is ordinary text.
	static func attachments(from pasteboard: NSPasteboard) -> [URL]? {
		let files = fileURLs(pasteboard)
		if !files.isEmpty { return files }
		guard hasImage(pasteboard), let image = NSImage(pasteboard: pasteboard), let file = Upload.writePasted(image) else { return nil }
		return [file]
	}
}
