const std = @import("std");
pub const memory = @import("memory.zig");
const transport = @import("transport.zig");

const log = @import("log.zig");

/// Compile-time switch to include benchmark counters on `Circuit`. The
/// `build_options` module is supplied by `build.zig` per consumer: native and
/// WASM builds wire it to `false`; the `zig build bench` runner wires it to
/// `true`. When false, `Circuit.metrics` is `void` and every counter bump is
/// dead code stripped — production and test builds are byte-identical to a
/// metrics-free engine.
pub const COLLECT_METRICS: bool = @import("build_options").collect_metrics;

pub const Metrics = struct {
    events_popped: u64 = 0,
    events_committed: u64 = 0,
    recalcs: u64 = 0,
    peak_queue: u64 = 0,
    final_time: u64 = 0,
};

const PROPAGATION_DELAY: Timestamp = 5;
const WIRE_PROPAGATION_DELAY: Timestamp = 1;

const IN_PORT_NAME = "in";
const A_PORT_NAME = "a";
const B_PORT_NAME = "b";
const OUT_PORT_NAME = "out";
const OUTPUT_PIN_IN_PORT_NAME = "in";
const OUTPUT_PIN_OUT_PORT_NAME = "out";

fn calculateDominantState(circuit: *const Circuit, input_comp_list: std.ArrayList(*Component), width: u8) BitVecState {
    // Per-bit dominance: every bit position where some input reads
    // defined-high is locked high in the result; remaining bits come
    // from the LAST input's state. Reduces at width=1 to the previous
    // "any input reading high wins immediately, otherwise the last
    // input's state is dominant" rule (the early-return on isHigh was
    // an optimization; the bitwise form gives the same answer because
    // a locked-high bit overrides whatever the last input said there).
    var dominant_state = BitVecState.undefined_(width);
    var locked_high: u64 = 0;
    for (input_comp_list.items) |input_comp| {
        const s = circuit.readState(input_comp.state_handle);
        locked_high |= s.value & s.defined;
        dominant_state = s;
    }
    const m = widthMask(width);
    const high_mask = locked_high & m;
    const carry_value = dominant_state.value & dominant_state.defined & m;
    const carry_defined = dominant_state.defined & m;
    return .{
        .value = high_mask | carry_value,
        .defined = high_mask | carry_defined,
        .width = width,
    };
}

fn recalculateAndReschedule(
    circuit: *const Circuit,
    component: *Component,
    queue: *EventQueue,
    current_time: Timestamp,
) !void {
    // Width comes from the component's own state slot's tier (the
    // `tier = width` convention); the dispatch below stays in this width
    // throughout, and BitVecState ops compose with width-agnostic bit ops.
    const width: u8 = component.state_handle.tier;
    var calculated_state = BitVecState.undefined_(width);

    switch (component.kind) {
        .not_gate => |gate| {
            calculated_state = calculateDominantState(circuit, gate.inputs, width).flip();
        },
        .and_gate => |gate| {
            const aValue = calculateDominantState(circuit, gate.inputs_a, width);
            const bValue = calculateDominantState(circuit, gate.inputs_b, width);
            calculated_state = aValue.bitAnd(bValue);
        },
        .led => |led_internals| {
            calculated_state = calculateDominantState(circuit, led_internals.inputs, width);
            const current = circuit.readState(component.state_handle);
            if (!calculated_state.equals(current)) {
                if (comptime log.enabled(.info)) {
                    log.info("💡 LED (id={d}) state will be {s}", .{ component.id, calculated_state.tagName() });
                }
            }
        },
        .wire => |wire| {
            // Wire relays the first non-null input to the output. If
            // multiple inputs are connected, the wire takes the first
            // defined state.
            for (wire.inputs.items) |input_comp| {
                const s = circuit.readState(input_comp.state_handle);
                if (!s.isUndefined()) {
                    calculated_state = calculateDominantState(circuit, wire.inputs, width);
                    break;
                }
            }
        },
        .output_pin => |output_pin| {
            calculated_state = calculateDominantState(circuit, output_pin.inputs, width);
        },
        .input_pin_gate => |gate| {
            if (gate.inputs.items.len == 0) return;
            calculated_state = calculateDominantState(circuit, gate.inputs, width);
        },
    }

    const current_state = circuit.readState(component.state_handle);
    if (!current_state.equals(calculated_state)) {
        if (comptime log.enabled(.info)) {
            log.info(" - Component (id={d}, type={s}) output changed from {s} -> {s}. Scheduling new event.", .{ component.id, @tagName(component.kind), current_state.tagName(), calculated_state.tagName() });
        }

        const delay = switch (component.kind) {
            .wire, .output_pin, .led => WIRE_PROPAGATION_DELAY,
            else => PROPAGATION_DELAY,
        };

        try queue.add(.{
            .timestamp = current_time + delay,
            .component = component,
            .new_state = calculated_state,
        });
    }
}

/// Maximum wire width supported by `BitVecState` and the pool tiers. Width is
/// stored as `u8` for arithmetic convenience; the assertion in `widthMask`
/// keeps the legal range to 1..=64.
pub const MAX_WIDTH: u8 = 64;

/// Width-agnostic wire state value type. Carries paired `value` / `defined`
/// bitmaps and an explicit `width` so equality, flip, and downstream rules
/// stay tier-agnostic. Width=1 is the only exercised case today; the next
/// issue lifts wider widths into the language without re-touching this code.
///
/// Equality treats two undefined slots as equal regardless of payload bits
/// in `value`: `(a.defined == b.defined) AND ((a.value & a.defined) ==
/// (b.value & b.defined))`. That preserves today's `State.undefined ==
/// State.undefined` semantics exactly, which the Phase-1 dedup at
/// `propagate()` relies on.
pub const BitVecState = struct {
    value: u64,
    defined: u64,
    width: u8,

    pub fn undefined_(width: u8) BitVecState {
        return .{ .value = 0, .defined = 0, .width = width };
    }

    pub fn low(width: u8) BitVecState {
        return .{ .value = 0, .defined = widthMask(width), .width = width };
    }

    pub fn high(width: u8) BitVecState {
        const m = widthMask(width);
        return .{ .value = m, .defined = m, .width = width };
    }

    pub fn equals(self: BitVecState, other: BitVecState) bool {
        if (self.width != other.width) return false;
        if (self.defined != other.defined) return false;
        return (self.value & self.defined) == (other.value & other.defined);
    }

    /// Flips defined bits within `width`; undefined bits stay undefined.
    /// Bits outside `width` are kept zero so `equals` stays canonical.
    pub fn flip(self: BitVecState) BitVecState {
        const m = widthMask(self.width);
        return .{
            .value = (~self.value) & m & self.defined,
            .defined = self.defined,
            .width = self.width,
        };
    }

    /// Bitwise AND with three-state semantics: a bit is low if either
    /// operand's bit is defined-low, high if both are defined-high, and
    /// undefined otherwise. Reduces to the existing width=1 AND predicate
    /// in `recalculateAndReschedule` for all nine three-state combinations.
    pub fn bitAnd(self: BitVecState, other: BitVecState) BitVecState {
        std.debug.assert(self.width == other.width);
        const m = widthMask(self.width);
        const high_mask = self.value & self.defined & other.value & other.defined;
        const low_mask = ((~self.value) & self.defined) | ((~other.value) & other.defined);
        return .{
            .value = high_mask & m,
            .defined = (high_mask | low_mask) & m,
            .width = self.width,
        };
    }

    /// Bitwise OR with three-state semantics: a bit is high if either
    /// operand's bit is defined-high, low if both are defined-low, and
    /// undefined otherwise. Dual of `bitAnd`.
    pub fn bitOr(self: BitVecState, other: BitVecState) BitVecState {
        std.debug.assert(self.width == other.width);
        const m = widthMask(self.width);
        const high_mask = (self.value & self.defined) | (other.value & other.defined);
        const low_mask = ((~self.value) & self.defined) & ((~other.value) & other.defined);
        return .{
            .value = high_mask & m,
            .defined = (high_mask | low_mask) & m,
            .width = self.width,
        };
    }

    /// Bitwise XOR with three-state semantics: a bit is defined iff both
    /// operands' bits are defined; its value is `self.value ^ other.value`
    /// within the both-defined mask. Any undefined input bit propagates as
    /// undefined regardless of the other operand.
    pub fn bitXor(self: BitVecState, other: BitVecState) BitVecState {
        std.debug.assert(self.width == other.width);
        const m = widthMask(self.width);
        const both_defined = self.defined & other.defined;
        return .{
            .value = (self.value ^ other.value) & both_defined & m,
            .defined = both_defined & m,
            .width = self.width,
        };
    }

    /// Width=1 helper: defined and value bit set.
    pub fn isHigh(self: BitVecState) bool {
        std.debug.assert(self.width == 1);
        return (self.defined & 1) != 0 and (self.value & 1) != 0;
    }

    /// Width=1 helper: defined and value bit clear.
    pub fn isLow(self: BitVecState) bool {
        std.debug.assert(self.width == 1);
        return (self.defined & 1) != 0 and (self.value & 1) == 0;
    }

    /// Any-width helper: every bit is undefined.
    pub fn isUndefined(self: BitVecState) bool {
        return self.defined == 0;
    }

    /// Transport-wire encoding for the WASM API contract. Width=1 only:
    /// undefined=0, low=1, high=2. Matches the byte values that
    /// `@intFromEnum(State)` produced when wire state lived inline on
    /// `Component` (declaration order: undefined, low, high).
    pub fn toTransportByte(self: BitVecState) u8 {
        std.debug.assert(self.width == 1);
        if (self.defined == 0) return 0;
        if ((self.value & 1) == 0) return 1;
        return 2;
    }

    /// Width=1 mirror of `State.fromInt`: 0→low, 1→high, else→undefined.
    /// Used by the truth-table driver, which today calls `State.fromInt`
    /// per input vector bit.
    pub fn fromInt(int: i32, width: u8) BitVecState {
        std.debug.assert(width == 1);
        if (int == 0) return low(1);
        if (int == 1) return high(1);
        return undefined_(1);
    }

    /// Width=1 mirror of `State.toInt`: low=0, high=1, undefined=2. Distinct
    /// from `toTransportByte` (which uses the enum-declaration order).
    pub fn toInt(self: BitVecState) i32 {
        std.debug.assert(self.width == 1);
        if (self.isLow()) return 0;
        if (self.isHigh()) return 1;
        return 2;
    }

    /// Short label for logs and debug dumps. At width=1 matches the
    /// names the old `State` enum carried ("undefined", "low", "high")
    /// so log scrubbing doesn't have to learn a new vocabulary. At
    /// wider widths returns "multi-bit" because the value/defined pair
    /// doesn't reduce to a single label and the call sites are debug
    /// logs that don't need the full bit pattern.
    pub fn tagName(self: BitVecState) []const u8 {
        if (self.width != 1) return "multi-bit";
        if (self.isUndefined()) return "undefined";
        if (self.isLow()) return "low";
        return "high";
    }
};

fn widthMask(width: u8) u64 {
    std.debug.assert(width >= 1 and width <= MAX_WIDTH);
    if (width == 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << @as(u6, @intCast(width))) - 1;
}

pub const Timestamp = u64;

pub const Event = struct {
    timestamp: Timestamp,
    component: *Component,
    new_state: BitVecState,

    pub fn lessThan(_: void, lhs: Event, rhs: Event) std.math.Order {
        return std.math.order(lhs.timestamp, rhs.timestamp);
    }
};

pub const ComponentType = enum { input_pin_gate, not_gate, led, and_gate, wire, output_pin };

pub fn toKind(kind: u8) !Component.Kind {
    return switch (kind) {
        0 => .input_pin_gate,
        1 => .not_gate,
        2 => .led,
        3 => .and_gate,
        4 => .wire,
        5 => .output_pin,
        else => return error.InvalidComponentKind,
    };
}

pub const ComponentPortReference = struct { *Component, []const u8 };

pub const Component = struct {
    id: u32,
    kind: Kind,
    /// Opaque handle into a width-tiered pool owned by `Circuit`. The
    /// pool is the source of truth for wire state; reads and writes go
    /// through `Circuit.readState` / `Circuit.writeState`. Populated by
    /// `Circuit.createComponent` immediately after `Component.init`
    /// returns. The default's `slot = maxInt(u32)` is a sentinel: reads
    /// against it trap with an out-of-bounds panic in `Pool.read`, which
    /// catches "constructed a Component without going through Circuit".
    state_handle: PoolHandle = .{ .tier = 0, .slot = std.math.maxInt(u32) },
    /// Flat list of downstream components. Every component kind has exactly
    /// one output port (`"out"`), so the per-port map collapses to a single
    /// slice. Phase 2 of propagate walks this list directly.
    outputs: std.ArrayList(*Component) = .{},

    const Kind = union(ComponentType) {
        input_pin_gate: struct { inputs: std.ArrayList(*Component) = .{} },
        not_gate: struct { inputs: std.ArrayList(*Component) = .{} },
        led: struct { inputs: std.ArrayList(*Component) = .{} },
        /// AND is the only kind with two distinct input ports; everything
        /// else uses a single `inputs` field.
        and_gate: struct {
            inputs_a: std.ArrayList(*Component) = .{},
            inputs_b: std.ArrayList(*Component) = .{},
        },
        wire: struct { inputs: std.ArrayList(*Component) = .{} },
        output_pin: struct { inputs: std.ArrayList(*Component) = .{} },
    };

    pub fn init(id: u32, kind: Kind) !*Component {
        const self = try memory.allocator.create(Component);
        self.* = .{ .id = id, .kind = kind, .outputs = .{} };
        return self;
    }

    pub fn deinit(self: *Component) void {
        self.outputs.deinit(memory.allocator);
        switch (self.kind) {
            .and_gate => |*g| {
                g.inputs_a.deinit(memory.allocator);
                g.inputs_b.deinit(memory.allocator);
            },
            .not_gate => |*g| g.inputs.deinit(memory.allocator),
            .led => |*g| g.inputs.deinit(memory.allocator),
            .wire => |*g| g.inputs.deinit(memory.allocator),
            .output_pin => |*g| g.inputs.deinit(memory.allocator),
            .input_pin_gate => |*g| g.inputs.deinit(memory.allocator),
        }
        memory.allocator.destroy(self);
    }

    pub fn port(self: *Component, portName: []const u8) ComponentPortReference {
        return .{ self, portName };
    }
};

const EventQueue = struct {
    heap: std.PriorityQueue(Event, void, Event.lessThan),

    pub fn init() EventQueue {
        return .{ .heap = std.PriorityQueue(Event, void, Event.lessThan).init(memory.allocator, {}) };
    }

    pub fn deinit(self: *EventQueue) void {
        self.heap.deinit();
    }

    pub fn add(self: *EventQueue, event: Event) !void {
        try self.heap.add(event);
    }

    pub fn pop(self: *EventQueue) ?Event {
        return self.heap.removeOrNull();
    }

    pub fn peek(self: *EventQueue) ?Event {
        return self.heap.peek();
    }
};

/// Opaque handle into a width-tiered state pool. Components carry one of
/// these instead of an inline `output_state` field; `Circuit.readState` and
/// `Circuit.writeState` dispatch on `tier` exactly once to land in the
/// right pool's storage. Width is recovered from the pool, not stored on
/// the handle.
pub const PoolHandle = struct {
    tier: u8,
    slot: u32,
};

/// Maps a width to the index of the pool that owns it. Convention: tier
/// number equals width number, so `Circuit.tiers[width]` is the canonical
/// pool lookup. Tier 0 is reserved/unused; legal widths are 1..=MAX_WIDTH.
fn tierIndexForWidth(width: u8) u8 {
    std.debug.assert(width >= 1 and width <= MAX_WIDTH);
    return width;
}

/// Width-tiered Structure-of-Arrays pool for wire state. The storage layout
/// switches on `width`:
///
/// * **width = 1**: bit-packed, 64 slots per `u64` word across two parallel
///   buffers (one for value bits, one for defined bits). Growth appends one
///   `u64` to each buffer every 64 slots.
/// * **widths 2..=64**: one `u64` per slot in each buffer. Reads return the
///   slot's full `u64` directly; writes mask to `widthMask(width)` so
///   out-of-width payload bits stay zero, and undefined bits are
///   canonicalized to value=0 to preserve the invariant `BitVecState.equals`
///   relies on.
///
/// The two buffers grow together; `allocateSlot` is the only growth site
/// and always appends to both, so length-mismatch is structurally impossible
/// regardless of width.
pub const Pool = struct {
    width: u8,
    next_slot: u32 = 0,
    values: std.ArrayList(u64) = .{},
    defined: std.ArrayList(u64) = .{},

    pub fn init(width: u8) Pool {
        std.debug.assert(width >= 1 and width <= MAX_WIDTH);
        return .{ .width = width };
    }

    pub fn deinit(self: *Pool) void {
        self.values.deinit(memory.allocator);
        self.defined.deinit(memory.allocator);
    }

    pub fn allocateSlot(self: *Pool) !u32 {
        const slot = self.next_slot;
        // Width=1 packs 64 slots per word; wider widths use one slot per word.
        const slots_per_word: u32 = if (self.width == 1) 64 else 1;
        const word_idx: usize = @intCast(slot / slots_per_word);
        if (word_idx >= self.values.items.len) {
            try self.values.append(memory.allocator, 0);
            try self.defined.append(memory.allocator, 0);
        }
        self.next_slot += 1;
        return slot;
    }

    pub fn read(self: *const Pool, slot: u32) BitVecState {
        if (self.width == 1) {
            const word_idx: usize = @intCast(slot / 64);
            const bit_idx: u6 = @intCast(slot % 64);
            const v: u64 = (self.values.items[word_idx] >> bit_idx) & 1;
            const d: u64 = (self.defined.items[word_idx] >> bit_idx) & 1;
            return .{ .value = v, .defined = d, .width = 1 };
        }
        const idx: usize = @intCast(slot);
        return .{
            .value = self.values.items[idx],
            .defined = self.defined.items[idx],
            .width = self.width,
        };
    }

    pub fn write(self: *Pool, slot: u32, state: BitVecState) void {
        std.debug.assert(state.width == self.width);
        if (self.width == 1) {
            const word_idx: usize = @intCast(slot / 64);
            const bit_idx: u6 = @intCast(slot % 64);
            const mask: u64 = @as(u64, 1) << bit_idx;
            if ((state.defined & 1) != 0) {
                self.defined.items[word_idx] |= mask;
                if ((state.value & 1) != 0) {
                    self.values.items[word_idx] |= mask;
                } else {
                    self.values.items[word_idx] &= ~mask;
                }
            } else {
                // Undefined: clear both bits so reads canonicalize to value=0
                // (matters for `BitVecState.equals`, which only masks `value`
                // by `defined` and so could otherwise carry stale payload).
                self.defined.items[word_idx] &= ~mask;
                self.values.items[word_idx] &= ~mask;
            }
            return;
        }
        // Widths 2..=64: one u64 per slot. Mask to `widthMask` so out-of-width
        // payload stays zero. `value & defined` implicitly canonicalizes
        // undefined bits to value=0 (any "1" outside the defined mask is
        // cleared), keeping reads consistent with the equals() invariant.
        const idx: usize = @intCast(slot);
        const m = widthMask(self.width);
        self.values.items[idx] = state.value & state.defined & m;
        self.defined.items[idx] = state.defined & m;
    }
};

pub const Circuit = struct {
    nodes: std.ArrayList(*Component),
    event_queue: EventQueue,
    next_id: u32 = 0,
    current_time: Timestamp = 0,
    listener: ?*const fn (component: *Component, new_state: BitVecState) void = null,
    /// Scratch buffer reused across `propagate()` calls. Hoisted onto the
    /// circuit so the first append in each propagation doesn't reallocate
    /// from zero capacity; instead the previous run's capacity is retained
    /// (length reset to 0 at the end of each per-timestamp iteration).
    changed_at_step: std.ArrayList(*Component) = .{},
    /// Width-tiered SoA pool array indexed by tier number (tier N owns
    /// width-N state slots). Tier 0 is reserved/unused; the convention
    /// `tier = width` makes `tiers[handle.tier]` the canonical lookup for
    /// any state. Each tier is allocated lazily by `getOrInitTier` on its
    /// first use, so a single-bit circuit pays for only one Pool rather
    /// than `MAX_WIDTH + 1` of them.
    tiers: [MAX_WIDTH + 1]?Pool = [_]?Pool{null} ** (MAX_WIDTH + 1),
    /// Benchmark counters. Present only when `COLLECT_METRICS` is true so
    /// shipping builds carry zero bytes and zero instructions for the
    /// metrics path. The conditional type is `void` (zero-sized) otherwise,
    /// so `circuit.metrics.foo` outside an `if (COLLECT_METRICS)` block is
    /// a compile error — the compiler enforces the gating for us.
    metrics: if (COLLECT_METRICS) Metrics else void = if (COLLECT_METRICS) Metrics{} else {},

    pub fn init() !Circuit {
        return .{
            .nodes = .{},
            .event_queue = EventQueue.init(),
            .listener = null,
            .changed_at_step = .{},
            .metrics = if (COLLECT_METRICS) Metrics{} else {},
        };
    }

    pub fn deinit(self: *Circuit) void {
        for (self.nodes.items) |node| {
            node.deinit();
        }
        self.nodes.deinit(memory.allocator);
        self.event_queue.deinit();
        self.changed_at_step.deinit(memory.allocator);
        for (&self.tiers) |*maybe_pool| {
            if (maybe_pool.* != null) maybe_pool.*.?.deinit();
        }
    }

    /// Returns the pool that owns `width`, allocating it lazily on first
    /// access. Cheap when the pool already exists (one null check); one
    /// `Pool.init` plus an optional store otherwise.
    fn getOrInitTier(self: *Circuit, width: u8) *Pool {
        const tier = tierIndexForWidth(width);
        if (self.tiers[tier] == null) {
            self.tiers[tier] = Pool.init(width);
        }
        return &self.tiers[tier].?;
    }

    /// Allocate a fresh state slot in the pool that owns `width`. Returns
    /// the opaque handle that future `readState`/`writeState` calls use.
    pub fn allocateStateSlot(self: *Circuit, width: u8) !PoolHandle {
        const tier = tierIndexForWidth(width);
        const pool = self.getOrInitTier(width);
        const slot = try pool.allocateSlot();
        return .{ .tier = tier, .slot = slot };
    }

    /// Read the BitVecState at `handle`. Tier dispatch happens exactly once;
    /// everything above this line sees only the value type.
    pub fn readState(self: *const Circuit, handle: PoolHandle) BitVecState {
        return self.tiers[handle.tier].?.read(handle.slot);
    }

    /// Write `state` to the slot at `handle`. The caller is responsible for
    /// the `state.width == pool.width` invariant; debug-mode asserts inside
    /// the pool catch mismatches.
    pub fn writeState(self: *Circuit, handle: PoolHandle, state: BitVecState) void {
        self.tiers[handle.tier].?.write(handle.slot, state);
    }

    pub fn notifyStateChange(self: *Circuit, component: *Component, new_state: BitVecState) void {
        if (self.listener) |listener| {
            listener(component, new_state);
        }
    }

    pub fn createComponent(self: *Circuit, kind: Component.Kind, width: u8) !*Component {
        const new_component = try Component.init(self.next_id, kind);
        // Allocate the state slot before the component is published to
        // `nodes`, so `deinit` (which never sees an in-flight component)
        // does not have to special-case the half-constructed state.
        new_component.state_handle = try self.allocateStateSlot(width);
        self.next_id += 1;
        try self.nodes.append(memory.allocator, new_component);
        return new_component;
    }

    pub fn connect(self: *Circuit, from: ComponentPortReference, to: ComponentPortReference) !void {
        _ = self;

        const fromComponent, _ = from;
        const toComponent, const toPort = to;

        try fromComponent.outputs.append(memory.allocator, toComponent);

        switch (toComponent.kind) {
            .and_gate => |*g| {
                if (std.mem.eql(u8, toPort, A_PORT_NAME)) {
                    try g.inputs_a.append(memory.allocator, fromComponent);
                } else if (std.mem.eql(u8, toPort, B_PORT_NAME)) {
                    try g.inputs_b.append(memory.allocator, fromComponent);
                } else return error.InvalidInputPort;
            },
            .not_gate => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
            .led => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
            .wire => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
            .output_pin => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
            .input_pin_gate => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
        }
    }

    pub fn propagate(self: *Circuit) !void {
        // Two-phase processing per timestamp: first commit ALL state changes
        // at time T, then walk every changed component's outputs to schedule
        // downstream events. Without this batching, a downstream gate's
        // recalculateAndReschedule could read partially-updated upstream
        // state when multiple upstream events fire at the same timestamp,
        // computing an intermediate value that then gets dedup'd by the
        // "if state == new_state, continue" check, leaving the gate stuck
        // at the wrong final value. Manifests in deep-fanout circuits where
        // a single control bit drives many parallel gates whose outputs
        // converge into a serial carry chain (e.g. 4-bit ALU with shared
        // nx/ny normalization).

        while (self.event_queue.peek()) |first| {
            const step_time = first.timestamp;
            self.current_time = step_time;

            // Phase 1: drain all events at this timestamp, applying state
            // changes immediately. Components whose state actually flipped
            // get queued for downstream notification.
            while (self.event_queue.peek()) |next_event| {
                if (next_event.timestamp != step_time) break;
                const event = self.event_queue.pop().?;
                if (COLLECT_METRICS) self.metrics.events_popped += 1;
                const component = event.component;

                // Dedup: a single BitVecState equality check decides
                // whether this event commits or is a no-op. Width=1 reads
                // are a single bit lookup on each side; equality is a
                // bitmask AND plus two compares.
                if (self.readState(component.state_handle).equals(event.new_state)) continue;
                if (COLLECT_METRICS) self.metrics.events_committed += 1;

                if (comptime log.enabled(.info)) {
                    log.info("[Time: {d}] Updating component id={d} to {s}", .{ self.current_time, component.id, event.new_state.tagName() });
                }
                self.writeState(component.state_handle, event.new_state);
                try self.changed_at_step.append(memory.allocator, component);
            }

            // Phase 2: with all state at this timestamp committed, walk
            // outputs of every changed component. Now downstream recalcs
            // see consistent upstream state.
            for (self.changed_at_step.items) |component| {
                for (component.outputs.items) |output| {
                    if (comptime log.enabled(.info)) {
                        log.info("  -> Notifying downstream component id={d}", .{output.id});
                    }
                    if (COLLECT_METRICS) self.metrics.recalcs += 1;
                    try recalculateAndReschedule(self, output, &self.event_queue, self.current_time);

                    self.notifyStateChange(output, self.readState(output.state_handle));
                }
            }
            self.changed_at_step.clearRetainingCapacity();

            // Sample queue depth after Phase 2. This IS the iteration's true
            // peak: Phase 1 only pops (queue monotonically shrinks), Phase 2
            // only adds (queue monotonically grows), so end-of-Phase-2 is
            // always the per-iteration maximum. Also equals the next
            // iteration's start-of-iteration depth (nothing happens between
            // iterations), so a second sample there would be redundant.
            if (COLLECT_METRICS) {
                const depth: u64 = @intCast(self.event_queue.heap.items.len);
                if (depth > self.metrics.peak_queue) self.metrics.peak_queue = depth;
            }
        }

        if (COLLECT_METRICS) self.metrics.final_time = self.current_time;
    }

    pub fn propagateEvent(self: *Circuit, component: *Component, new_state: BitVecState) !void {
        // Short-circuit no-op events: when the caller drives a component to
        // its current state, the event would just be popped and skipped at
        // Phase 1 (the `BitVecState.equals` dedup inside propagate), wasting
        // a queue insertion plus a pop. Skip the enqueue, but still advance
        // `current_time` by the propagation delay so the timing model, and
        // the `final_time` counter, match what the original behavior would
        // have produced.
        //
        // Dominates the pop-inefficiency picture on the truth-table corpus:
        // the bench's driver unconditionally writes every input pin on every
        // vector, so for fixtures like and_6bit ~71% of pops used to be
        // no-ops where the requested state already matched. With this short-
        // circuit, the only events that enter the queue from the outside
        // are the ones that genuinely change state; pop efficiency lifts
        // toward 100% across the corpus.
        if (self.readState(component.state_handle).equals(new_state)) {
            self.current_time += PROPAGATION_DELAY;
            if (COLLECT_METRICS) self.metrics.final_time = self.current_time;
            return;
        }

        try self.event_queue.add(.{
            .timestamp = self.current_time + PROPAGATION_DELAY,
            .component = component,
            .new_state = new_state,
        });

        try self.propagate();
    }

    pub fn printState(self: *Circuit) void {
        for (self.nodes.items) |node| {
            const s = self.readState(node.state_handle);
            log.info("Component id={d} type={s} state={s}", .{ node.id, @tagName(node.kind), s.tagName() });
        }
    }

    pub fn encodeState(self: *Circuit) ![]u8 {
        var buffer = try std.ArrayList(u8).initCapacity(memory.allocator, 0);
        defer buffer.deinit(memory.allocator);

        const len_u32: u8 = @intCast(self.nodes.items.len);
        try buffer.appendSlice(memory.allocator, std.mem.asBytes(&len_u32));

        for (self.nodes.items) |node| {
            const state = self.readState(node.state_handle);
            const encoded_state = try transport.encodeState(node, state).encode(memory.allocator);
            defer memory.allocator.free(encoded_state);

            try buffer.appendSlice(memory.allocator, encoded_state);
        }

        return buffer.toOwnedSlice(memory.allocator);
    }
};

test "output_pin kind exists and constructs" {
    comptime {
        const kind: Component.Kind = .{ .output_pin = .{} };
        _ = kind;
    }
}

test "output_pin: passes input through" {
    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} }, 1);
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, BitVecState.low(1));

        try std.testing.expect(circuit.readState(output_pin.state_handle).equals(BitVecState.low(1)));
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} }, 1);
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, BitVecState.high(1));

        try std.testing.expect(circuit.readState(output_pin.state_handle).equals(BitVecState.high(1)));
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} }, 1);
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, BitVecState.undefined_(1));

        try std.testing.expect(circuit.readState(output_pin.state_handle).equals(BitVecState.undefined_(1)));
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} }, 1);
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, BitVecState.low(1));
        try std.testing.expect(circuit.readState(output_pin.state_handle).equals(BitVecState.low(1)));

        try circuit.propagateEvent(input, BitVecState.high(1));

        try std.testing.expect(circuit.readState(output_pin.state_handle).equals(BitVecState.high(1)));
        try std.testing.expectEqual(@as(Timestamp, (PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY) * 2), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
        const output_pin_1 = try circuit.createComponent(.{ .output_pin = .{} }, 1);
        const output_pin_2 = try circuit.createComponent(.{ .output_pin = .{} }, 1);
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin_1.port(OUTPUT_PIN_IN_PORT_NAME));
        try circuit.connect(output_pin_1.port(OUTPUT_PIN_OUT_PORT_NAME), output_pin_2.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, BitVecState.high(1));

        try std.testing.expect(circuit.readState(output_pin_1.state_handle).equals(BitVecState.high(1)));
        try std.testing.expect(circuit.readState(output_pin_2.state_handle).equals(BitVecState.high(1)));
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY + (WIRE_PROPAGATION_DELAY * 2)), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const upstream = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
        const downstream = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
        try circuit.connect(upstream.port(OUT_PORT_NAME), downstream.port(IN_PORT_NAME));

        try circuit.propagateEvent(upstream, BitVecState.low(1));
        try std.testing.expect(circuit.readState(downstream.state_handle).equals(BitVecState.low(1)));

        try circuit.propagateEvent(upstream, BitVecState.high(1));
        try std.testing.expect(circuit.readState(downstream.state_handle).equals(BitVecState.high(1)));
    }
}

test "led: registers out port and drives downstream output_pin" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
    const led = try circuit.createComponent(.{ .led = .{} }, 1);
    const output_pin = try circuit.createComponent(.{ .output_pin = .{} }, 1);
    try circuit.connect(input.port(OUT_PORT_NAME), led.port(IN_PORT_NAME));
    try circuit.connect(led.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

    try circuit.propagateEvent(input, BitVecState.low(1));
    try std.testing.expect(circuit.readState(led.state_handle).equals(BitVecState.low(1)));

    try circuit.propagateEvent(input, BitVecState.high(1));
    try std.testing.expect(circuit.readState(led.state_handle).equals(BitVecState.high(1)));
}

// ============================================================================
// BitVecState / Pool unit tests. Exercise the value-type equality / flip
// rules and the tier-1 pool's slot allocator + read/write directly, without
// going through the full engine.
// ============================================================================

test "BitVecState: equality masks undefined value bits" {
    const a: BitVecState = .{ .value = 0xDEAD, .defined = 0, .width = 1 };
    const b: BitVecState = .{ .value = 0xBEEF, .defined = 0, .width = 1 };
    try std.testing.expect(a.equals(b));
    try std.testing.expect(b.equals(a));
}

test "BitVecState: equality distinguishes low / high / undefined" {
    const lo = BitVecState.low(1);
    const hi = BitVecState.high(1);
    const un = BitVecState.undefined_(1);
    try std.testing.expect(!lo.equals(hi));
    try std.testing.expect(!lo.equals(un));
    try std.testing.expect(!hi.equals(un));
    try std.testing.expect(lo.equals(BitVecState.low(1)));
    try std.testing.expect(hi.equals(BitVecState.high(1)));
    try std.testing.expect(un.equals(BitVecState.undefined_(1)));
}

test "BitVecState: equality rejects different widths" {
    const lo1 = BitVecState.low(1);
    const lo2: BitVecState = .{ .value = 0, .defined = 0b11, .width = 2 };
    try std.testing.expect(!lo1.equals(lo2));
}

test "BitVecState: flip preserves undefined, swaps defined" {
    try std.testing.expect(BitVecState.undefined_(1).flip().equals(BitVecState.undefined_(1)));
    try std.testing.expect(BitVecState.low(1).flip().equals(BitVecState.high(1)));
    try std.testing.expect(BitVecState.high(1).flip().equals(BitVecState.low(1)));
}

test "BitVecState: bitAnd width=1 matches the engine's AND predicate" {
    // Mirror the three-branch logic in `recalculateAndReschedule`'s
    // and_gate arm so the new bitwise op is provably equivalent at the
    // width the existing engine actually exercises.
    const refAnd = struct {
        fn pred(a: BitVecState, b: BitVecState) BitVecState {
            if (a.isLow() or b.isLow()) return BitVecState.low(1);
            if (a.isUndefined() or b.isUndefined()) return BitVecState.undefined_(1);
            return BitVecState.high(1);
        }
    };

    const states = [_]BitVecState{ BitVecState.low(1), BitVecState.high(1), BitVecState.undefined_(1) };
    for (states) |a| {
        for (states) |b| {
            try std.testing.expect(a.bitAnd(b).equals(refAnd.pred(a, b)));
        }
    }
}

test "BitVecState: bitOr width=1 truth table" {
    const lo = BitVecState.low(1);
    const hi = BitVecState.high(1);
    const un = BitVecState.undefined_(1);

    try std.testing.expect(lo.bitOr(lo).equals(lo));
    try std.testing.expect(lo.bitOr(hi).equals(hi));
    try std.testing.expect(lo.bitOr(un).equals(un));
    try std.testing.expect(hi.bitOr(lo).equals(hi));
    try std.testing.expect(hi.bitOr(hi).equals(hi));
    try std.testing.expect(hi.bitOr(un).equals(hi));
    try std.testing.expect(un.bitOr(lo).equals(un));
    try std.testing.expect(un.bitOr(hi).equals(hi));
    try std.testing.expect(un.bitOr(un).equals(un));
}

test "BitVecState: bitXor width=1 truth table" {
    const lo = BitVecState.low(1);
    const hi = BitVecState.high(1);
    const un = BitVecState.undefined_(1);

    try std.testing.expect(lo.bitXor(lo).equals(lo));
    try std.testing.expect(lo.bitXor(hi).equals(hi));
    try std.testing.expect(lo.bitXor(un).equals(un));
    try std.testing.expect(hi.bitXor(lo).equals(hi));
    try std.testing.expect(hi.bitXor(hi).equals(lo));
    try std.testing.expect(hi.bitXor(un).equals(un));
    try std.testing.expect(un.bitXor(lo).equals(un));
    try std.testing.expect(un.bitXor(hi).equals(un));
    try std.testing.expect(un.bitXor(un).equals(un));
}

test "BitVecState: bitAnd at widths > 1" {
    // Width 4, all-defined: per-bit AND of arbitrary patterns.
    {
        const a = BitVecState{ .value = 0b1100, .defined = 0b1111, .width = 4 };
        const b = BitVecState{ .value = 0b1010, .defined = 0b1111, .width = 4 };
        const result = a.bitAnd(b);
        try std.testing.expectEqual(@as(u64, 0b1000), result.value);
        try std.testing.expectEqual(@as(u64, 0b1111), result.defined);
        try std.testing.expectEqual(@as(u8, 4), result.width);
    }

    // Width 4, mixed undefined: a defined-low input forces the result bit
    // to low even when the other input is undefined at that bit.
    //   a (bit 0..3): hi, undef, lo, hi  -> value=0b1001, defined=0b1101
    //   b (bit 0..3): lo, hi,    hi, hi  -> value=0b1110, defined=0b1111
    //   result:       lo, undef, lo, hi  -> value=0b1000, defined=0b1101
    {
        const a = BitVecState{ .value = 0b1001, .defined = 0b1101, .width = 4 };
        const b = BitVecState{ .value = 0b1110, .defined = 0b1111, .width = 4 };
        const result = a.bitAnd(b);
        try std.testing.expectEqual(@as(u64, 0b1000), result.value);
        try std.testing.expectEqual(@as(u64, 0b1101), result.defined);
    }

    // Width 8, all-defined.
    {
        const a = BitVecState{ .value = 0xF0, .defined = 0xFF, .width = 8 };
        const b = BitVecState{ .value = 0xAA, .defined = 0xFF, .width = 8 };
        const result = a.bitAnd(b);
        try std.testing.expectEqual(@as(u64, 0xA0), result.value);
        try std.testing.expectEqual(@as(u64, 0xFF), result.defined);
    }

    // Width 64, all-defined: full-register pattern.
    {
        const a = BitVecState{ .value = 0xF0F0F0F0F0F0F0F0, .defined = std.math.maxInt(u64), .width = 64 };
        const b = BitVecState{ .value = 0xAAAAAAAAAAAAAAAA, .defined = std.math.maxInt(u64), .width = 64 };
        const result = a.bitAnd(b);
        try std.testing.expectEqual(@as(u64, 0xA0A0A0A0A0A0A0A0), result.value);
        try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), result.defined);
    }

    // All-undefined remains all-undefined at any width.
    try std.testing.expect(BitVecState.undefined_(4).bitAnd(BitVecState.undefined_(4)).equals(BitVecState.undefined_(4)));
    try std.testing.expect(BitVecState.undefined_(64).bitAnd(BitVecState.undefined_(64)).equals(BitVecState.undefined_(64)));
}

test "BitVecState: bitOr at widths > 1" {
    // Width 4, all-defined: per-bit OR of arbitrary patterns.
    {
        const a = BitVecState{ .value = 0b1100, .defined = 0b1111, .width = 4 };
        const b = BitVecState{ .value = 0b1010, .defined = 0b1111, .width = 4 };
        const result = a.bitOr(b);
        try std.testing.expectEqual(@as(u64, 0b1110), result.value);
        try std.testing.expectEqual(@as(u64, 0b1111), result.defined);
    }

    // Width 4, mixed undefined: a defined-high input forces the result bit
    // to high even when the other input is undefined at that bit.
    //   a (bit 0..3): hi, undef, lo, hi  -> value=0b1001, defined=0b1101
    //   b (bit 0..3): lo, hi,    hi, lo  -> value=0b0110, defined=0b1111
    //   result:       hi, hi,    hi, hi  -> value=0b1111, defined=0b1111
    {
        const a = BitVecState{ .value = 0b1001, .defined = 0b1101, .width = 4 };
        const b = BitVecState{ .value = 0b0110, .defined = 0b1111, .width = 4 };
        const result = a.bitOr(b);
        try std.testing.expectEqual(@as(u64, 0b1111), result.value);
        try std.testing.expectEqual(@as(u64, 0b1111), result.defined);
    }

    // Width 8, all-defined: complementary halves OR to all-ones.
    {
        const a = BitVecState{ .value = 0xF0, .defined = 0xFF, .width = 8 };
        const b = BitVecState{ .value = 0x0F, .defined = 0xFF, .width = 8 };
        const result = a.bitOr(b);
        try std.testing.expectEqual(@as(u64, 0xFF), result.value);
        try std.testing.expectEqual(@as(u64, 0xFF), result.defined);
    }

    // Width 64, all-defined.
    {
        const a = BitVecState{ .value = 0xF0F0F0F0F0F0F0F0, .defined = std.math.maxInt(u64), .width = 64 };
        const b = BitVecState{ .value = 0x0F0F0F0F0F0F0F0F, .defined = std.math.maxInt(u64), .width = 64 };
        const result = a.bitOr(b);
        try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), result.value);
        try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), result.defined);
    }

    // All-undefined remains all-undefined.
    try std.testing.expect(BitVecState.undefined_(4).bitOr(BitVecState.undefined_(4)).equals(BitVecState.undefined_(4)));
    try std.testing.expect(BitVecState.undefined_(64).bitOr(BitVecState.undefined_(64)).equals(BitVecState.undefined_(64)));
}

test "BitVecState: bitXor at widths > 1" {
    // Width 4, all-defined: per-bit XOR of arbitrary patterns.
    {
        const a = BitVecState{ .value = 0b1100, .defined = 0b1111, .width = 4 };
        const b = BitVecState{ .value = 0b1010, .defined = 0b1111, .width = 4 };
        const result = a.bitXor(b);
        try std.testing.expectEqual(@as(u64, 0b0110), result.value);
        try std.testing.expectEqual(@as(u64, 0b1111), result.defined);
    }

    // Width 4, mixed undefined: any undefined input bit makes the result
    // bit undefined, regardless of the other operand. The XOR's "defined
    // iff both defined" rule shows up here as defined = a.defined & b.defined.
    //   a (bit 0..3): hi, undef, lo, hi  -> value=0b1001, defined=0b1101
    //   b (bit 0..3): lo, hi,    hi, lo  -> value=0b0110, defined=0b1111
    //   defined = 0b1101 & 0b1111 = 0b1101
    //   value   = (0b1001 ^ 0b0110) & 0b1101 = 0b1111 & 0b1101 = 0b1101
    {
        const a = BitVecState{ .value = 0b1001, .defined = 0b1101, .width = 4 };
        const b = BitVecState{ .value = 0b0110, .defined = 0b1111, .width = 4 };
        const result = a.bitXor(b);
        try std.testing.expectEqual(@as(u64, 0b1101), result.value);
        try std.testing.expectEqual(@as(u64, 0b1101), result.defined);
    }

    // Width 8, all-defined: all-ones XOR with low nibble flips the low half.
    {
        const a = BitVecState{ .value = 0xFF, .defined = 0xFF, .width = 8 };
        const b = BitVecState{ .value = 0x0F, .defined = 0xFF, .width = 8 };
        const result = a.bitXor(b);
        try std.testing.expectEqual(@as(u64, 0xF0), result.value);
        try std.testing.expectEqual(@as(u64, 0xFF), result.defined);
    }

    // Width 64, all-defined.
    {
        const a = BitVecState{ .value = std.math.maxInt(u64), .defined = std.math.maxInt(u64), .width = 64 };
        const b = BitVecState{ .value = 0x0F0F0F0F0F0F0F0F, .defined = std.math.maxInt(u64), .width = 64 };
        const result = a.bitXor(b);
        try std.testing.expectEqual(@as(u64, 0xF0F0F0F0F0F0F0F0), result.value);
        try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), result.defined);
    }

    // Any undefined input propagates as undefined.
    {
        const lo4 = BitVecState.low(4);
        const un4 = BitVecState.undefined_(4);
        try std.testing.expect(lo4.bitXor(un4).equals(un4));
        try std.testing.expect(un4.bitXor(lo4).equals(un4));
        try std.testing.expect(un4.bitXor(un4).equals(un4));
    }
}

test "BitVecState: bitwise ops mask out-of-width payload to zero" {
    // The public constructors normally prevent out-of-width payload, but
    // the bitwise ops still apply `widthMask` to result bitmaps so a
    // hand-built value with dirty high bits cannot leak past `width`.
    const dirty_a = BitVecState{ .value = 0xFF, .defined = 0xFF, .width = 4 };
    const dirty_b = BitVecState{ .value = 0xFF, .defined = 0xFF, .width = 4 };
    const high_bits = ~widthMask(4);

    try std.testing.expectEqual(@as(u64, 0), dirty_a.bitAnd(dirty_b).value & high_bits);
    try std.testing.expectEqual(@as(u64, 0), dirty_a.bitAnd(dirty_b).defined & high_bits);
    try std.testing.expectEqual(@as(u64, 0), dirty_a.bitOr(dirty_b).value & high_bits);
    try std.testing.expectEqual(@as(u64, 0), dirty_a.bitOr(dirty_b).defined & high_bits);
    try std.testing.expectEqual(@as(u64, 0), dirty_a.bitXor(dirty_b).value & high_bits);
    try std.testing.expectEqual(@as(u64, 0), dirty_a.bitXor(dirty_b).defined & high_bits);
}

test "BitVecState: transport byte matches enum declaration order" {
    // The WASM API contract uses @intFromEnum(State), which is the State
    // enum's declaration order: undefined=0, low=1, high=2. The new
    // BitVecState encoding must produce the same bytes for width=1 so
    // transport.encodeState stays byte-identical across the refactor.
    try std.testing.expectEqual(@as(u8, 0), BitVecState.undefined_(1).toTransportByte());
    try std.testing.expectEqual(@as(u8, 1), BitVecState.low(1).toTransportByte());
    try std.testing.expectEqual(@as(u8, 2), BitVecState.high(1).toTransportByte());
}

test "BitVecState: fromInt / toInt round-trip mirrors State" {
    try std.testing.expect(BitVecState.fromInt(0, 1).equals(BitVecState.low(1)));
    try std.testing.expect(BitVecState.fromInt(1, 1).equals(BitVecState.high(1)));
    try std.testing.expect(BitVecState.fromInt(2, 1).equals(BitVecState.undefined_(1)));
    try std.testing.expect(BitVecState.fromInt(-1, 1).equals(BitVecState.undefined_(1)));

    // toInt mirrors State.toInt (low=0, high=1, else=2), distinct from the
    // transport byte ordering.
    try std.testing.expectEqual(@as(i32, 0), BitVecState.low(1).toInt());
    try std.testing.expectEqual(@as(i32, 1), BitVecState.high(1).toInt());
    try std.testing.expectEqual(@as(i32, 2), BitVecState.undefined_(1).toInt());
}

test "Pool: width=1 round-trip" {
    var pool = Pool.init(1);
    defer pool.deinit();

    const a = try pool.allocateSlot();
    const b = try pool.allocateSlot();
    try std.testing.expectEqual(@as(u32, 0), a);
    try std.testing.expectEqual(@as(u32, 1), b);

    try std.testing.expect(pool.read(a).equals(BitVecState.undefined_(1)));
    try std.testing.expect(pool.read(b).equals(BitVecState.undefined_(1)));

    pool.write(a, BitVecState.low(1));
    pool.write(b, BitVecState.high(1));
    try std.testing.expect(pool.read(a).equals(BitVecState.low(1)));
    try std.testing.expect(pool.read(b).equals(BitVecState.high(1)));

    pool.write(a, BitVecState.undefined_(1));
    try std.testing.expect(pool.read(a).equals(BitVecState.undefined_(1)));
    try std.testing.expect(pool.read(b).equals(BitVecState.high(1)));
}

test "Pool: grows across 64-slot boundary, parallel buffers stay in lockstep" {
    var pool = Pool.init(1);
    defer pool.deinit();

    var slots: [130]u32 = undefined;
    for (&slots, 0..) |*s, i| {
        s.* = try pool.allocateSlot();
        try std.testing.expectEqual(@as(u32, @intCast(i)), s.*);
    }

    // Two words allocated for 65+ slots, three for 129+ slots.
    try std.testing.expectEqual(@as(usize, 3), pool.values.items.len);
    try std.testing.expectEqual(@as(usize, 3), pool.defined.items.len);

    // Drive an alternating pattern across the boundary; confirm round-trip.
    for (slots, 0..) |s, i| {
        pool.write(s, if (i % 2 == 0) BitVecState.low(1) else BitVecState.high(1));
    }
    for (slots, 0..) |s, i| {
        const expected = if (i % 2 == 0) BitVecState.low(1) else BitVecState.high(1);
        try std.testing.expect(pool.read(s).equals(expected));
    }
}

test "Pool: undefined writes clear both value and defined bits" {
    var pool = Pool.init(1);
    defer pool.deinit();

    const s = try pool.allocateSlot();
    pool.write(s, BitVecState.high(1));
    try std.testing.expect(pool.read(s).equals(BitVecState.high(1)));

    pool.write(s, BitVecState.undefined_(1));
    const got = pool.read(s);
    try std.testing.expectEqual(@as(u64, 0), got.value);
    try std.testing.expectEqual(@as(u64, 0), got.defined);
    try std.testing.expect(got.equals(BitVecState.undefined_(1)));
}

test "Pool: width 4 round-trip smoke test" {
    // Smallest path through the new width > 1 storage: allocate a slot,
    // observe its initial undefined state, write low / high / undefined,
    // confirm read-back equals each write.
    var pool = Pool.init(4);
    defer pool.deinit();

    const s = try pool.allocateSlot();
    try std.testing.expect(pool.read(s).equals(BitVecState.undefined_(4)));

    pool.write(s, BitVecState.low(4));
    try std.testing.expect(pool.read(s).equals(BitVecState.low(4)));

    pool.write(s, BitVecState.high(4));
    try std.testing.expect(pool.read(s).equals(BitVecState.high(4)));

    pool.write(s, BitVecState.undefined_(4));
    try std.testing.expect(pool.read(s).equals(BitVecState.undefined_(4)));
}

test "Pool: round-trip at widths 4, 8, 64" {
    // Parameterized round-trip: undefined -> low -> high -> undefined for
    // each of the canonical wider widths. `inline for` unrolls so each
    // width sees its own comptime-bound Pool.init call.
    inline for (.{ 4, 8, 64 }) |w| {
        var pool = Pool.init(w);
        defer pool.deinit();

        const s = try pool.allocateSlot();
        try std.testing.expect(pool.read(s).equals(BitVecState.undefined_(w)));

        pool.write(s, BitVecState.low(w));
        try std.testing.expect(pool.read(s).equals(BitVecState.low(w)));

        pool.write(s, BitVecState.high(w));
        try std.testing.expect(pool.read(s).equals(BitVecState.high(w)));

        pool.write(s, BitVecState.undefined_(w));
        try std.testing.expect(pool.read(s).equals(BitVecState.undefined_(w)));
    }
}

test "Pool: width 4 stores mixed defined/undefined patterns" {
    var pool = Pool.init(4);
    defer pool.deinit();

    const s = try pool.allocateSlot();
    // Per-bit (LSB first): hi, undef, lo, hi -> value=0b1001, defined=0b1101
    const mixed = BitVecState{ .value = 0b1001, .defined = 0b1101, .width = 4 };
    pool.write(s, mixed);

    const got = pool.read(s);
    try std.testing.expectEqual(@as(u64, 0b1001), got.value);
    try std.testing.expectEqual(@as(u64, 0b1101), got.defined);
    try std.testing.expectEqual(@as(u8, 4), got.width);
}

test "Pool: widths > 1 allocate one u64 per slot and isolate writes" {
    var pool = Pool.init(8);
    defer pool.deinit();

    var slots: [10]u32 = undefined;
    for (&slots, 0..) |*s, i| {
        s.* = try pool.allocateSlot();
        try std.testing.expectEqual(@as(u32, @intCast(i)), s.*);
    }

    // Ten slots -> ten u64s in each buffer (one per slot, no packing).
    // At width=1 the same ten slots would share one u64; this confirms
    // the wider storage path is selected.
    try std.testing.expectEqual(@as(usize, 10), pool.values.items.len);
    try std.testing.expectEqual(@as(usize, 10), pool.defined.items.len);

    // Distinct writes to different slots must not interfere.
    for (slots, 0..) |s, i| {
        pool.write(s, BitVecState{ .value = @intCast(i), .defined = 0xFF, .width = 8 });
    }
    for (slots, 0..) |s, i| {
        const got = pool.read(s);
        try std.testing.expectEqual(@as(u64, @intCast(i)), got.value);
        try std.testing.expectEqual(@as(u64, 0xFF), got.defined);
    }
}

test "Pool: widths > 1 write canonicalizes undefined and out-of-width bits" {
    var pool = Pool.init(4);
    defer pool.deinit();

    const s = try pool.allocateSlot();

    // Dirty input: bit 1 is undefined (defined=0) but its value bit is set;
    // bits beyond width 4 are also set in both buffers. Canonical form has
    // undefined positions cleared from value, and bits >= 4 cleared in both.
    //   input    value=0b111011, defined=0b111101, width=4
    //   canonical value=0b001001, defined=0b001101
    const dirty = BitVecState{ .value = 0b111011, .defined = 0b111101, .width = 4 };
    pool.write(s, dirty);

    const got = pool.read(s);
    try std.testing.expectEqual(@as(u64, 0), got.value & ~widthMask(4));
    try std.testing.expectEqual(@as(u64, 0), got.defined & ~widthMask(4));
    try std.testing.expectEqual(@as(u64, 0b1001), got.value);
    try std.testing.expectEqual(@as(u64, 0b1101), got.defined);
}

test "Pool: widths > 1 undefined overwrite clears both buffers" {
    var pool = Pool.init(8);
    defer pool.deinit();

    const s = try pool.allocateSlot();
    pool.write(s, BitVecState.high(8));
    try std.testing.expect(pool.read(s).equals(BitVecState.high(8)));

    pool.write(s, BitVecState.undefined_(8));
    const got = pool.read(s);
    try std.testing.expectEqual(@as(u64, 0), got.value);
    try std.testing.expectEqual(@as(u64, 0), got.defined);
    try std.testing.expect(got.equals(BitVecState.undefined_(8)));
}

test "Circuit: allocateStateSlot returns a tier=width handle and round-trips" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const h1 = try circuit.allocateStateSlot(1);
    const h2 = try circuit.allocateStateSlot(1);
    // Width=1 now lives in tier 1 (the convention `tier = width`); tier 0
    // is reserved/unused.
    try std.testing.expectEqual(@as(u8, 1), h1.tier);
    try std.testing.expectEqual(@as(u32, 0), h1.slot);
    try std.testing.expectEqual(@as(u8, 1), h2.tier);
    try std.testing.expectEqual(@as(u32, 1), h2.slot);

    try std.testing.expect(circuit.readState(h1).equals(BitVecState.undefined_(1)));
    circuit.writeState(h1, BitVecState.high(1));
    circuit.writeState(h2, BitVecState.low(1));
    try std.testing.expect(circuit.readState(h1).equals(BitVecState.high(1)));
    try std.testing.expect(circuit.readState(h2).equals(BitVecState.low(1)));
}

test "Circuit: createComponent at widths 4, 8, 64 lands in the matching tier" {
    inline for (.{ 4, 8, 64 }) |w| {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const comp = try circuit.createComponent(.{ .wire = .{} }, w);
        // Handle's tier equals the requested width under `tier = width`.
        try std.testing.expectEqual(@as(u8, w), comp.state_handle.tier);
        try std.testing.expectEqual(@as(u32, 0), comp.state_handle.slot);
        // Initial state is undefined at the requested width.
        try std.testing.expect(circuit.readState(comp.state_handle).equals(BitVecState.undefined_(w)));

        // Round-trip a defined value to confirm the slot dispatches to the
        // right pool's storage on both read and write.
        circuit.writeState(comp.state_handle, BitVecState.high(w));
        try std.testing.expect(circuit.readState(comp.state_handle).equals(BitVecState.high(w)));
    }
}

test "Circuit: mixed-width components allocate in independent tiers" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const scalar = try circuit.createComponent(.{ .wire = .{} }, 1);
    const bus4 = try circuit.createComponent(.{ .wire = .{} }, 4);
    const bus8 = try circuit.createComponent(.{ .wire = .{} }, 8);
    const scalar2 = try circuit.createComponent(.{ .wire = .{} }, 1);

    // Each width gets its own tier; same-width components share a tier
    // and receive dense slot indices within it.
    try std.testing.expectEqual(@as(u8, 1), scalar.state_handle.tier);
    try std.testing.expectEqual(@as(u32, 0), scalar.state_handle.slot);
    try std.testing.expectEqual(@as(u8, 4), bus4.state_handle.tier);
    try std.testing.expectEqual(@as(u32, 0), bus4.state_handle.slot);
    try std.testing.expectEqual(@as(u8, 8), bus8.state_handle.tier);
    try std.testing.expectEqual(@as(u32, 0), bus8.state_handle.slot);
    try std.testing.expectEqual(@as(u8, 1), scalar2.state_handle.tier);
    try std.testing.expectEqual(@as(u32, 1), scalar2.state_handle.slot);

    // Writes to one tier must not bleed into another.
    circuit.writeState(scalar.state_handle, BitVecState.high(1));
    circuit.writeState(bus4.state_handle, BitVecState{ .value = 0b1010, .defined = 0b1111, .width = 4 });
    circuit.writeState(bus8.state_handle, BitVecState.low(8));
    circuit.writeState(scalar2.state_handle, BitVecState.low(1));

    try std.testing.expect(circuit.readState(scalar.state_handle).equals(BitVecState.high(1)));
    try std.testing.expectEqual(@as(u64, 0b1010), circuit.readState(bus4.state_handle).value);
    try std.testing.expectEqual(@as(u64, 0b1111), circuit.readState(bus4.state_handle).defined);
    try std.testing.expect(circuit.readState(bus8.state_handle).equals(BitVecState.low(8)));
    try std.testing.expect(circuit.readState(scalar2.state_handle).equals(BitVecState.low(1)));
}

test "Circuit: lazy tier init only allocates tiers actually used" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    // Empty Circuit: every tier slot is null.
    for (circuit.tiers) |maybe_pool| {
        try std.testing.expect(maybe_pool == null);
    }

    // After allocating at width 4: only tier 4 exists.
    _ = try circuit.createComponent(.{ .wire = .{} }, 4);
    try std.testing.expect(circuit.tiers[4] != null);
    try std.testing.expect(circuit.tiers[1] == null);
    try std.testing.expect(circuit.tiers[8] == null);
    try std.testing.expect(circuit.tiers[64] == null);
    // Tier 0 stays null forever (reserved/unused under `tier = width`).
    try std.testing.expect(circuit.tiers[0] == null);

    // After allocating at width 1: tiers 1 and 4 exist; others still null.
    _ = try circuit.createComponent(.{ .wire = .{} }, 1);
    try std.testing.expect(circuit.tiers[1] != null);
    try std.testing.expect(circuit.tiers[4] != null);
    try std.testing.expect(circuit.tiers[8] == null);
    try std.testing.expect(circuit.tiers[64] == null);
}

test "Circuit: deinit frees every allocated tier with mixed widths" {
    // Build a Circuit that touches four different tiers, then deinit.
    // Zig's debug allocator catches double-frees and leaks at scope exit;
    // a clean test pass here is the evidence that deinit walks every
    // non-null tier and frees its ArrayLists.
    var circuit = try Circuit.init();
    _ = try circuit.createComponent(.{ .wire = .{} }, 1);
    _ = try circuit.createComponent(.{ .wire = .{} }, 4);
    _ = try circuit.createComponent(.{ .wire = .{} }, 8);
    _ = try circuit.createComponent(.{ .wire = .{} }, 64);
    // Force allocator growth in each tier so deinit has buffers to free.
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        _ = try circuit.createComponent(.{ .wire = .{} }, 4);
        _ = try circuit.createComponent(.{ .wire = .{} }, 8);
    }
    circuit.deinit();
}

// ============================================================================
// End-to-end engine tests over the BitVecState / pool surface. State lives
// exclusively in the per-tier SoA pool; `Circuit.createComponent` allocates
// a slot per component and `propagate()` writes through `Circuit.writeState`.
// ============================================================================

test "engine: pool view tracks state across a propagation chain" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
    const not_gate = try circuit.createComponent(.{ .not_gate = .{} }, 1);
    const out = try circuit.createComponent(.{ .output_pin = .{} }, 1);
    try circuit.connect(input.port(OUT_PORT_NAME), not_gate.port(IN_PORT_NAME));
    try circuit.connect(not_gate.port(OUT_PORT_NAME), out.port(OUTPUT_PIN_IN_PORT_NAME));

    // Every component got a fresh pool slot.
    try std.testing.expectEqual(@as(u32, 0), input.state_handle.slot);
    try std.testing.expectEqual(@as(u32, 1), not_gate.state_handle.slot);
    try std.testing.expectEqual(@as(u32, 2), out.state_handle.slot);

    try circuit.propagateEvent(input, BitVecState.low(1));

    // NOT(low) = high, output_pin relays it.
    try std.testing.expect(circuit.readState(input.state_handle).equals(BitVecState.low(1)));
    try std.testing.expect(circuit.readState(not_gate.state_handle).equals(BitVecState.high(1)));
    try std.testing.expect(circuit.readState(out.state_handle).equals(BitVecState.high(1)));

    try circuit.propagateEvent(input, BitVecState.high(1));
    try std.testing.expect(circuit.readState(not_gate.state_handle).equals(BitVecState.low(1)));
    try std.testing.expect(circuit.readState(out.state_handle).equals(BitVecState.low(1)));
}

test "engine: pool slot indices are dense and unique" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    var ids: [70]u32 = undefined;
    for (&ids, 0..) |*slot, i| {
        const comp = try circuit.createComponent(.{ .wire = .{} }, 1);
        slot.* = comp.state_handle.slot;
        try std.testing.expectEqual(@as(u32, @intCast(i)), slot.*);
        // Width=1 components live in tier 1 under the `tier = width` rule.
        try std.testing.expectEqual(@as(u8, 1), comp.state_handle.tier);
    }

    // Slot 64 crossed the first word boundary; confirm the second word
    // actually exists on both buffers of the lazily-initialized tier-1 pool.
    try std.testing.expect(circuit.tiers[1].?.values.items.len >= 2);
    try std.testing.expect(circuit.tiers[1].?.defined.items.len >= 2);
}

test "engine: width=4 AND gate propagates bit-by-bit through full circuit" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const a = try circuit.createComponent(.{ .input_pin_gate = .{} }, 4);
    const b = try circuit.createComponent(.{ .input_pin_gate = .{} }, 4);
    const gate = try circuit.createComponent(.{ .and_gate = .{} }, 4);
    const out = try circuit.createComponent(.{ .output_pin = .{} }, 4);
    try circuit.connect(a.port(OUT_PORT_NAME), gate.port(A_PORT_NAME));
    try circuit.connect(b.port(OUT_PORT_NAME), gate.port(B_PORT_NAME));
    try circuit.connect(gate.port(OUT_PORT_NAME), out.port(OUTPUT_PIN_IN_PORT_NAME));

    // 0b1100 AND 0b1010 = 0b1000 (only bit 3 high in both operands).
    try circuit.propagateEvent(a, BitVecState{ .value = 0b1100, .defined = 0b1111, .width = 4 });
    try circuit.propagateEvent(b, BitVecState{ .value = 0b1010, .defined = 0b1111, .width = 4 });
    var result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0b1000), result.value);
    try std.testing.expectEqual(@as(u64, 0b1111), result.defined);
    try std.testing.expectEqual(@as(u8, 4), result.width);

    // All-ones AND zero = zero across every bit.
    try circuit.propagateEvent(a, BitVecState.high(4));
    try circuit.propagateEvent(b, BitVecState.low(4));
    result = circuit.readState(out.state_handle);
    try std.testing.expect(result.equals(BitVecState.low(4)));

    // Mixed-defined operand: defined-low at any bit forces the result
    // bit low even when the other operand is undefined there.
    //   a (LSB..MSB): hi, undef, lo, hi -> value=0b1001, defined=0b1101
    //   b (LSB..MSB): hi, hi,    hi, hi -> value=0b1111, defined=0b1111
    //   result:       hi, undef, lo, hi -> value=0b1001, defined=0b1101
    try circuit.propagateEvent(a, BitVecState{ .value = 0b1001, .defined = 0b1101, .width = 4 });
    try circuit.propagateEvent(b, BitVecState.high(4));
    result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0b1001), result.value);
    try std.testing.expectEqual(@as(u64, 0b1101), result.defined);
}

test "engine: width=4 NOT gate flips defined bits, preserves undefined" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 4);
    const inverter = try circuit.createComponent(.{ .not_gate = .{} }, 4);
    const out = try circuit.createComponent(.{ .output_pin = .{} }, 4);
    try circuit.connect(input.port(OUT_PORT_NAME), inverter.port(IN_PORT_NAME));
    try circuit.connect(inverter.port(OUT_PORT_NAME), out.port(OUTPUT_PIN_IN_PORT_NAME));

    // NOT 0b1010 = 0b0101.
    try circuit.propagateEvent(input, BitVecState{ .value = 0b1010, .defined = 0b1111, .width = 4 });
    var result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0b0101), result.value);
    try std.testing.expectEqual(@as(u64, 0b1111), result.defined);

    // NOT all-high = all-low.
    try circuit.propagateEvent(input, BitVecState.high(4));
    result = circuit.readState(out.state_handle);
    try std.testing.expect(result.equals(BitVecState.low(4)));

    // Mixed: undefined bits stay undefined; defined bits flip.
    //   input  (LSB..MSB): hi, undef, lo, hi -> value=0b1001, defined=0b1101
    //   output (LSB..MSB): lo, undef, hi, lo -> value=0b0100, defined=0b1101
    try circuit.propagateEvent(input, BitVecState{ .value = 0b1001, .defined = 0b1101, .width = 4 });
    result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0b0100), result.value);
    try std.testing.expectEqual(@as(u64, 0b1101), result.defined);
}

test "engine: width=64 NOT gate handles full-register patterns" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 64);
    const inverter = try circuit.createComponent(.{ .not_gate = .{} }, 64);
    const out = try circuit.createComponent(.{ .output_pin = .{} }, 64);
    try circuit.connect(input.port(OUT_PORT_NAME), inverter.port(IN_PORT_NAME));
    try circuit.connect(inverter.port(OUT_PORT_NAME), out.port(OUTPUT_PIN_IN_PORT_NAME));

    // NOT 0xF0F0... = 0x0F0F...
    try circuit.propagateEvent(input, BitVecState{
        .value = 0xF0F0F0F0F0F0F0F0,
        .defined = std.math.maxInt(u64),
        .width = 64,
    });
    var result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0x0F0F0F0F0F0F0F0F), result.value);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), result.defined);

    // NOT all-high = all-low at width 64.
    try circuit.propagateEvent(input, BitVecState.high(64));
    result = circuit.readState(out.state_handle);
    try std.testing.expect(result.equals(BitVecState.low(64)));
}

test "engine: width=4 wire passes multi-bit state through unchanged" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 4);
    const buf = try circuit.createComponent(.{ .wire = .{} }, 4);
    const out = try circuit.createComponent(.{ .output_pin = .{} }, 4);
    try circuit.connect(input.port(OUT_PORT_NAME), buf.port(IN_PORT_NAME));
    try circuit.connect(buf.port(OUT_PORT_NAME), out.port(OUTPUT_PIN_IN_PORT_NAME));

    try circuit.propagateEvent(input, BitVecState{ .value = 0b1010, .defined = 0b1111, .width = 4 });
    const result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0b1010), result.value);
    try std.testing.expectEqual(@as(u64, 0b1111), result.defined);
}

test "engine: width=8 LED records the driven state across all bits" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 8);
    const led = try circuit.createComponent(.{ .led = .{} }, 8);
    try circuit.connect(input.port(OUT_PORT_NAME), led.port(IN_PORT_NAME));

    try circuit.propagateEvent(input, BitVecState{ .value = 0xAB, .defined = 0xFF, .width = 8 });
    const driven = circuit.readState(led.state_handle);
    try std.testing.expectEqual(@as(u64, 0xAB), driven.value);
    try std.testing.expectEqual(@as(u64, 0xFF), driven.defined);

    try circuit.propagateEvent(input, BitVecState.undefined_(8));
    try std.testing.expect(circuit.readState(led.state_handle).equals(BitVecState.undefined_(8)));
}

test "engine: width=2 AND gate covers two-bit combinations including undefined" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const a = try circuit.createComponent(.{ .input_pin_gate = .{} }, 2);
    const b = try circuit.createComponent(.{ .input_pin_gate = .{} }, 2);
    const gate = try circuit.createComponent(.{ .and_gate = .{} }, 2);
    const out = try circuit.createComponent(.{ .output_pin = .{} }, 2);
    try circuit.connect(a.port(OUT_PORT_NAME), gate.port(A_PORT_NAME));
    try circuit.connect(b.port(OUT_PORT_NAME), gate.port(B_PORT_NAME));
    try circuit.connect(gate.port(OUT_PORT_NAME), out.port(OUTPUT_PIN_IN_PORT_NAME));

    // 0b01 AND 0b10 = 0b00: no bit position has both operands high.
    try circuit.propagateEvent(a, BitVecState{ .value = 0b01, .defined = 0b11, .width = 2 });
    try circuit.propagateEvent(b, BitVecState{ .value = 0b10, .defined = 0b11, .width = 2 });
    var result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0b00), result.value);
    try std.testing.expectEqual(@as(u64, 0b11), result.defined);
    try std.testing.expectEqual(@as(u8, 2), result.width);

    // 0b11 AND 0b10 = 0b10: bit 1 is high in both operands; bit 0 fails.
    try circuit.propagateEvent(a, BitVecState{ .value = 0b11, .defined = 0b11, .width = 2 });
    try circuit.propagateEvent(b, BitVecState{ .value = 0b10, .defined = 0b11, .width = 2 });
    result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0b10), result.value);
    try std.testing.expectEqual(@as(u64, 0b11), result.defined);

    // Mixed-defined: a (bit 0..1) = undef, hi -> value=0b10, defined=0b10;
    //                b (bit 0..1) = hi,    hi -> value=0b11, defined=0b11.
    // Result bit 1 = hi (both defined-high); bit 0 stays undefined.
    try circuit.propagateEvent(a, BitVecState{ .value = 0b10, .defined = 0b10, .width = 2 });
    try circuit.propagateEvent(b, BitVecState.high(2));
    result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0b10), result.value);
    try std.testing.expectEqual(@as(u64, 0b10), result.defined);
}

test "engine: width=8 NOT gate inverts a byte and preserves undefined nibbles" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 8);
    const inverter = try circuit.createComponent(.{ .not_gate = .{} }, 8);
    const out = try circuit.createComponent(.{ .output_pin = .{} }, 8);
    try circuit.connect(input.port(OUT_PORT_NAME), inverter.port(IN_PORT_NAME));
    try circuit.connect(inverter.port(OUT_PORT_NAME), out.port(OUTPUT_PIN_IN_PORT_NAME));

    // NOT 0xAA = 0x55: alternating bit pattern flips perfectly.
    try circuit.propagateEvent(input, BitVecState{ .value = 0xAA, .defined = 0xFF, .width = 8 });
    var result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0x55), result.value);
    try std.testing.expectEqual(@as(u64, 0xFF), result.defined);

    // NOT all-high = all-low at byte width.
    try circuit.propagateEvent(input, BitVecState.high(8));
    result = circuit.readState(out.state_handle);
    try std.testing.expect(result.equals(BitVecState.low(8)));

    // Mixed: upper nibble defined, lower nibble undefined.
    //   input  value=0xA5, defined=0xF0  -> defined bits in value are 0xA0
    //   flip masks (~value & widthMask & defined) = 0x5A & 0xF0 = 0x50
    //   undefined lower nibble stays undefined: value=0x50, defined=0xF0.
    try circuit.propagateEvent(input, BitVecState{ .value = 0xA5, .defined = 0xF0, .width = 8 });
    result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0x50), result.value);
    try std.testing.expectEqual(@as(u64, 0xF0), result.defined);
}

test "engine: width=64 wire passes a full-register pattern through unchanged" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} }, 64);
    const buf = try circuit.createComponent(.{ .wire = .{} }, 64);
    const out = try circuit.createComponent(.{ .output_pin = .{} }, 64);
    try circuit.connect(input.port(OUT_PORT_NAME), buf.port(IN_PORT_NAME));
    try circuit.connect(buf.port(OUT_PORT_NAME), out.port(OUTPUT_PIN_IN_PORT_NAME));

    // Full-register alternating pattern round-trips bit-for-bit.
    try circuit.propagateEvent(input, BitVecState{
        .value = 0xAAAAAAAAAAAAAAAA,
        .defined = std.math.maxInt(u64),
        .width = 64,
    });
    var result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0xAAAAAAAAAAAAAAAA), result.value);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), result.defined);

    // Mixed defined/undefined halves survive the round-trip: the upper
    // 32 bits are defined to 0xDEADBEEF, the lower 32 are undefined.
    try circuit.propagateEvent(input, BitVecState{
        .value = 0xDEADBEEF00000000,
        .defined = 0xFFFFFFFF00000000,
        .width = 64,
    });
    result = circuit.readState(out.state_handle);
    try std.testing.expectEqual(@as(u64, 0xDEADBEEF00000000), result.value);
    try std.testing.expectEqual(@as(u64, 0xFFFFFFFF00000000), result.defined);
}
