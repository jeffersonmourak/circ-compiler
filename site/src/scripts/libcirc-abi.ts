// The alloc/copy/call/read protocol over a libcirc.wasm instance. One
// function, used by the worker and by the tests, so the ABI lives in one
// place (DOCS/libcirc-api.md § The wasm module).

export type CallOp = 'analyze' | 'compile' | 'preview' | 'truth_table';

export interface LibcircRequest {
  root: string;
  files: Record<string, string>;
  options?: Record<string, unknown>;
}

export interface LibcircExports {
  memory: WebAssembly.Memory;
  circ_alloc(len: number): number;
  circ_free(ptr: number, len: number): void;
  circ_version(): number;
  circ_analyze(ptr: number, len: number): number;
  circ_compile(ptr: number, len: number): number;
  circ_preview(ptr: number, len: number): number;
  circ_truth_table(ptr: number, len: number): number;
  circ_result_ptr(): number;
  circ_result_len(): number;
  circ_reset(): number;
}

export const LIBCIRC_IMPORTS = {
  env: { debugEnabled: () => 0, onDebugLog: () => {} },
};

export async function instantiateLibcirc(
  source: BufferSource | Response | Promise<Response>,
): Promise<LibcircExports> {
  if (source instanceof Response || source instanceof Promise) {
    try {
      const r = await WebAssembly.instantiateStreaming(source as Promise<Response>, LIBCIRC_IMPORTS);
      return r.instance.exports as unknown as LibcircExports;
    } catch {
      const resp = await (source as Promise<Response>);
      const bytes = await resp.arrayBuffer();
      const r = await WebAssembly.instantiate(bytes, LIBCIRC_IMPORTS);
      return r.instance.exports as unknown as LibcircExports;
    }
  }
  const r = await WebAssembly.instantiate(source as BufferSource, LIBCIRC_IMPORTS);
  return r.instance.exports as unknown as LibcircExports;
}

/** Copy the library-owned result out. Re-views memory.buffer: it detaches on grow. */
export function readResult(w: LibcircExports): Uint8Array {
  const ptr = w.circ_result_ptr();
  const len = w.circ_result_len();
  return new Uint8Array(w.memory.buffer).slice(ptr, ptr + len);
}

export function callVersion(w: LibcircExports): { status: number; bytes: Uint8Array } {
  const status = w.circ_version();
  return { status, bytes: readResult(w) };
}

/** alloc → copy in → circ_<op> → copy out → free. Synchronous. */
export function callOp(
  w: LibcircExports,
  op: CallOp,
  request: LibcircRequest | string,
): { status: number; bytes: Uint8Array } {
  const req = new TextEncoder().encode(typeof request === 'string' ? request : JSON.stringify(request));
  const ptr = w.circ_alloc(req.length);
  if (ptr === 0) throw new Error('circ_alloc failed');
  if (req.length > 0) new Uint8Array(w.memory.buffer).set(req, ptr);
  const status = w[`circ_${op}`](ptr, req.length);
  const bytes = readResult(w);
  w.circ_free(ptr, req.length);
  return { status, bytes };
}
