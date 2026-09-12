import { describe, expect, test } from 'bun:test';
import { AgentToolRegistry } from '../src/scripts/agent-tools/registry.ts';
import { statusDescriptor } from '../src/scripts/agent-tools/status.ts';
import { readFileDescriptor } from '../src/scripts/agent-tools/workspace.ts';

function registry(result: unknown = { value: 'ok' }) {
  let calls = 0;
  return {
    calls: () => calls,
    registry: new AgentToolRegistry('page-test', [{ descriptor: statusDescriptor, handler: () => { calls += 1; return result; } }]),
  };
}

describe('agent tools', () => {
  test('catalogue_has_one_status_tool', async () => {
    const { registry: tools } = registry();
    const result = await tools.listTools();
    expect(result).toMatchObject({ ok: true, apiVersion: 1, pageId: 'page-test' });
    if (!result.ok) throw new Error('expected catalogue');
    expect(result.data.tools).toEqual([statusDescriptor]);
    result.data.tools[0].name = 'changed';
    const again = await tools.listTools();
    expect(again.ok && again.data.tools[0].name).toBe('circ_get_status');
  });

  test('invalid_status_arguments_are_inert', async () => {
    const entry = registry();
    for (const input of [null, [], 'bad', { extra: true }, new Date()]) {
      const result = await entry.registry.callTool('circ_get_status', input);
      expect(result.ok).toBe(false);
      expect(!result.ok && result.error.code).toBe('INVALID_ARGUMENT');
    }
    expect(entry.calls()).toBe(0);
  });

  test('unknown_tool_is_distinct', async () => {
    const { registry: tools } = registry();
    const unknown = await tools.callTool('missing', {});
    const malformed = await tools.callTool('circ_get_status', { nope: true });
    expect(!unknown.ok && unknown.error.code).toBe('UNKNOWN_TOOL');
    expect(!malformed.ok && malformed.error.code).toBe('INVALID_ARGUMENT');
  });

  test('results_are_json_safe_and_bounded', async () => {
    const nonJson = registry({ bad: undefined });
    const oversized = registry({ text: 'x'.repeat(40 * 1024) });
    const thrown = new AgentToolRegistry('page-test', [{ descriptor: statusDescriptor, handler: () => { throw new Error('nope'); } }]);
    const a = await nonJson.registry.callTool('circ_get_status', {});
    const b = await oversized.registry.callTool('circ_get_status', {});
    const c = await thrown.callTool('circ_get_status', {});
    expect(!a.ok && a.error.code).toBe('INTERNAL_ERROR');
    expect(!b.ok && b.error.code).toBe('RESULT_TOO_LARGE');
    expect(!c.ok && c.error.code).toBe('INTERNAL_ERROR');
  });

  test('cached_page_suspends_and_resumes', async () => {
    const { registry: tools } = registry();
    tools.suspend();
    const suspended = await tools.callTool('circ_get_status', {});
    expect(!suspended.ok && suspended.error.code).toBe('PAGE_SUSPENDED');
    tools.resume();
    expect((await tools.callTool('circ_get_status', {})).ok).toBe(true);
    tools.dispose();
    const disposed = await tools.callTool('circ_get_status', {});
    expect(!disposed.ok && disposed.error.code).toBe('PAGE_DISPOSED');
  });

  test('workspace_descriptors_validate_declared_arguments_and_preserve_domain_errors', async () => {
    const tools = new AgentToolRegistry('page-test', [{
      descriptor: readFileDescriptor,
      handler: (input) => input.name === 'missing.circ'
        ? { ok: false, error: { code: 'FILE_NOT_FOUND', message: 'missing', retryable: false } }
        : { ok: true, value: { name: input.name } },
    }]);
    expect(await tools.callTool('circ_read_file', {})).toMatchObject({ ok: false, error: { code: 'INVALID_ARGUMENT' } });
    expect(await tools.callTool('circ_read_file', { name: 'missing.circ' })).toMatchObject({ ok: false, error: { code: 'FILE_NOT_FOUND' } });
    expect(await tools.callTool('circ_read_file', { name: 'main.circ', extra: true })).toMatchObject({ ok: false, error: { code: 'INVALID_ARGUMENT' } });
  });
});
