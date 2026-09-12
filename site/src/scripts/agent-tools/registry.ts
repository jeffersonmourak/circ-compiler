import {
  AGENT_API_VERSION,
  MAX_TOOL_RESULT_BYTES,
  type AgentError,
  type AgentErrorCode,
  type ToolCatalogue,
  type ToolDescriptor,
  type ToolResult,
} from '../playground-contract.ts';
import { ControllerDisposedError } from '../playground-controller.ts';

export interface RegisteredTool {
  descriptor: ToolDescriptor;
  handler: (input: Record<string, never>) => unknown | Promise<unknown>;
}

const text = (value: unknown, fallback: string) =>
  typeof value === 'string' ? value.slice(0, 240) : fallback;

function plainJson(value: unknown, seen = new Set<object>()): boolean {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return true;
  if (typeof value === 'number') return Number.isFinite(value);
  if (Array.isArray(value)) return value.every((item) => plainJson(item, seen));
  if (typeof value !== 'object') return false;
  if (Object.getPrototypeOf(value) !== Object.prototype || seen.has(value as object)) return false;
  seen.add(value as object);
  const ok = Object.values(value as Record<string, unknown>).every((item) => plainJson(item, seen));
  seen.delete(value as object);
  return ok;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
}

function copy<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function bytes(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

export class AgentToolRegistry {
  private state: 'active' | 'suspended' | 'disposed' = 'active';
  private readonly tools = new Map<string, RegisteredTool>();

  constructor(readonly pageId: string, tools: readonly RegisteredTool[]) {
    for (const tool of tools) {
      if (this.tools.has(tool.descriptor.name)) throw new Error(`Duplicate agent tool: ${tool.descriptor.name}`);
      this.tools.set(tool.descriptor.name, { descriptor: copy(tool.descriptor), handler: tool.handler });
    }
  }

  suspend(): void { if (this.state !== 'disposed') this.state = 'suspended'; }
  resume(): void { if (this.state === 'suspended') this.state = 'active'; }
  dispose(): void { this.state = 'disposed'; }

  descriptors(): ToolDescriptor[] {
    return [...this.tools.values()].map((tool) => copy(tool.descriptor));
  }

  private error(code: AgentErrorCode, message: string, retryable = false): ToolResult<never> {
    const error: AgentError = { code, message: message.slice(0, 240), retryable };
    return { apiVersion: AGENT_API_VERSION, pageId: this.pageId, ok: false, error };
  }

  private gate(): ToolResult<never> | null {
    if (this.state === 'suspended') return this.error('PAGE_SUSPENDED', 'The page is suspended. Retry after it is visible again.', true);
    if (this.state === 'disposed') return this.error('PAGE_DISPOSED', 'The page was disposed. Rediscover its tools after reload.');
    return null;
  }

  private normalize<T>(data: T): ToolResult<T> {
    if (!plainJson(data)) return this.error('INTERNAL_ERROR', 'The tool produced a non-JSON-safe result.') as ToolResult<T>;
    const result: ToolResult<T> = { apiVersion: AGENT_API_VERSION, pageId: this.pageId, ok: true, data: copy(data) };
    return bytes(result) <= MAX_TOOL_RESULT_BYTES
      ? result
      : this.error('RESULT_TOO_LARGE', 'The tool result exceeds the response limit.') as ToolResult<T>;
  }

  async listTools(): Promise<ToolResult<ToolCatalogue>> {
    const gate = this.gate();
    if (gate) return gate;
    return this.normalize({
      apiVersion: AGENT_API_VERSION,
      pageId: this.pageId,
      tools: this.descriptors(),
    });
  }

  async callTool(name: string, input: unknown): Promise<ToolResult<unknown>> {
    const gate = this.gate();
    if (gate) return gate;
    const tool = this.tools.get(name);
    if (!tool) return this.error('UNKNOWN_TOOL', `Unknown tool: ${text(name, 'unknown')}.`);
    if (!isPlainObject(input) || Object.keys(input).length !== 0) {
      return this.error('INVALID_ARGUMENT', 'This tool accepts exactly an empty object.');
    }
    try {
      return this.normalize(await tool.handler(input as Record<string, never>));
    } catch (error) {
      if (error instanceof ControllerDisposedError) return this.error('PAGE_DISPOSED', error.message);
      return this.error('INTERNAL_ERROR', 'The tool could not complete.');
    }
  }
}
