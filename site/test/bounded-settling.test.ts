import { expect, test } from 'bun:test';
import { resolve } from 'node:path';

test('shipped compiler bounds feedback in CLI-equivalent, canvas, raw WASM, and Truth paths while latches still settle', async () => {
  const child = Bun.spawn([process.execPath, resolve(import.meta.dir, 'settling-probe.ts')], { stdout: 'pipe', stderr: 'pipe' });
  let timedOut = false;
  const timeout = setTimeout(() => { timedOut = true; child.kill(); }, 10_000);
  const [exit, stdout, stderr] = await Promise.all([child.exited, new Response(child.stdout).text(), new Response(child.stderr).text()]);
  clearTimeout(timeout);
  expect(timedOut).toBe(false);
  expect(stderr).toBe('');
  expect(exit).toBe(0);
  const result = JSON.parse(stdout);
  const failure = 'err E_NOSETTLE settle work budget exceeded; reset required';
  expect(result.transcript).toEqual(['ok', 'ok', 'ok', 'ok', failure, failure, failure, failure, 'ok', 'ok 0x0 0x0', 'ok', 'ok']);
  expect(result.events).toContain('settle-failed');
  expect(result.events.filter((event: string) => event === 'settle-failed')).toHaveLength(1);
  expect(result.canvasError).toContain('E_NOSETTLE');
  expect(result.poisoned).toBe(true);
  expect([result.beforeInit, result.afterInit, result.afterFailure]).toEqual([-1, 0, 1]);
  expect(result.trapped).toBe(true);
  expect(result.repeatTrapped).toBe(true);
  expect(result.invalidDefined).toBe('0');
  expect(result.truthStatus).toBe(3);
  expect(result.truthError.error).toContain('E_NOSETTLE');
  expect(result.scratchError).toContain('E_NOSETTLE');
  expect(result.latchValues.slice(1)).toEqual(['1/1', '1/1', '0/1', '0/1']);
}, 15_000);
