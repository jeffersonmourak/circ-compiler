// The Data tab, as a pure module: one row per root pin, an edit that drives
// the session, a toggle for a one-bit input, and the protocol's refusals as
// sentences.
//
// Values are spelled the site's way here — the renderer's `parsePinValue` and
// `formatPinValue` in the reader's chosen base, the spelling the bus dialog
// and the memory grid use: `?` unknown, `0x` and `0b` overriding the base, a
// half-known value written bit by bit with `x` for each unknown bit (out
// only: a typed value is wholly known, as in the bus dialog). The console
// spells them the protocol's way; that is Phase 2's, and not this file's.
//
// Reaches the renderer's index (for the two value helpers), so the island
// imports this module dynamically beside the renderer; it must not enter the
// eager graph.

import { formatPinValue, parsePinValue, type BitValue, type ValueFormat } from 'circ-renderer';
import type { PinRef, SimError, SimResult } from './sim-session.ts';

/** The slice of a session the view drives and reads. */
export interface SessionLike {
  readonly pins: readonly PinRef[];
  get(name: string): SimResult<{ pin: PinRef; value: BitValue }>;
  set(name: string, value: bigint, defined?: bigint): SimResult;
}

export interface DataRow {
  name: string;
  kind: 'in' | 'out';
  width: number;
  /** `formatPinValue(value, format)`: `?` unknown, `x` per unknown bit, else the base. */
  text: string;
  /** The one-bit view for a toggle: 0, 1, or 2 for unknown. */
  signal: 0 | 1 | 2;
}

export type EditOutcome = { ok: true } | { ok: false; message: string };

const signalOf = (v: BitValue): 0 | 1 | 2 => ((v.defined & 1n) === 0n ? 2 : (v.value & 1n) === 1n ? 1 : 0);

/** One row per root pin, inputs then outputs, in the reader's base. */
export function rowsFor(session: SessionLike, format: ValueFormat): DataRow[] {
  return session.pins.map((pin) => {
    const r = session.get(pin.name);
    const value: BitValue = r.ok ? r.value : { value: 0n, defined: 0n, width: pin.width };
    return { name: pin.name, kind: pin.kind, width: pin.width, text: formatPinValue(value, format), signal: signalOf(value) };
  });
}

/** The protocol's refusal as a sentence a reader can act on. */
export function describeError(code: SimError, arg: string): string {
  switch (code) {
    case 'E_NOPIN': return `There is no pin named ${arg}.`;
    case 'E_NOTIN': return `${arg} is an output; only inputs can be driven.`;
    case 'E_WIDTH': return `That value does not fit in ${arg}'s width.`;
    case 'E_BADVAL': return `${arg} is not a value.`;
    case 'E_NOMEM': return `There is no memory named ${arg}.`;
    case 'E_ADDR': return `Address out of range: ${arg}.`;
    case 'E_MEMFMT': return `The image is not valid: ${arg}.`;
    case 'E_IO': return `Could not read or write ${arg}.`;
    case 'E_NOSETTLE': return 'The circuit did not settle.';
    case 'E_PROTO': return arg ? `The circuit refused: ${arg}.` : 'The circuit refused the command.';
  }
}

/**
 * Parse the reader's text for the pin and drive it. A parse failure is the
 * renderer's reason and drives nothing; a session refusal is a sentence.
 */
export function editRow(session: SessionLike, name: string, text: string, format: ValueFormat): EditOutcome {
  const pin = session.pins.find((p) => p.name === name);
  if (!pin) return { ok: false, message: describeError('E_NOPIN', name) };
  if (pin.kind !== 'in') return { ok: false, message: describeError('E_NOTIN', name) };
  const parsed = parsePinValue(text, pin.width, format);
  if (!parsed.ok) return { ok: false, message: parsed.message };
  const r = session.set(name, parsed.value, parsed.defined);
  return r.ok ? { ok: true } : { ok: false, message: describeError(r.code, r.arg) };
}

/** A one-bit input: unknown → 1, 1 → 0, 0 → 1. */
export function toggleRow(session: SessionLike, name: string): EditOutcome {
  const pin = session.pins.find((p) => p.name === name);
  if (!pin) return { ok: false, message: describeError('E_NOPIN', name) };
  if (pin.kind !== 'in') return { ok: false, message: describeError('E_NOTIN', name) };
  if (pin.width !== 1) return { ok: false, message: `${name} is ${pin.width} bits wide; type its value instead.` };
  const cur = session.get(name);
  const next = cur.ok && signalOf(cur.value) === 1 ? 0n : 1n;
  const r = session.set(name, next, 1n);
  return r.ok ? { ok: true } : { ok: false, message: describeError(r.code, r.arg) };
}
