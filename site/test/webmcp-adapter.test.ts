import { describe, expect, test } from 'bun:test';
import { AgentToolRegistry } from '../src/scripts/agent-tools/registry.ts';
import { statusDescriptor } from '../src/scripts/agent-tools/status.ts';
import { WebMcpAdapter, detectNativeRegistrar, type NativeRegistrar, type NativeRegistration } from '../src/scripts/webmcp-adapter.ts';

function tools() {
  return new AgentToolRegistry('page-test', [{ descriptor: statusDescriptor, handler: () => ({ ready: true }) }]);
}

function registrar(overrides: Partial<NativeRegistrar> = {}) {
  const registrations: NativeRegistration[] = [];
  const native: NativeRegistrar = {
    apiVariant: 'test-native',
    async register(_descriptor, _invoke, _signal) {
      const registration = { dispose: async () => {} };
      registrations.push(registration);
      return registration;
    },
    ...overrides,
  };
  return { native, registrations };
}

describe('WebMCP adapter', () => {
  test('detects document and navigator model contexts', () => {
    const originalDocument = globalThis.document;
    const originalNavigator = globalThis.navigator;
    const documentRegister = async () => {};
    const navigatorRegister = async () => {};
    try {
      (globalThis as { document?: unknown }).document = { modelContext: { registerTool: documentRegister } };
      (globalThis as { navigator?: unknown }).navigator = { modelContext: { registerTool: navigatorRegister } };
      expect(detectNativeRegistrar()?.apiVariant).toBe('document.modelContext.registerTool');
      (globalThis as { document?: unknown }).document = {};
      expect(detectNativeRegistrar()?.apiVariant).toBe('navigator.modelContext.registerTool');
    } finally {
      (globalThis as { document?: unknown }).document = originalDocument;
      (globalThis as { navigator?: unknown }).navigator = originalNavigator;
    }
  });

  test('missing_native_api_keeps_page_registry', async () => {
    const registry = tools();
    const adapter = new WebMcpAdapter(registry, null);
    await adapter.start();
    expect(adapter.status().state).toBe('unsupported');
    expect((await registry.callTool('circ_get_status', {})).ok).toBe(true);
  });

  test('native_registration_failure_is_isolated', async () => {
    const registry = tools();
    const { native } = registrar({ register: async () => { throw new Error('no registration'); } });
    const adapter = new WebMcpAdapter(registry, native);
    await adapter.start();
    expect(adapter.status()).toMatchObject({ state: 'failed', reason: 'no registration' });
    expect((await registry.callTool('circ_get_status', {})).ok).toBe(true);
  });

  test('native_and_page_calls_share_dispatch', async () => {
    const registry = tools();
    let invoke: ((input: unknown) => Promise<unknown>) | null = null;
    const { native } = registrar({
      register: async (_descriptor, callback) => {
        invoke = callback;
        return { dispose: async () => {} };
      },
    });
    const adapter = new WebMcpAdapter(registry, native);
    await adapter.start();
    expect(await invoke!({})).toEqual(await registry.callTool('circ_get_status', {}));
    expect(await invoke!({ bad: true })).toEqual(await registry.callTool('circ_get_status', { bad: true }));
  });

  test('late_registration_cannot_revive_disposed_tools', async () => {
    const registry = tools();
    let resolve!: (registration: NativeRegistration) => void;
    let registered!: () => void;
    const pending = new Promise<NativeRegistration>((done) => { resolve = done; });
    const called = new Promise<void>((done) => { registered = done; });
    let disposed = 0;
    const { native } = registrar({ register: () => { registered(); return pending; } });
    const adapter = new WebMcpAdapter(registry, native);
    const starting = adapter.start();
    await called;
    await adapter.dispose();
    resolve({ dispose: async () => { disposed += 1; } });
    await starting;
    expect(disposed).toBe(1);
    expect(adapter.status().state).not.toBe('registered');
  });
});
