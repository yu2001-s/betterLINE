import Foundation

/// The server has no sticker catalogue, so the picker offers stickers seen in
/// chats: ones you sent first, then ones you received, most recent first.
@MainActor
@Observable
final class StickerHistory {
	private(set) var stickers: [Sticker] = []
	private let defaults: UserDefaults
	private let limit = 80
	private static let key = "stickerHistory"

	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([Sticker].self, from: data) {
			stickers = saved
		}
	}

	/// Remembers stickers from loaded messages without reordering existing ones.
	func noteSeen(_ messages: [Message]) {
		var changed = false
		for m in messages.reversed() {
			guard let s = m.sticker, !stickers.contains(where: { $0.stickerId == s.stickerId }) else { continue }
			stickers.append(s)
			changed = true
		}
		if changed { trimAndSave() }
	}

	/// Moves a sticker to the front, as when you send it.
	func noteUsed(_ sticker: Sticker) {
		stickers.removeAll { $0.stickerId == sticker.stickerId }
		stickers.insert(sticker, at: 0)
		trimAndSave()
	}

	private func trimAndSave() {
		if stickers.count > limit { stickers.removeLast(stickers.count - limit) }
		if let data = try? JSONEncoder().encode(stickers) { defaults.set(data, forKey: Self.key) }
	}
}
