import AppKit
import Foundation
import Testing
@testable import betterLINE

struct DecodingTests {
	@Test func chatListWithStickerAndReactions() throws {
		let json = """
		{"chats":[{"chat_id":"c11111111111111111111111111111111","name":"群","type":"group","unread":3,"muted":true,
		"last_message":{"id":"100000000000000002","chat_id":"c11111111111111111111111111111111","from_id":"u22222222222222222222222222222222",
		"from_name":"小明","mine":false,"time_ms":1790517131342,"delivered":"1790517131342","kind":"sticker","text":"[sticker]",
		"reply_to":"100000000000000001","sticker":{"package_id":"7117","sticker_id":"12955359","version":"3","animated":false,
		"url":"https://stickershop.line-scdn.net/stickershop/v1/sticker/12955359/android/sticker.png"},
		"reactions":[{"type":"LOVE","from_id":"u33333333333333333333333333333333"}]}}]}
		"""
		let list = try JSONDecoder.api.decode(ChatList.self, from: Data(json.utf8))
		let chat = try #require(list.chats.first)
		#expect(chat.type == .group)
		#expect(chat.isMuted)
		#expect(chat.unread == 3)
		let last = try #require(chat.lastMessage)
		#expect(last.kind == .sticker)
		#expect(last.sticker?.stickerId == "12955359")
		#expect(last.replyTo == "100000000000000001")
		#expect(last.reactions?.first?.type == "LOVE")
		#expect(last.preview == "[貼圖]")
		#expect(last.local == nil)
	}

	@Test func unknownKindAndStatusFallBack() throws {
		let json = """
		{"id":"1","chat_id":"u0","from_id":"u1","from_name":"a","mine":true,"time_ms":1,"delivered":"1","kind":"hologram","text":"x","media":{}}
		"""
		let m = try JSONDecoder.api.decode(Message.self, from: Data(json.utf8))
		#expect(m.kind == .other)
		#expect(m.media == MediaInfo())
		let me = try JSONDecoder.api.decode(Me.self, from: Data(#"{"id":"u1","name":"me","status":"sleeping"}"#.utf8))
		#expect(me.status == .unknown)
	}

	@Test func searchHitCarriesChatName() throws {
		let json = """
		{"results":[{"id":"9","chat_id":"u2","from_id":"u2","from_name":"b","mine":false,"time_ms":5,"delivered":"5","kind":"text","text":"开会","chat_name":"Bob"}]}
		"""
		let results = try JSONDecoder.api.decode(SearchResults.self, from: Data(json.utf8))
		#expect(results.results.first?.chatName == "Bob")
		#expect(results.results.first?.message.text == "开会")
	}

	@Test func archiveStatus() throws {
		let json = """
		{"rules":{"auto":true,"maxGroupMembers":10,"skipOfficialAccounts":true},"chats":[{"chat_id":"u25","name":"x","mode":"auto",
		"added_at":1791200571496,"last_synced_at":null,"last_error":null,"messages":27,"oldest":1790059086912,"newest":1790920158572}]}
		"""
		let status = try JSONDecoder.api.decode(ArchiveStatus.self, from: Data(json.utf8))
		#expect(status.rules.maxGroupMembers == 10)
		#expect(status.chats.first?.lastSyncedAt == nil)
		#expect(status.chats.first?.messages == 27)
	}
}

struct EventTests {
	@Test func parsesEventLines() {
		guard case let .event(.read(chat, reader, message)) = EventStream.parse(#"data: {"type":"read","chat_id":"c1","reader_id":"u2","message_id":"3"}"#) else {
			Issue.record("expected a read event")
			return
		}
		#expect(chat == "c1" && reader == "u2" && message == "3")

		guard case .event(.chatRead(chatId: "c1", messageId: "9")) = EventStream.parse(#"data: {"type":"chat_read","chat_id":"c1","message_id":"9"}"#) else {
			Issue.record("expected chat_read")
			return
		}
		guard case .event(.status(.loggedOut)) = EventStream.parse(#"data: {"type":"status","status":"logged_out"}"#) else {
			Issue.record("expected status")
			return
		}
		guard case .heartbeat = EventStream.parse(": ping") else {
			Issue.record("expected heartbeat")
			return
		}
		#expect(EventStream.parse("") == nil)
	}

	@Test func reactionWithoutMessageId() {
		guard case .event(.reaction(chatId: "c1", messageId: nil)) = EventStream.parse(#"data: {"type":"reaction","chat_id":"c1"}"#) else {
			Issue.record("expected reaction")
			return
		}
	}
}

@MainActor
struct FormattingTests {
	@Test func foldsTraditionalAndSimplified() {
		#expect(TextFold.matches("炸雞", query: "炸鸡"))
		#expect(TextFold.matches("开会通知", query: "開會"))
		#expect(TextFold.matches("Ｌｉｎｅ Desk", query: "line"))
		#expect(!TextFold.matches("Alice", query: "bob"))
	}

	@Test func contentDispositionFileName() {
		#expect(LineAPI.fileName(fromDisposition: "inline; filename*=UTF-8''S__22749200.jpg") == "S__22749200.jpg")
		#expect(LineAPI.fileName(fromDisposition: "inline; filename*=UTF-8''%E5%A0%B1%E5%91%8A.pdf") == "報告.pdf")
		#expect(LineAPI.fileName(fromDisposition: nil) == nil)
	}

	@Test func serverAddresses() {
		#expect(Preferences.parseServer("linebox:8791")?.absoluteString == "http://linebox:8791")
		#expect(Preferences.parseServer(" http://linebox.your-tailnet.ts.net:8791/ ")?.absoluteString == "http://linebox.your-tailnet.ts.net:8791")
		#expect(Preferences.parseServer("ftp://x") == nil)
	}

	@Test func uploadKinds() {
		#expect(Upload.kind(of: URL(fileURLWithPath: "/a.HEIC")) == .image)
		#expect(Upload.kind(of: URL(fileURLWithPath: "/a.mp4")) == .video)
		#expect(Upload.kind(of: URL(fileURLWithPath: "/a.m4a")) == .audio)
		#expect(Upload.kind(of: URL(fileURLWithPath: "/a.pdf")) == .file)
		#expect(Upload.kind(of: URL(fileURLWithPath: "/a.zip")) == .file)
	}

	@Test func rowsGroupRunsAndTimeHeaders() {
		func msg(_ id: String, _ from: String, _ minutes: Int64, day: Int64 = 0) -> Message {
			let base: Int64 = 1_790_000_000_000
			return Message(id: id, chatId: "c", fromId: from, fromName: from, mine: false,
				timeMs: base + day * 86_400_000 + minutes * 60_000, delivered: "0", kind: .text, text: id)
		}
		// 1–2 a run; 3 another sender; 4 after a 2-minute pause, same run; 5 after 18 minutes
		// gets a time header; 6 is the next day.
		let rows = MessageRowModel.build([
			msg("1", "a", 0), msg("2", "a", 1), msg("3", "b", 2), msg("4", "b", 4), msg("5", "b", 22), msg("6", "b", 22, day: 1),
		])
		var runs: [String: String] = [:]
		var headers: [String] = []
		for row in rows {
			switch row.kind {
			case let .message(m, startsRun, endsRun): runs[m.id] = "\(startsRun ? "S" : "-")\(endsRun ? "E" : "-")"
			case .timeHeader: headers.append(row.id)
			case .unreadDivider: break
			}
		}
		#expect(runs == ["1": "S-", "2": "-E", "3": "S-", "4": "-E", "5": "SE", "6": "SE"])
		#expect(headers == ["time-1", "time-5", "time-6"])

		let withUnread = MessageRowModel.build([msg("1", "a", 0), msg("2", "a", 1), msg("3", "a", 2)], firstUnreadId: "2")
		#expect(withUnread.map(\.id) == ["time-1", "1", "unread", "2", "3"])
		if case let .message(_, _, endsRun) = withUnread[1].kind {
			#expect(endsRun, "the run ends before the unread divider")
		}
	}

	@Test func richTextIsUnwrapped() {
		var m = Message(id: "1", chatId: "c", fromId: "u", fromName: "u", mine: false, timeMs: 0, delivered: "0", kind: .rich, text: "[rich message: 帳戶通知]")
		#expect(m.preview == "帳戶通知")
		m.text = "[rich message]"
		#expect(m.displayText == "[rich message]")
		m.kind = .text
		m.text = ""
		#expect(m.preview == "[訊息]")
	}
}

/// Defaults kept in memory. A real suite leaves a plist in ~/Library/Preferences
/// on every run, even after removePersistentDomain.
private final class MemoryDefaults: UserDefaults {
	private var values: [String: Any] = [:]
	init() { super.init(suiteName: "betterLINE.tests")! }
	override func object(forKey key: String) -> Any? { values[key] }
	override func set(_ value: Any?, forKey key: String) { values[key] = value }
	override func removeObject(forKey key: String) { values[key] = nil }
}

@MainActor
struct OrganizerTests {
	private func fresh() -> Organizer {
		let defaults = MemoryDefaults()
		return Organizer(defaults: defaults)
	}

	@Test func groupsAndMembership() throws {
		let organizer = fresh()
		#expect(organizer.addGroup(named: "  ") == nil)
		let work = try #require(organizer.addGroup(named: " 工作 "))
		let family = try #require(organizer.addGroup(named: "家人"))
		#expect(work.name == "工作")
		organizer.assign("u1", to: work.id)
		organizer.assign("u2", to: family.id)
		#expect(organizer.group(of: "u1") == work)
		organizer.move(family.id, by: -1)
		#expect(organizer.groups.map(\.name) == ["家人", "工作"])
		organizer.delete(family.id)
		#expect(organizer.group(of: "u2") == nil, "deleting a group ungroups its chats")
		organizer.assign("u1", to: nil)
		#expect(organizer.group(of: "u1") == nil)
	}

	@Test func hiddenChatsPersist() throws {
		let defaults = MemoryDefaults()
		let organizer = Organizer(defaults: defaults)
		let group = try #require(organizer.addGroup(named: "朋友"))
		organizer.assign("c9", to: group.id)
		organizer.hide("u7", name: "某人")
		organizer.setCollapsed(group.id, true)

		let reloaded = Organizer(defaults: defaults)
		#expect(reloaded.isHidden("u7"))
		#expect(reloaded.hidden["u7"] == "某人")
		#expect(reloaded.group(of: "c9")?.name == "朋友")
		#expect(reloaded.collapsed.contains(group.id))
		reloaded.unhide("u7")
		#expect(!Organizer(defaults: defaults).isHidden("u7"))
	}
}

struct ContactDecodingTests {
	@Test func contactsAndSenderPictures() throws {
		let contacts = try JSONDecoder.api.decode(ContactList.self, from: Data(#"{"contacts":[{"id":"u1","name":"阿明","type":"user","picture":"https://profile.line-scdn.net/x/preview"},{"id":"c2","name":"家人","type":"group"}]}"#.utf8))
		#expect(contacts.contacts.count == 2)
		#expect(contacts.contacts[0].picture?.host() == "profile.line-scdn.net")
		#expect(contacts.contacts[1].type == .group)
		let m = try JSONDecoder.api.decode(Message.self, from: Data(#"{"id":"1","chat_id":"c2","from_id":"u3","from_name":"小華","from_picture":"https://profile.line-scdn.net/y/preview","mine":false,"time_ms":1,"delivered":"1","kind":"text","text":"hi"}"#.utf8))
		#expect(m.fromPicture?.path() == "/y/preview")
	}
}

@MainActor
struct ClipboardTests {
	private func board() -> NSPasteboard {
		let pasteboard = NSPasteboard(name: NSPasteboard.Name("betterLINE.tests.\(UUID().uuidString)"))
		pasteboard.clearContents()
		return pasteboard
	}

	private var tiff: Data {
		let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
			NSColor.systemBlue.setFill()
			rect.fill()
			return true
		}
		return image.tiffRepresentation!
	}

	@Test func imageOnlyBecomesAnAttachment() throws {
		let pasteboard = board()
		pasteboard.setData(tiff, forType: .tiff)
		#expect(Clipboard.hasAttachment(pasteboard))
		let files = try #require(Clipboard.attachments(from: pasteboard))
		#expect(files.count == 1)
		#expect(files[0].pathExtension == "png")
		#expect(NSImage(contentsOf: files[0]) != nil)
	}

	@Test func textStaysText() {
		let pasteboard = board()
		pasteboard.setString("你好", forType: .string)
		#expect(!Clipboard.hasAttachment(pasteboard))
		#expect(Clipboard.attachments(from: pasteboard) == nil)
	}

	@Test func textThatAlsoCarriesAnImageStaysText() {
		let pasteboard = board()
		pasteboard.declareTypes([.string, .tiff], owner: nil)
		pasteboard.setString("一段網頁文字", forType: .string)
		pasteboard.setData(tiff, forType: .tiff)
		#expect(!Clipboard.hasImage(pasteboard))
	}

	@Test func copiedImageWithItsAddressIsAnImage() {
		let pasteboard = board()
		pasteboard.declareTypes([.tiff, .string], owner: nil)
		pasteboard.setData(tiff, forType: .tiff)
		pasteboard.setString("https://example.com/a.png", forType: .string)
		#expect(Clipboard.hasImage(pasteboard))
	}

	@Test func pasteIsOfferedForAnImage() {
		let pasteboard = board()
		pasteboard.setData(tiff, forType: .tiff)
		let input = InputTextView()
		input.isRichText = false
		input.importsGraphics = false
		input.pasteboard = pasteboard
		let item = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		#expect(input.validateMenuItem(item))
	}

	@Test func copiedFilesWin() throws {
		let file = FileManager.default.temporaryDirectory.appending(path: "betterLINE-test-\(UUID().uuidString).txt")
		try Data("x".utf8).write(to: file)
		defer { try? FileManager.default.removeItem(at: file) }
		let pasteboard = board()
		pasteboard.writeObjects([file as NSURL])
		#expect(Clipboard.attachments(from: pasteboard)?.map(\.lastPathComponent) == [file.lastPathComponent])
	}
}

struct SwipeTrackerTests {
	@Test func leftSwipeShowsTimesAndSnapsBack() {
		var swipe = SwipeTracker()
		swipe.begin()
		let step1 = swipe.move(dx: -10, dy: 1, target: "m1")
		#expect(step1)
		#expect(swipe.timesOffset == 10)
		#expect(swipe.replyTarget == nil, "a left swipe never replies")
		let step2 = swipe.move(dx: -200, dy: 0, target: "m1")
		#expect(step2)
		#expect(swipe.timesOffset == SwipeTracker.timesWidth)
		#expect(swipe.isHorizontal)
		#expect(swipe.end() == nil)
		#expect(swipe.timesOffset == 0)
		#expect(swipe.mode == nil)
	}

	@Test func rightSwipeRepliesOnlyPastTheThreshold() {
		var short = SwipeTracker()
		short.begin()
		let step3 = short.move(dx: 20, dy: 0, target: "m1")
		#expect(step3)
		#expect(short.replyOffset > 0 && !short.replyArmed)
		#expect(short.end() == nil)

		var far = SwipeTracker()
		far.begin()
		let step4 = far.move(dx: 20, dy: 0, target: "m1")
		#expect(step4)
		let step5 = far.move(dx: 150, dy: 0, target: "m2")
		#expect(step5, "the target is fixed when the swipe starts")
		#expect(far.replyArmed)
		#expect(far.replyOffset < SwipeTracker.replyLimit)
		#expect(far.end() == "m1")
	}

	@Test func backingOffDisarmsTheReply() {
		var swipe = SwipeTracker()
		swipe.begin()
		_ = swipe.move(dx: 200, dy: 0, target: "m1")
		#expect(swipe.replyArmed)
		_ = swipe.move(dx: -180, dy: 0, target: "m1")
		#expect(!swipe.replyArmed)
		#expect(swipe.end() == nil)
	}

	@Test func verticalScrollsAreLeftAlone() {
		var swipe = SwipeTracker()
		swipe.begin()
		let step6 = swipe.move(dx: 0.2, dy: 0.1, target: "m1")
		#expect(!step6, "jitter does not decide the direction")
		#expect(swipe.mode == .undecided)
		let step7 = swipe.move(dx: 3, dy: -8, target: "m1")
		#expect(!step7)
		#expect(swipe.mode == .vertical)
		let step8 = swipe.move(dx: 40, dy: 0, target: "m1")
		#expect(!step8, "once vertical, the gesture stays a scroll")
		#expect(!swipe.isHorizontal)
	}

	@Test func rightSwipeOffAMessageScrolls() {
		var swipe = SwipeTracker()
		swipe.begin()
		let step9 = swipe.move(dx: 30, dy: 0, target: nil)
		#expect(!step9)
		#expect(swipe.mode == .vertical)
	}

	@Test func eventsOutsideAGestureAreIgnored() {
		var swipe = SwipeTracker()
		let step10 = swipe.move(dx: -30, dy: 0, target: nil)
		#expect(!step10)
		#expect(swipe.timesOffset == 0)
	}
}

@MainActor
struct ImagePipelineTests {
	/// The attachment chip asks for a 96 px thumbnail of a file before the sent
	/// bubble asks for 640 px of the same file; the bubble must not get the chip's.
	@Test func sizesOfTheSameFileAreCachedApart() async throws {
		let file = FileManager.default.temporaryDirectory.appending(path: "betterLINE-wide-\(UUID().uuidString).png")
		let image = NSImage(size: NSSize(width: 2000, height: 500), flipped: false) { rect in
			NSColor.systemTeal.setFill()
			rect.fill()
			return true
		}
		let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 500, bitsPerSample: 8, samplesPerPixel: 4,
			hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
		image.draw(in: NSRect(x: 0, y: 0, width: 2000, height: 500))
		NSGraphicsContext.restoreGraphicsState()
		try rep.representation(using: .png, properties: [:])!.write(to: file)
		defer { try? FileManager.default.removeItem(at: file) }

		let pipeline = ImagePipeline()
		let chip = try #require(await pipeline.image(key: "file:\(file.path)", maxPixel: 96) { file })
		let bubble = try #require(await pipeline.image(key: "file:\(file.path)", maxPixel: 640) { file })
		#expect(chip.size.width == 96)
		#expect(bubble.size.width == 640)
	}
}
