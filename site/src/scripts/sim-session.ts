// One simulation session, three faces.
//
// The playground used to let the canvas own the runtime: `renderCircuit`
// created the `CircRuntime` inside the canvas, the memory dock reached it
// through `sim.view.runtime`, and nothing else could drive the circuit. This
// is the thing that outlives the canvas: it owns the runtime built from the
// compiled artifact, knows the root pins and memories by name in declaration
// order (the same collection `lib/engine_session.zig` makes for `--sim`:
// `origin.length === 0`, inputs then outputs), drives and reads through the
// renderer's typed runtime, and tells every face after each change. The
// canvas, the Data tab and the console are faces on it; none holds a runtime
// of its own.
//
// Errors are the protocol's, as values: the ten codes of
// `lib/sim/protocol.zig`, with the argument `--sim` would print after them.
// The console spells them `err E_NOPIN a`; the Data tab spells them as a
// sentence. One set of reasons, two spellings.
//
// The runtime is injected: `CircRuntime` on the page, a stub in a test.

import { ComponentKind, widthMask, type BitValue } from 'circ-renderer/topology';
import {
  applyRomImages,
  imageErrorReason,
  romPlan,
  validateImageBytes,
  type ApplyResult,
  type MemorySymbol,
  type RomImageMap,
} from '../utils/rom-image.ts';

export type PinKind = 'in' | 'out';
export interface PinRef {
  name: string;
  id: number;
  width: number;
  kind: PinKind;
}
export interface MemRef {
  name: string;
  id: number;
  kind: 'rom' | 'ram';
  width: number;
  addrWidth: number;
}

/** The ten codes of `lib/sim/protocol.zig`, as the session reports them. */
export type SimError =
  | 'E_PROTO'
  | 'E_NOPIN'
  | 'E_NOTIN'
  | 'E_WIDTH'
  | 'E_BADVAL'
  | 'E_NOSETTLE'
  | 'E_NOMEM'
  | 'E_IO'
  | 'E_MEMFMT'
  | 'E_ADDR';

export type SimFailure = { ok: false; code: SimError; arg: string };
export type SimResult<T = object> = ({ ok: true } & T) | SimFailure;

/** The slice of the decoded topology the session reads. */
export interface TopologyLike {
  components: readonly {
    id: number;
    kind: number;
    name: string;
    width: number;
    origin: readonly unknown[];
    memory?: { addrWidth: number };
  }[];
}

/**
 * The slice of `CircRuntime` the session uses. A test stubs it; the page
 * hands in the real one. Every value is `(value, defined, width)` with bigint
 * masks, as the renderer's `BitValue` is.
 */
export interface RuntimeLike {
  readonly topology: TopologyLike;
  setValue(id: number, value: bigint, defined: bigint): void;
  run(): void;
  readValue(id: number): BitValue;
  readonly hasMemory: boolean;
  memories(): readonly { id: number; name: string; info: { kind: 'rom' | 'ram'; width: number; addrWidth: number } }[];
  readMemWord(id: number, addr: number): BitValue;
  writeMemWord(id: number, addr: number, value: bigint, defined: bigint): number;
  loadMemImage(id: number, bytes: Uint8Array): number;
  storeMemImage(id: number): Uint8Array | null;
  clearMem(id: number): number;
  destroy(): void;
}

export interface SessionWarning {
  code: string;
  file: string;
  line: number;
  col: number;
  message: string;
}

export interface SessionInit {
  bytes: Uint8Array;
  /** `CircRuntime.loadFromBytes` on the page; a stub factory in a test. */
  load: (bytes: Uint8Array) => Promise<RuntimeLike>;
  /** Declared roms and their images from the Memory tab, applied at build and at reset. */
  roms?: readonly MemorySymbol[];
  images?: RomImageMap;
  /** Analysis warnings, for the console's handshake. */
  warnings?: readonly SessionWarning[];
  /**
   * Drive every root input low and settle once after building, the way the
   * page has always booted a canvas (the renderer's `loadFromBytes` did it
   * until the session took over loading with `noInitialPinDrive`). Never
   * applied by `reset`, which is the protocol's: every pin floating, as after
   * `init()`. A test that replays `--sim` transcripts leaves this off.
   */
  bootLow?: boolean;
}

export type SessionEvent =
  /** Pins were driven, by any face. */
  | { kind: 'drive'; names: readonly string[] }
  /** A memory's contents changed. */
  | { kind: 'memory'; name: string }
  /** `reset`: a new runtime; a face holding the old one rebuilds. */
  | { kind: 'rebuilt' }
  | { kind: 'destroyed' };

export type SessionListener = (event: SessionEvent) => void;

export interface Assign {
  pin: string;
  value: bigint;
  /** Omitted: fully defined. */
  defined?: bigint;
}

const fail = (code: SimError, arg: string): SimFailure => ({ ok: false, code, arg });

/** The root pins: `origin` empty, inputs then outputs, in declaration order. */
export function collectPins(topology: TopologyLike): PinRef[] {
  const inputs: PinRef[] = [];
  const outputs: PinRef[] = [];
  for (const c of topology.components) {
    if (c.origin.length !== 0) continue;
    if (c.kind === ComponentKind.InputPin) inputs.push({ name: c.name, id: c.id, width: c.width, kind: 'in' });
    else if (c.kind === ComponentKind.OutputPin) outputs.push({ name: c.name, id: c.id, width: c.width, kind: 'out' });
  }
  return [...inputs, ...outputs];
}

/** The root memories, in declaration order. */
export function collectMems(topology: TopologyLike): MemRef[] {
  const out: MemRef[] = [];
  for (const c of topology.components) {
    if (c.origin.length !== 0) continue;
    if (c.kind !== ComponentKind.Rom && c.kind !== ComponentKind.Ram) continue;
    out.push({
      name: c.name,
      id: c.id,
      kind: c.kind === ComponentKind.Rom ? 'rom' : 'ram',
      width: c.width,
      addrWidth: c.memory?.addrWidth ?? 0,
    });
  }
  return out;
}

/** True when `value` and `defined` both fit in `width` bits. */
const fits = (width: number, value: bigint, defined: bigint): boolean =>
  value >= 0n && defined >= 0n && value >> BigInt(width) === 0n && defined >> BigInt(width) === 0n;

export class SimSession {
  private rt: RuntimeLike;
  private readonly bytes: Uint8Array;
  private readonly load: SessionInit['load'];
  private readonly roms: readonly MemorySymbol[];
  private readonly images: RomImageMap;
  private readonly listeners = new Set<SessionListener>();
  private alive = true;
  private resetting: Promise<void> | null = null;

  readonly pins: readonly PinRef[];
  readonly mems: readonly MemRef[];
  readonly warnings: readonly SessionWarning[];

  private constructor(init: SessionInit, runtime: RuntimeLike) {
    this.rt = runtime;
    this.bytes = init.bytes;
    this.load = init.load;
    this.roms = init.roms ?? [];
    this.images = init.images ?? new Map();
    this.warnings = init.warnings ?? [];
    this.pins = collectPins(runtime.topology);
    this.mems = collectMems(runtime.topology);
  }

  /** Build over a fresh runtime and apply the preloads, as `--sim` does before its handshake. */
  static async build(init: SessionInit): Promise<SimSession> {
    const runtime = await init.load(init.bytes);
    const session = new SimSession(init, runtime);
    session.applyPreloads();
    if (init.bootLow) session.bootLow();
    return session;
  }

  /** Every root input to 0, fully defined, then one settle. No event: nothing was watching yet. */
  private bootLow(): void {
    for (const pin of this.pins) {
      if (pin.kind === 'in') this.rt.setValue(pin.id, 0n, widthMask(pin.width));
    }
    this.rt.run();
  }

  /** The current runtime. Replaced by `reset()`; a face that holds it listens for `rebuilt`. */
  get runtime(): RuntimeLike {
    return this.rt;
  }

  // ---- listeners ------------------------------------------------------------

  subscribe(listener: SessionListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(event: SessionEvent): void {
    for (const listener of Array.from(this.listeners)) {
      try {
        listener(event);
      } catch (err) {
        // One face's throw must not silence the others.
        console.error('sim-session: listener failed', err);
      }
    }
  }

  /** A face drove the runtime around the session (the canvas's click): tell the others. */
  notifyExternal(names: readonly string[]): void {
    this.emit({ kind: 'drive', names });
  }

  // ---- pins -----------------------------------------------------------------

  private input(name: string): PinRef | undefined {
    return this.pins.find((p) => p.kind === 'in' && p.name === name);
  }
  private output(name: string): PinRef | undefined {
    return this.pins.find((p) => p.kind === 'out' && p.name === name);
  }

  /**
   * Resolve a `set`/`eval` target and check its value, as `resolveDrive` does
   * in `lib/sim/loop.zig`: an output is `E_NOTIN`, an unknown name `E_NOPIN`,
   * a bit beyond the width `E_WIDTH`. Nothing is driven here.
   */
  private resolveDrive(a: Assign): SimResult<{ pin: PinRef; defined: bigint }> {
    const pin = this.input(a.pin);
    if (!pin) return fail(this.output(a.pin) ? 'E_NOTIN' : 'E_NOPIN', a.pin);
    const defined = a.defined ?? widthMask(pin.width);
    if (!fits(pin.width, a.value, defined)) return fail('E_WIDTH', a.pin);
    return { ok: true, pin, defined };
  }

  private drive(pin: PinRef, value: bigint, defined: bigint): void {
    this.rt.setValue(pin.id, value, defined);
    this.rt.run();
  }

  /** Drive a root input and settle. An omitted `defined` is the full mask. */
  set(name: string, value: bigint, defined?: bigint): SimResult {
    const r = this.resolveDrive({ pin: name, value, defined });
    if (!r.ok) return r;
    this.drive(r.pin, value, r.defined);
    this.emit({ kind: 'drive', names: [name] });
    return { ok: true };
  }

  /** Read a root pin: outputs first, then inputs, as `doGet` looks them up. */
  get(name: string): SimResult<{ pin: PinRef; value: BitValue }> {
    const pin = this.output(name) ?? this.input(name);
    if (!pin) return fail('E_NOPIN', name);
    return { ok: true, pin, value: this.rt.readValue(pin.id) };
  }

  /** Every root pin of the kind asked for, inputs then outputs. */
  dump(which: 'in' | 'out' | 'all'): { pin: PinRef; value: BitValue }[] {
    return this.pins
      .filter((p) => which === 'all' || p.kind === which)
      .map((pin) => ({ pin, value: this.rt.readValue(pin.id) }));
  }

  /**
   * One-shot vector: every assignment and query is checked before anything is
   * driven, so a malformed eval is inert; then the assignments are driven in
   * order, each settling, and the queries read.
   */
  eval(assigns: readonly Assign[], queries: readonly string[]): SimResult<{ values: { pin: PinRef; value: BitValue }[] }> {
    const resolved: { pin: PinRef; value: bigint; defined: bigint }[] = [];
    for (const a of assigns) {
      const r = this.resolveDrive(a);
      if (!r.ok) return r;
      resolved.push({ pin: r.pin, value: a.value, defined: r.defined });
    }
    for (const q of queries) {
      if (!this.output(q) && !this.input(q)) return fail('E_NOPIN', q);
    }
    for (const r of resolved) this.drive(r.pin, r.value, r.defined);
    if (resolved.length > 0) this.emit({ kind: 'drive', names: resolved.map((r) => r.pin.name) });
    const values = queries.map((q) => {
      const pin = (this.output(q) ?? this.input(q))!;
      return { pin, value: this.rt.readValue(pin.id) };
    });
    return { ok: true, values };
  }

  /** Drain the event queue. Redundant after `set`; kept for parity with the artifact's `run()`. */
  run(): void {
    this.rt.run();
  }

  // ---- preloads and reset ---------------------------------------------------

  /** Write the Memory tab's images into the runtime, as `--mem` preloads. */
  applyPreloads(): ApplyResult {
    if (this.roms.length === 0 || !this.rt.hasMemory) return { applied: [], errors: new Map() };
    return applyRomImages(this.rt, romPlan(this.images, this.roms), this.roms);
  }

  /**
   * The protocol's `reset`: a new runtime from the same bytes, every pin
   * undefined, the preloads re-applied, mid-session memory contents dropped.
   * The old runtime is destroyed; a face holding it rebuilds on `rebuilt`.
   */
  reset(): Promise<void> {
    if (this.resetting) return this.resetting;
    this.resetting = (async () => {
      const fresh = await this.load(this.bytes);
      const old = this.rt;
      this.rt = fresh;
      old.destroy();
      this.applyPreloads();
      this.emit({ kind: 'rebuilt' });
    })().finally(() => {
      this.resetting = null;
    });
    return this.resetting;
  }

  // ---- memories -------------------------------------------------------------

  private mem(name: string): MemRef | undefined {
    return this.mems.find((m) => m.name === name);
  }

  private wordCount(mem: MemRef): bigint {
    return 1n << BigInt(mem.addrWidth);
  }

  /** Read one cell. */
  peek(name: string, addr: bigint): SimResult<{ mem: MemRef; value: BitValue }> {
    const mem = this.mem(name);
    if (!mem) return fail('E_NOMEM', name);
    if (addr < 0n || addr >= this.wordCount(mem)) return fail('E_ADDR', `${name} 0x${addr.toString(16)}`);
    return { ok: true, mem, value: this.rt.readMemWord(mem.id, Number(addr)) };
  }

  /** Write one cell and settle, like `set`. An omitted `defined` is the full mask. */
  poke(name: string, addr: bigint, value: bigint, defined?: bigint): SimResult {
    const mem = this.mem(name);
    if (!mem) return fail('E_NOMEM', name);
    if (addr < 0n || addr >= this.wordCount(mem)) return fail('E_ADDR', `${name} 0x${addr.toString(16)}`);
    const mask = defined ?? widthMask(mem.width);
    if (!fits(mem.width, value, mask)) return fail('E_WIDTH', name);
    const rc = this.rt.writeMemWord(mem.id, Number(addr), value, mask);
    if (rc !== 0) return fail('E_PROTO', 'write failed');
    this.rt.run();
    this.emit({ kind: 'memory', name });
    return { ok: true };
  }

  /** A range of cells; `start` past the end is `E_ADDR`, `count` is clipped. */
  dumpMem(name: string, start?: bigint, count?: bigint): SimResult<{ mem: MemRef; cells: { addr: bigint; value: BitValue }[] }> {
    const mem = this.mem(name);
    if (!mem) return fail('E_NOMEM', name);
    const total = this.wordCount(mem);
    const from = start ?? 0n;
    if (from < 0n || from >= total) return fail('E_ADDR', `${name} 0x${from.toString(16)}`);
    const n = count === undefined ? total - from : count < total - from ? count : total - from;
    const cells: { addr: bigint; value: BitValue }[] = [];
    for (let addr = from; addr < from + n; addr += 1n) {
      cells.push({ addr, value: this.rt.readMemWord(mem.id, Number(addr)) });
    }
    return { ok: true, mem, cells };
  }

  /** Every cell undefined, and settle. */
  clear(name: string): SimResult {
    const mem = this.mem(name);
    if (!mem) return fail('E_NOMEM', name);
    const rc = this.rt.clearMem(mem.id);
    if (rc !== 0) return fail('E_PROTO', 'clear failed');
    this.rt.run();
    this.emit({ kind: 'memory', name });
    return { ok: true };
  }

  /**
   * Replace every cell from a raw image, checked first the way the compiler
   * checks it: an `E_MEMFMT` carries the reason `--sim` prints after the
   * path. A runtime refusal after that check should not happen and is
   * reported with its status.
   */
  loadImage(name: string, bytes: Uint8Array): SimResult<{ mem: MemRef; words: number }> {
    const mem = this.mem(name);
    if (!mem) return fail('E_NOMEM', name);
    const checked = validateImageBytes(bytes, mem);
    if (!checked.ok) return fail('E_MEMFMT', imageErrorReason(checked.error, mem));
    const rc = this.rt.loadMemImage(mem.id, bytes);
    if (rc !== 0) return fail('E_MEMFMT', `runtime refused the image (status ${rc})`);
    this.rt.run();
    this.emit({ kind: 'memory', name });
    return { ok: true, mem, words: checked.words };
  }

  /** The whole memory as a raw image, `value & defined` per word. */
  storeImage(name: string): SimResult<{ mem: MemRef; bytes: Uint8Array; words: number }> {
    const mem = this.mem(name);
    if (!mem) return fail('E_NOMEM', name);
    const bytes = this.rt.storeMemImage(mem.id);
    if (!bytes) return fail('E_PROTO', 'store failed');
    return { ok: true, mem, bytes, words: Number(this.wordCount(mem)) };
  }

  // ---- life -----------------------------------------------------------------

  get isAlive(): boolean {
    return this.alive;
  }

  destroy(): void {
    if (!this.alive) return;
    this.alive = false;
    this.rt.destroy();
    this.emit({ kind: 'destroyed' });
    this.listeners.clear();
  }
}
