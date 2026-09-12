import { describe, expect, test } from 'bun:test';
import { decodeCursor, encodeCursor, search } from '../src/scripts/knowledge-search.ts';
import type { KnowledgeIndex } from '../src/scripts/knowledge-contract.ts';

const citation = { sourcePath: 'DOCS/language.md', sourceHash: 'a', startLine: 1, endLine: 2, htmlPath: '/reference', markdownPath: '/reference.md', heading: 'x' };
const index: KnowledgeIndex = {
  schemaVersion: 1, corpusId: 'corpus', aliases: {}, removed: {}, resources: {}, records: [
    { id: 'ref:language:multi-bit-wires', kind: 'reference', title: 'Multi-bit wires', parentId: null, relatedIds: [], citation, shardKey: 'language', headingPath: [], tags: [], excerpt: 'width', directContentLength: 50, terms: { title: { width: 1 }, headings: {}, tags: {}, prose: { width: 1 }, code: {} } },
    { id: 'diagnostic:E014', kind: 'diagnostic', title: 'E014: width mismatch', parentId: null, relatedIds: [], citation, shardKey: 'circuit-format', headingPath: [], tags: [], excerpt: 'width mismatch', directContentLength: 20, terms: { title: { e014: 1, width: 1, mismatch: 1 }, headings: {}, tags: {}, prose: { e014: 1, width: 1 }, code: {} } },
  ],
};
describe('knowledge search', () => {
  test('exact diagnostic is ranked first and unknown codes are not invented', () => {
    expect(search(index, 'how do I fix e014', 'diagnostic')[0].id).toBe('diagnostic:E014');
    expect(search(index, 'E999', 'diagnostic')).toEqual([]);
  });
  test('cursor binds corpus query and filter', () => {
    const cursor = encodeCursor('corpus', 'width', 'reference', 1);
    expect(decodeCursor(cursor)).toEqual(['corpus', 'width', 'reference', 1]);
  });
});
