import { homedir } from "node:os";
import { join } from "node:path";

const stateDir = process.env.LINE_MCP_STATE_DIR ??
	join(homedir(), ".local/state/line-mcp");

export const config = {
	stateDir,
	storagePath: join(stateDir, "storage.json"),
	lockPath: join(stateDir, "session.lock"),
	sendLogPath: join(stateDir, "sent.log"),
	archivePath: join(stateDir, "archive.db"),
	mediaCacheDir: join(stateDir, "media-cache"),
	/** Desktop client API: bound to the Tailscale address only. */
	clientHost: process.env.LINE_CLIENT_HOST ?? "",
	clientPort: Number(process.env.LINE_CLIENT_PORT ?? 8791),
	clientKey: process.env.LINE_CLIENT_KEY ?? "",
	host: "127.0.0.1",
	port: Number(process.env.LINE_MCP_PORT ?? 8790),
	/** Shared secret the Cloudflare Worker sends in `x-line-mcp-key`. */
	backendKey: process.env.LINE_MCP_BACKEND_KEY ?? "",
	/**
	 * Secondary-device slot. It is the only secondary type that both supports
	 * QR login and gets refreshable (V3) tokens, and it does not displace the
	 * desktop (Mac/Windows) session.
	 */
	device: "ANDROIDSECONDARY" as const,
	timeZone: process.env.LINE_MCP_TZ ?? "Asia/Taipei",
};

/** Storage key for the access token (linejs does not persist it itself). */
export const AUTH_TOKEN_KEY = "lineMcp:authToken";
