import type { NativeConnectionState, ToolDescriptor, ToolResult } from './playground-contract.ts';
import type { AgentToolRegistry } from './agent-tools/registry.ts';

export interface NativeRegistration {
  dispose(): Promise<void>;
}

export interface NativeRegistrar {
  readonly apiVariant: string;
  register(
    descriptor: ToolDescriptor,
    invoke: (input: unknown) => Promise<ToolResult<unknown>>,
    signal: AbortSignal,
  ): Promise<NativeRegistration>;
}

export interface NativeConnectionStatus {
  state: NativeConnectionState;
  apiVariant: string | null;
  reason: string | null;
}

export class WebMcpAdapter {
  private generation = 0;
  private abort: AbortController | null = null;
  private registrations: NativeRegistration[] = [];
  private cleanup: Promise<void> = Promise.resolve();
  private current: NativeConnectionStatus;

  constructor(private readonly registry: AgentToolRegistry, private readonly registrar: NativeRegistrar | null) {
    this.current = registrar
      ? { state: 'not-configured', apiVariant: registrar.apiVariant, reason: null }
      : { state: 'unsupported', apiVariant: null, reason: 'No supported native WebMCP API is available.' };
  }

  status(): NativeConnectionStatus {
    return { ...this.current };
  }

  async start(): Promise<void> {
    if (!this.registrar) return;
    const generation = ++this.generation;
    this.abort?.abort();
    await this.clearRegistration();
    if (generation !== this.generation) return;
    const abort = new AbortController();
    this.abort = abort;
    this.current = { state: 'registering', apiVariant: this.registrar.apiVariant, reason: null };
    try {
      const descriptors = this.registry.descriptors();
      if (descriptors.length === 0) throw new Error('No tools are available for native registration.');
      const registrations = await Promise.all(descriptors.map((descriptor) =>
        this.registrar!.register(descriptor, (input) => this.registry.callTool(descriptor.name, input), abort.signal)));
      if (generation !== this.generation || abort.signal.aborted) {
        await Promise.all(registrations.map((registration) => registration.dispose()));
        return;
      }
      this.registrations = registrations;
      this.current = { state: 'registered', apiVariant: this.registrar.apiVariant, reason: null };
    } catch (error) {
      if (generation !== this.generation || abort.signal.aborted) return;
      this.current = { state: 'failed', apiVariant: this.registrar.apiVariant, reason: message(error) };
    }
  }

  async suspend(): Promise<void> {
    if (!this.registrar) return;
    this.generation += 1;
    this.abort?.abort();
    await this.clearRegistration();
    this.current = { state: 'suspended', apiVariant: this.registrar.apiVariant, reason: null };
  }

  async resume(): Promise<void> {
    if (!this.registrar) return;
    await this.start();
  }

  async dispose(): Promise<void> {
    this.generation += 1;
    this.abort?.abort();
    await this.clearRegistration();
  }

  private async clearRegistration(): Promise<void> {
    const registrations = this.registrations;
    this.registrations = [];
    if (registrations.length === 0) return this.cleanup;
    this.cleanup = this.cleanup.then(() => Promise.all(registrations.map((registration) => registration.dispose())).then(() => undefined)).catch(() => undefined);
    await this.cleanup;
  }
}

function message(error: unknown): string {
  return error instanceof Error && error.message
    ? error.message.slice(0, 240)
    : 'Native WebMCP registration failed.';
}

/**
 * Browser WebMCP is intentionally opt-in: no unverified global shape is
 * treated as a native implementation. Phase 0 records the concrete adapter
 * before supplying a registrar for a supported browser product.
 */
export function detectNativeRegistrar(): NativeRegistrar | null {
  const documentContext = (globalThis.document as Document & { modelContext?: ModelContextLike } | undefined)?.modelContext;
  const navigatorContext = (globalThis.navigator as Navigator & { modelContext?: ModelContextLike } | undefined)?.modelContext;
  const context = documentContext ?? navigatorContext;
  if (!context || typeof context.registerTool !== 'function') return null;
  return {
    apiVariant: documentContext ? 'document.modelContext.registerTool' : 'navigator.modelContext.registerTool',
    async register(descriptor, invoke, signal) {
      const controller = new AbortController();
      const abort = () => controller.abort();
      signal.addEventListener('abort', abort, { once: true });
      try {
        await context.registerTool({
          name: descriptor.name,
          description: descriptor.description,
          inputSchema: descriptor.inputSchema,
          async execute(input: unknown) {
            const result = await invoke(input);
            return { content: [{ type: 'text', text: JSON.stringify(result) }] };
          },
        }, { signal: controller.signal });
      } catch (error) {
        signal.removeEventListener('abort', abort);
        throw error;
      }
      return {
        async dispose() {
          signal.removeEventListener('abort', abort);
          controller.abort();
        },
      };
    },
  };
}

interface ModelContextLike {
  registerTool(
    tool: {
      name: string;
      description: string;
      inputSchema: ToolDescriptor['inputSchema'];
      execute(input: unknown): Promise<{ content: { type: 'text'; text: string }[] }>;
    },
    options: { signal: AbortSignal },
  ): Promise<unknown>;
}
