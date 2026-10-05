import assert from "node:assert/strict";
import { test } from "node:test";
import { foldForSearch } from "./text.ts";

const matches = (name: string, query: string) => foldForSearch(name).includes(foldForSearch(query));

test("Simplified and Traditional queries find each other", () => {
	assert.ok(matches("炸雞", "炸鸡"));
	assert.ok(matches("炸鸡", "炸雞"));
	assert.ok(matches("臺灣大學", "台湾"));
	assert.ok(matches("家裡", "家里"));
	assert.ok(!matches("炸雞", "炸鸭"));
});

test("substrings fold the same way as the whole name", () => {
	assert.ok(matches("乾隆", "乾"));
	assert.ok(matches("頭髮", "发"));
});

test("still folds case and full-width letters", () => {
	assert.ok(matches("Amy 開會", "AMY"));
	assert.ok(matches("ＡＢＣ", "abc"));
});
