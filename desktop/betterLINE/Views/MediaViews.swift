import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Fits media into a bubble: at most 260×300 points, keeping the aspect ratio.
private func bubbleSize(aspect: CGFloat, maxWidth: CGFloat = 260, maxHeight: CGFloat = 300) -> CGSize {
	let a = min(max(aspect, 0.3), 3.5)
	var width = maxWidth
	var height = width / a
	if height > maxHeight {
		height = maxHeight
		width = height * a
	}
	return CGSize(width: max(width, 90), height: max(height, 70))
}

struct ImageContent: View {
	let message: Message
	let preview: (URL) -> Void

	@Environment(AppModel.self) private var app
	@State private var image: NSImage?
	@State private var failed = false

	var body: some View {
		let aspect = ImagePipeline.shared.aspects[message.id] ?? image.map { $0.size.width / max($0.size.height, 1) } ?? 4 / 3
		let size = bubbleSize(aspect: aspect)
		ZStack {
			if let image {
				Image(nsImage: image).resizable().scaledToFill()
			} else {
				Rectangle().fill(Color.bubbleTheirs)
				if failed {
					VStack(spacing: 4) {
						Image(systemName: "photo.badge.exclamationmark").font(.title2)
						Text("按一下重試").font(.caption)
					}
					.foregroundStyle(.secondary)
				} else {
					ProgressView().controlSize(.small)
				}
			}
		}
		.frame(width: size.width, height: size.height)
		.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator))
		.pressable(failed ? "重新載入照片" : "查看照片") {
			if failed {
				failed = false
				Task { await load() }
			} else {
				open()
			}
		}
		// A sent photo first shows the local file, then the server's copy with the
		// same id; reload when the source changes, not only the id.
		.task(id: "\(message.id)|\(message.localFile?.path ?? "")") { await load() }
	}

	private func load() async {
		if let file = message.localFile {
			image = await ImagePipeline.shared.image(key: "file:\(file.path)", maxPixel: 640) { file }
		} else if let api = app.api {
			image = await ImagePipeline.shared.mediaImage(message, api: api, maxPixel: 640)
		}
		failed = image == nil
	}

	private func open() {
		guard let api = app.api else { return }
		Task {
			if let url = try? await MediaStore.shared.file(for: message, api: api) { preview(url) }
		}
	}
}

struct VideoContent: View {
	let message: Message
	let preview: (URL) -> Void

	@Environment(AppModel.self) private var app
	@State private var thumbnail: NSImage?
	@State private var downloading = false
	@State private var failed = false

	var body: some View {
		let aspect = ImagePipeline.shared.aspects[message.id] ?? 16 / 9
		let size = bubbleSize(aspect: aspect, maxHeight: 260)
		ZStack {
			if let thumbnail {
				Image(nsImage: thumbnail).resizable().scaledToFill()
			} else {
				Rectangle().fill(Color.black.opacity(0.75))
			}
			if downloading {
				ProgressView().controlSize(.regular).tint(.white)
			} else {
				Image(systemName: failed ? "exclamationmark.triangle.fill" : "play.circle.fill")
					.font(.system(size: 42))
					.foregroundStyle(.white.opacity(0.92))
					.shadow(radius: 4)
			}
			if let ms = message.media?.durationMs {
				Text(Format.duration(ms: ms))
					.font(.caption.monospacedDigit())
					.foregroundStyle(.white)
					.padding(.horizontal, 6)
					.padding(.vertical, 2)
					.background(.black.opacity(0.5), in: Capsule())
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
					.padding(8)
			}
		}
		.frame(width: size.width, height: size.height)
		.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
		.pressable("播放影片") { Task { await play() } }
		.task(id: message.id) {
			if let file = message.localFile ?? MediaStore.shared.cachedFile(for: message.id) {
				thumbnail = await ImagePipeline.shared.videoThumbnail(message, file: file)
			}
		}
		.help("播放影片")
	}

	private func play() async {
		guard let api = app.api, !downloading else { return }
		downloading = true
		defer { downloading = false }
		do {
			let file = try await MediaStore.shared.file(for: message, api: api)
			failed = false
			preview(file)
			if thumbnail == nil { thumbnail = await ImagePipeline.shared.videoThumbnail(message, file: file) }
		} catch {
			failed = true
		}
	}
}

/// Voice messages play inline, one at a time.
@MainActor
@Observable
final class AudioPlayback {
	static let shared = AudioPlayback()

	private(set) var playingId: String?
	private(set) var loadingId: String?
	private(set) var progress: Double = 0

	@ObservationIgnored private var player: AVPlayer?
	@ObservationIgnored private var timeObserver: Any?
	@ObservationIgnored private var endObserver: NSObjectProtocol?

	func toggle(_ message: Message, api: LineAPI) {
		if playingId == message.id || loadingId == message.id {
			stop()
			return
		}
		stop()
		loadingId = message.id
		Task {
			let file = try? await MediaStore.shared.file(for: message, api: api)
			guard loadingId == message.id else { return }
			loadingId = nil
			guard let file else { return }
			start(file, id: message.id)
		}
	}

	private func start(_ file: URL, id: String) {
		let item = AVPlayerItem(url: file)
		let player = AVPlayer(playerItem: item)
		self.player = player
		playingId = id
		progress = 0
		timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
			MainActor.assumeIsolated {
				guard let self, let duration = self.player?.currentItem?.duration.seconds, duration > 0 else { return }
				self.progress = min(1, time.seconds / duration)
			}
		}
		endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated { self?.stop() }
		}
		player.play()
	}

	func stop() {
		player?.pause()
		if let timeObserver { player?.removeTimeObserver(timeObserver) }
		if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
		timeObserver = nil
		endObserver = nil
		player = nil
		playingId = nil
		loadingId = nil
		progress = 0
	}
}

struct AudioContent: View {
	let message: Message

	@Environment(AppModel.self) private var app
	private var playback: AudioPlayback { .shared }

	var body: some View {
		let playing = playback.playingId == message.id
		HStack(spacing: 10) {
			Button {
				if let api = app.api { playback.toggle(message, api: api) }
			} label: {
				ZStack {
					if playback.loadingId == message.id {
						ProgressView().controlSize(.small)
					} else {
						Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
							.font(.system(size: 28))
					}
				}
				.frame(width: 30, height: 30)
			}
			.buttonStyle(.plain)
			.disabled(message.isLocal)
			ZStack(alignment: .leading) {
				Capsule().fill(.tertiary)
				Capsule().fill(.secondary)
					.frame(width: 120 * (playing ? playback.progress : 0))
			}
			.frame(width: 120, height: 4)
			Text(message.media?.durationMs.map { Format.duration(ms: $0) } ?? "語音")
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
		}
	}
}

struct FileContent: View {
	let message: Message
	let preview: (URL) -> Void

	@Environment(AppModel.self) private var app
	@State private var downloading = false
	@State private var failed = false

	var body: some View {
		HStack(spacing: 10) {
			Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (name as NSString).pathExtension) ?? .data))
				.resizable()
				.frame(width: 34, height: 34)
			VStack(alignment: .leading, spacing: 2) {
				Text(name).lineLimit(2).font(.callout)
				Text(detail).font(.caption).foregroundStyle(failed ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
			}
			if downloading { ProgressView().controlSize(.small) }
		}
		.frame(maxWidth: 260, alignment: .leading)
		.pressable("打開檔案 \(name)") { Task { await open() } }
		.help("快速查看")
	}

	private var name: String {
		message.media?.fileName ?? "檔案"
	}

	private var detail: String {
		if failed { return "下載失敗，按一下重試" }
		return message.media?.size.map { Format.bytes($0) } ?? "檔案"
	}

	private func open() async {
		guard let api = app.api, !downloading else { return }
		downloading = true
		defer { downloading = false }
		do {
			preview(try await MediaStore.shared.file(for: message, api: api))
			failed = false
		} catch {
			failed = true
		}
	}
}

struct LocationContent: View {
	let location: Location?
	let fallback: String

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "mappin.circle.fill")
				.font(.system(size: 30))
				.foregroundStyle(.red)
			VStack(alignment: .leading, spacing: 2) {
				Text(location?.title ?? "位置資訊").font(.callout.weight(.medium)).lineLimit(2)
				if let address = location?.address {
					Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
				}
			}
		}
		.frame(maxWidth: 260, alignment: .leading)
		.pressable("在地圖中打開") { openMaps() }
		.help("在「地圖」中打開")
	}

	private func openMaps() {
		guard let lat = location?.latitude, let lon = location?.longitude else { return }
		var components = URLComponents(string: "https://maps.apple.com/")!
		components.queryItems = [
			URLQueryItem(name: "ll", value: "\(lat),\(lon)"),
			URLQueryItem(name: "q", value: location?.title ?? fallback),
		]
		if let url = components.url { NSWorkspace.shared.open(url) }
	}
}
