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

fn calculateDominantState(circuit: *const Circuit, input_comp_list: std.ArrayList(*Component)) State {
    // Preserves the existing asymmetric rule: any input reading `.high`
    // wins immediately; otherwise the *last* input's state is dominant
    // (the loop overwrites `dominant_state` on every iteration). Reads
    // route through the pool accessor, but the comparison currency stays
    // in `State` space so the AND/NOT/wire rules below don't have to
    // change shape until Phase 4.
    var dominant_state: State = .undefined;
    for (input_comp_list.items) |input_comp| {
        const s = circuit.readState(input_comp.state_handle).toState();
        if (s == .high) {
            return .high;
        }
        dominant_state = s;
    }
    return dominant_state;
}

fn recalculateAndReschedule(
    circuit: *const Circuit,
    component: *Component,
    queue: *EventQueue,
    current_time: Timestamp,
) !void {
    var calculated_state: State = .undefined;

    switch (component.kind) {
        .not_gate => |gate| {
            calculated_state = calculateDominantState(circuit, gate.inputs).flip();
        },
        .and_gate => |gate| {
            const aValue = calculateDominantState(circuit, gate.inputs_a);
            const bValue = calculateDominantState(circuit, gate.inputs_b);

            if (aValue == .low or bValue == .low) {
                calculated_state = .low;
            } else if (aValue == .undefined or bValue == .undefined) {
                calculated_state = .undefined;
            } else {
                calculated_state = .high;
            }
        },
        .led => |led_internals| {
            calculated_state = calculateDominantState(circuit, led_internals.inputs);
            const current = circuit.readState(component.state_handle).toState();
            if (calculated_state != current) {
                if (comptime log.enabled(.info)) {
                    log.info("💡 LED (id={d}) state will be {s}", .{ component.id, @tagName(calculated_state) });
                }
            }
        },
        .wire => |wire| {
            // Wire relays the first non-null input to the output
            // If multiple inputs are connected, the wire takes the first defined state
            for (wire.inputs.items) |input_comp| {
                const s = circuit.readState(input_comp.state_handle).toState();
                if (s != .undefined) {
                    calculated_state = calculateDominantState(circuit, wire.inputs);
                    break;
                }
            }
        },
        .output_pin => |output_pin| {
            calculated_state = calculateDominantState(circuit, output_pin.inputs);
        },
        .input_pin_gate => |gate| {
            if (gate.inputs.items.len == 0) return;
            calculated_state = calculateDominantState(circuit, gate.inputs);
        },
    }

    const current_state = circuit.readState(component.state_handle).toState();
    if (current_state != calculated_state) {
        if (comptime log.enabled(.info)) {
            log.info(" - Component (id={d}, type={s}) output changed from {s} -> {s}. Scheduling new event.", .{ component.id, @tagName(component.kind), @tagName(current_state), @tagName(calculated_state) });
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

pub const State = enum {
    undefined,
    low,
    high,

    pub fn flip(self: State) State {
        return switch (self) {
            .low => .high,
            .high => .low,
            .undefined => .undefined,
        };
    }

    pub fn fromInt(int: i32) State {
        if (int == 0) return .low;
        if (int == 1) return .high;
        return .undefined;
    }

    pub fn toInt(self: State) i32 {
        return switch (self) {
            .low => 0,
            .high => 1,
            else => 2,
        };
    }

    /// Transitional helper used during the Phase 2-4 migration so that any
    /// site still talking in `State` can mirror its value through
    /// `Circuit.writeState`. Removed in Phase 4 when `State` itself is
    /// deleted in favor of `BitVecState`.
    pub fn toBitVec(self: State) BitVecState {
        return switch (self) {
            .undefined => BitVecState.undefined_(1),
            .low => BitVecState.low(1),
            .high => BitVecState.high(1),
        };
    }
};

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

    /// Transitional helper used during Phase 3 so engine sites that compare
    /// against `Event.new_state` (still a `State` enum) can keep their
    /// equality checks in `State` space while reads source from the pool.
    /// Phase 4 deletes both `State` and this helper when the engine flips
    /// to `BitVecState`-everywhere.
    pub fn toState(self: BitVecState) State {
        std.debug.assert(self.width == 1);
        if (self.isUndefined()) return .undefined;
        if (self.isLow()) return .low;
        return .high;
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
    new_state: State,

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
    output_state: State = .undefined,
    /// Opaque handle into a width-tiered pool owned by `Circuit`. Populated
    /// by `Circuit.createComponent` immediately after `Component.init`
    /// returns. The default's `slot = maxInt(u32)` is a sentinel: reads
    /// against it trap with an out-of-bounds panic in `Pool.read`, which
    /// catches "constructed a Component without going through Circuit"
    /// during the Phase-2 / Phase-3 migration. Phase 4 removes the inline
    /// `output_state` field above and makes this the source of truth.
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
        self.* = .{ .id = id, .output_state = .undefined, .kind = kind, .outputs = .{} };
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

/// Maps a width to the index of the pool that owns it. Only width=1 (tier 0)
/// is wired today; wider widths panic with a pointer back to the follow-up
/// issue. Adding a tier in the future is purely additive here.
fn tierIndexForWidth(width: u8) u8 {
    std.debug.assert(width >= 1 and width <= MAX_WIDTH);
    if (width == 1) return 0;
    @panic("widths > 1 not wired yet; see issue #11 follow-up");
}

/// Width-tiered Structure-of-Arrays pool for wire state. For width=1, the
/// pool packs 64 slots per `u64` word across two parallel buffers (one for
/// value bits, one for defined bits). Reads and writes are direct bitmap
/// operations; growth appends one `u64` to each buffer every 64 slots.
///
/// The two buffers grow together; `allocateSlot` is the only growth site
/// and it always appends to both, so length-mismatch is structurally
/// impossible.
pub const Pool = struct {
    width: u8,
    next_slot: u32 = 0,
    values: std.ArrayList(u64) = .{},
    defined: std.ArrayList(u64) = .{},

    pub fn init(width: u8) Pool {
        std.debug.assert(width == 1);
        return .{ .width = width };
    }

    pub fn deinit(self: *Pool) void {
        self.values.deinit(memory.allocator);
        self.defined.deinit(memory.allocator);
    }

    pub fn allocateSlot(self: *Pool) !u32 {
        const slot = self.next_slot;
        const word_idx: usize = @intCast(slot / 64);
        if (word_idx >= self.values.items.len) {
            try self.values.append(memory.allocator, 0);
            try self.defined.append(memory.allocator, 0);
        }
        self.next_slot += 1;
        return slot;
    }

    pub fn read(self: *const Pool, slot: u32) BitVecState {
        std.debug.assert(self.width == 1);
        const word_idx: usize = @intCast(slot / 64);
        const bit_idx: u6 = @intCast(slot % 64);
        const v: u64 = (self.values.items[word_idx] >> bit_idx) & 1;
        const d: u64 = (self.defined.items[word_idx] >> bit_idx) & 1;
        return .{ .value = v, .defined = d, .width = 1 };
    }

    pub fn write(self: *Pool, slot: u32, state: BitVecState) void {
        std.debug.assert(self.width == 1);
        std.debug.assert(state.width == 1);
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
            // (matters for `BitVecState.equals`, which only masks `value` by
            // `defined` and so could otherwise carry stale payload bits).
            self.defined.items[word_idx] &= ~mask;
            self.values.items[word_idx] &= ~mask;
        }
    }
};

pub const Circuit = struct {
    nodes: std.ArrayList(*Component),
    event_queue: EventQueue,
    next_id: u32 = 0,
    current_time: Timestamp = 0,
    listener: ?*const fn (component: *Component, new_state: State) void = null,
    /// Scratch buffer reused across `propagate()` calls. Hoisted onto the
    /// circuit so the first append in each propagation doesn't reallocate
    /// from zero capacity; instead the previous run's capacity is retained
    /// (length reset to 0 at the end of each per-timestamp iteration).
    changed_at_step: std.ArrayList(*Component) = .{},
    /// Width-tiered SoA pool for wire state. Today only tier 1 (width=1) is
    /// exercised; the field is a single `Pool` rather than `[N]Pool` because
    /// nothing else has storage yet. The next issue widens this into an
    /// array indexed by `PoolHandle.tier`. Phase-1 lands the type alongside
    /// the inline `Component.output_state` field; Phases 2-4 migrate reads
    /// and writes through the accessor.
    tier1: Pool = Pool.init(1),
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
            .tier1 = Pool.init(1),
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
        self.tier1.deinit();
    }

    /// Allocate a fresh state slot in the pool that owns `width`. Returns
    /// the opaque handle that future `readState`/`writeState` calls use.
    /// Today only width=1 is legal; wider widths trap via the dispatcher.
    pub fn allocateStateSlot(self: *Circuit, width: u8) !PoolHandle {
        const tier = tierIndexForWidth(width);
        const slot = switch (tier) {
            0 => try self.tier1.allocateSlot(),
            else => unreachable,
        };
        return .{ .tier = tier, .slot = slot };
    }

    /// Read the BitVecState at `handle`. Tier dispatch happens exactly once;
    /// everything above this line sees only the value type.
    pub fn readState(self: *const Circuit, handle: PoolHandle) BitVecState {
        return switch (handle.tier) {
            0 => self.tier1.read(handle.slot),
            else => unreachable,
        };
    }

    /// Write `state` to the slot at `handle`. The caller is responsible for
    /// the `state.width == pool.width` invariant; debug-mode asserts inside
    /// the pool catch mismatches.
    pub fn writeState(self: *Circuit, handle: PoolHandle, state: BitVecState) void {
        switch (handle.tier) {
            0 => self.tier1.write(handle.slot, state),
            else => unreachable,
        }
    }

    pub fn notifyStateChange(self: *Circuit, component: *Component, new_state: State) void {
        if (self.listener) |listener| {
            listener(component, new_state);
        }
    }

    pub fn createComponent(self: *Circuit, kind: Component.Kind) !*Component {
        const new_component = try Component.init(self.next_id, kind);
        // Allocate the state slot before the component is published to
        // `nodes`, so `deinit` (which never sees an in-flight component)
        // does not have to special-case the half-constructed state.
        new_component.state_handle = try self.allocateStateSlot(1);
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

                // Phase-3 dedup: read the component's current state through
                // the pool accessor, then compare in `State` space against
                // the (still `State`-typed) event payload. Phase 4 flips
                // `Event.new_state` to `BitVecState` and the comparison
                // becomes a single `BitVecState.equals` call.
                if (self.readState(component.state_handle).toState() == event.new_state) continue;
                if (COLLECT_METRICS) self.metrics.events_committed += 1;

                if (comptime log.enabled(.info)) {
                    log.info("[Time: {d}] Updating component id={d} to {s}", .{ self.current_time, component.id, @tagName(event.new_state) });
                }
                // The pool write is now the source of truth; the inline
                // mirror keeps `output_state` consistent for any external
                // reader (transport, emit, in-file tests) that still
                // references the field. Phase 4 deletes the inline write.
                self.writeState(component.state_handle, event.new_state.toBitVec());
                component.output_state = event.new_state;
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

                    self.notifyStateChange(output, self.readState(output.state_handle).toState());
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

    pub fn propagateEvent(self: *Circuit, component: *Component, new_state: State) !void {
        // Short-circuit no-op events: when the caller drives a component to
        // its current state, the event would just be popped and skipped at
        // Phase 1 (the `component.output_state == event.new_state` check
        // inside propagate), wasting a queue insertion plus a pop. Skip the
        // enqueue, but still advance `current_time` by the propagation delay
        // so the timing model — and the `final_time` counter — match what
        // the original behavior would have produced.
        //
        // Dominates the pop-inefficiency picture on the truth-table corpus:
        // the bench's driver unconditionally writes every input pin on every
        // vector, so for fixtures like and_6bit ~71% of pops used to be
        // no-ops where the requested state already matched. With this short-
        // circuit, the only events that enter the queue from the outside
        // are the ones that genuinely change state; pop efficiency lifts
        // toward 100% across the corpus.
        if (self.readState(component.state_handle).toState() == new_state) {
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
            const s = self.readState(node.state_handle).toState();
            log.info("Component id={d} type={s} state={s}", .{ node.id, @tagName(node.kind), @tagName(s) });
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

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .low);

        try std.testing.expectEqual(State.low, output_pin.output_state);
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .high);

        try std.testing.expectEqual(State.high, output_pin.output_state);
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .undefined);

        try std.testing.expectEqual(State.undefined, output_pin.output_state);
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .low);
        try std.testing.expectEqual(State.low, output_pin.output_state);

        try circuit.propagateEvent(input, .high);

        try std.testing.expectEqual(State.high, output_pin.output_state);
        try std.testing.expectEqual(@as(Timestamp, (PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY) * 2), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin_1 = try circuit.createComponent(.{ .output_pin = .{} });
        const output_pin_2 = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin_1.port(OUTPUT_PIN_IN_PORT_NAME));
        try circuit.connect(output_pin_1.port(OUTPUT_PIN_OUT_PORT_NAME), output_pin_2.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .high);

        try std.testing.expectEqual(State.high, output_pin_1.output_state);
        try std.testing.expectEqual(State.high, output_pin_2.output_state);
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY + (WIRE_PROPAGATION_DELAY * 2)), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const upstream = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const downstream = try circuit.createComponent(.{ .input_pin_gate = .{} });
        try circuit.connect(upstream.port(OUT_PORT_NAME), downstream.port(IN_PORT_NAME));

        try circuit.propagateEvent(upstream, .low);
        try std.testing.expectEqual(State.low, downstream.output_state);

        try circuit.propagateEvent(upstream, .high);
        try std.testing.expectEqual(State.high, downstream.output_state);
    }
}

test "led: registers out port and drives downstream output_pin" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
    const led = try circuit.createComponent(.{ .led = .{} });
    const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
    try circuit.connect(input.port(OUT_PORT_NAME), led.port(IN_PORT_NAME));
    try circuit.connect(led.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

    try circuit.propagateEvent(input, .low);
    try std.testing.expectEqual(State.low, led.output_state);

    try circuit.propagateEvent(input, .high);
    try std.testing.expectEqual(State.high, led.output_state);
}

// ============================================================================
// Phase 1 (issue #11): BitVecState / Pool foundation tests. These run in
// isolation against the new accessor surface; the engine itself does not yet
// use them. Phases 2-4 will migrate the engine onto these structures.
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

test "Circuit: allocateStateSlot returns tier-0 handle and round-trips" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const h1 = try circuit.allocateStateSlot(1);
    const h2 = try circuit.allocateStateSlot(1);
    try std.testing.expectEqual(@as(u8, 0), h1.tier);
    try std.testing.expectEqual(@as(u32, 0), h1.slot);
    try std.testing.expectEqual(@as(u8, 0), h2.tier);
    try std.testing.expectEqual(@as(u32, 1), h2.slot);

    try std.testing.expect(circuit.readState(h1).equals(BitVecState.undefined_(1)));
    circuit.writeState(h1, BitVecState.high(1));
    circuit.writeState(h2, BitVecState.low(1));
    try std.testing.expect(circuit.readState(h1).equals(BitVecState.high(1)));
    try std.testing.expect(circuit.readState(h2).equals(BitVecState.low(1)));
}

// ============================================================================
// Phase 2 (issue #11): parity tests. `Circuit.createComponent` now allocates
// a pool slot per component and `propagate()` mirrors every state write into
// the pool. These tests assert the inline `output_state` and the pool's view
// of the same component stay in lockstep across the engine's real code
// paths. When Phase 4 deletes `output_state`, these tests are reworked to
// assert pool reads directly.
// ============================================================================

test "Phase-2 parity: pool view matches output_state after a propagation chain" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
    const not_gate = try circuit.createComponent(.{ .not_gate = .{} });
    const out = try circuit.createComponent(.{ .output_pin = .{} });
    try circuit.connect(input.port(OUT_PORT_NAME), not_gate.port(IN_PORT_NAME));
    try circuit.connect(not_gate.port(OUT_PORT_NAME), out.port(OUTPUT_PIN_IN_PORT_NAME));

    // Every component got a fresh pool slot.
    try std.testing.expectEqual(@as(u32, 0), input.state_handle.slot);
    try std.testing.expectEqual(@as(u32, 1), not_gate.state_handle.slot);
    try std.testing.expectEqual(@as(u32, 2), out.state_handle.slot);

    try circuit.propagateEvent(input, .low);

    // After propagation: NOT(low) = high, output_pin relays it. Pool agrees.
    try std.testing.expectEqual(State.low, input.output_state);
    try std.testing.expect(circuit.readState(input.state_handle).equals(BitVecState.low(1)));
    try std.testing.expectEqual(State.high, not_gate.output_state);
    try std.testing.expect(circuit.readState(not_gate.state_handle).equals(BitVecState.high(1)));
    try std.testing.expectEqual(State.high, out.output_state);
    try std.testing.expect(circuit.readState(out.state_handle).equals(BitVecState.high(1)));

    try circuit.propagateEvent(input, .high);
    try std.testing.expectEqual(State.low, not_gate.output_state);
    try std.testing.expect(circuit.readState(not_gate.state_handle).equals(BitVecState.low(1)));
    try std.testing.expectEqual(State.low, out.output_state);
    try std.testing.expect(circuit.readState(out.state_handle).equals(BitVecState.low(1)));
}

test "Phase-2 parity: pool slot indices are dense and unique" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    var ids: [70]u32 = undefined;
    for (&ids, 0..) |*slot, i| {
        const comp = try circuit.createComponent(.{ .wire = .{} });
        slot.* = comp.state_handle.slot;
        try std.testing.expectEqual(@as(u32, @intCast(i)), slot.*);
        try std.testing.expectEqual(@as(u8, 0), comp.state_handle.tier);
    }

    // Slot 64 crossed the first word boundary; confirm the second word
    // actually exists on both buffers.
    try std.testing.expect(circuit.tier1.values.items.len >= 2);
    try std.testing.expect(circuit.tier1.defined.items.len >= 2);
}
