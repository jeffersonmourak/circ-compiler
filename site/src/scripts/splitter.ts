// A draggable, keyboard-operable divider between two panes.
//
// The whole arithmetic half is pure and exported, because that is the half a
// test can reach: the DOM half is pointer capture and attribute writes, which
// no headless runner can exercise.
//
// The rendered position is one CSS custom property, and one grid rule reads
// it. In the ratio unit it holds a unitless fraction in (0, 1) — the first
// pane's share of the space left over after the divider's own width. A
// percentage that ignored the divider would sum past 100% and, under the app
// layout's `overflow: hidden` body, clip invisibly rather than raise a
// scrollbar. In the pixel unit it holds the first pane's width in CSS pixels,
// which is how the bench's source column is drawn (design file: `480px 1px
// minmax(0, 1fr)`): the reader's intent is a width, and a narrower window
// borrows from it rather than overwriting it.

export interface SplitterBounds {
  min: number;
  max: number;
}

export interface SplitterOptions {
  /** The grid container carrying the custom property. */
  container: HTMLElement;
  /** The `role="separator"` element. */
  separator: HTMLElement;
  property?: string;
  /** The divider's own orientation: 'vertical' is a bar between left and right. */
  orientation?: 'vertical' | 'horizontal';
  /** What the property holds: a share of the container, or the first pane's
   *  width in pixels. `initial`, `onChange` and `onCommit` speak that unit. */
  unit?: 'ratio' | 'px';
  /** In pixel mode, which pane the property sizes. */
  pane?: 'first' | 'second';
  /** Usable axis span when the container also carries fixed chrome. */
  measure?: () => { start: number; size: number };
  /** Hard minimum for either pane, in px (the ratio unit). */
  minPanePx?: number | [number, number];
  minRatio?: number;
  maxRatio?: number;
  step?: number;
  coarseStep?: number;
  /** The pixel unit's bounds: the first pane never below `minPx`, the second
   *  never below `maxReservePx`. */
  minPx?: number;
  maxReservePx?: number;
  stepPx?: number;
  coarseStepPx?: number;
  initial?: number;
  label?: string;
  labels?: [string, string];
  /** Every visual change: drag frames and key presses. */
  onChange?: (ratio: number) => void;
  /** A user-driven settle only — pointerup, key press, double-click. The
   *  persistence hook: a resize must never write a preference. */
  onCommit?: (ratio: number) => void;
}

export interface SplitterHandle {
  /** What is rendered: the intent clamped by the current container width. */
  readonly ratio: number;
  /** What the user last asked for, unclamped — so a narrow window borrows the
   *  position rather than overwriting it. */
  readonly intent: number;
  set(ratio: number, opts?: { commit?: boolean }): void;
  refresh(): void;
  destroy(): void;
}

const DEFAULTS = {
  property: '--pg-split-main',
  orientation: 'vertical' as const,
  unit: 'ratio' as const,
  pane: 'first' as const,
  minPanePx: 240,
  minRatio: 0.2,
  maxRatio: 0.8,
  step: 0.02,
  coarseStep: 0.1,
  minPx: 320,
  maxReservePx: 480,
  stepPx: 16,
  coarseStepPx: 64,
  initial: 0.5,
  labels: ['editor', 'output'] as [string, string],
};

// ---------------------------------------------------------------------------
// The pixel unit.
// ---------------------------------------------------------------------------

export function clampPx(px: number, bounds: SplitterBounds): number {
  if (!Number.isFinite(px)) return bounds.min;
  return Math.min(bounds.max, Math.max(bounds.min, Math.round(px)));
}

/**
 * The usable widths at this container size: from `minPx` up to whatever
 * leaves `maxReservePx` for the far pane. A container too narrow for both
 * collapses the range to `minPx`, so the far pane is what gives, and the
 * bounds never invert. A zero size (nothing laid out yet) is not a narrow
 * window: the intent renders as asked, and the ResizeObserver re-clamps once
 * there is a size to clamp to — so the first paint is the reader's width, not
 * the minimum.
 */
export function pxBounds(sizePx: number, o: { minPx: number; maxReservePx: number }): SplitterBounds {
  if (!Number.isFinite(sizePx) || sizePx <= 0) return { min: o.minPx, max: Number.POSITIVE_INFINITY };
  const max = Math.floor(sizePx - o.maxReservePx);
  return max < o.minPx ? { min: o.minPx, max: o.minPx } : { min: o.minPx, max };
}

/** Where a pointer sits, in pixels from the container's near edge. */
export function pxFromPointer(startPx: number, clientPx: number, sizePx = 0, pane: 'first' | 'second' = 'first'): number {
  const raw = pane === 'second' ? startPx + sizePx - clientPx : clientPx - startPx;
  return Number.isFinite(raw) ? Math.max(0, raw) : 0;
}

/** The pixel twin of `stepRatio`: the same keys, the same `null` for a key
 *  that is not part of the contract. */
export function stepPx(
  px: number,
  ev: { key: string; shiftKey?: boolean },
  o: {
    orientation: 'vertical' | 'horizontal';
    stepPx: number;
    coarseStepPx: number;
    bounds: SplitterBounds;
    pane?: 'first' | 'second';
  },
): number | null {
  const delta = (ev.shiftKey ? o.coarseStepPx : o.stepPx) * (o.pane === 'second' ? -1 : 1);
  const decrease = o.orientation === 'vertical' ? 'ArrowLeft' : 'ArrowUp';
  const increase = o.orientation === 'vertical' ? 'ArrowRight' : 'ArrowDown';
  if (ev.key === decrease) return clampPx(px - delta, o.bounds);
  if (ev.key === increase) return clampPx(px + delta, o.bounds);
  if (ev.key === 'Home') return o.pane === 'second' ? o.bounds.max : o.bounds.min;
  if (ev.key === 'End') return o.pane === 'second' ? o.bounds.min : o.bounds.max;
  return null;
}

export function clampRatio(ratio: number, bounds: SplitterBounds): number {
  if (!Number.isFinite(ratio)) return bounds.min;
  return Math.min(bounds.max, Math.max(bounds.min, ratio));
}

/**
 * The usable range at this container width: the configured bounds, tightened
 * so neither pane can fall below `minPanePx`. A container too narrow to hold
 * two minimums has no usable range at all, and both ends collapse to the
 * midpoint rather than producing an inverted or empty interval.
 */
export function effectiveBounds(
  sizePx: number,
  o: { minPanePx: number | [number, number]; minRatio: number; maxRatio: number },
): SplitterBounds {
  if (!Number.isFinite(sizePx) || sizePx <= 0) return { min: o.minRatio, max: o.maxRatio };
  const [first, second] = Array.isArray(o.minPanePx) ? o.minPanePx : [o.minPanePx, o.minPanePx];
  if (sizePx < first + second) return { min: 0.5, max: 0.5 };
  const min = Math.max(o.minRatio, first / sizePx);
  const max = Math.min(o.maxRatio, 1 - second / sizePx);
  return max < min ? { min: 0.5, max: 0.5 } : { min, max };
}

/** Where a pointer sits, as a fraction of the container. A zero-width
 *  container yields the midpoint rather than a division by zero. */
export function ratioFromPointer(startPx: number, sizePx: number, clientPx: number): number {
  if (!Number.isFinite(sizePx) || sizePx <= 0) return 0.5;
  const raw = (clientPx - startPx) / sizePx;
  if (!Number.isFinite(raw)) return 0.5;
  return Math.min(1, Math.max(0, raw));
}

/**
 * The next ratio for a key, or `null` when the key is not part of the
 * contract — which is what lets the caller skip `preventDefault` and leave the
 * key its browser meaning. The wrong-axis arrows return `null` deliberately,
 * so `ArrowUp`/`ArrowDown` on a vertical divider still scroll the page.
 */
export function stepRatio(
  ratio: number,
  ev: { key: string; shiftKey?: boolean },
  o: {
    orientation: 'vertical' | 'horizontal';
    step: number;
    coarseStep: number;
    bounds: SplitterBounds;
  },
): number | null {
  const delta = ev.shiftKey ? o.coarseStep : o.step;
  const decrease = o.orientation === 'vertical' ? 'ArrowLeft' : 'ArrowUp';
  const increase = o.orientation === 'vertical' ? 'ArrowRight' : 'ArrowDown';

  if (ev.key === decrease) return clampRatio(ratio - delta, o.bounds);
  if (ev.key === increase) return clampRatio(ratio + delta, o.bounds);
  if (ev.key === 'Home') return o.bounds.min;
  if (ev.key === 'End') return o.bounds.max;
  return null;
}

export function ariaValues(
  ratio: number,
  bounds: SplitterBounds,
  labels: [string, string],
): { now: number; min: number; max: number; text: string } {
  const pct = (n: number) => Math.round(n * 100);
  const now = pct(ratio);
  return {
    now,
    min: pct(bounds.min),
    max: pct(bounds.max),
    text: `${labels[0]} ${now}%, ${labels[1]} ${100 - now}%`,
  };
}

export function createSplitter(options: SplitterOptions): SplitterHandle {
  const o = { ...DEFAULTS, ...options };
  const { container, separator } = o;
  const sizeOf = (): number => {
    if (o.measure) return o.measure().size;
    const rect = container.getBoundingClientRect();
    return o.orientation === 'vertical' ? rect.width : rect.height;
  };
  const startOf = (): number => {
    if (o.measure) return o.measure().start;
    const rect = container.getBoundingClientRect();
    return o.orientation === 'vertical' ? rect.left : rect.top;
  };

  const px = o.unit === 'px';
  const labels: [string, string] = px && o.pane === 'second' ? [o.labels[1], o.labels[0]] : o.labels;
  const boundsAt = (size: number): SplitterBounds => (px ? pxBounds(size, o) : effectiveBounds(size, o));
  const clamp = (value: number, b: SplitterBounds): number => (px ? clampPx(value, b) : clampRatio(value, b));

  let intent = o.initial;
  let bounds = boundsAt(sizeOf());
  let rendered = clamp(intent, bounds);
  let dragFrom: number | null = null;
  let pointerId: number | null = null;

  const render = () => {
    const size = sizeOf();
    bounds = boundsAt(size);
    rendered = clamp(intent, bounds);
    container.style.setProperty(o.property, px ? `${rendered}px` : String(rendered));
    // The accessible value is a share of the container in either unit, so a
    // screen reader hears the same sentence whatever the property holds.
    const aria = px && size > 0
      ? ariaValues(rendered / size, { min: bounds.min / size, max: Math.min(1, bounds.max / size) }, labels)
      : ariaValues(px ? 0 : rendered, px ? { min: 0, max: 1 } : bounds, labels);
    separator.setAttribute('aria-valuenow', String(aria.now));
    separator.setAttribute('aria-valuemin', String(aria.min));
    separator.setAttribute('aria-valuemax', String(aria.max));
    separator.setAttribute('aria-valuetext', aria.text);
  };

  const apply = (next: number, commit: boolean) => {
    intent = next;
    render();
    o.onChange?.(rendered);
    if (commit) o.onCommit?.(rendered);
  };

  const onPointerDown = (e: PointerEvent) => {
    if (e.button !== 0) return;
    e.preventDefault();
    dragFrom = intent;
    pointerId = e.pointerId;
    // Capture keeps pointermove on the separator even over the canvas, so the
    // renderer's own pointer handling never sees a drag.
    try { separator.setPointerCapture(e.pointerId); } catch { /* Synthetic pointers have no capture. */ }
  };

  const onPointerMove = (e: PointerEvent) => {
    if (dragFrom === null || e.pointerId !== pointerId) return;
    const client = o.orientation === 'vertical' ? e.clientX : e.clientY;
    const raw = px ? pxFromPointer(startOf(), client, sizeOf(), o.pane) : ratioFromPointer(startOf(), sizeOf(), client);
    apply(clamp(raw, bounds), false);
  };

  const endDrag = (commit: boolean) => {
    if (dragFrom === null) return;
    if (!commit) apply(dragFrom, false);
    dragFrom = null;
    if (pointerId !== null && separator.hasPointerCapture?.(pointerId)) {
      separator.releasePointerCapture(pointerId);
    }
    pointerId = null;
    if (commit) o.onCommit?.(rendered);
  };

  const onPointerUp = (e: PointerEvent) => {
    if (e.pointerId !== pointerId) return;
    endDrag(true);
  };
  const onPointerCancel = () => endDrag(false);

  const onKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'Escape' && dragFrom !== null) {
      e.preventDefault();
      endDrag(false);
      return;
    }
    const next = px
      ? stepPx(rendered, e, { orientation: o.orientation, pane: o.pane, stepPx: o.stepPx, coarseStepPx: o.coarseStepPx, bounds })
      : stepRatio(rendered, e, { orientation: o.orientation, step: o.step, coarseStep: o.coarseStep, bounds });
    if (next === null) return; // not ours: the key keeps its browser meaning
    e.preventDefault();
    apply(next, true);
  };

  const onDoubleClick = (e: MouseEvent) => {
    e.preventDefault();
    apply(o.initial, true);
  };

  separator.setAttribute('role', 'separator');
  separator.setAttribute('aria-orientation', o.orientation);
  if (o.label) separator.setAttribute('aria-label', o.label);
  if (!separator.hasAttribute('tabindex')) separator.tabIndex = 0;

  separator.addEventListener('pointerdown', onPointerDown);
  separator.addEventListener('pointermove', onPointerMove);
  separator.addEventListener('pointerup', onPointerUp);
  separator.addEventListener('pointercancel', onPointerCancel);
  separator.addEventListener('keydown', onKeyDown);
  separator.addEventListener('dblclick', onDoubleClick);

  // Re-clamp on a container resize, but never commit: a transient narrow
  // window must not overwrite the reader's preference.
  const observer =
    typeof ResizeObserver === 'function' ? new ResizeObserver(() => render()) : null;
  observer?.observe(container);

  render();

  return {
    get ratio() {
      return rendered;
    },
    get intent() {
      return intent;
    },
    set(ratio: number, opts?: { commit?: boolean }) {
      apply(ratio, opts?.commit === true);
    },
    refresh() {
      render();
    },
    destroy() {
      observer?.disconnect();
      separator.removeEventListener('pointerdown', onPointerDown);
      separator.removeEventListener('pointermove', onPointerMove);
      separator.removeEventListener('pointerup', onPointerUp);
      separator.removeEventListener('pointercancel', onPointerCancel);
      separator.removeEventListener('keydown', onKeyDown);
      separator.removeEventListener('dblclick', onDoubleClick);
    },
  };
}
