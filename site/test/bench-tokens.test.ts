// Every colour and every face in a playground rule is a token.
//
// The bench is drawn on CircDS tokens (`--bg`, `--pane-bg`, `--code-bg`,
// `--pane-label-bg`, `--fg`, `--muted`, `--accent`, `--accent-soft`,
// `--border`, the three font stacks) plus the site's own terminal tokens
// (`--term-ok`, `--term-echo`, `--danger`). A literal hex in a `.pg-` rule
// is a colour that stops following the theme, and a named face is a font the
// site does not ship. Neither shows up in a build, so this holds them the way
// `circ-skins.test.ts` holds "every colour a skin sets comes from the
// palette": by reading the stylesheet.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const css = readFileSync(resolve(import.meta.dir, '..', 'src', 'styles', 'global.css'), 'utf8');

interface Rule {
  selector: string;
  declarations: { property: string; value: string }[];
}

/** Every `selector { declarations }` pair, comments stripped, at-rule preludes
 *  skipped so `@media (...)` is not read as a selector. Nested blocks are
 *  flattened: a rule inside a media query is still a rule. */
function rulesOf(source: string): Rule[] {
  const body = source.replace(/\/\*[\s\S]*?\*\//g, '');
  const out: Rule[] = [];
  const re = /([^{}]+)\{([^{}]*)\}/g;
  for (let m = re.exec(body); m; m = re.exec(body)) {
    const selector = m[1].trim().replace(/\s+/g, ' ');
    if (!selector || selector.startsWith('@')) continue;
    const declarations = m[2]
      .split(';')
      .map((d) => d.trim())
      .filter((d) => d.includes(':'))
      .map((d) => {
        const at = d.indexOf(':');
        return { property: d.slice(0, at).trim(), value: d.slice(at + 1).trim() };
      });
    out.push({ selector, declarations });
  }
  return out;
}

const benchRules = rulesOf(css).filter((r) => r.selector.includes('.pg-'));

/** The properties that carry a colour. `border` and its sides are shorthands
 *  whose colour is the only token-bearing part; the widths and styles pass. */
const COLOUR_PROPERTIES = new Set([
  'color',
  'background',
  'background-color',
  'background-image',
  'border',
  'border-top',
  'border-right',
  'border-bottom',
  'border-left',
  'border-color',
  'border-top-color',
  'border-right-color',
  'border-bottom-color',
  'border-left-color',
  'outline',
  'outline-color',
  'fill',
  'stroke',
  'box-shadow',
  'caret-color',
  'text-decoration-color',
]);

/** A colour literal: hex, a functional colour that is not a token expression,
 *  or a named colour. `transparent`, `currentColor`, `inherit` and `none` are
 *  keywords, not colours. */
const LITERAL = /#[0-9a-f]{3,8}\b|\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch)\(|\b(?:white|black|red|green|blue|yellow|orange|purple|gray|grey|pink)\b/i;

/** A shadow may carry a black at some alpha: that is a shade of the surface
 *  under it, not a colour of its own, and the design file draws every shadow
 *  that way (`0 12px 32px rgba(0,0,0,.28)`). */
const BLACK_SHADOW = /\brgba?\(\s*0\s*[, ]\s*0\s*[, ]\s*0\s*(?:[,/]\s*[0-9.]+\s*)?\)/gi;

function offending(rule: Rule): string[] {
  const out: string[] = [];
  for (const { property, value } of rule.declarations) {
    if (COLOUR_PROPERTIES.has(property)) {
      const stripped = property === 'box-shadow' ? value.replace(BLACK_SHADOW, '') : value;
      if (LITERAL.test(stripped)) out.push(`${rule.selector} → ${property}: ${value}`);
    }
    if (property === 'font-family' || property === 'font') {
      // `font` shorthand carries a size and a family; the family is what is
      // held. A `var(--font-…)` token or `inherit` is the whole allowance.
      const families = value.replace(/var\(--font-(?:prose|mono|mono-strict)\)/g, '');
      if (/['"]|\b(?:monospace|sans-serif|serif|system-ui|ui-monospace|Menlo|Monaco|Consolas|Arial|Helvetica)\b/.test(families)) {
        out.push(`${rule.selector} → ${property}: ${value}`);
      }
    }
  }
  return out;
}

describe('bench tokens', () => {
  test('the guard sees the rules', () => {
    // A regex that silently matched nothing would pass every assertion below.
    expect(benchRules.length).toBeGreaterThan(100);
  });

  test('every colour in a .pg- rule is a token', () => {
    const failures = benchRules.flatMap(offending).filter((f) => !/→ font/.test(f));
    expect(failures).toEqual([]);
  });

  test('every face in a .pg- rule is a token', () => {
    const failures = benchRules.flatMap(offending).filter((f) => /→ font/.test(f));
    expect(failures).toEqual([]);
  });

  test('the allowances are what they say', () => {
    // A black shadow passes; a coloured one, a hex, a named face do not.
    const pass: Rule = { selector: '.pg-x', declarations: [{ property: 'box-shadow', value: '0 12px 32px rgba(0, 0, 0, 0.28)' }] };
    expect(offending(pass)).toEqual([]);
    const tokens: Rule = {
      selector: '.pg-x',
      declarations: [
        { property: 'color', value: 'var(--fg)' },
        { property: 'background', value: 'color-mix(in srgb, var(--accent) 18%, transparent)' },
        { property: 'border', value: '1px solid var(--border)' },
        { property: 'font-family', value: 'var(--font-mono-strict)' },
      ],
    };
    expect(offending(tokens)).toEqual([]);
    const fail: Rule = {
      selector: '.pg-x',
      declarations: [
        { property: 'box-shadow', value: '0 0 0 3px rgba(110, 73, 171, 0.18)' },
        { property: 'color', value: '#e5484d' },
        { property: 'font-family', value: '"JetBrains Mono", monospace' },
      ],
    };
    expect(offending(fail)).toHaveLength(3);
  });
});
