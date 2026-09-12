import type { PlaygroundController, ToolDescriptor } from '../playground-contract.ts';

export const waitForOperationDescriptor: ToolDescriptor = {
  name: 'circ_wait_for_operation',
  description: 'Wait for an existing playground operation to finish. This never starts, restarts, or changes work.',
  inputSchema: {
    type: 'object',
    properties: { operationId: { type: 'string' }, timeoutMs: { type: 'number' } },
    required: ['operationId'], additionalProperties: false,
  },
  readOnly: true,
};

export function waitForOperationHandler(controller: PlaygroundController) {
  return (input: Record<string, unknown>) => controller.waitForOperation(input as { operationId: string; timeoutMs?: number });
}
