const std = @import("std");
const diagnostics = @import("diagnostics");
const ir = @import("ir_types");
const validator_run = @import("validator_run");
const sub_circuit_validation = @import("sub_circuit_validation");

pub fn run(allocator: std.mem.Allocator, project: *const ir.Project) !diagnostics.DiagnosticList {
    var all_diagnostics = diagnostics.initDiagnosticList();

    var loops = validator_run.LoopContext.init(allocator, project);
    defer loops.deinit();

    for (project.files) |*module| {
        var per_file = try validator_run.runInProject(allocator, module, &loops);
        defer per_file.deinit(allocator);
        try all_diagnostics.appendSlice(allocator, per_file.items);
        try sub_circuit_validation.runForModule(allocator, project, module, &all_diagnostics);
    }

    return all_diagnostics;
}
