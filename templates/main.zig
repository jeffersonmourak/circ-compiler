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
    
    runtime_initialized = true;
}

fn run_impl() callconv(.c) void {
    if (!runtime_initialized) return;
    runtime_circuit.propagate() catch return;
}

fn setPin_impl(component_id: i32, state: i32) callconv(.c) void {
    if (!runtime_initialized or component_id < 0) return;
    const id: u32 = @intCast(component_id);
    if (id >= runtime_circuit.nodes.items.len) return;
    
    const comp = runtime_circuit.nodes.items[id];
    if (comp.kind != .input_pin_gate) return;
    
    runtime_circuit.propagateEvent(comp, engine.BitVecState.fromInt(state, 1)) catch return;
}

fn getOutputState_impl(component_id: i32) callconv(.c) i32 {
    if (!runtime_initialized or component_id < 0) return 2; // 2 = undefined state
    const id: u32 = @intCast(component_id);
    if (id >= runtime_circuit.nodes.items.len) return 2;

    const comp = runtime_circuit.nodes.items[id];
    return runtime_circuit.readState(comp.state_handle).toInt();
}

comptime {
    if (is_prebuilt) {
        @export(&topology_alloc_impl, .{ .name = "topology_alloc", .linkage = .strong });
        @export(&init_impl, .{ .name = "init", .linkage = .strong });
        @export(&run_impl, .{ .name = "run", .linkage = .strong });
        @export(&setPin_impl, .{ .name = "setPin", .linkage = .strong });
        @export(&getOutputState_impl, .{ .name = "getOutputState", .linkage = .strong });
    } else {
        // Old pipeline: compiled.zig defines the exports, so we just force its analysis.
        _ = compiled;
        @export(&topology_alloc_impl, .{ .name = "topology_alloc", .linkage = .strong });
        
        // Expose init wrapper if compiled.zig doesn't expose it? No, compiled.zig exposes init().
    }
}
