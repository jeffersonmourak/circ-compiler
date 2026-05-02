const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const validator_run = @import("validator_run");
const diagnostics = @import("diagnostics");
const emit_main = @import("emit_main");
const wasm_run = @import("wasm_run");

fn hasHardErrors(diagnostic_list: []const diagnostics.Diagnostic) bool {
    for (diagnostic_list) |diagnostic| {
        if (diagnostic.level == .err) return true;
    }
    return false;
}

test "behavioral harness: inverter responds to pin toggles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = try std.fs.cwd().readFileAlloc(allocator, "tests/fixtures/circuits/inverter.circ", 1024 * 1024);
    const ast_file = try translate.parseSource(allocator, 0, source);
    const ir_module = try resolver.resolve(allocator, ast_file, 0);
    var diagnostic_list = try validator_run.run(allocator, &ir_module);
    defer diagnostic_list.deinit(allocator);
    if (hasHardErrors(diagnostic_list.items)) return error.InvalidFixtureForEmission;

    const emitted_source = try emit_main.emitModuleSource(allocator, &ir_module, .{
        .source_name = "inverter.circ",
        .compile_timestamp = "2026-05-01T22:00:00Z",
        .compiler_version = "circ-renderer-z/dev",
    });

    const script =
        \\wasm.setPin(0, 1);
        \\wasm.run();
        \\console.log(wasm.getOutputState(1));
        \\wasm.setPin(0, 0);
        \\wasm.run();
        \\console.log(wasm.getOutputState(1));
    ;

    const stdout = try wasm_run.compileAndRun(allocator, emitted_source, script);
    try std.testing.expectEqualStrings("0\n1\n", stdout);
}
