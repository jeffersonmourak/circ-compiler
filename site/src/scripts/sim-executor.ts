// The `--sim` reply strings, in the browser.
//
// `lib/sim/loop.zig` is the truth: every string here is copied from its
// `serve` loop and `do*` functions, not paraphrased, so a transcript typed at
// the console matches `tests/fixtures/expected-sim/*.txt` byte for byte. The
// session does the driving and the checking; this module only spells its
// answers, and holds the one piece of state the session does not: where a
// `load` reads and a `save` writes.
//
// `execute` is async for `reset` and `quit`, which await the session's new
// runtime. Every other verb answers at once. A counted reply (`pins`,
// `vals`, `mems`, `cells`) is its header plus one line per record, in the
// same array; the console prints an array as lines.

import { widthMask, type BitValue } from 'circ-renderer/topology';
import { imageErrorReason } from '../utils/rom-image.ts';
import { parseLine, writeHex, type Assign } from './sim-protocol.ts';
import type { MemRef, PinRef, SimFailure, SimSession } from './sim-session.ts';

export const PROTO_VERSION = 1;

/**
 * Where `load` reads and `save` writes. The CLI's is the process cwd; a test's
 * is a map or the repository's fixtures; the page's refuses and points the
 * reader at the Memory tab. `error` is spelled as Zig's `@errorName` would
 * spell it (`FileNotFound`, `AccessDenied`, …); `FileTooBig` on a read is the
 * CLI's cap and is reported as `E_MEMFMT`, not `E_IO`.
 */
export interface FileSource {
  read(path: string): { ok: true; bytes: Uint8Array } | { ok: false; error: string };
  write(path: string, bytes: Uint8Array): { ok: true } | { ok: false; error: string };
}

/** A file source over a map, for tests and scripts that never touch a disk. */
export class MemoryFileSource implements FileSource {
  constructor(readonly files: Map<string, Uint8Array> = new Map()) {}

  read(path: string): { ok: true; bytes: Uint8Array } | { ok: false; error: string } {
    const bytes = this.files.get(path);
    return bytes ? { ok: true, bytes } : { ok: false, error: 'FileNotFound' };
  }

  write(path: string, bytes: Uint8Array): { ok: true } {
    this.files.set(path, bytes);
    return { ok: true };
  }
}

const err = (f: SimFailure): string => `err ${f.code} ${f.arg}`;

/**
 * `readPin` in the loop: undefined bits and bits beyond the width read as 0,
 * the engine's own equality rule, so a half-known value has one spelling.
 */
const canonical = (v: BitValue, width: number): { value: bigint; defined: bigint } => {
  const defined = v.defined & widthMask(width);
  return { value: v.value & defined, defined };
};

const pinLine = (p: PinRef): string => `pin ${p.name} ${p.kind} ${p.width}`;
const valLine = (p: PinRef, v: BitValue): string => {
  const c = canonical(v, p.width);
  return `${p.name} ${writeHex(c.value)} ${writeHex(c.defined)}`;
};
const cellText = (mem: MemRef, v: BitValue): string => {
  const c = canonical(v, mem.width);
  return `${writeHex(c.value)} ${writeHex(c.defined)}`;
};

/**
 * The lines `--sim` prints before its first prompt: `ready`, one `pin` line
 * per root pin, one `diag warning` line per analysis warning. `fileName` is
 * the path the CLI was given, printed on every `diag` line whichever file the
 * diagnostic is in, as the loop does.
 */
export function handshake(session: SimSession, fileName: string): string[] {
  const lines = [`ready proto=${PROTO_VERSION} pins=${session.pins.length} warnings=${session.warnings.length}`];
  for (const p of session.pins) lines.push(pinLine(p));
  for (const w of session.warnings) lines.push(`diag warning ${w.code} ${fileName}:${w.line}:${w.col} ${w.message}`);
  return lines;
}

const toSessionAssign = (a: Assign) => ({ pin: a.pin, value: a.value, defined: a.mask ?? undefined });

/**
 * One request line in, the reply lines out. A blank line or a comment gets an
 * empty array, as the loop prints nothing for them.
 */
export async function execute(session: SimSession, files: FileSource, line: string): Promise<string[]> {
  const parsed = parseLine(line);
  if (!parsed.ok) {
    if (parsed.reason === 'empty') return [];
    if (parsed.reason === 'badval') return ['err E_BADVAL invalid integer literal'];
    return ['err E_PROTO malformed command'];
  }
  const cmd = parsed.command;
  switch (cmd.verb) {
    case 'quit':
      // There is no process to end: the console prints the CLI's farewell and
      // the session starts over, as the plan's decision 3 has it.
      await session.reset();
      return ['ok bye'];
    case 'pins':
      return [`pins ${session.pins.length}`, ...session.pins.map(pinLine)];
    case 'run':
      session.run();
      return ['ok'];
    case 'reset':
      await session.reset();
      return ['ok'];
    case 'set': {
      const r = session.set(cmd.pin, cmd.value, cmd.mask ?? undefined);
      return [r.ok ? 'ok' : err(r)];
    }
    case 'get': {
      const r = session.get(cmd.pin);
      if (!r.ok) return [err(r)];
      const c = canonical(r.value, r.pin.width);
      return [`ok ${writeHex(c.value)} ${writeHex(c.defined)}`];
    }
    case 'dump': {
      const rows = session.dump(cmd.which);
      return [`vals ${rows.length}`, ...rows.map((row) => valLine(row.pin, row.value))];
    }
    case 'eval': {
      const r = session.eval(cmd.assigns.map(toSessionAssign), cmd.queries);
      if (!r.ok) return [err(r)];
      const parts = r.values.map((row) => {
        const c = canonical(row.value, row.pin.width);
        return ` ${row.pin.name}=${writeHex(c.value)}/${writeHex(c.defined)}`;
      });
      return [`ok${parts.join('')}`];
    }
    case 'mems':
      return [`mems ${session.mems.length}`, ...session.mems.map((m) => `mem ${m.name} ${m.kind} ${m.width} ${m.addrWidth}`)];
    case 'load': {
      // The memory is resolved before the file is read, so an unknown name
      // wins over a missing file.
      const mem = session.mems.find((m) => m.name === cmd.mem);
      if (!mem) return [`err E_NOMEM ${cmd.mem}`];
      const file = files.read(cmd.path);
      if (!file.ok) {
        if (file.error === 'FileTooBig') return [`err E_MEMFMT ${cmd.path}: ${imageErrorReason({ kind: 'too_big' }, mem)}`];
        return [`err E_IO ${cmd.path}: ${file.error}`];
      }
      const r = session.loadImage(cmd.mem, file.bytes);
      if (!r.ok) return [r.code === 'E_MEMFMT' ? `err E_MEMFMT ${cmd.path}: ${r.arg}` : err(r)];
      return [`ok words=${r.words}`];
    }
    case 'save': {
      const r = session.storeImage(cmd.mem);
      if (!r.ok) return [err(r)];
      const w = files.write(cmd.path, r.bytes);
      if (!w.ok) return [`err E_IO ${cmd.path}: ${w.error}`];
      return [`ok words=${r.words}`];
    }
    case 'peek': {
      const r = session.peek(cmd.mem, cmd.addr);
      return [r.ok ? `ok ${cellText(r.mem, r.value)}` : err(r)];
    }
    case 'poke': {
      const r = session.poke(cmd.mem, cmd.addr, cmd.value, cmd.mask ?? undefined);
      return [r.ok ? 'ok' : err(r)];
    }
    case 'mem': {
      const r = session.dumpMem(cmd.mem, cmd.start ?? undefined, cmd.count ?? undefined);
      if (!r.ok) return [err(r)];
      return [`cells ${r.cells.length}`, ...r.cells.map((c) => `${writeHex(c.addr)} ${cellText(r.mem, c.value)}`)];
    }
    case 'clear': {
      const r = session.clear(cmd.mem);
      return [r.ok ? 'ok' : err(r)];
    }
  }
}
