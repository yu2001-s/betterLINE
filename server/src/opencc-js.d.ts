// opencc-js ships its dictionaries without type declarations.
declare module "opencc-js/dict/*" {
	const dict: string;
	export default dict;
}
