import type { PlaygroundController, ToolDescriptor } from '../playground-contract.ts';

const text = { type: 'string' } as const;
const num = { type: 'number' } as const;
export const compileDescriptor: ToolDescriptor = { name: 'circ_compile', description: 'Start, join, or reuse exact-input analyze and compile operations for the visible entry. Read status first, then wait for compile.operationId.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: text, expectedSourceRevision: text, expectedTargetEpoch: text, expectedOptionsRevision: text }, required: ['projectId', 'expectedSourceRevision', 'expectedTargetEpoch', 'expectedOptionsRevision'], additionalProperties: false } };
export const diagnosticsDescriptor: ToolDescriptor = { name: 'circ_get_diagnostics', description: 'Read a bounded structured diagnostic page for a completed analyze or compile operation. Wait for the operation first.', readOnly: true, inputSchema: { type: 'object', properties: { operationId: text, expectedSourceRevision: text, cursor: text, limit: num }, required: ['operationId'], additionalProperties: false } };
export function compilerHandlers(controller: PlaygroundController) {
  return {
    compile: (input: Record<string, unknown>) => controller.compile(input as Parameters<PlaygroundController['compile']>[0]),
    diagnostics: (input: Record<string, unknown>) => controller.getDiagnostics(input as Parameters<PlaygroundController['getDiagnostics']>[0]),
  };
}
