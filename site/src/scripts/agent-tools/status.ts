import type { PlaygroundController, ToolDescriptor } from '../playground-contract.ts';

export const statusDescriptor: ToolDescriptor = {
  name: 'circ_get_status',
  description: 'Read the open circ playground project, revision-aware output freshness, operation identities, session state, and compiler transport. This operation does not compile or change the project.',
  inputSchema: { type: 'object', properties: {}, required: [], additionalProperties: false },
  readOnly: true,
};

export function statusHandler(controller: PlaygroundController): () => unknown {
  return () => controller.getStatus();
}
