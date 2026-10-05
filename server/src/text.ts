import { createHash } from "node:crypto";
import { ConverterFactory } from "opencc-js/core";
import HKVariantsRev from "opencc-js/dict/HKVariantsRev";
import TSCharacters from "opencc-js/dict/TSCharacters";
import TWVariantsRev from "opencc-js/dict/TWVariantsRev";

// Character dictionaries only: phrase rules convert a character differently
// depending on its neighbours (乾隆 stays 乾隆 but 乾 becomes 干), which would
// break substring matching.
const toSimplified = ConverterFactory([TWVariantsRev, HKVariantsRev], [TSCharacters]);

/** Folds width, case and Traditional/Simplified Chinese so 炸鸡 finds 炸雞. */
export function foldForSearch(s: string): string {
	return toSimplified(s.normalize("NFKC").toLowerCase());
}

/**
 * Changes whenever foldForSearch could fold text differently (a dictionary
 * update, or bump the leading number after editing foldForSearch), so stored
 * folds can be rebuilt.
 */
export const foldVersion = createHash("sha256")
	.update(`1|${TWVariantsRev}|${HKVariantsRev}|${TSCharacters}`)
	.digest("hex")
	.slice(0, 16);
