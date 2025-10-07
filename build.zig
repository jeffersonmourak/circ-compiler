// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const optimize = b.standardOptimizeOption(.{});

    const exe_debug_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("lib/wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });

    const wasm_lib = b.addExecutable(.{
        .name = "circ-renderer-lib-wasm",
        .root_module = wasm_mod,
    });

    wasm_lib.entry = .disabled;
    wasm_lib.rdynamic = false;

    b.installArtifact(wasm_lib);

    const exe = b.addExecutable(.{
        .name = "logic-sim",
        .root_module = exe_debug_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    const wasm_step = b.step("wasm", "Build the application for WebAssembly");

    const install_wasm_step = b.addInstallFile(
        wasm_lib.getEmittedBin(),
        "wasm/circ-renderer-lib.wasm",
    );

    wasm_step.dependOn(&wasm_lib.step);
    wasm_step.dependOn(&install_wasm_step.step);

    const wasm_src_step = b.addInstallFile(
        wasm_lib.getEmittedBin(),
        "../example/circ-renderer-lib.wasm",
    );

    wasm_step.dependOn(&wasm_src_step.step);
}
