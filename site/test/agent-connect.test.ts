import { expect, test } from 'bun:test';
import { agentConnectPrompt } from '../src/scripts/agent-connect.ts';
import { decodeShare } from '../src/utils/share-link.ts';

test('agent handoff shares the captured multi-file source instead of the old URL fragment', async () => {
  const project = { name: 'Unsaved circuit', entryFile: 'child.circ', source: '// child.circ\ninput a\n// root.circ\ninput b\n' };
  const pending = agentConnectPrompt('https://example.com/playground?old=1#pick=example:half-adder', project);
  const captured = project.source;
  project.source = 'changed after click';
  const prompt = await pending;
  const url = new URL(prompt.split('\n')[1]);
  expect(url.search).toBe('');
  expect(url.hash).toStartWith('#src0=');
  expect(await decodeShare(url.hash)).toMatchObject({ ok: true, source: captured });
  expect(prompt).toContain('"entryFile":"child.circ"');
});

test('oversize handoff carries exact source data rather than silently dropping the project', async () => {
  const source = 'input a\n'.repeat(2000);
  const prompt = await agentConnectPrompt('https://example.com/playground', { name: 'Large circuit', entryFile: 'main.circ', source });
  expect(prompt).toContain('exceeds the Share URL limit');
  expect(JSON.parse(prompt.split('Combined marker source (JSON data):\n')[1])).toEqual({ source });
});
