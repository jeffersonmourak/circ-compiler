const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_lib_dir = b.graph.zig_lib_directory.path orelse
        @panic("zig_lib_directory has no path; spike requires a resolvable system Zig lib dir");

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "zig_lib_dir", zig_lib_dir);

    const exe = b.addExecutable(.{
        .name = "spike",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", build_options);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the spike binary");
    run_step.dependOn(&run_cmd.step);
}
