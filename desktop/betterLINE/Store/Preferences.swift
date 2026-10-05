import Foundation
import Security

/// User settings in UserDefaults; the client key lives in the login keychain.
@MainActor
@Observable
final class Preferences {
	static let defaultServer = "http://linebox.your-tailnet.ts.net:8791"

	var serverURL: String { didSet { defaults.set(serverURL, forKey: "serverURL") } }
	/// Return sends, Shift-Return inserts a newline. Off: the other way round.
	var sendOnEnter: Bool { didSet { defaults.set(sendOnEnter, forKey: "sendOnEnter") } }
	/// Opening a chat sends LINE's read receipt, as the phone app does.
	var autoMarkRead: Bool { didSet { defaults.set(autoMarkRead, forKey: "autoMarkRead") } }
	var notifications: Bool { didSet { defaults.set(notifications, forKey: "notifications") } }
	var notificationPreview: Bool { didSet { defaults.set(notificationPreview, forKey: "notificationPreview") } }
	var lastChatId: String? { didSet { defaults.set(lastChatId, forKey: "lastChatId") } }

	private let defaults: UserDefaults

	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		defaults.register(defaults: [
			"serverURL": Self.defaultServer,
			"sendOnEnter": true,
			"autoMarkRead": true,
			"notifications": true,
			"notificationPreview": true,
		])
		serverURL = defaults.string(forKey: "serverURL") ?? Self.defaultServer
		sendOnEnter = defaults.bool(forKey: "sendOnEnter")
		autoMarkRead = defaults.bool(forKey: "autoMarkRead")
		notifications = defaults.bool(forKey: "notifications")
		notificationPreview = defaults.bool(forKey: "notificationPreview")
		lastChatId = defaults.string(forKey: "lastChatId")
	}

	/// The saved server and key, if both exist.
	func serverConfig() -> ServerConfig? {
		#if DEBUG
		// Development runs: `BETTERLINE_KEY=… betterLINE.app/Contents/MacOS/betterLINE`.
		let env = ProcessInfo.processInfo.environment
		if let key = env["BETTERLINE_KEY"], !key.isEmpty, let url = URL(string: env["BETTERLINE_SERVER"] ?? serverURL) {
			return ServerConfig(baseURL: url, key: key)
		}
		#endif
		guard let url = Self.parseServer(serverURL), let key = Keychain.read(), !key.isEmpty else { return nil }
		return ServerConfig(baseURL: url, key: key)
	}

	static func parseServer(_ text: String) -> URL? {
		var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmed.contains("://") { trimmed = "http://" + trimmed }
		while trimmed.hasSuffix("/") { trimmed.removeLast() }
		guard let url = URL(string: trimmed), url.host() != nil, ["http", "https"].contains(url.scheme ?? "") else { return nil }
		return url
	}
}

/// The client key as a generic password in the login keychain.
enum Keychain {
	/// Per bundle id, so development builds never read the installed app's key.
	private static let service = Bundle.main.bundleIdentifier ?? "com.example.betterline"
	private static let account = "client-key"

	static func read() -> String? {
		let query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: service,
			kSecAttrAccount: account,
			kSecReturnData: true,
			kSecMatchLimit: kSecMatchLimitOne,
		]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func write(_ key: String) throws {
		delete()
		let item: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: service,
			kSecAttrAccount: account,
			kSecAttrLabel: "betterLINE client key",
			kSecValueData: Data(key.utf8),
		]
		let status = SecItemAdd(item as CFDictionary, nil)
		guard status == errSecSuccess else {
			throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
				NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "無法寫入鑰匙圈（\(status)）",
			])
		}
	}

	static func delete() {
		let query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: service,
			kSecAttrAccount: account,
		]
		SecItemDelete(query as CFDictionary)
	}
}
