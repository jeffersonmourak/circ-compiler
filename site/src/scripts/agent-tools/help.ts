import type { DomainResult, ToolDescriptor } from '../playground-contract.ts';
import type { CompilerIdentity, HelpInput } from '../knowledge-contract.ts';

export const helpDescriptor: ToolDescriptor = {
  name: 'circ_help',
  description: 'Search and read the shipped circ reference, compiler diagnostics, and complete examples. Lookup is read-only and does not change the active project.',
  inputSchema: {
    type: 'object', properties: {
      action: { type: 'string', enum: ['search', 'read', 'example'] }, query: { type: 'string' }, kind: { type: 'string' }, limit: { type: 'number' }, cursor: { type: 'string' }, id: { type: 'string' }, offset: { type: 'number' }, maxCodeUnits: { type: 'number' }, expectedCorpusId: { type: 'string' },
    }, required: ['action'], additionalProperties: false,
  }, readOnly: true,
};

export interface HelpToolOptions { manifestUrl: string; corpusId: string; compilerIdentity: () => Partial<CompilerIdentity> | null; }
export function helpHandler(options: HelpToolOptions): (input: Record<string, unknown>) => Promise<DomainResult<unknown>> {
  let client: import('../knowledge-client.ts').KnowledgeClient | null = null;
  const invalid = (message: string): DomainResult<never> => ({ ok: false, error: { code: 'INVALID_ARGUMENT', message, retryable: false } });
  return async (input) => {
    const action = input.action;
    if (action !== 'search' && action !== 'read' && action !== 'example') return invalid('action must be search, read, or example.');
    const allowed = action === 'search' ? ['action', 'query', 'kind', 'limit', 'cursor', 'expectedCorpusId'] : action === 'read' ? ['action', 'id', 'offset', 'maxCodeUnits', 'expectedCorpusId'] : ['action', 'id', 'expectedCorpusId'];
    if (Object.keys(input).some((key) => !allowed.includes(key))) return invalid('The input includes fields for another help action.');
    if ((action === 'search' && typeof input.query !== 'string') || (action !== 'search' && typeof input.id !== 'string')) return invalid(action === 'search' ? 'search requires query.' : `${action} requires id.`);
    client ??= new (await import('../knowledge-client.ts')).KnowledgeClient(options);
    if (action === 'search') return client.search(input as HelpInput & { action: 'search' });
    if (action === 'read') return client.read(input as HelpInput & { action: 'read' });
    return client.example(input as HelpInput & { action: 'example' });
  };
}
