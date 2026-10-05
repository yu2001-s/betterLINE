/**
 * Interactive QR login. Run it yourself in a terminal (it needs your phone):
 *   systemctl --user stop line-mcp && npm run login && systemctl --user start line-mcp
 */
import qrcode from "qrcode-terminal";
import { AUTH_TOKEN_KEY, config } from "./config.ts";
import { createBaseClient, errorMessage } from "./line.ts";
import { acquireSessionLock, AtomicFileStorage } from "./storage.ts";

process.umask(0o077);
acquireSessionLock(config.lockPath);
const storage = new AtomicFileStorage(config.storagePath);

if (await storage.get(AUTH_TOKEN_KEY) && !process.argv.includes("--force")) {
	console.log("Already logged in. Pass --force to log in again.");
	process.exit(0);
}

const { base, tokenSaved } = createBaseClient(storage);

base.on("qrcall", (url) => {
	console.log("\n1. On your phone, open LINE → Home → the QR code scanner, and scan this:\n");
	qrcode.generate(url, { small: true });
	console.log(`   (Or open this link on the phone: ${url})\n`);
});
base.on("pincall", (pin) => {
	console.log(`2. When LINE on your phone asks for a code, enter:  ${pin}\n`);
});

try {
	await base.loginProcess.login({ qr: true });
	await tokenSaved();
	console.log(`Logged in as ${base.profile?.displayName}. Start the server now.`);
	process.exit(0);
} catch (e) {
	console.error(`Login failed: ${errorMessage(e)}`);
	process.exit(1);
}
