import {
	closeSync,
	mkdirSync,
	openSync,
	readFileSync,
	renameSync,
	unlinkSync,
	writeFileSync,
} from "node:fs";
import { dirname } from "node:path";
import { BaseStorage } from "@jsr/evex__linejs/storage";

type Value = Parameters<BaseStorage["set"]>[1];

/**
 * linejs storage that holds the session token, refresh token and E2EE private
 * keys. Unlike linejs' FileStorage it writes atomically (temp file + rename) so
 * a crash mid-write cannot corrupt the key material, and it creates the file
 * owner-only.
 */
export class AtomicFileStorage extends BaseStorage {
	#data: Record<string, Value>;
	#writes: Promise<void> = Promise.resolve();
	readonly path: string;

	constructor(path: string) {
		super();
		this.path = path;
		mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
		let raw = "{}";
		try {
			raw = readFileSync(path, "utf-8");
		} catch (e) {
			if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
		}
		this.#data = JSON.parse(raw);
	}

	async get(key: string): Promise<Value | undefined> {
		return this.#data[key];
	}

	async set(key: string, value: Value): Promise<void> {
		this.#data[key] = value;
		await this.#flush();
	}

	async delete(key: string): Promise<void> {
		delete this.#data[key];
		await this.#flush();
	}

	async clear(): Promise<void> {
		this.#data = {};
		await this.#flush();
	}

	async migrate(storage: BaseStorage): Promise<void> {
		for (const [key, value] of Object.entries(this.#data)) {
			await storage.set(key, value);
		}
	}

	#flush(): Promise<void> {
		const snapshot = JSON.stringify(this.#data);
		const write = this.#writes.then(() => {
			const tmp = `${this.path}.tmp`;
			writeFileSync(tmp, snapshot, { mode: 0o600 });
			renameSync(tmp, this.path);
		});
		// A failed write must not block later ones; the caller still sees it.
		this.#writes = write.catch(() => {});
		return write;
	}
}

/**
 * Only one process may hold the session at a time: two linejs clients sharing
 * one storage file would overwrite each other's tokens and key material.
 */
export function acquireSessionLock(lockPath: string): () => void {
	mkdirSync(dirname(lockPath), { recursive: true, mode: 0o700 });
	try {
		const fd = openSync(lockPath, "wx", 0o600);
		writeFileSync(fd, String(process.pid));
		closeSync(fd);
	} catch (e) {
		if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
		const pid = Number(readFileSync(lockPath, "utf-8"));
		if (pid && isAlive(pid)) {
			throw new Error(
				`LINE session is in use by process ${pid}. Stop it first (systemctl --user stop line-mcp).`,
			);
		}
		writeFileSync(lockPath, String(process.pid), { mode: 0o600 });
	}
	const release = () => {
		try {
			if (Number(readFileSync(lockPath, "utf-8")) === process.pid) {
				unlinkSync(lockPath);
			}
		} catch { /* already gone */ }
	};
	process.once("exit", release);
	return release;
}

function isAlive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch (e) {
		return (e as NodeJS.ErrnoException).code === "EPERM";
	}
}
