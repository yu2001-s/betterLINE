import Foundation

/// Parses `GET /api/events`. The server writes one `data:` line per event and
/// a `: ping` comment every 25 s; either counts as a sign of life.
enum EventStream {
	enum Item: Sendable {
		case event(LineEvent)
		case heartbeat
	}

	static func items(from api: LineAPI) -> AsyncThrowingStream<Item, Error> {
		AsyncThrowingStream { continuation in
			let task = Task {
				do {
					let bytes = try await api.eventBytes()
					for try await line in bytes.lines {
						if let item = parse(line) { continuation.yield(item) }
					}
					continuation.finish()
				} catch {
					continuation.finish(throwing: error)
				}
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	static func parse(_ line: String) -> Item? {
		if line.hasPrefix(":") { return .heartbeat }
		guard line.hasPrefix("data:") else { return nil }
		let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
		guard let event = try? JSONDecoder.api.decode(LineEvent.self, from: Data(payload.utf8)) else {
			return .heartbeat
		}
		return .event(event)
	}
}
