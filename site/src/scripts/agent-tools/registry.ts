import {
  AGENT_API_VERSION,
  MAX_AGENT_INPUT_BYTES,
  MAX_TOOL_RESULT_BYTES,
  type AgentError,
  type AgentErrorCode,
  type ToolCatalogue,
  type ToolDescriptor,
  type ToolResult,
} from '../playground-contract.ts';
import { ControllerDisposedError } from '../playground-controller.ts';
import type { DomainResult } from '../playground-contract.ts';

export interface RegisteredTool {
  descriptor: ToolDescriptor;
  handler: (input: Record<string, unknown>) => unknown | Promise<unknown>;
}

export interface AgentActivity {
  activeRequests: number;
  lastRequestAt: number;
  lastTool: string | null;
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

function matchesSchema(schema: unknown, value: unknown): boolean {
  if (!isPlainObject(schema)) return false;
  if (schema.nullable === true && value === null) return true;
  if (Array.isArray(schema.oneOf)) return schema.oneOf.filter((option) => matchesSchema(option, value)).length === 1;
  if ('const' in schema && value !== schema.const) return false;
  switch (schema.type) {
    case 'string': return typeof value === 'string';
    case 'number': return typeof value === 'number' && Number.isFinite(value);
    case 'boolean': return typeof value === 'boolean';
    case 'array': {
      if (!Array.isArray(value)) return false;
      if (typeof schema.minItems === 'number' && value.length < schema.minItems) return false;
      if (typeof schema.maxItems === 'number' && value.length > schema.maxItems) return false;
      return !('items' in schema) || value.every((item) => matchesSchema(schema.items, item));
    }
    case 'object': {
      if (!isPlainObject(value)) return false;
      const properties = isPlainObject(schema.properties) ? schema.properties : null;
      const required = Array.isArray(schema.required) ? schema.required : [];
      if (required.some((key) => typeof key !== 'string' || !(key in value))) return false;
      if (!properties) return true;
      if (schema.additionalProperties === false && Object.keys(value).some((key) => !(key in properties))) return false;
      return Object.entries(value).every(([key, item]) => matchesSchema(properties[key], item));
    }
    default: return false;
  }
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
  private activeRequests = 0;
  private lastRequestAt = 0;
  private lastTool: string | null = null;

  constructor(readonly pageId: string, tools: readonly RegisteredTool[], private readonly onActivity?: (activity: AgentActivity) => void) {
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

  private validInput(descriptor: ToolDescriptor, input: unknown): input is Record<string, unknown> {
    return matchesSchema(descriptor.inputSchema, input);
  }

  async listTools(): Promise<ToolResult<ToolCatalogue>> {
    const gate = this.gate();
    if (gate) return gate;
    this.beginActivity(null);
    try {
      return this.normalize({
        apiVersion: AGENT_API_VERSION,
        pageId: this.pageId,
        tools: this.descriptors(),
      });
    } finally {
      this.endActivity();
    }
  }

  async callTool(name: string, input: unknown): Promise<ToolResult<unknown>> {
    const gate = this.gate();
    if (gate) return gate;
    this.beginActivity(name);
    try {
      const tool = this.tools.get(name);
      if (!tool) return this.error('UNKNOWN_TOOL', `Unknown tool: ${text(name, 'unknown')}.`);
      if (plainJson(input) && bytes(input) > MAX_AGENT_INPUT_BYTES) return this.error('INPUT_TOO_LARGE', 'The tool input exceeds the 128 KiB JSON limit.');
      if (!this.validInput(tool.descriptor, input)) {
        return this.error('INVALID_ARGUMENT', 'The tool input does not match its schema.');
      }
      try {
        const result = await tool.handler(input);
        if (isDomainResult(result)) {
          if (!result.ok) return { apiVersion: AGENT_API_VERSION, pageId: this.pageId, ok: false, error: copy(result.error) };
          return this.normalize(result.value);
        }
        return this.normalize(result);
      } catch (error) {
        if (error instanceof ControllerDisposedError) return this.error('PAGE_DISPOSED', error.message);
        return this.error('INTERNAL_ERROR', 'The tool could not complete.');
      }
    } finally {
      this.endActivity();
    }
  }

  private beginActivity(tool: string | null): void {
    this.activeRequests += 1;
    this.lastRequestAt = Date.now();
    this.lastTool = tool;
    this.emitActivity();
  }

  private endActivity(): void {
    this.activeRequests = Math.max(0, this.activeRequests - 1);
    this.emitActivity();
  }

  private emitActivity(): void {
    try {
      this.onActivity?.({ activeRequests: this.activeRequests, lastRequestAt: this.lastRequestAt, lastTool: this.lastTool });
    } catch {
      // Status UI failures must not affect agent calls.
    }
  }
}

function isDomainResult(value: unknown): value is DomainResult<unknown> {
  return isPlainObject(value) && typeof value.ok === 'boolean' && (value.ok ? 'value' in value : 'error' in value);
}
