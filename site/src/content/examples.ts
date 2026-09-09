// Examples gallery, in three tiers: `intro` introduces one language feature at
// a time, `medium` builds the standard combinational parts, and `advanced` is
// where width, state and macros meet.
//
// Nothing here repeats a tour step verbatim — the tour is a lesson and this is
// a reference, and a reader browsing the workspace should not meet the same
// circuit twice. Every entry now has a real `--preview` output (compiled
// from the source field by `scripts/compile-content.ts`) and a matching
// `<slug>.wasm` artifact under `public/wasm/` for live in-page simulation.
//
// To regenerate:
//   1. From the repo root: `zig build circ-compile`
//   2. From site/:         `bun run scripts/compile-content.ts`
//   3. Paste the new previews from `scripts/.compiled.json` back into this file.

/** How much of the language an example assumes. The gallery and the
 *  playground's workspace both group by this, so a reader can start at the
 *  shallow end and see where the deep end is. */
export type ExampleLevel = 'intro' | 'medium' | 'advanced';

export interface Example {
  slug: string;
  title: string;
  level: ExampleLevel;
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
    slug: 'inverter-chain',
    title: 'NOT chain',
    level: 'intro',
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
    slug: 'fan-out',
    title: 'One input, three destinations',
    level: 'intro',
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
    slug: 'builtin-xor',
    title: 'A built-in macro',
    level: 'intro',
    lede: 'The five built-in macros — or, nand, nor, xor, xnor — expand to primitives at compile time, and a single file may use one with no import at all.',
    source: `input a, b
xor g(a=a, b=b)
output out(in=g.out)
`,
    preview: `╭───╮     ╭───────╮     ╭─────╮
│ a ├○───▶┤       │ ╭──▶┤ out │
╰───╯     │[xor:g]├○╯   ╰─────╯
       ╭─▶┤       │            
       │  ╰───────╯            
       │                       
╭───╮  │                       
│ b ├○─╯                       
╰───╯                          `,
    repoPath: 'tests/fixtures/circuits/builtin_xor.circ',
    wasm: 'builtin-xor.wasm',
  },
  {
    slug: 'slice-and-concat',
    title: 'Slicing and joining a bus',
    level: 'intro',
    lede: 'Takes a 4-bit input apart with a[0..2] and a[2..4] and puts it back together with a concat, which reconstructs the original.',
    source: `input[4] a
output[4] o(in={a[0..2], a[2..4]})
`,
    preview: `╭──────╮     ╭──────╮
│ a[4] ├○───▶┤ o[4] │
╰──────╯     ╰──────╯`,
    repoPath: 'tests/fixtures/circuits/slice_then_concat.circ',
    wasm: 'slice-and-concat.wasm',
  },
  {
    slug: 'wide-not',
    title: 'One gate across eight bits',
    level: 'intro',
    lede: 'A primitive written not[8] inverts a whole bus at once, so the width lives on the gate rather than in eight copies of it.',
    source: `input[8] a
not[8] inv(in=a)
output[8] o(in=inv.out)
`,
    preview: `╭──────╮     ╭───╮     ╭──────╮
│ a[8] ├○───▶┤NOT├○───▶┤ o[8] │
╰──────╯     ╰───╯     ╰──────╯`,
    repoPath: 'tests/fixtures/circuits/multibit_not_full.circ',
    wasm: 'wide-not.wasm',
  },
  {
    slug: 'half-adder',
    title: 'Half-adder',
    level: 'medium',
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
          ╰───────╯              `,
    wasm: 'half-adder.wasm',
  },
  {
    slug: 'mux-2to1',
    title: '2-to-1 multiplexer',
    level: 'medium',
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
    slug: 'demux-1to2',
    title: '1-to-2 demultiplexer',
    level: 'medium',
    lede: 'The mux read backwards: one input is routed to whichever output sel names, and the other is held at 0.',
    source: `// 1-to-2 demultiplexer: routes \`in\` to \`out_a\` when sel=0, to \`out_b\` when sel=1.
// The unselected output is held at 0.
input in, sel
not sel_inv(in=sel)
and route_a(a=in, b=sel_inv.out)
and route_b(a=in, b=sel)
output out_a(in=route_a.out)
output out_b(in=route_b.out)
`,
    preview: `╭────╮      ╭───╮     ╭───╮     ╭───────╮
│ in ├○●╭──▶┤NOT├○─╮╭▶┤   │ ╭──▶┤ out_a │
╰────╯ ││   ╰───╯  ││ │AND├○╯   ╰───────╯
       ●┼──────────┴┴▶┤   │              
       ││             ╰───╯              
       ││                                
╭─────╮││   ╭───╮               ╭───────╮
│ sel ├○┼──▶┤   │ ╭────────────▶┤ out_b │
╰─────╯ │   │AND├○╯             ╰───────╯
        ╰──▶┤   │                        
            ╰───╯                        `,
    repoPath: 'tests/fixtures/circuits/demux_1to2.circ',
    wasm: 'demux-1to2.wasm',
  },
  {
    slug: 'full-adder',
    title: 'Full-adder',
    level: 'medium',
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
    slug: 'rom-lookup',
    title: 'A ROM the host loads',
    level: 'medium',
    lede: 'A rom is a compile-time shape and a run-time image: the circuit declares rom code[8, 4] and the page loads its bytes from the settings drawer.',
    source: `input[4] pc
rom code[8, 4](addr = pc.out)
output[8] out(in = code.out)
`,
    preview: `╭───────╮     ╭───────────────╮     ╭────────╮
│ pc[4] ├○───▶┤ rom code[8,4] ├○───▶┤ out[8] │
╰───────╯     ╰───────────────╯     ╰────────╯`,
    repoPath: 'tests/fixtures/circuits/rom_lookup.circ',
    wasm: 'rom-lookup.wasm',
  },
  {
    slug: 'two-bit-adder',
    title: '2-bit ripple-carry adder',
    level: 'advanced',
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
    slug: 'four-bit-adder',
    title: '4-bit ripple-carry adder',
    level: 'advanced',
    lede: 'Four full adders chained by their carry, the point where the ripple delay starts to show in the schematic.',
    source: `// 4-bit ripple-carry adder: (a3 a2 a1 a0) + (b3 b2 b1 b0) → (cout s3 s2 s1 s0).
// Bit 0 is a half adder; bits 1-3 are full adders chained via the previous
// bit's carry-out. Largest arithmetic fixture in the suite at 256 rows.
input a0, a1, a2, a3, b0, b1, b2, b3

// Bit 0 (half adder)
xor s0_xor(a=a0, b=b0)
and s0_carry(a=a0, b=b0)

// Bit 1 (full adder, cin = s0_carry.out)
xor s1_x1(a=a1, b=b1)
xor s1_x2(a=s1_x1.out, b=s0_carry.out)
and s1_a1(a=a1, b=b1)
and s1_a2(a=s1_x1.out, b=s0_carry.out)
or s1_or(a=s1_a1.out, b=s1_a2.out)

// Bit 2 (full adder, cin = s1_or.out)
xor s2_x1(a=a2, b=b2)
xor s2_x2(a=s2_x1.out, b=s1_or.out)
and s2_a1(a=a2, b=b2)
and s2_a2(a=s2_x1.out, b=s1_or.out)
or s2_or(a=s2_a1.out, b=s2_a2.out)

// Bit 3 (full adder, cin = s2_or.out)
xor s3_x1(a=a3, b=b3)
xor s3_x2(a=s3_x1.out, b=s2_or.out)
and s3_a1(a=a3, b=b3)
and s3_a2(a=s3_x1.out, b=s2_or.out)
or s3_or(a=s3_a1.out, b=s3_a2.out)

output s0(in=s0_xor.out)
output s1(in=s1_x2.out)
output s2(in=s2_x2.out)
output s3(in=s3_x2.out)
output cout(in=s3_or.out)
`,
    preview: `╭────╮     ╭───╮              ╭───╮             ╭──────────╮     ╭───╮             ╭──────────╮     ╭───╮             ╭──────────╮     ╭──────╮
│ a1 ├○──●▶┤   │         ╭───▶┤   │           ╭▶┤          │   ╭▶┤   │           ╭▶┤          │   ╭▶┤   │           ╭▶┤          │ ╭──▶┤ cout │
╰────╯   │ │AND├○╮       │    │AND├○╮         │ │[or:s1_or]├○● │ │AND├○╮         │ │[or:s2_or]├○● │ │AND├○╮         │ │[or:s3_or]├○╯   ╰──────╯
       ╭─┼▶┤   │ │  ╭────┼───▶┤   │ ╰─────────┼▶┤          │ ●─┼▶┤   │ ╰─────────┼▶┤          │ ●─┼▶┤   │ ╰─────────┼▶┤          │             
       │ │ ╰───╯ │  │    │    ╰───╯           │ ╰──────────╯ │ │ ╰───╯           │ ╰──────────╯ │ │ ╰───╯           │ ╰──────────╯             
       │ │       ╰──┼────┼────────────────────╯              │ │                 │              │ │                 │                          
╭────╮ │ │ ╭───╮    │    │    ╭───────────╮                  │ │ ╭───────────╮   │              │ │ ╭───────────╮   │                  ╭────╮  
│ b1 ├○●╭┼▶┤   │    │    ●───▶┤           │                  │ ●▶┤           │   │              │ ●▶┤           │   │                ╭▶┤ s0 │  
╰────╯ │││ │AND├○─╮ │    │    │[xor:s1_x2]├○╮                │ │ │[xor:s2_x2]├○╮ │              │ │ │[xor:s3_x2]├○╮ │                │ ╰────╯  
       ││├▶┤   │  │ ●────┼───▶┤           │ │                ╰─┼▶┤           │ │ │              ╰─┼▶┤           │ │ │                │         
       │││ ╰───╯  │ │    │    ╰───────────╯ │                  │ ╰───────────╯ │ │                │ ╰───────────╯ │ │                │         
       │││        ╰─●────┼──────────────────┼──────────────────┼───────────────┼─╯                │               │ │                │         
╭────╮ │││ ╭───╮    │    │                  │                  │               │                  │               │ │                │ ╭────╮  
│ a2 ├○●●┼▶┤   │    │    │                  ╰──────────────────┼───────────────┼──────────────────┼───────────────┼─┼────────────────┼▶┤ s1 │  
╰────╯ │││ │AND├○───●────┼─────────────────────────────────────┼───────────────┼──────────────────┼───────────────┼─╯                │ ╰────╯  
       ││├▶┤   │    │    │                                     │               │                  │               │                  │         
       │││ ╰───╯    │    │                                     │               │                  │               │                  │         
       │││          │    │                                     │               │                  │               │                  │         
╭────╮ │││ ╭───╮    │    │                                     │               │                  │               │                  │ ╭────╮  
│ b2 ├○┼┼┼▶┤   │    │    │                                     │               ╰──────────────────┼───────────────┼──────────────────┼▶┤ s2 │  
╰────╯ │││ │AND├○───●    │                                     │                                  │               │                  │ ╰────╯  
       ││├▶┤   │         │                                     │                                  │               │                  │         
       │││ ╰───╯         │                                     │                                  │               │                  │         
       │││               │                                     │                                  │               │                  │         
╭────╮ │││ ╭───────────╮ │                                     │                                  │               │                  │ ╭────╮  
│ a3 ├○●┼┼▶┤           │ │                                     │                                  │               ╰──────────────────┼▶┤ s3 │  
╰────╯ │││ │[xor:s1_x1]├○●                                     │                                  │                                  │ ╰────╯  
       ╰┼┼▶┤           │                                       │                                  │                                  │         
        ││ ╰───────────╯                                       │                                  │                                  │         
        ││                                                     │                                  │                                  │         
╭────╮  ││ ╭───────────╮                                       │                                  │                                  │         
│ b3 ├○─┴┼▶┤           │                                       │                                  │                                  │         
╰────╯   │ │[xor:s2_x1]├○──────────────────────────────────────●                                  │                                  │         
         ├▶┤           │                                                                          │                                  │         
         │ ╰───────────╯                                                                          │                                  │         
         │                                                                                        │                                  │         
╭────╮   │ ╭───────────╮                                                                          │                                  │         
│ a0 ├○──●▶┤           │                                                                          │                                  │         
╰────╯   │ │[xor:s3_x1]├○─────────────────────────────────────────────────────────────────────────●                                  │         
         ├▶┤           │                                                                                                             │         
         │ ╰───────────╯                                                                                                             │         
         │                                                                                                                           │         
╭────╮   │ ╭────────────╮                                                                                                            │         
│ b0 ├○──┼▶┤            │                                                                                                            │         
╰────╯   │ │[xor:s0_xor]├○───────────────────────────────────────────────────────────────────────────────────────────────────────────╯         
         ╰▶┤            │                                                                                                                      
           ╰────────────╯                                                                                                                      `,
    repoPath: 'tests/fixtures/circuits/four_bit_adder.circ',
    wasm: 'four-bit-adder.wasm',
  },
  {
    slug: 'sr-latch',
    title: 'SR latch',
    level: 'advanced',
    lede: 'Two NOT gates connected end-to-end through two `wire` pass-throughs. Chain length four, no cycle in the signal graph — compiles cleanly. The substrate the SR latch above is built on. (No inputs to drive — open the live canvas to read the wire states.)',
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
    slug: 'ram-write-read',
    title: 'A RAM with a clock',
    level: 'advanced',
    lede: 'Single-port RAM: the write commits on a rising clock edge when we is high, so this one needs the simulator rather than a truth table.',
    source: `input[4] a
input[8] d
input we, clk
ram data[8, 4](addr = a.out, din = d.out, we = we.out, clk = clk.out)
output[8] q(in = data.out)
`,
    preview: `╭──────╮     ╭───────────────╮     ╭──────╮
│ a[4] ├○───▶┤               │ ╭──▶┤ q[8] │
╰──────╯     │               │ │   ╰──────╯
          ╭─▶┤               │ │           
          │  │ ram data[8,4] ├○╯           
        ╭─┼─▶┤               │             
        │ │  │               │             
        ├─┼─▶┤               │             
        │ │  ╰───────────────╯             
        │ │                                
╭──────╮│ │                                
│ d[8] ├○─╯                                
╰──────╯│                                  
        │                                  
╭────╮  │                                  
│ we ├○─┤                                  
╰────╯  │                                  
        │                                  
╭─────╮ │                                  
│ clk ├○╯                                  
╰─────╯                                    `,
    repoPath: 'tests/fixtures/circuits/ram_write_read.circ',
    wasm: 'ram-write-read.wasm',
  },
  {
    slug: 'alu-4bit',
    title: 'The Nand2Tetris ALU',
    level: 'advanced',
    lede: 'Six control bits over two 4-bit buses give eighteen functions. Broadcasts, macros, slices and a ripple adder in one circuit — the deep end.',
    source: `// 4-bit Nand2Tetris (Hack) ALU — multi-bit version of alu_4bit.circ.
//
// Same control surface and same logic as the scalar fixture, but the data
// path runs on width-4 buses x and y. Scalar control bits broadcast into
// the lanes via {c, c, c, c} concat. The ripple-carry adder stays serial
// because the carry between bit lanes can't be expressed as a single
// width-4 primitive.
//
// Total inputs: 6 control + 4 (x bus) + 4 (y bus) = 14 → 16,384 rows.
// The truth-table column layout differs from alu_4bit.circ because x, y,
// and out render as multi-bit values, but every row's logical mapping
// (zx, nx, zy, ny, f, no, x, y) → out is identical.

input zx, nx, zy, ny, f, no
input[4] x, y

// ----- broadcast scalar control bits to width-4 buses ------------------
// The macros (xor / or) and primitives accept width-4 ports when written
// \`xor name[4](...)\`; passing a {c, c, c, c} concat directly into a macro
// port currently confuses the validator's width inference (the destination
// reads as width 1 before the macro is specialised at the call site), so
// we route every scalar-broadcast input through a width-4 wire first.
wire[4] nx_b(in={nx, nx, nx, nx})
wire[4] ny_b(in={ny, ny, ny, ny})
wire[4] no_b(in={no, no, no, no})

// ----- pre-set x: x' = (NOT zx) AND x;  x'' = nx XOR x' ----------------
not zx_inv(in=zx)
and[4] xz(a={zx_inv.out, zx_inv.out, zx_inv.out, zx_inv.out}, b=x)
xor    xn[4](a=nx_b.out, b=xz.out)

// ----- pre-set y: same shape -------------------------------------------
not zy_inv(in=zy)
and[4] yz(a={zy_inv.out, zy_inv.out, zy_inv.out, zy_inv.out}, b=y)
xor    yn[4](a=ny_b.out, b=yz.out)

// ----- compute ADD: 4-bit ripple-carry, drop final carry-out ----------
// Bit-parallel propagate (XOR) and generate (AND) terms across all 4 bits.
//
// The propagate is hand-expanded from primitives instead of using
// \`xor add_p[4]\` — the xor[W] macro produces incorrect simulation
// values for some input combinations when its output flows through a
// wire-buffered slice chain into the per-bit scalar macros below.
// Logic: xor(a, b) = NOT(AND(NOT(AND(a, NOT b)), NOT(AND(NOT a, b))))
// The generate stays as the primitive \`and[4]\`.
not[4] xn_inv(in=xn.out)
not[4] yn_inv(in=yn.out)
and[4] p1(a=xn.out, b=yn_inv.out)
and[4] p2(a=xn_inv.out, b=yn.out)
not[4] p1_inv(in=p1.out)
not[4] p2_inv(in=p2.out)
and[4] p_nor(a=p1_inv.out, b=p2_inv.out)
not[4] add_p(in=p_nor.out)
and[4] add_g(a=xn.out, b=yn.out)

// Wire-buffer each slice that feeds a scalar macro. Slice-into-scalar-
// macro (\`signal[i]\` directly into \`xor\`/\`or\`/\`nand\`/...) trips an
// InternalError in the topology builder; routing through a scalar wire
// avoids it. Primitives (\`and add1_pcy\`) don't need this, but using the
// buffered slices uniformly keeps the bit-N adder readable.
wire add_p0(in=add_p.out[0])
wire add_p1(in=add_p.out[1])
wire add_p2(in=add_p.out[2])
wire add_p3(in=add_p.out[3])
wire add_g0(in=add_g.out[0])
wire add_g1(in=add_g.out[1])
wire add_g2(in=add_g.out[2])

// Bit 0: half adder is "free" — sum is add_p0, carry is add_g0.
// Bit 1: full adder fed by add_g0
xor add1_sum(a=add_p1.out, b=add_g0.out)
and add1_pcy(a=add_p1.out, b=add_g0.out)
or  add1_cy (a=add_g1.out, b=add1_pcy.out)

// Bit 2: full adder fed by add1_cy
xor add2_sum(a=add_p2.out, b=add1_cy.out)
and add2_pcy(a=add_p2.out, b=add1_cy.out)
or  add2_cy (a=add_g2.out, b=add2_pcy.out)

// Bit 3: sum only — final carry-out is intentionally dropped per ALU spec.
xor add3_sum(a=add_p3.out, b=add2_cy.out)

// Pack the 4 sum bits (low-on-left) into a width-4 bus.
wire[4] add(in={add_p0.out, add1_sum.out, add2_sum.out, add3_sum.out})

// ----- compute AND: bitwise across all 4 bits --------------------------
and[4] and_result(a=xn.out, b=yn.out)

// ----- mux per bit: out = (f AND add) OR ((NOT f) AND and_result) -----
not f_inv(in=f)
and[4] mux_l(a={f,         f,         f,         f},         b=add.out)
and[4] mux_r(a={f_inv.out, f_inv.out, f_inv.out, f_inv.out}, b=and_result.out)
or     mux[4](a=mux_l.out, b=mux_r.out)

// ----- post-set: if no then out := NOT out -----------------------------
xor    result[4](a=no_b.out, b=mux.out)

output[4] out(in=result.out)
`,
    preview: `╭────╮       ╭───╮     ╭───╮     ╭────────╮     ╭───╮     ╭───╮     ╭───╮     ╭───╮     ╭───╮     ╭───╮                ╭────────────╮     ╭───╮                ╭────────────╮     ╭──────────────╮     ╭───╮     ╭────────╮     ╭────────────╮     ╭────────╮
│ zy ├○─────▶┤NOT├○───▶┤   │   ╭▶┤        │ ╭──▶┤NOT├○╮ ╭▶┤   │ ╭──▶┤NOT├○───▶┤   │ ╭──▶┤NOT├●●──▶┤   │              ╭▶┤            │   ╭▶┤   │              ╭▶┤            │   ╭▶┤              │   ╭▶┤   │ ╭──▶┤        │   ╭▶┤            │ ╭──▶┤ out[4] │
╰────╯       ╰───╯     │AND├○╮ │ │[xor:yn]├●●   ╰───╯ │ │ │AND├○╯   ╰───╯     │AND├○╯   ╰───╯ │   │AND├○╮            │ │[or:add1_cy]├○● │ │AND├○╮            │ │[or:add2_cy]├○╮ │ │[xor:add3_sum]├○╮ │ │AND├○╯   │[or:mux]├○╮ │ │[xor:result]├○╯   ╰────────╯
         ╭────────────▶┤   │ ╰─┼▶┤        │ │         ╰─┼▶┤   │            ╭─▶┤   │           │ ╭▶┤   │ ╰────────────┼▶┤            │ ●─┼▶┤   │ ╰────────────┼▶┤            │ ╰─┼▶┤              │ ╰─┼▶┤   │   ╭▶┤        │ ╰─┼▶┤            │               
         │             ╰───╯   │ ╰────────╯ │           │ ╰───╯            │  ╰───╯           │ │ ╰───╯              │ ╰────────────╯ │ │ ╰───╯              │ ╰────────────╯   │ ╰──────────────╯   │ ╰───╯   │ ╰────────╯   │ ╰────────────╯               
       ╭─┼─────────────────────╯            │╭──────────╯                  │                  ●─●────────────────────●────────────────●─●────────────────────┼──────────────────╯                    │         │              │                              
╭────╮ │ │   ╭───╮     ╭───╮     ╭────────╮ ││  ╭───╮     ╭───╮     ╭───╮  │                  │ │ ╭──────────────╮   │                │ │ ╭──────────────╮   │                                       │         │              │                              
│ ny ├○╯ ├──▶┤NOT├○───▶┤   │   ╭▶┤        │ │●─▶┤   │   ╭▶┤   │  ╭─▶┤NOT├○─╯                  ╰─┼▶┤              │   │                │ ╰▶┤              │   │                                       │         │              │                              
╰────╯   │   ╰───╯     │AND├○─╮│ │[xor:xn]├●●●  │AND├●──● │AND├○╮│  ╰───╯                       │ │[xor:add1_sum]├   │                │   │[xor:add2_sum]├   │                                       │         │              │                              
         │╭───────────▶┤   │  ╰┼▶┤        │ ●●─▶┤   │   ●▶┤   │ ││                              ●▶┤              │   │                ╰──▶┤              │   │                                       │         │              │                              
         ││            ╰───╯   │ ╰────────╯ ││  ╰───╯   │ ╰───╯ ││                              │ ╰──────────────╯   │                    ╰──────────────╯   │                                       │         │              │                              
        ╭┼┼────────────────────┼────────────┼┼──────────┼───────┼┼──────────────────────────────┼────────────────────┼───────────────────────────────────────┼───────────────────────────────────────┼─────────┼──────────────╯                              
╭────╮  │││  ╭───╮             │            ││  ╭───╮   │ ╭───╮ ││                              │                    │                                       │                                       │         │                                             
│ no ├○─┼┼┼─▶┤NOT├○─╮          │            │●─▶┤   │  ╭┼▶┤   │ ││                              │                    │                                       │                                       │         │                                             
╰────╯  │││  ╰───╯  │          │            ││  │AND├○─┼● │AND├○┼╯                              │                    │                                       │                                       │         │                                             
        │││         │          │            ●┼─▶┤   │  │●▶┤   │ │                               │                    │                                       │                                       │         │                                             
        │││         │          │            ││  ╰───╯  ││ ╰───╯ │                               │                    │                                       │                                       │         │                                             
        │││         │          │            ││         │●───────●───────────────────────────────●────────────────────●───────────────────────────────────────╯                                       │         │                                             
╭──────╮│││         │          │            ││  ╭───╮  ││       │                                                                                                                                    │         │                                             
│ y[4] ├○┤│         │          │            │╰─▶┤NOT├○─╯│       ╰────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────╯                                             
╰──────╯│││         │          │            │   ╰───╯   │                                                                                                                                            │                                                       
        │││         ╰──────────┼────────────┼───────────┤                                                                                                                                            │                                                       
╭────╮  │││                    │            │           │                                                                                                                                            │                                                       
│ zx ├○─┼╯│                    │            ╰───────────╯                                                                                                                                            │                                                       
╰────╯  │ │                    │                                                                                                                                                                     │                                                       
        │ │                    │                                                                                                                                                                     │                                                       
╭────╮  │ │                    │                                                                                                                                                                     │                                                       
│ nx ├○─┼─┼────────────────────╯                                                                                                                                                                     │                                                       
╰────╯  │ │                                                                                                                                                                                          │                                                       
        │ │                                                                                                                                                                                          │                                                       
╭───╮   │ │                                                                                                                                                                                          │                                                       
│ f ├○──●─┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯                                                       
╰───╯     │                                                                                                                                                                                                                                                  
          │                                                                                                                                                                                                                                                  
╭──────╮  │                                                                                                                                                                                                                                                  
│ x[4] ├○─╯                                                                                                                                                                                                                                                  
╰──────╯                                                                                                                                                                                                                                                     `,
    repoPath: 'tests/fixtures/circuits/alu_4bit_multibit.circ',
    wasm: 'alu-4bit.wasm',
  },
];
