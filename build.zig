const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build option for static vs shared library
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Library linkage (static or dynamic)") orelse .dynamic;

    // =========================================================================
    // Core nvvk module (Zig API)
    // =========================================================================
    const nvvk_mod = b.addModule("nvvk", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true, // Required for DlDynLib
    });

    // =========================================================================
    // Library with C ABI exports (libnvvk.so / libnvvk.a)
    // =========================================================================
    const lib = b.addLibrary(.{
        .linkage = linkage,
        .name = "nvvk",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "nvvk", .module = nvvk_mod },
            },
        }),
    });

    // Link Vulkan
    lib.linkSystemLibrary("vulkan");

    // Install library
    b.installArtifact(lib);

    // Install C headers
    b.installFile("include/nvvk.h", "include/nvvk.h");
    b.installFile("include/nvvk_low_latency.h", "include/nvvk_low_latency.h");
    b.installFile("include/nvvk_diagnostics.h", "include/nvvk_diagnostics.h");

    // =========================================================================
    // CLI tool for testing/demos
    // =========================================================================
    const exe = b.addExecutable(.{
        .name = "nvvk-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "nvvk", .module = nvvk_mod },
            },
        }),
    });
    exe.linkSystemLibrary("vulkan");
    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the CLI tool");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // =========================================================================
    // Tests
    // =========================================================================
    const mod_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    mod_tests.linkSystemLibrary("vulkan");

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_mod_tests.step);

    // =========================================================================
    // Documentation
    // =========================================================================
    const docs_step = b.step("docs", "Generate documentation");
    const docs = b.addLibrary(.{
        .name = "nvvk-docs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
