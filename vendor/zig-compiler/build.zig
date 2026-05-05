const std = @import("std");

// Must match Dev.Env in src/dev.zig field-for-field.
// The build system serialises the tag name, and dev.zig reconstructs it via
// @field(Env, @tagName(build_options.dev)) — so ordinal order does not matter,
// only that the names are identical to the actual Dev.Env enum.
const DevEnv = enum {
    bootstrap,
    core,
    full,
    c_source,
    ast_gen,
    sema,
    @"aarch64-linux",
    cbe,
    @"powerpc-linux",
    @"riscv64-linux",
    spirv,
    wasm,
    @"x86_64-linux",
};

// Must match value_interpret_mode enum in src/build_options expected by Compilation.
const ValueInterpretMode = enum { direct, by_name };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // aro: C parser required by src/translate_c.zig (name must be registered even when
    // not reached at runtime, because the module-resolution layer type-checks import bodies).
    const aro_mod = b.createModule(.{
        .root_source_file = b.path("lib/compiler/aro/aro.zig"),
        .target = target,
        .optimize = optimize,
    });

    const aro_translate_c_mod = b.createModule(.{
        .root_source_file = b.path("lib/compiler/aro_translate_c.zig"),
        .target = target,
        .optimize = optimize,
    });
    aro_translate_c_mod.addImport("aro", aro_mod);

    // Build options expected by the embedded Zig 0.15.1 compiler source.
    // Mirrors spike/build.zig exactly; see DOCS/STATUS.md Phase 0 findings for rationale.
    const zig_options = b.addOptions();
    zig_options.addOption(u32, "mem_leak_frames", 0);
    zig_options.addOption(bool, "skip_non_native", false);
    zig_options.addOption(bool, "have_llvm", false);
    zig_options.addOption(bool, "llvm_has_m68k", false);
    zig_options.addOption(bool, "llvm_has_csky", false);
    zig_options.addOption(bool, "llvm_has_arc", false);
    zig_options.addOption(bool, "llvm_has_xtensa", false);
    zig_options.addOption(bool, "debug_gpa", false);
    // dev=.full required because Env.wasm omits the legalize feature in 0.15.1
    // even though arch/wasm/CodeGen.zig:legalizeFeatures() returns non-null.
    zig_options.addOption(DevEnv, "dev", .full);
    zig_options.addOption(ValueInterpretMode, "value_interpret_mode", .direct);
    zig_options.addOption([:0]const u8, "version", "0.15.1");
    zig_options.addOption(std.SemanticVersion, "semver", .{ .major = 0, .minor = 15, .patch = 1 });
    // enable_debug_extensions=true required when dev=.full: Air/print.zig has a
    // comptime assert on this flag, triggered even when the WASM backend is the only target.
    zig_options.addOption(bool, "enable_debug_extensions", true);
    zig_options.addOption(bool, "enable_logging", false);
    zig_options.addOption(bool, "enable_link_snapshots", false);
    zig_options.addOption(bool, "enable_tracy", false);
    zig_options.addOption(bool, "enable_tracy_callstack", false);
    zig_options.addOption(bool, "enable_tracy_allocation", false);
    zig_options.addOption(u32, "tracy_callstack_depth", 0);
    zig_options.addOption(bool, "value_tracing", false);

    // Public named module — accessible to parent builds via dep.module("zig-compiler").
    const mod = b.addModule("zig-compiler", .{
        .root_source_file = b.path("src/exports.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.link_libc = true;
    mod.addImport("aro", aro_mod);
    mod.addImport("aro_translate_c", aro_translate_c_mod);
    mod.addOptions("build_options", zig_options);
}
