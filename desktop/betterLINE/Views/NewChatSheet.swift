import SwiftUI

/// The address book: every friend and group, including ones with no messages
/// in LINE's 14-day window. Picking one opens its chat.
struct NewChatSheet: View {
	@Environment(AppModel.self) private var app
	@Environment(\.dismiss) private var dismiss
	@State private var query = ""
	@FocusState private var focused: Bool

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
				TextField("搜尋好友或群組", text: $query)
					.textFieldStyle(.plain)
					.focused($focused)
					.onSubmit { if let first = matches.first { open(first) } }
			}
			.padding(10)
			.background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
			.padding(12)

			Divider()

			if app.contacts.isEmpty {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.task { await app.refreshContacts() }
			} else if matches.isEmpty {
				Text("找不到「\(query)」")
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				List {
					let friends = matches.filter { $0.type == .user }
					let groups = matches.filter { $0.type != .user }
					if !friends.isEmpty {
						Section("好友（\(friends.count)）") {
							ForEach(friends) { contact in row(contact) }
						}
					}
					if !groups.isEmpty {
						Section("群組（\(groups.count)）") {
							ForEach(groups) { contact in row(contact) }
						}
					}
				}
				.listStyle(.inset)
			}
		}
		.frame(width: 400, height: 520)
		.onAppear { focused = true }
		.onExitCommand { dismiss() }
	}

	private var matches: [Contact] {
		app.contacts.filter { !app.organizer.isHidden($0.id) && TextFold.matches($0.name, query: query) }
	}

	private func row(_ contact: Contact) -> some View {
		Button {
			open(contact)
		} label: {
			ContactRow(contact: contact)
				.frame(maxWidth: .infinity, alignment: .leading)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}

	private func open(_ contact: Contact) {
		app.selectedChatId = contact.id
		dismiss()
	}
}
