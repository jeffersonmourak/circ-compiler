import { widthMask, type BitValue } from 'circ-renderer/topology';
import type { MemRef, PinRef, SimError, SimFailure, SimSession } from './sim-session.ts';
import { parseRomImage } from '../utils/rom-image.ts';

export const HEX = /^0x(?:0|[1-9a-f][0-9a-f]*)$/;
export const IMAGE_HEX = /^(?:[0-9a-f]{2})*$/;

export function parseHex(value: unknown, width?: number): bigint | null {
  if (typeof value !== 'string' || !HEX.test(value)) return null;
  const parsed = BigInt(value);
  return width === undefined || parsed <= widthMask(width) ? parsed : null;
}

export function canonical(value: bigint, defined: bigint, width: number) {
  const mask = widthMask(width);
  const d = defined & mask;
  return { value: `0x${(value & d & mask).toString(16)}`, defined: `0x${d.toString(16)}`, width };
}

export function signal(value: BitValue, width: number) { return canonical(value.value, value.defined, width); }
export function pinValue(pin: PinRef, value: BitValue) { return { name: pin.name, kind: pin.kind, width: pin.width, state: signal(value, pin.width) }; }
export function memoryShape(mem: MemRef) {
  return { name: mem.name, kind: mem.kind, width: mem.width, addressWidth: mem.addrWidth, words: 2 ** mem.addrWidth, liveAccess: 'root' as const, sourceOwner: null };
}
export function simFailure(error: SimFailure) {
  return { code: 'SIMULATION_REFUSED' as const, message: `Simulation refused ${error.arg}.`, retryable: false, details: { simCode: error.code, arg: error.arg } };
}
export function imageBytes(hex: unknown, mem: Pick<MemRef, 'name' | 'kind' | 'width' | 'addrWidth'>): { ok: true; bytes: Uint8Array; words: number } | { ok: false; message: string } {
  if (typeof hex !== 'string' || !IMAGE_HEX.test(hex)) return { ok: false, message: 'hex must be lowercase whole-byte hexadecimal text.' };
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i += 1) bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  const parsed = parseRomImage(hex, mem);
  return parsed.ok ? { ok: true, bytes, words: parsed.words } : { ok: false, message: parsed.message };
}

/** Validation shared by live and disposable sessions. It deliberately does no I/O. */
export function validateDrive(session: SimSession, assignments: readonly { pin: string; value: string; defined?: string }[], queries: readonly string[]) {
  const resolved: { pin: string; value: bigint; defined?: bigint }[] = [];
  for (const assignment of assignments) {
    if (!assignment || typeof assignment.pin !== 'string') return { ok: false as const, message: 'Each assignment needs a pin.' };
    const pin = session.pins.find((item) => item.kind === 'in' && item.name === assignment.pin);
    const output = session.pins.find((item) => item.kind === 'out' && item.name === assignment.pin);
    if (!pin) return { ok: false as const, failure: { ok: false, code: output ? 'E_NOTIN' as SimError : 'E_NOPIN' as SimError, arg: assignment.pin } };
    const value = parseHex(assignment.value, pin.width);
    const defined = assignment.defined === undefined ? undefined : parseHex(assignment.defined, pin.width);
    if (value === null || (assignment.defined !== undefined && defined === null)) return { ok: false as const, failure: { ok: false, code: 'E_WIDTH' as SimError, arg: assignment.pin } };
    resolved.push({ pin: pin.name, value, defined: defined ?? undefined });
  }
  const seen = new Set<string>();
  for (const query of queries) {
    if (typeof query !== 'string' || seen.has(query)) return { ok: false as const, message: 'Queries must be unique pin names.' };
    seen.add(query);
    if (!session.pins.some((pin) => pin.name === query)) return { ok: false as const, failure: { ok: false, code: 'E_NOPIN' as SimError, arg: query } };
  }
  return { ok: true as const, assignments: resolved };
}
