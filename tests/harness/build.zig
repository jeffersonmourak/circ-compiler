const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const module = b.createModule(.{
        .root_source_file = b.path("compiled.zig"),
        .target = target,
        .optimize = optimize,
    });

    // circuit.zig (copied into this workspace by wasm_run.zig) imports a
    // `build_options` module to read its COLLECT_METRICS toggle. The harness
    // never benchmarks, so we always wire false here.
    const circuit_options = b.addOptions();
    circuit_options.addOption(bool, "collect_metrics", false);
    module.addOptions("build_options", circuit_options);

    const artifact = b.addExecutable(.{
        .name = "compiled",
        .root_module = module,
    });
    artifact.entry = .disabled;
    artifact.rdynamic = true;

    const install = b.addInstallArtifact(artifact, .{});
    const wasm_step = b.step("wasm", "Build compiled WASM artifact");
    wasm_step.dependOn(&install.step);
}
