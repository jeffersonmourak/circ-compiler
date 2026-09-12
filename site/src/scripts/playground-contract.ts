export const AGENT_API_VERSION = 1 as const;
export const MAX_TOOL_RESULT_BYTES = 32 * 1024;

export type AgentErrorCode =
  | 'UNKNOWN_TOOL'
  | 'INVALID_ARGUMENT'
  | 'PAGE_SUSPENDED'
  | 'PAGE_DISPOSED'
  | 'RESULT_TOO_LARGE'
  | 'INTERNAL_ERROR';

export interface AgentError {
  code: AgentErrorCode;
  message: string;
  retryable: boolean;
}

export type ToolResult<T> = {
  apiVersion: 1;
  pageId: string;
} & ({ ok: true; data: T } | { ok: false; error: AgentError });

export interface ToolDescriptor {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties: Record<string, unknown>;
    required: string[];
    additionalProperties: false;
  };
  readOnly: boolean;
}

export interface ToolCatalogue {
  apiVersion: 1;
  pageId: string;
  tools: ToolDescriptor[];
}

export interface PlaygroundPageApi {
  readonly apiVersion: 1;
  readonly pageId: string;
  listTools(): Promise<ToolResult<ToolCatalogue>>;
  callTool(name: string, input: unknown): Promise<ToolResult<unknown>>;
}

export type NativeConnectionState =
  | 'not-configured'
  | 'checking'
  | 'unsupported'
  | 'registering'
  | 'registered'
  | 'failed'
  | 'suspended';

export interface PlaygroundStatus {
  lifecycle: 'initializing' | 'ready' | 'failed';
  bootstrapError: string | null;
  project: { id: string; name: string; entryFile: string; fileCount: number } | null;
  view: 'schematic' | 'live' | 'truth';
  compiler: {
    ready: boolean;
    loading: boolean;
    identity: {
      version: string;
      revision: string;
      topologyVersion: number;
      fullVersion: number;
      grammarSha256: string;
    } | null;
    simulationCompatible: boolean | null;
  };
  reportedPipeline: {
    kind: 'idle' | 'loading' | 'compiling' | 'live' | 'error';
    analyzing: boolean;
    building: boolean;
    analyzePending: boolean;
    buildPending: boolean;
    errors: number;
    warnings: number;
    stale: boolean;
    failure: string | null;
  };
  artifact: { present: boolean; bytes: number | null };
  session: { present: boolean };
  provenance: {
    tracking: 'untracked';
    sourceRevision: string | null;
    buildRevision: string | null;
    sessionId: string | null;
  };
  persistence: { enabled: boolean };
  agentAccess: {
    pageRegistry: 'available';
    native: { state: NativeConnectionState; apiVariant: string | null; reason: string | null };
  };
}

export interface StatusReader {
  read(): PlaygroundStatus;
}

export interface PlaygroundController {
  getStatus(): PlaygroundStatus;
  dispose(): void;
}
