const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const validator_run_project = @import("validator_run_project");
const diagnostics = @import("diagnostics");
const serializer = @import("serializer");
const full_serializer = @import("full_serializer");
const full_decoder = @import("full_decoder");
const section_writer = @import("section_writer");
const runtime_embed = @import("runtime_embed");

fn hasHardErrors(diags: []const diagnostics.Diagnostic) bool {
    for (diags) |d| {
        if (d.level == .err) return true;
    }
    return false;
}

const WASM_HEADER_LEN = 8; // magic(4) + version(4)

const NamedSection = struct {
    name: []const u8,
    payload: []const u8,
};

fn readLeb128(bytes: []const u8, pos: *usize) !u32 {
    var result: u32 = 0;
    var shift: u5 = 0;
    while (true) {
        if (pos.* >= bytes.len) return error.Truncated;
        const byte = bytes[pos.*];
        pos.* += 1;
        result |= @as(u32, byte & 0x7F) << shift;
        if (byte & 0x80 == 0) return result;
        shift += 7;
        if (shift >= 32) return error.Leb128Overflow;
    }
}

/// Walk WASM custom sections starting after the 8-byte header. Returns the first
/// custom section whose name matches `target_name`, or null if none found.
fn findCustomSection(wasm: []const u8, target_name: []const u8) !?NamedSection {
    if (wasm.len < WASM_HEADER_LEN) return error.Truncated;
    var pos: usize = WASM_HEADER_LEN;
    while (pos < wasm.len) {
        const section_id = wasm[pos];
        pos += 1;
        const body_len = try readLeb128(wasm, &pos);
        const body_start = pos;
        if (body_start + body_len > wasm.len) return error.Truncated;
        const body_end = body_start + body_len;

        if (section_id == 0x00) { // custom section
            var inner = body_start;
            const name_len = try readLeb128(wasm, &inner);
            if (inner + name_len > body_end) return error.Truncated;
            const name = wasm[inner..][0..name_len];
            inner += name_len;
            if (std.mem.eql(u8, name, target_name)) {
                return NamedSection{ .name = name, .payload = wasm[inner..body_end] };
            }
        }
        pos = body_end;
    }
    return null;
}

test "phase0_full_pipeline_roundtrip: and_pair fixture carries both sections with origin chains" {
    const allocator = std.testing.allocator;

    // Resolve the project from disk via the same pipeline the CLI uses.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const root_path = "tests/fixtures/projects/and_pair/root.circ";
    const scan_result = try scan_imports.scanProjectImports(arena_alloc, root_path);
    if (hasHardErrors(scan_result.diagnostics.items)) return error.ScanFailed;
    const cycle_result = try import_cycle.analyzeImports(arena_alloc, scan_result.file_paths, scan_result.import_table);
    if (hasHardErrors(cycle_result.diagnostics.items)) return error.CycleFailed;
    var resolver_diagnostics = diagnostics.initDiagnosticList();
    const project = try resolve_bodies.resolveBodies(
        arena_alloc,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
        &resolver_diagnostics,
    );
    if (hasHardErrors(resolver_diagnostics.items)) return error.UnexpectedResolverDiagnostics;
    var diag_list = try validator_run_project.run(arena_alloc, &project);
    defer diag_list.deinit(arena_alloc);
    if (hasHardErrors(diag_list.items)) return error.UnexpectedDiagnostics;

    // Serialize both payloads.
    const min_bytes = try serializer.serializeProject(allocator, &project);
    defer allocator.free(min_bytes);
    const full_bytes = try full_serializer.serializeProjectFull(allocator, &project);
    defer allocator.free(full_bytes);

    // Combine onto the embedded runtime WASM.
    const wasm = try section_writer.combineTwo(allocator, runtime_embed.runtime_wasm, min_bytes, full_bytes);
    defer allocator.free(wasm);

    // (a) Both sections are present.
    const min_section = (try findCustomSection(wasm, "circ.topology.v0.min")) orelse return error.MissingMinSection;
    const full_section = (try findCustomSection(wasm, "circ.topology.v0.full")) orelse return error.MissingFullSection;
    try std.testing.expectEqualSlices(u8, min_bytes, min_section.payload);
    try std.testing.expectEqualSlices(u8, full_bytes, full_section.payload);

    // (b) Decode the full payload and inspect.
    var decoded = try full_decoder.decode(allocator, full_section.payload);
    defer decoded.deinit(allocator);

    // (c) Component count parity: the min payload's component count is at offset 5..9 (after CIRC + version).
    const min_component_count = std.mem.readInt(u32, min_bytes[5..9], .little);
    try std.testing.expectEqual(@as(usize, min_component_count), decoded.components.len);

    // (d) Every component has a non-empty name.
    var any_empty_name = false;
    for (decoded.components) |comp| {
        if (comp.name.len == 0) any_empty_name = true;
    }
    try std.testing.expect(!any_empty_name);

    // (e) At least one component carries a non-empty origin chain referencing "paired_and".
    var found_origin = false;
    for (decoded.components) |comp| {
        if (comp.origin.len == 0) continue;
        for (comp.origin) |frame| {
            if (std.mem.eql(u8, frame.subcircuit, "paired_and")) {
                found_origin = true;
                break;
            }
        }
        if (found_origin) break;
    }
    try std.testing.expect(found_origin);

    // (f) Connections match byte-for-byte: connections section in the full payload begins after
    //     the components section. Rather than re-parse, decode min by mirroring its layout and
    //     compare connection counts and ids structurally.
    const min_conn_count = std.mem.readInt(u32, min_bytes[9..13], .little);
    try std.testing.expectEqual(@as(usize, min_conn_count), decoded.connections.len);

    // Walk min bytes to extract each connection record and compare with decoded full.
    // Min layout: header(13) + components(6 bytes each: id+kind+width) + connections(9 bytes each).
    var min_pos: usize = 13 + min_component_count * 6;
    for (decoded.connections) |full_conn| {
        const from_id = std.mem.readInt(u32, min_bytes[min_pos..][0..4], .little);
        min_pos += 4;
        const to_id = std.mem.readInt(u32, min_bytes[min_pos..][0..4], .little);
        min_pos += 4;
        const port = min_bytes[min_pos];
        min_pos += 1;
        try std.testing.expectEqual(from_id, full_conn.from_id);
        try std.testing.expectEqual(to_id, full_conn.to_id);
        try std.testing.expectEqual(port, full_conn.port);
    }
}

test "multibit_import: widths flow through the import boundary into the min payload" {
    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const root_path = "tests/fixtures/projects/multibit_import/root.circ";
    const scan_result = try scan_imports.scanProjectImports(arena_alloc, root_path);
    if (hasHardErrors(scan_result.diagnostics.items)) return error.ScanFailed;
    const cycle_result = try import_cycle.analyzeImports(arena_alloc, scan_result.file_paths, scan_result.import_table);
    if (hasHardErrors(cycle_result.diagnostics.items)) return error.CycleFailed;
    var resolver_diagnostics = diagnostics.initDiagnosticList();
    const project = try resolve_bodies.resolveBodies(
        arena_alloc,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
        &resolver_diagnostics,
    );
    if (hasHardErrors(resolver_diagnostics.items)) return error.UnexpectedResolverDiagnostics;
    var diag_list = try validator_run_project.run(arena_alloc, &project);
    defer diag_list.deinit(arena_alloc);
    if (hasHardErrors(diag_list.items)) return error.UnexpectedDiagnostics;

    const min_bytes = try serializer.serializeProject(allocator, &project);
    defer allocator.free(min_bytes);

    // Header: magic(4) + ver(1) + comp_count(4) + conn_count(4) = 13. Each record is id(4)+kind(1)+width(1).
    const min_component_count = std.mem.readInt(u32, min_bytes[5..9], .little);
    try std.testing.expect(min_component_count > 0);

    var offset: usize = 13;
    var i: usize = 0;
    while (i < min_component_count) : (i += 1) {
        const width = min_bytes[offset + 5];
        try std.testing.expectEqual(@as(u8, 4), width);
        offset += 6;
    }
}
