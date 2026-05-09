// Examples gallery. Mix of small (single gate), medium (adders, mux), and
// stateful (latches). Every entry now has a real `--preview` output (compiled
// from the source field by `scripts/compile-content.ts`) and a matching
// `<slug>.wasm` artifact under `public/wasm/` for live in-page simulation.
//
// To regenerate:
//   1. From the repo root: `zig build circ-compile`
//   2. From site/:         `bun run scripts/compile-content.ts`
//   3. Paste the new previews from `scripts/.compiled.json` back into this file.

export interface Example {
  slug: string;
  title: string;
  lede: string;
  source: string;
  preview: string;
  /** Path inside the circ-compiler repo, relative to the repo root. */
  repoPath?: string;
  /** Pre-compiled WASM filename under public/wasm/, enabling live simulation. */
  wasm?: string;
}

export const examples: Example[] = [
  {
    slug: 'inverter',
    title: 'Inverter',
    lede: 'A single NOT gate, the smallest non-trivial circuit you can write.',
    source: `input a
not n(in=a)
output out(in=n.out)
`,
    preview: `╭───╮     ╭───╮     ╭─────╮
│ a ├○───▶┤NOT├○───▶┤ out │
╰───╯     ╰───╯     ╰─────╯`,
    wasm: 'inverter.wasm',
  },
  {
    slug: 'and-not',
    title: 'AND with one inverted input',
    lede: 'Combines a NOT and an AND to compute `a AND (NOT b)`.',
    source: `input a
input b
not inv(in=b)
and gate1(a=a, b=inv.out)
output out(in=gate1.out)
`,
    preview: `╭───╮     ╭───╮     ╭───╮     ╭─────╮
│ a ├○┬──▶┤NOT├○╮ ╭▶┤   │ ╭──▶┤ out │
╰───╯ │   ╰───╯ │ │ │AND├○╯   ╰─────╯
      ├─────────┴─┴▶┤   │
      │             ╰───╯
      │
╭───╮ │
│ b ├○╯
╰───╯                                `,
    wasm: 'and-not.wasm',
  },
  {
    slug: 'fan-out',
    title: 'One input, three destinations',
    lede: 'A single input drives three independent NOT gates. The `●` glyphs in the ASCII preview mark fan-out taps where the same wire is reused.',
    source: `input a
not n1(in=a)
not n2(in=a)
not n3(in=a)
output o1(in=n1.out)
output o2(in=n2.out)
output o3(in=n3.out)
`,
    preview: `╭───╮     ╭───╮     ╭────╮
│ a ├●●──▶┤NOT├○───▶┤ o1 │
╰───╯ │   ╰───╯     ╰────╯
      │
      │   ╭───╮     ╭────╮
      ●──▶┤NOT├○───▶┤ o2 │
      │   ╰───╯     ╰────╯
      │
      │   ╭───╮     ╭────╮
      ╰──▶┤NOT├○───▶┤ o3 │
          ╰───╯     ╰────╯`,
    wasm: 'fan-out.wasm',
  },
  {
    slug: 'inverter-chain',
    title: 'NOT chain',
    lede: 'Three inverters in series. The output is just `a` — but the chain still gets compiled and simulated faithfully.',
    source: `input a
not n1(in=a)
not n2(in=n1.out)
not n3(in=n2.out)
output out(in=n3.out)
`,
    preview: `╭───╮     ╭───╮     ╭───╮     ╭───╮     ╭─────╮
│ a ├○───▶┤NOT├○───▶┤NOT├○───▶┤NOT├○───▶┤ out │
╰───╯     ╰───╯     ╰───╯     ╰───╯     ╰─────╯`,
    wasm: 'inverter-chain.wasm',
  },
  {
    slug: 'half-adder',
    title: 'Half-adder',
    lede: '`sum = a XOR b`, `carry = a AND b`. The simplest circuit that does arithmetic. Click "Run" — the `xor` macro expands into the gates you can see in the live canvas.',
    source: `import xor "<builtin>/xor.circ"
input a, b
xor s(a=a, b=b)
and c(a=a, b=b)
output sum(in=s.out)
output carry(in=c.out)
`,
    preview: `╭───╮     ╭───╮         ╭───────╮
│ a ├○─●─▶┤   │ ╭──────▶┤ carry │
╰───╯  │  │AND├○╯       ╰───────╯
      ╭┼─▶┤   │
      ││  ╰───╯
      ││
╭───╮ ││  ╭───────╮     ╭─────╮
│ b ├○●╰─▶┤       │ ╭──▶┤ sum │
╰───╯ │   │[xor:s]├○╯   ╰─────╯
      ╰──▶┤       │
          ╰───────╯`,
    wasm: 'half-adder.wasm',
  },
  {
    slug: 'mux-2to1',
    title: '2-to-1 multiplexer',
    lede: '`out = sel ? b : a`. Built from two ANDs that route the picked input through, an inverter for the selector, and an OR that combines them.',
    source: `// 2-to-1 multiplexer: out = sel ? b : a
// When sel=0 the gate routes 'a' through; when sel=1 it routes 'b'.
import or "<builtin>/or.circ"
input a, b, sel
not sel_inv(in=sel)
and pick_a(a=sel_inv.out, b=a)
and pick_b(a=sel, b=b)
or out_or(a=pick_a.out, b=pick_b.out)
output out(in=out_or.out)
`,
    preview: `╭───╮       ╭───╮     ╭───╮     ╭───────────╮     ╭─────╮
│ a ├○╮ ╭──▶┤NOT├○───▶┤   │ ╭──▶┤           │ ╭──▶┤ out │
╰───╯ │ │   ╰───╯     │AND├○╯   │[or:out_or]├○╯   ╰─────╯
      ╰─┼────────────▶┤   │   ╭▶┤           │
        │             ╰───╯   │ ╰───────────╯
        │                     │
╭─────╮ │   ╭───╮             │
│ sel ├○●──▶┤   │             │
╰─────╯     │AND├○────────────╯
       ╭───▶┤   │
       │    ╰───╯
       │
╭───╮  │
│ b ├○─╯
╰───╯                                                    `,
    wasm: 'mux-2to1.wasm',
  },
  {
    slug: 'full-adder',
    title: 'Full-adder',
    lede: 'Two XORs, two ANDs, one OR. Adds three bits (a, b, cin) into a sum bit and a carry-out.',
    source: `import xor "<builtin>/xor.circ"
import or  "<builtin>/or.circ"
input a, b, cin
xor s1(a=a, b=b)
xor s2(a=s1.out, b=cin)
and c1(a=a, b=b)
and c2(a=s1.out, b=cin)
or  c3(a=c1.out, b=c2.out)
output sum (in=s2.out)
output cout(in=c3.out)
`,
    preview: `╭───╮       ╭───╮          ╭───╮          ╭───────╮     ╭──────╮
│ a ├○─●───▶┤   │      ╭──▶┤   │        ╭▶┤       │ ╭──▶┤ cout │
╰───╯  │    │AND├○╮    │   │AND├○╮      │ │[or:c3]├○╯   ╰──────╯
      ╭┼───▶┤   │ │    │ ╭▶┤   │ ╰──────┼▶┤       │
      ││    ╰───╯ │    │ │ ╰───╯        │ ╰───────╯
      ││          ╰────┼─┼──────────────╯
╭───╮ ││    ╭────────╮ │ │ ╭────────╮                   ╭─────╮
│ b ├○●╰───▶┤        │ ●─┼▶┤        │ ╭────────────────▶┤ sum │
╰───╯ │     │[xor:s1]├○● │ │[xor:s2]├○╯                 ╰─────╯
      ╰────▶┤        │   ●▶┤        │
            ╰────────╯   │ ╰────────╯
                         │
╭─────╮                  │
│ cin ├○─────────────────●
╰─────╯                                                         `,
    wasm: 'full-adder.wasm',
  },
  {
    slug: 'two-bit-adder',
    title: '2-bit ripple-carry adder',
    lede: 'A half-adder for the low bit and a full-adder above it. The lower bit’s carry feeds into the upper bit’s `cin`.',
    source: `// 2-bit ripple-carry adder: (a1 a0) + (b1 b0) → (cout s1 s0)
import xor "<builtin>/xor.circ"
import or  "<builtin>/or.circ"
input a0, a1, b0, b1

// Lower bit (half adder)
xor s0_xor(a=a0, b=b0)
and s0_carry(a=a0, b=b0)

// Upper bit (full adder, cin = s0_carry.out)
xor s1_x1(a=a1, b=b1)
xor s1_x2(a=s1_x1.out, b=s0_carry.out)
and s1_a1(a=a1, b=b1)
and s1_a2(a=s1_x1.out, b=s0_carry.out)
or  s1_or(a=s1_a1.out, b=s1_a2.out)

output s0  (in=s0_xor.out)
output s1  (in=s1_x2.out)
output cout(in=s1_or.out)
`,
    preview: `╭────╮     ╭───╮              ╭───╮             ╭──────────╮     ╭──────╮
│ a1 ├○──●▶┤   │         ╭───▶┤   │           ╭▶┤          │ ╭──▶┤ cout │
╰────╯   │ │AND├○╮       │    │AND├○╮         │ │[or:s1_or]├○╯   ╰──────╯
       ╭─┼▶┤   │ ├───────┼───▶┤   │ ╰─────────┼▶┤          │
       │ │ ╰───╯ │       │    ╰───╯           │ ╰──────────╯
       │ │       ├───────┼────────────────────╯
╭────╮ │ │ ╭───╮ │       │    ╭───────────╮                      ╭────╮
│ b1 ├○●╭┼▶┤   │ │       ●───▶┤           │                    ╭▶┤ s0 │
╰────╯ │││ │AND├○●       │    │[xor:s1_x2]├○╮                  │ ╰────╯
       ││├▶┤   │ ╰───────┼───▶┤           │ │                  │
       │││ ╰───╯         │    ╰───────────╯ │                  │
       │││               │                  │                  │
╭────╮ │││ ╭───────────╮ │                  │                  │ ╭────╮
│ a0 ├○●●┼▶┤           │ │                  ╰──────────────────┼▶┤ s1 │
╰────╯ │││ │[xor:s1_x1]├○●                                     │ ╰────╯
       ╰┼┼▶┤           │                                       │
        ││ ╰───────────╯                                       │
        ││                                                     │
╭────╮  ││ ╭────────────╮                                      │
│ b0 ├○─┴┼▶┤            │                                      │
╰────╯   │ │[xor:s0_xor]├○─────────────────────────────────────╯
         ╰▶┤            │
           ╰────────────╯                                                `,
    wasm: 'two-bit-adder.wasm',
  },
  {
    slug: 'sr-latch',
    title: 'SR latch',
    lede:
      'Two cross-coupled NOR cells. The first circuit on the page that *remembers*: with both inputs low it holds whatever was last written. Try clicking S to set, then both back to 0, then R to reset.',
    source: `// SR-latch built from cross-coupled NOR gates.
//   Q    = NOR(R, Qbar)
//   Qbar = NOR(S, Q)
//
// NOR(a, b) = NOT(a OR b) = NOT a AND NOT b   (De Morgan)
// so each NOR is one AND and two NOTs.
input s, r

not nr(in=r)
not ns(in=s)

// Cross-coupled cells. Forward references are fine — names resolve globally.
and qcell(a=nr.out, b=nqbar.out)
and qbcell(a=ns.out, b=nq.out)

// Feedback inverters that close the loop.
not nq(in=qcell.out)
not nqbar(in=qbcell.out)

output q(in=qcell.out)
output qbar(in=qbcell.out)
`,
    preview: `╭───╮     ╭───╮     ╭───╮     ╭───╮     ╭───╮     ╭───╮
│ r ├○───▶┤NOT├○┬──▶┤   │ ╭──▶┤NOT├○╮ ╭▶┤   │ ╭──▶┤NOT├○╮
╰───╯     ╰───╯ │   │AND├○●   ╰───╯ │ │ │AND├○●   ╰───╯ │
                │ ╭▶┤   │ │         ╰─┼▶┤   │ │         │
                │ │ ╰───╯ │           │ ╰───╯ │         │
                ├─┼───────┼───────────╯       │         │
╭───╮     ╭───╮ │ │       │                   │   ╭───╮ │
│ s ├○───▶┤NOT├○╯ │       │                   ╰──▶┤ q │ │
╰───╯     ╰───╯   │       │                       ╰───╯ │
                  ╰───────┼─────────────────────────────╯
                          │                       ╭──────╮
                          ╰──────────────────────▶┤ qbar │
                                                  ╰──────╯`,
    wasm: 'sr-latch.wasm',
  },
  {
    slug: 'feedback-chain',
    title: 'Stable feedback through wires',
    lede: 'Two NOT gates connected end-to-end through two `wire` pass-throughs. Chain length four, no cycle in the signal graph — compiles cleanly. The substrate the SR latch above is built on. (No inputs to drive — open the live canvas to read the wire states.)',
    source: `not n1(in=w2.out)
wire w1(in=n1.out)
not n2(in=w1.out)
wire w2(in=n2.out)
`,
    preview: `     ╭───╮     ╭───╮
   ╭▶┤NOT├○───▶┤NOT├○╮
   │ ╰───╯     ╰───╯ │
   ╰─────────────────╯`,
    wasm: 'feedback-chain.wasm',
  },
];
