import SwiftUI

/// First run, or after the server rejects the saved key.
struct SetupView: View {
	var problem: String?

	@Environment(AppModel.self) private var app
	@State private var server = ""
	@State private var key = ""
	@State private var working = false
	@State private var error: String?

	private static let keyCommand = "ssh linebox 'grep ^LINE_CLIENT_KEY= ~/.config/line-mcp/env | cut -d= -f2-' | pbcopy"

	var body: some View {
		VStack(spacing: 18) {
			Image(nsImage: NSApp.applicationIconImage)
				.resizable()
				.frame(width: 72, height: 72)
			VStack(spacing: 6) {
				Text("連線到你的 LINE 伺服器").font(.title2.weight(.semibold))
				Text("betterLINE 透過 Tailscale 連線到你伺服器上的 line-mcp 服務。")
					.foregroundStyle(.secondary)
			}

			if let message = error ?? problem {
				InfoStrip(text: message, tone: .error, systemImage: "exclamationmark.triangle.fill")
			}

			Form {
				TextField("伺服器", text: $server, prompt: Text(Preferences.defaultServer))
				SecureField("用戶端金鑰", text: $key, prompt: Text("LINE_CLIENT_KEY"))
			}
			.formStyle(.grouped)
			.scrollDisabled(true)
			.frame(height: 130)

			VStack(alignment: .leading, spacing: 6) {
				Text("金鑰是伺服器 ~/.config/line-mcp/env 中的 LINE_CLIENT_KEY。在「終端機」執行下面的指令就能把它拷貝到剪貼簿：")
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				HStack {
					Text(Self.keyCommand)
						.font(.system(.caption, design: .monospaced))
						.textSelection(.enabled)
						.lineLimit(2)
					Spacer()
					Button("拷貝指令") {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(Self.keyCommand, forType: .string)
					}
					.controlSize(.small)
				}
				.padding(8)
				.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
			}

			Button {
				Task { await connect() }
			} label: {
				if working {
					ProgressView().controlSize(.small).frame(width: 80)
				} else {
					Text("連線").frame(width: 80)
				}
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.keyboardShortcut(.defaultAction)
			.disabled(working || key.trimmingCharacters(in: .whitespaces).isEmpty)
		}
		.padding(32)
		.frame(maxWidth: 520)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.onAppear { server = app.prefs.serverURL }
	}

	private func connect() async {
		working = true
		defer { working = false }
		do {
			try await app.configure(server: server.isEmpty ? Preferences.defaultServer : server, key: key)
			key = ""
			error = nil
		} catch {
			self.error = error.userMessage
		}
	}
}
