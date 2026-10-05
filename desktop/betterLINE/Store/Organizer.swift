import Foundation

/// The owner's own arrangement of chats, kept on this Mac: named groups shown as
/// sidebar sections, and chats hidden everywhere (list, search, Dock badge,
/// notifications) until unhidden in Settings.
@MainActor
@Observable
final class Organizer {
	struct Group: Codable, Identifiable, Hashable {
		var id: UUID
		var name: String
	}

	private(set) var groups: [Group] = []
	/// chatId → group id.
	private(set) var membership: [String: UUID] = [:]
	/// chatId → chat name at the time it was hidden, for the Settings list.
	private(set) var hidden: [String: String] = [:]
	private(set) var collapsed: Set<UUID> = []

	private let defaults: UserDefaults
	private static let key = "organizer"

	private struct Stored: Codable {
		var groups: [Group]
		var membership: [String: UUID]
		var hidden: [String: String]
		var collapsed: Set<UUID>
	}

	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
			groups = stored.groups
			membership = stored.membership.filter { _, id in stored.groups.contains { $0.id == id } }
			hidden = stored.hidden
			collapsed = stored.collapsed
		}
	}

	func group(of chatId: String) -> Group? {
		membership[chatId].flatMap { id in groups.first { $0.id == id } }
	}

	func isHidden(_ chatId: String) -> Bool {
		hidden[chatId] != nil
	}

	// MARK: Groups

	@discardableResult
	func addGroup(named name: String) -> Group? {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		let group = Group(id: UUID(), name: trimmed)
		groups.append(group)
		save()
		return group
	}

	func rename(_ id: UUID, to name: String) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, let i = groups.firstIndex(where: { $0.id == id }) else { return }
		groups[i].name = trimmed
		save()
	}

	/// Deletes the group; its chats go back to the ungrouped list.
	func delete(_ id: UUID) {
		groups.removeAll { $0.id == id }
		membership = membership.filter { $0.value != id }
		collapsed.remove(id)
		save()
	}

	func move(_ id: UUID, by offset: Int) {
		guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
		let j = min(max(i + offset, 0), groups.count - 1)
		guard i != j else { return }
		groups.swapAt(i, j)
		save()
	}

	func moveGroups(from source: IndexSet, to destination: Int) {
		groups.move(fromOffsets: source, toOffset: destination)
		save()
	}

	/// Puts a chat in a group, or takes it out with `nil`.
	func assign(_ chatId: String, to groupId: UUID?) {
		if let groupId, groups.contains(where: { $0.id == groupId }) {
			membership[chatId] = groupId
		} else {
			membership[chatId] = nil
		}
		save()
	}

	func setCollapsed(_ id: UUID, _ isCollapsed: Bool) {
		if isCollapsed { collapsed.insert(id) } else { collapsed.remove(id) }
		save()
	}

	// MARK: Hidden chats

	func hide(_ chatId: String, name: String) {
		hidden[chatId] = name
		save()
	}

	func unhide(_ chatId: String) {
		hidden[chatId] = nil
		save()
	}

	private func save() {
		let stored = Stored(groups: groups, membership: membership, hidden: hidden, collapsed: collapsed)
		if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.key) }
	}
}
