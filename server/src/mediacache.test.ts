import assert from "node:assert/strict";
import { existsSync, mkdtempSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MEDIA_CACHE_BYTES, readCache, writeCache } from "./mediacache.ts";

const media = (bytes: number) => ({ data: new Uint8Array(bytes), type: "image/png", name: "a.png" });

test("the cache limit is a positive 2 GiB", () => {
	assert.equal(MEDIA_CACHE_BYTES, 2_147_483_648);
});

test("a written file is kept and read back", () => {
	const dir = mkdtempSync(join(tmpdir(), "media-"));
	writeCache(dir, "100", media(10));
	const hit = readCache(dir, "100");
	assert.equal(hit?.data.length, 10);
	assert.equal(hit?.type, "image/png");
	assert.equal(hit?.name, "a.png");
});

test("over the limit, the oldest files go first", () => {
	const dir = mkdtempSync(join(tmpdir(), "media-"));
	writeCache(dir, "1", media(10), 25);
	utimesSync(join(dir, "1"), 1, 1);
	writeCache(dir, "2", media(10), 25);
	utimesSync(join(dir, "2"), 2, 2);
	writeCache(dir, "3", media(10), 25);
	assert.equal(existsSync(join(dir, "1")), false);
	assert.equal(existsSync(join(dir, "1.json")), false);
	assert.ok(readCache(dir, "2"));
	assert.ok(readCache(dir, "3"));
});
