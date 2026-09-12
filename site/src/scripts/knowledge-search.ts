import type { IndexedRecord, KnowledgeIndex, SearchKind } from './knowledge-contract.ts';
import { topicSynonyms } from '../content/agent-reference.ts';

const stop = new Set(['a', 'an', 'the', 'how', 'do', 'does', 'i', 'is', 'are', 'of', 'to', 'for', 'with', 'please', 'what']);
export function tokens(value: string): string[] {
  return [...new Set((value.normalize('NFKC').toLowerCase().match(/[\p{L}\p{N}_]+/gu) ?? []).flatMap((token) => token.includes('_') ? [token, ...token.split('_')] : [token]).filter((token) => !stop.has(token)))];
}
function score(record: IndexedRecord, original: string[], all: string[]): [number, number] {
  let points = 0; let coverage = 0;
  for (const term of all) {
    const originalTerm = original.includes(term);
    let count = 0;
    for (const [field, weight] of [['title', 8], ['tags', 6], ['headings', 4], ['prose', 2], ['code', 2]] as const) count += Math.min(record.terms[field][term] ?? 0, 3) * weight;
    if (count) points += count * (originalTerm ? 1 : .5);
  }
  for (const term of original) if (Object.values(record.terms).some((terms) => terms[term])) coverage++;
  return [points + coverage * 12, coverage];
}
export function search(index: KnowledgeIndex, query: string, kind?: SearchKind): IndexedRecord[] {
  const original = tokens(query); if (!original.length) return [];
  const expanded = [...new Set(original.flatMap((term) => [term, ...(topicSynonyms[term] ?? [])]))];
  const exactCode = original.find((term) => /^[ew]\d{3}$/i.test(term))?.toUpperCase();
  return index.records.filter((record) => !kind || record.kind === kind).map((record) => ({ record, rank: score(record, original, expanded) }))
    .filter(({ rank }) => rank[1] > 0)
    .sort((a, b) => (exactCode && a.record.id === `diagnostic:${exactCode}` ? -1 : exactCode && b.record.id === `diagnostic:${exactCode}` ? 1 : b.rank[0] - a.rank[0] || b.rank[1] - a.rank[1] || a.record.directContentLength - b.record.directContentLength || a.record.id.localeCompare(b.record.id)))
    .map(({ record }) => record);
}
export function encodeCursor(corpusId: string, query: string, kind: SearchKind | undefined, offset: number): string { return btoa(JSON.stringify([corpusId, query.normalize('NFKC').toLowerCase(), kind ?? null, offset])); }
export function decodeCursor(value: string): [string, string, SearchKind | null, number] | null { try { const x: unknown = JSON.parse(atob(value)); return Array.isArray(x) && x.length === 4 && typeof x[0] === 'string' && typeof x[1] === 'string' && (x[2] === null || x[2] === 'reference' || x[2] === 'diagnostic' || x[2] === 'example') && Number.isSafeInteger(x[3]) ? [x[0], x[1], x[2], x[3]] : null; } catch { return null; } }
