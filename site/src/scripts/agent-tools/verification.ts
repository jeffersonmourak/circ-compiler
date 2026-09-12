import type { PlaygroundController, ToolDescriptor } from '../playground-contract.ts';
const string = { type: 'string' } as const;
const number = { type: 'number' } as const;
const boolean = { type: 'boolean' } as const;
export const runVerificationDescriptor: ToolDescriptor = { name: 'circ_run_verification', description: 'Run bounded cases in disposable sessions. It never changes live pins, memory, views, storage, or the console.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: string, expectedSourceRevision: string, expectedTargetEpoch: string, expectedArtifactId: string, expectedImageRevision: string, timeoutMs: number, stopOnFailure: boolean, cases: { type: 'array' } }, required: ['projectId', 'expectedSourceRevision', 'expectedTargetEpoch', 'expectedArtifactId', 'expectedImageRevision', 'cases'], additionalProperties: false } };
export const getVerificationDescriptor: ToolDescriptor = { name: 'circ_get_verification', description: 'Read a bounded page of a completed isolated verification result.', readOnly: true, inputSchema: { type: 'object', properties: { operationId: string, cursor: string, limit: number }, required: ['operationId'], additionalProperties: false } };
export function verificationHandlers(controller: PlaygroundController) {
  return {
    run: (input: Record<string, unknown>) => controller.runVerification(input as unknown as Parameters<PlaygroundController['runVerification']>[0]),
    get: (input: Record<string, unknown>) => controller.getVerification(input as Parameters<PlaygroundController['getVerification']>[0]),
  };
}
