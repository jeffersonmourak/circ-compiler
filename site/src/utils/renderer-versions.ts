// CIRF (`circ.topology.v0.full`) versions the pinned circ-renderer decodes,
// re-exported from the package so the pin and this list cannot drift;
// `test/renderer-pin.test.ts` proves the committed libcirc.wasm emits one
// of them.
export { SUPPORTED_TOPOLOGY_VERSIONS } from 'circ-renderer';

/**
 * The pinned package's own version, restated here so a half-applied `bun add`
 * fails a test instead of shipping. The sha in `package.json` and the version
 * inside the installed package are two facts that can disagree, and only one
 * of them is visible in a diff.
 */
export const RENDERER_PIN_VERSION = '2.2.0-alpha.6';

