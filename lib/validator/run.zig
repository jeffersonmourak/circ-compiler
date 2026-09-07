const std = @import("std");
const diagnostics = @import("diagnostics");
const ir = @import("ir_types");
const name_resolution = @import("name_resolution");
const name_collision = @import("name_collision");
const port_validation = @import("port_validation");
const multi_driver = @import("multi_driver");
const required_input = @import("required_input");
const output_assignment = @import("output_assignment");
const combinational_loop = @import("combinational_loop");
const dead_code = @import("dead_code");
const unused_import = @import("unused_import");
const memory_validation = @import("memory_validation");

pub fn run(allocator: std.mem.Allocator, module: *const ir.Module) !diagnostics.DiagnosticList {
    var diagnostic_list = diagnostics.initDiagnosticList();

    try name_resolution.run(allocator, module, &diagnostic_list);
    try name_collision.run(allocator, module, &diagnostic_list);
    try memory_validation.run(allocator, module, &diagnostic_list);
    try port_validation.run(allocator, module, &diagnostic_list);
    try multi_driver.run(allocator, module, &diagnostic_list);
    try required_input.run(allocator, module, &diagnostic_list);
    try output_assignment.run(allocator, module, &diagnostic_list);
    try combinational_loop.run(allocator, module, &diagnostic_list);
    try dead_code.run(allocator, module, &diagnostic_list);
    try unused_import.run(allocator, module, &diagnostic_list);

    return diagnostic_list;
}
