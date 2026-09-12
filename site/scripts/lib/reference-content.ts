import type { Doc } from './site-config.ts';

/** Keep page sync, Markdown twins, and corpus extraction on one canonical body rule. */
export function stripDocumentTitle(body: string): string { return body.replace(/^# .+\n+/, ''); }
export function publicDocPath(doc: Doc): string { return `/${doc.dst.replace(/\.md$/, '')}`; }
export function markdownDocPath(doc: Doc): string { return `/${doc.dst}`; }
