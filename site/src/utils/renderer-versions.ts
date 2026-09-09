// CIRF (`circ.topology.v0.full`) versions the pinned circ-renderer decodes.
// The renderer at the pinned commit reads 0x01 and 0x02 and does not export
// the list itself; `test/renderer-pin.test.ts` proves the pin decodes what
// the committed libcirc.wasm emits, so this constant cannot drift silently.
export const SUPPORTED_TOPOLOGY_VERSIONS: readonly number[] = [0x01, 0x02];
