// The playground's compiler thread. Owns the single libcirc.wasm instance
// and answers {id, op, request} messages; every circ_* call is synchronous
// here, so two ops never interleave and the library-owned result buffer is
// always copied out before the next message is handled.
import {
  callOp,
  callVersion,
  instantiateLibcirc,
  type CallOp,
  type LibcircExports,
  type LibcircRequest,
} from '../scripts/libcirc-abi.ts';

export type Op = 'init' | CallOp | 'reset';

export interface WorkerMsg {
  id: number;
  op: Op;
  wasmUrl?: string;
  request?: LibcircRequest;
}

export interface WorkerReply {
  id: number;
  op: Op;
  /** 0 ok, 1 diagnostics, 2 bad request, 3 refusal, 4 oom, 5 internal; -1 thrown. */
  status: number;
  /** analyze/preview/truth_table/version JSON or diagnostics JSON, UTF-8 decoded. */
  text?: string;
  /** compile status 0: the .wasm artifact (transferred). */
  bytes?: Uint8Array;
  /** status 2/3/5: the `error` field of the body, or a thrown message. */
  error?: string;
}

let exportsPromise: Promise<LibcircExports> | null = null;
const decoder = new TextDecoder();

function errorOf(text: string): string {
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed.error === 'string') return parsed.error;
  } catch {
    /* not JSON */
  }
  return text;
}

async function handle(msg: WorkerMsg): Promise<{ reply: WorkerReply; transfer: Transferable[] }> {
  if (msg.op === 'init') {
    exportsPromise ??= instantiateLibcirc(fetch(msg.wasmUrl!));
    const w = await exportsPromise;
    const v = callVersion(w);
    return { reply: { id: msg.id, op: 'init', status: v.status, text: decoder.decode(v.bytes) }, transfer: [] };
  }
  const w = await (exportsPromise ?? Promise.reject(new Error('libcirc worker: init first')));
  if (msg.op === 'reset') {
    return { reply: { id: msg.id, op: 'reset', status: w.circ_reset() }, transfer: [] };
  }
  const out = callOp(w, msg.op, msg.request!);
  // A truth table leaves the engine arena populated; release it right away.
  if (msg.op === 'truth_table') w.circ_reset();
  if (msg.op === 'compile' && out.status === 0) {
    return { reply: { id: msg.id, op: msg.op, status: 0, bytes: out.bytes }, transfer: [out.bytes.buffer] };
  }
  const text = decoder.decode(out.bytes);
  const reply: WorkerReply = { id: msg.id, op: msg.op, status: out.status, text };
  if (out.status >= 2) reply.error = errorOf(text);
  return { reply, transfer: [] };
}

self.onmessage = async (ev: MessageEvent<WorkerMsg>) => {
  const msg = ev.data;
  try {
    const { reply, transfer } = await handle(msg);
    (self as unknown as Worker).postMessage(reply, transfer);
  } catch (err) {
    const reply: WorkerReply = { id: msg.id, op: msg.op, status: -1, error: String((err as Error)?.message ?? err) };
    (self as unknown as Worker).postMessage(reply);
  }
};
