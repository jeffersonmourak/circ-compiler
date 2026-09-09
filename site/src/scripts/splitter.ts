// A draggable, keyboard-operable divider between two panes.
//
// The whole arithmetic half is pure and exported, because that is the half a
// test can reach: the DOM half is pointer capture and attribute writes, which
// no headless runner can exercise.
//
// The rendered position is one CSS custom property holding a unitless fraction
// in (0, 1) — the first pane's share of the space left over after the divider's
// own width. One grid rule reads it. A percentage that ignored the divider
// would sum past 100% and, under the app layout's `overflow: hidden` body,
// clip invisibly rather than raise a scrollbar.

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
  /** Hard minimum for either pane, in px. */
  minPanePx?: number;
  minRatio?: number;
  maxRatio?: number;
  step?: number;
  coarseStep?: number;
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
  minPanePx: 240,
  minRatio: 0.2,
  maxRatio: 0.8,
  step: 0.02,
  coarseStep: 0.1,
  initial: 0.5,
  labels: ['editor', 'output'] as [string, string],
};

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
  o: { minPanePx: number; minRatio: number; maxRatio: number },
): SplitterBounds {
  if (!Number.isFinite(sizePx) || sizePx <= 0) return { min: o.minRatio, max: o.maxRatio };
  if (sizePx < o.minPanePx * 2) return { min: 0.5, max: 0.5 };
  const margin = o.minPanePx / sizePx;
  const min = Math.max(o.minRatio, margin);
  const max = Math.min(o.maxRatio, 1 - margin);
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
    const rect = container.getBoundingClientRect();
    return o.orientation === 'vertical' ? rect.width : rect.height;
  };
  const startOf = (): number => {
    const rect = container.getBoundingClientRect();
    return o.orientation === 'vertical' ? rect.left : rect.top;
  };

  let intent = o.initial;
  let bounds = effectiveBounds(sizeOf(), o);
  let rendered = clampRatio(intent, bounds);
  let dragFrom: number | null = null;
  let pointerId: number | null = null;

  const render = () => {
    bounds = effectiveBounds(sizeOf(), o);
    rendered = clampRatio(intent, bounds);
    container.style.setProperty(o.property, String(rendered));
    const aria = ariaValues(rendered, bounds, o.labels);
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
    separator.setPointerCapture(e.pointerId);
  };

  const onPointerMove = (e: PointerEvent) => {
    if (dragFrom === null || e.pointerId !== pointerId) return;
    const client = o.orientation === 'vertical' ? e.clientX : e.clientY;
    apply(clampRatio(ratioFromPointer(startOf(), sizeOf(), client), bounds), false);
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
    const next = stepRatio(rendered, e, {
      orientation: o.orientation,
      step: o.step,
      coarseStep: o.coarseStep,
      bounds,
    });
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
