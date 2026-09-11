// The closed terminal line's summary, read off the console's transcript.
import { describe, expect, test } from 'bun:test';
import { summaryOf } from '../src/scripts/terminal-line.ts';
import { Transcript, promptEcho } from '../src/scripts/console.ts';

describe('terminal line', () => {
  test('no echo yields nulls', () => {
    expect(summaryOf([])).toEqual({ command: null, reply: null });
    expect(summaryOf(['# circ-compile --sim', '# proto=1'])).toEqual({ command: null, reply: null });
  });

  test('the last echo and its reply', () => {
    expect(summaryOf(['> set a 1', 'ok', '> get out', 'out 0'])).toEqual({ command: 'get out', reply: 'out 0' });
    // Built the way the console builds them.
    const t = new Transcript();
    t.append([promptEcho('set a 1'), 'ok']);
    t.append([promptEcho('get out'), 'out 1']);
    expect(summaryOf(t.lines)).toEqual({ command: 'get out', reply: 'out 1' });
  });

  test('a pending command has no reply', () => {
    expect(summaryOf(['> set a 1', 'ok', '> run'])).toEqual({ command: 'run', reply: null });
  });

  test('notes after the echo are skipped, and an error is a reply', () => {
    expect(summaryOf(['> reset', '# session rebuilt', 'ok'])).toEqual({ command: 'reset', reply: 'ok' });
    expect(summaryOf(['> set zz 1', 'err E_PIN no such pin: zz'])).toEqual({ command: 'set zz 1', reply: 'err E_PIN no such pin: zz' });
  });
});
