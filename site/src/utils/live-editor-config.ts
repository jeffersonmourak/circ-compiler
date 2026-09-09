// What a `<LiveEditor>` in the docs is configured with, and where it expands to.
//
// Pure: the component writes `data-le-*` attributes, this reads them back, and
// every shared constant is imported from the module that owns it rather than
// restated. Two copies of a locked number in two modules is exactly the drift
// the single-source rule exists to prevent.
import { encodeShare, webStreamsCodec } from './share-link.ts';

/** `simulate` is parseable but unused: a poster frame needs a committed
 *  artifact, and the tour's are deliberately untracked. Kept in the type so
 *  the parser's fall-back behaviour stays honest and tested. */
export type LiveEditorOutput = 'preview' | 'simulate';

export interface LiveEditorConfig {
  output: LiveEditorOutput;
  /** A validated CSS length, written to the root as a custom property. */
  height: string;
  readonly: boolean;
  /** The catalogue id this source came from, when it is shipped content. */
  pickId: string | null;
  /** A committed artifact for the simulate poster frame. */
  wasmHref: string | null;
  label: string;
}

export const LIVE_EDITOR_DEFAULTS = {
  output: 'preview',
  height: '14rem',
  readonly: false,
} as const;

// The two debounced stages and the share cap belong to the modules that own
// them; re-declaring either here would be a second copy that can drift.
export { Stage, ANALYZE_DEBOUNCE_MS, BUILD_DEBOUNCE_MS, outputsShouldClear } from '../scripts/pipeline.ts';
export { SHARE_CAP } from './share-link.ts';

const HEIGHT_RE = /^\d{1,4}(\.\d{1,2})?(rem|em|px|ch|vh)$/;

/** Anything that is not a plain CSS length falls back to the default. Never
 *  throws, because this reads an author-supplied attribute. */
export function clampHeight(raw: string | undefined | null): string {
  if (!raw) return LIVE_EDITOR_DEFAULTS.height;
  const trimmed = raw.trim();
  return HEIGHT_RE.test(trimmed) ? trimmed : LIVE_EDITOR_DEFAULTS.height;
}

/** Read a `.le` root's dataset back into a config. Unknown values fall back
 *  rather than propagating; nothing here throws. */
export function parseLiveEditorConfig(d: Record<string, string | undefined>): LiveEditorConfig {
  const output: LiveEditorOutput = d.leOutput === 'simulate' ? 'simulate' : 'preview';
  return {
    output,
    height: clampHeight(d.leHeight),
    readonly: d.leReadonly === 'true',
    pickId: d.lePick ? d.lePick : null,
    wasmHref: d.leWasm ? d.leWasm : null,
    label: d.leLabel && d.leLabel.trim() !== '' ? d.leLabel : 'circ source',
  };
}

export type ExpandResult =
  /** A content id: no source in the URL at all. `note` is set only when an
   *  edit had to be left behind. */
  | { kind: 'pick'; hash: string; note?: string }
  /** The encoder's fragment verbatim; it already carries its leading `#`. */
  | { kind: 'src'; hash: string }
  | { kind: 'refuse'; reason: string };

/**
 * Where the expand link should point.
 *
 * An unedited shipped source expands by id, so the URL stays short and the
 * playground opens the content rather than a copy of it — and the encoder is
 * never called at all. An edited one carries its source. When the source is
 * too large to carry and there is an id to fall back to, the link degrades to
 * the id **and says so**, because the reader would otherwise follow it and
 * find their edit gone.
 */
export async function expandTarget(o: {
  pickId: string | null;
  original: string;
  current: string;
  encode: (source: string) => Promise<
    | { ok: true; key: 'src' | 'src0'; fragment: string; chars: number }
    | { ok: false; reason: 'too-large'; chars: number; cap: number }
  >;
}): Promise<ExpandResult> {
  const edited = o.current !== o.original;
  if (!edited && o.pickId) return { kind: 'pick', hash: `#pick=${o.pickId}` };

  const encoded = await o.encode(o.current);
  if (encoded.ok) return { kind: 'src', hash: encoded.fragment };

  if (o.pickId) {
    return {
      kind: 'pick',
      hash: `#pick=${o.pickId}`,
      note: `This edit is too long to carry in a link (${encoded.chars} characters, limit ${encoded.cap}); opening the original instead.`,
    };
  }
  return {
    kind: 'refuse',
    reason: `This edit is too long to carry in a link (${encoded.chars} characters, limit ${encoded.cap}).`,
  };
}

/** The one encoder a browser consumer needs. `webStreamsCodec()` already
 *  returns null where the compression globals are absent, which is the
 *  plain-key fallback, so there is nothing to branch on here. */
export const browserEncoder = (source: string) => encodeShare(source, webStreamsCodec());
