import { readdirSync, readFileSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/**
 * 2 GiB. Written with `**`: `2 << 30` overflows JavaScript's 32-bit shift to a
 * negative number, which made every write evict the whole cache.
 */
export const MEDIA_CACHE_BYTES = 2 * 1024 ** 3;

export interface CachedMedia {
	data: Uint8Array;
	type: string;
	name: string;
}

export function readCache(dir: string, id: string): CachedMedia | undefined {
	try {
		const meta = JSON.parse(readFileSync(join(dir, `${id}.json`), "utf-8"));
		return { ...meta, data: readFileSync(join(dir, id)) };
	} catch {
		return undefined;
	}
}

/** Decrypted media stays on the encrypted disk, owner-only, capped by evicting the oldest. */
export function writeCache(dir: string, id: string, media: CachedMedia, limit = MEDIA_CACHE_BYTES) {
	writeFileSync(join(dir, id), media.data, { mode: 0o600 });
	writeFileSync(join(dir, `${id}.json`), JSON.stringify({ type: media.type, name: media.name }), { mode: 0o600 });
	const files = readdirSync(dir)
		.filter((f) => !f.endsWith(".json"))
		.map((f) => {
			const { size, mtimeMs } = statSync(join(dir, f));
			return { f, size, mtimeMs };
		})
		.sort((a, b) => a.mtimeMs - b.mtimeMs);
	let total = files.reduce((n, x) => n + x.size, 0);
	for (const x of files) {
		if (total <= limit) break;
		unlinkSync(join(dir, x.f));
		try {
			unlinkSync(join(dir, `${x.f}.json`));
		} catch { /* already gone */ }
		total -= x.size;
	}
}
