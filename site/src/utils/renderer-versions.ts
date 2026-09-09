// CIRF (`circ.topology.v0.full`) versions the pinned circ-renderer decodes,
// re-exported from the package so the pin and this list cannot drift;
// `test/renderer-pin.test.ts` proves the committed libcirc.wasm emits one
// of them.
export { SUPPORTED_TOPOLOGY_VERSIONS } from 'circ-renderer';
