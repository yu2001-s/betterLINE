import SwiftUI

/// Organizing actions for one chat, shared by the sidebar's context menu and
/// the conversation's "more" menu.
struct ChatActions: View {
	let chatId: String
	var unread = 0

	@Environment(AppModel.self) private var app

	var body: some View {
		if unread > 0 {
			Button("標示為已讀") { app.markRead(chatId, force: true) }
		}
		Menu("移到群組") {
			let current = app.organizer.group(of: chatId)?.id
			ForEach(app.organizer.groups) { group in
				Button {
					app.move(chatId, toGroup: group.id)
				} label: {
					if current == group.id {
						Label(group.name, systemImage: "checkmark")
					} else {
						Text(group.name)
					}
				}
			}
			if !app.organizer.groups.isEmpty { Divider() }
			Button("新增群組…") { app.promptNewGroup(assigning: chatId) }
			if current != nil {
				Button("移出群組") { app.move(chatId, toGroup: nil) }
			}
		}
		Divider()
		Button("隱藏聊天室") { app.hide(chatId) }
	}
}

extension View {
	/// The group name sheet, driven by `AppModel.groupPrompt`.
	func groupPrompt(_ app: AppModel) -> some View {
		sheet(isPresented: Binding(get: { app.groupPrompt != nil }, set: { if !$0 { app.groupPrompt = nil } })) {
			GroupNameSheet()
		}
	}
}

private struct GroupNameSheet: View {
	@Environment(AppModel.self) private var app
	@FocusState private var focused: Bool

	var body: some View {
		@Bindable var app = app
		VStack(alignment: .leading, spacing: 12) {
			Text(isRename ? "重新命名群組" : "新增群組").font(.headline)
			TextField("名稱", text: $app.groupNameDraft, prompt: Text("例如：工作、家人"))
				.textFieldStyle(.roundedBorder)
				.focused($focused)
				.onSubmit { if canSave { app.commitGroupPrompt() } }
			Text("群組只存在這台 Mac 上，用來整理側邊欄。")
				.font(.callout)
				.foregroundStyle(.secondary)
			HStack {
				Spacer()
				Button("取消", role: .cancel) { app.groupPrompt = nil }
					.keyboardShortcut(.cancelAction)
				Button(isRename ? "儲存" : "建立") { app.commitGroupPrompt() }
					.keyboardShortcut(.defaultAction)
					.disabled(!canSave)
			}
		}
		.padding(20)
		.frame(width: 340)
		.onAppear { focused = true }
	}

	private var isRename: Bool {
		if case .rename = app.groupPrompt { return true }
		return false
	}

	private var canSave: Bool {
		!app.groupNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
}
