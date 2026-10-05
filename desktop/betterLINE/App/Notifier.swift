import AppKit
import UserNotifications

/// Banners for new messages, with Reply and Mark as Read actions.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
	var onOpen: ((String) -> Void)?
	var onReply: ((String, String) -> Void)?
	var onMarkRead: ((String) -> Void)?

	private let center = UNUserNotificationCenter.current()
	private static let category = "message"

	func setUp() {
		center.delegate = self
		let reply = UNTextInputNotificationAction(
			identifier: "reply",
			title: "回覆",
			options: [],
			textInputButtonTitle: "傳送",
			textInputPlaceholder: "訊息",
		)
		let read = UNNotificationAction(identifier: "markRead", title: "標示為已讀")
		center.setNotificationCategories([
			UNNotificationCategory(identifier: Self.category, actions: [reply, read], intentIdentifiers: []),
		])
	}

	func requestAuthorization() {
		Task {
			_ = try? await center.requestAuthorization(options: [.alert, .sound])
		}
	}

	func post(chat: Chat, message: Message, preview: Bool) {
		let content = UNMutableNotificationContent()
		content.title = chat.name
		if chat.type != .user { content.subtitle = message.fromName }
		content.body = preview ? message.preview : "新訊息"
		content.sound = .default
		content.threadIdentifier = chat.chatId
		content.categoryIdentifier = Self.category
		content.userInfo = ["chat_id": chat.chatId]
		center.add(UNNotificationRequest(identifier: message.id, content: content, trigger: nil))
	}

	func remove(messageId: String) {
		center.removeDeliveredNotifications(withIdentifiers: [messageId])
	}

	func clear(chatId: String) {
		Task {
			let delivered = await center.deliveredNotifications()
			let ids = delivered.filter { $0.request.content.threadIdentifier == chatId }.map(\.request.identifier)
			if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
		}
	}

	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
	) async {
		guard let chatId = response.notification.request.content.userInfo["chat_id"] as? String else { return }
		let action = response.actionIdentifier
		let text = (response as? UNTextInputNotificationResponse)?.userText
		await MainActor.run {
			switch action {
			case "reply": if let text { onReply?(chatId, text) }
			case "markRead": onMarkRead?(chatId)
			default: onOpen?(chatId)
			}
		}
	}

	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
	) async -> UNNotificationPresentationOptions {
		[.banner, .sound, .list]
	}
}
