/** Stable public knowledge names. This metadata deliberately contains no copied prose. */
export const documentKeys = ['language', 'getting-started', 'circuit-format', 'wasm-api', 'preview', 'sim-protocol'] as const;
export const sectionOverrides: Record<string, string> = {
  'language:input-pins': 'input-pins',
  'language:parametric-sub-circuits': 'parametric-sub-circuits',
  // §5.3 is a wire-specific subsection; §6 is the canonical broad width reference.
  'language:5.3 Multi-bit wires': 'wires-multi-bit-wires',
  'language:3.5 Memories (declaration shape)': 'memories-declaration-shape',
};
export const aliases: Record<string, string> = {};
export const removed: Record<string, { replacementId: string | null }> = {};
export const topicSynonyms: Record<string, string[]> = {
  bus: ['width', 'multi_bit'], multi: ['width'], parametric: ['parameter'], parameter: ['parametric'],
  concat: ['concatenation'], rom: ['memory'], ram: ['memory'],
};
