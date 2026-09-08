const std = @import("std");
const compiled = @import("compiled.zig");
const engine = @import("circuit.zig");
const memory = @import("memory.zig");
const interpreter = @import("interpreter.zig");

// In the old pipeline, compiled.zig does not export `is_prebuilt_runtime`.
// For the pre-built WASM, we will provide a dummy compiled.zig that exports it.
const is_prebuilt = @hasDecl(compiled, "is_prebuilt_runtime");

pub var topo_ptr: ?[*]const u8 = null;
pub var topo_len: u32 = 0;

var runtime_circuit: engine.Circuit = undefined;
var runtime_initialized: bool = false;

/// Per-memory staging buffer for `memBuffer`/`memLoad`/`memStore`, indexed
/// by node position. Allocated once per memory on first `memBuffer` call
/// and reused forever: `memory.allocator` is an arena, so a fresh buffer
/// per call would grow linear memory without bound.
var mem_staging: []?[]u8 = &.{};

fn topology_alloc_impl(len: i32) callconv(.c) i32 {
    const buf = memory.allocator.alloc(u8, @intCast(len)) catch return -1;
    topo_ptr = buf.ptr;
    topo_len = @intCast(len);
    return @intCast(@intFromPtr(buf.ptr));
}

fn init_impl() callconv(.c) void {
    if (runtime_initialized) return;
    runtime_circuit = engine.Circuit.init() catch return;

    if (topo_ptr) |ptr| {
        interpreter.initFromTopology(&runtime_circuit, ptr[0..topo_len]) catch {
            runtime_circuit.deinit();
            return;
        };
    }

    mem_staging = memory.allocator.alloc(?[]u8, runtime_circuit.nodes.items.len) catch {
        runtime_circuit.deinit();
        return;
    };
    @memset(mem_staging, null);

    runtime_initialized = true;
}

// ---------------------------------------------------------------------------
// Memory exports. Ids address nodes by position exactly like setPin. Every
// mutator returns a status: 0 ok; -1 uninitialised, bad id, or not a memory;
// -2 image length is not a whole number of words; -3 a word has bits at or
// above the data width; -4 more words than the memory holds; -5 len exceeds
// the staging buffer; -6 memBuffer was never called; -7 address out of
// range. init() swallows its own errors, so these codes are the host's one
// diagnostic.
// ---------------------------------------------------------------------------

fn memNode(component_id: i32) ?*engine.Component {
    if (!runtime_initialized or component_id < 0) return null;
    const id: u32 = @intCast(component_id);
    if (id >= runtime_circuit.nodes.items.len) return null;
    const comp = runtime_circuit.nodes.items[id];
    if (comp.kind != .memory) return null;
    return comp;
}

fn imageStatus(err: anyerror) i32 {
    return switch (err) {
        error.LengthNotWordMultiple => -2,
        error.WordExceedsWidth => -3,
        error.TooManyWords => -4,
        else => -1,
    };
}

fn getMemInfo_impl(component_id: i32) callconv(.c) i32 {
    const comp = memNode(component_id) orelse return -1;
    const kind: i32 = interpreter.memKindByte(comp.kind.memory.mode);
    const data_width: i32 = comp.state_handle.tier;
    const addr_width: i32 = comp.kind.memory.cells.addr_width;
    return (kind << 16) | (data_width << 8) | addr_width;
}

fn memBuffer_impl(component_id: i32) callconv(.c) i32 {
    const comp = memNode(component_id) orelse return -1;
    const id: usize = @intCast(component_id);
    if (mem_staging[id] == null) {
        const size = engine.memimage.maxImageSize(comp.state_handle.tier, comp.kind.memory.cells.addr_width);
        mem_staging[id] = memory.allocator.alloc(u8, size) catch return -1;
    }
    return @intCast(@intFromPtr(mem_staging[id].?.ptr));
}

fn memLoad_impl(component_id: i32, len: i32) callconv(.c) i32 {
    const comp = memNode(component_id) orelse return -1;
    const staging = mem_staging[@intCast(component_id)] orelse return -6;
    if (len < 0) return -5;
    const n: usize = @intCast(len);
    if (n > staging.len) return -5;
    _ = runtime_circuit.memoryLoadImage(comp, staging[0..n]) catch |err| return imageStatus(err);
    return 0;
}

fn memStore_impl(component_id: i32) callconv(.c) i32 {
    const comp = memNode(component_id) orelse return -1;
    const staging = mem_staging[@intCast(component_id)] orelse return -6;
    const written = runtime_circuit.memoryStoreImage(comp, staging) catch return -1;
    return @intCast(written);
}

fn memClear_impl(component_id: i32) callconv(.c) i32 {
    const comp = memNode(component_id) orelse return -1;
    runtime_circuit.memoryClear(comp) catch return -1;
    return 0;
}

fn setMemWord_impl(component_id: i32, addr: i32, value: i64, defined: i64) callconv(.c) i32 {
    const comp = memNode(component_id) orelse return -1;
    if (addr < 0) return -7;
    const index: usize = @intCast(addr);
    if (index >= comp.kind.memory.cells.wordCount()) return -7;
    const state = engine.BitVecState.fromRaw(@bitCast(value), @bitCast(defined), comp.state_handle.tier);
    runtime_circuit.memoryWriteWord(comp, index, state) catch |err| return switch (err) {
        error.AddressOutOfRange => -7,
        else => -1,
    };
    return 0;
}

fn getMemValue_impl(component_id: i32, addr: i32) callconv(.c) i64 {
    const comp = memNode(component_id) orelse return 0;
    const cells = engine.memoryCells(comp) orelse return 0;
    if (addr < 0) return 0;
    const index: usize = @intCast(addr);
    if (index >= cells.wordCount()) return 0;
    return @bitCast(cells.values[index]);
}

fn getMemDefined_impl(component_id: i32, addr: i32) callconv(.c) i64 {
    const comp = memNode(component_id) orelse return 0;
    const cells = engine.memoryCells(comp) orelse return 0;
    if (addr < 0) return 0;
    const index: usize = @intCast(addr);
    if (index >= cells.wordCount()) return 0;
    return @bitCast(cells.defined[index]);
}

fn run_impl() callconv(.c) void {
    if (!runtime_initialized) return;
    runtime_circuit.propagate() catch return;
}

fn setPin_impl(component_id: i32, value: i64, defined: i64) callconv(.c) void {
    if (!runtime_initialized or component_id < 0) return;
    const id: u32 = @intCast(component_id);
    if (id >= runtime_circuit.nodes.items.len) return;

    const comp = runtime_circuit.nodes.items[id];
    if (comp.kind != .input_pin_gate) return;

    const width = comp.state_handle.tier;
    const state = engine.BitVecState.fromRaw(@bitCast(value), @bitCast(defined), width);
    runtime_circuit.propagateEvent(comp, state) catch return;
}

fn getOutputValue_impl(component_id: i32) callconv(.c) i64 {
    if (!runtime_initialized or component_id < 0) return 0;
    const id: u32 = @intCast(component_id);
    if (id >= runtime_circuit.nodes.items.len) return 0;

    const comp = runtime_circuit.nodes.items[id];
    return @bitCast(runtime_circuit.readState(comp.state_handle).value);
}

fn getOutputDefined_impl(component_id: i32) callconv(.c) i64 {
    if (!runtime_initialized or component_id < 0) return 0;
    const id: u32 = @intCast(component_id);
    if (id >= runtime_circuit.nodes.items.len) return 0;

    const comp = runtime_circuit.nodes.items[id];
    return @bitCast(runtime_circuit.readState(comp.state_handle).defined);
}

comptime {
    if (is_prebuilt) {
        @export(&topology_alloc_impl, .{ .name = "topology_alloc", .linkage = .strong });
        @export(&init_impl, .{ .name = "init", .linkage = .strong });
        @export(&run_impl, .{ .name = "run", .linkage = .strong });
        @export(&setPin_impl, .{ .name = "setPin", .linkage = .strong });
        @export(&getOutputValue_impl, .{ .name = "getOutputValue", .linkage = .strong });
        @export(&getOutputDefined_impl, .{ .name = "getOutputDefined", .linkage = .strong });
        @export(&getMemInfo_impl, .{ .name = "getMemInfo", .linkage = .strong });
        @export(&memBuffer_impl, .{ .name = "memBuffer", .linkage = .strong });
        @export(&memLoad_impl, .{ .name = "memLoad", .linkage = .strong });
        @export(&memStore_impl, .{ .name = "memStore", .linkage = .strong });
        @export(&memClear_impl, .{ .name = "memClear", .linkage = .strong });
        @export(&setMemWord_impl, .{ .name = "setMemWord", .linkage = .strong });
        @export(&getMemValue_impl, .{ .name = "getMemValue", .linkage = .strong });
        @export(&getMemDefined_impl, .{ .name = "getMemDefined", .linkage = .strong });
    } else {
        // Old pipeline: compiled.zig defines the exports, so we just force its analysis.
        _ = compiled;
        @export(&topology_alloc_impl, .{ .name = "topology_alloc", .linkage = .strong });
        
        // Expose init wrapper if compiled.zig doesn't expose it? No, compiled.zig exposes init().
    }
}
