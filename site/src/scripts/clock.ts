// The Clock panel's arithmetic: which pin a clock may drive, how a frequency
// is read and written, and how many edges are due on a given animation frame.
// Nothing here touches a session or the DOM, so `bun test` drives all of it;
// the island owns the loop and the drive (`SimSession.clock`).

export const MIN_HZ = 0.1;
export const MAX_HZ = 10_000;
export const DEFAULT_HZ = 1;

/** A frame that arrives later than this is a tab that was hidden, not a
 *  backlog to work off: the clock resumes instead of catching up. */
export const MAX_GAP_MS = 250;

export const clampHz = (hz: number): number => Math.min(MAX_HZ, Math.max(MIN_HZ, hz));

/** `2`, `0.5`, `2.5 Hz`, `1k`, `1.5 kHz`. Null when it is not a frequency. */
export function parseHz(text: string): number | null {
  const match = text.trim().toLowerCase().match(/^(\d+(?:\.\d+)?|\.\d+)\s*(k)?(?:hz)?$/);
  if (!match) return null;
  const hz = Number(match[1]) * (match[2] ? 1000 : 1);
  return Number.isFinite(hz) && hz > 0 ? clampHz(hz) : null;
}

/** The shortest honest spelling: `0.5`, `12`, `2.5k`. No unit. */
export function formatHz(hz: number): string {
  const trim = (n: number, digits: number) => String(Number(n.toFixed(digits)));
  if (hz >= 1000) return `${trim(hz / 1000, 2)}k`;
  if (hz >= 100) return trim(hz, 0);
  if (hz >= 10) return trim(hz, 1);
  return trim(hz, 2);
}

// The slider is logarithmic: a clock is tuned by ratio, not by difference.
export const SLIDER_STEPS = 1000;
const SPAN = Math.log(MAX_HZ / MIN_HZ);

export function sliderToHz(position: number): number {
  const t = Math.min(1, Math.max(0, position / SLIDER_STEPS));
  return clampHz(Number((MIN_HZ * Math.exp(t * SPAN)).toPrecision(3)));
}

export function hzToSlider(hz: number): number {
  return Math.round((Math.log(clampHz(hz) / MIN_HZ) / SPAN) * SLIDER_STEPS);
}

export interface ClockPin {
  name: string;
  kind: 'in' | 'out';
  width: number;
}

/** The pins a clock can drive: one-bit root inputs, in declaration order. */
export function clockable<P extends ClockPin>(pins: readonly P[]): P[] {
  return pins.filter((pin) => pin.kind === 'in' && pin.width === 1);
}

/** The pin the panel offers first: one named for a clock, else the first. */
export function pickClockPin(pins: readonly ClockPin[]): string | null {
  const candidates = clockable(pins);
  const named = candidates.find((pin) => /(^|_)(clk|clock|ck)(_|$|\d)|^(clk|clock)/i.test(pin.name));
  return (named ?? candidates[0])?.name ?? null;
}

/** The level that follows `current` (0, 1, or 2 for unknown). A pin that is
 *  not at 0 goes low first, because the first rising edge a `ram` or a
 *  flip-flop can see needs a defined low before it. */
export const nextLevel = (current: number): 0 | 1 => (current === 0 ? 1 : 0);

/**
 * How many edges are due. Two edges make one cycle, so a clock at `hz` owes
 * `2 * hz` edges a second; the fraction of an edge left over carries to the
 * next frame, which keeps a slow clock exact and a fast one from drifting.
 */
export class ClockPacer {
  private carry = 0;
  private last: number | null = null;

  constructor(private hz: number) {}

  get frequency(): number { return this.hz; }

  /** Takes effect from the next frame; the fraction already owed is kept. */
  setHz(hz: number): void { this.hz = clampHz(hz); }

  /** Whole edges due at `nowMs`. The first call only starts the timer. */
  due(nowMs: number): number {
    if (this.last === null) {
      this.last = nowMs;
      return 0;
    }
    const elapsed = Math.min(MAX_GAP_MS, Math.max(0, nowMs - this.last));
    this.last = nowMs;
    this.carry += (elapsed * 2 * this.hz) / 1000;
    const edges = Math.floor(this.carry);
    this.carry -= edges;
    return edges;
  }
}

/** Cycles per second over the last second of frames, for the readout: what
 *  the circuit actually ran at, which is below the setting once a frame's
 *  budget runs out. */
export class RateMeter {
  private readonly samples: { at: number; edges: number }[] = [];

  add(nowMs: number, edges: number): void {
    this.samples.push({ at: nowMs, edges });
    while (this.samples.length > 0 && nowMs - this.samples[0].at > 1000) this.samples.shift();
  }

  /** Null until there is a quarter second to measure over. */
  hz(nowMs: number): number | null {
    if (this.samples.length < 2) return null;
    const span = nowMs - this.samples[0].at;
    if (span < 250) return null;
    // The first sample's edges fell before the window it opens.
    const edges = this.samples.slice(1).reduce((sum, sample) => sum + sample.edges, 0);
    return (edges / 2) * (1000 / span);
  }
}
