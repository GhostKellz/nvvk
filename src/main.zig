//! nvvk CLI - NVIDIA Vulkan Extensions Library Demo/Test Tool

const std = @import("std");
const nvvk = @import("nvvk");

pub fn main() !void {
    std.debug.print("nvvk - NVIDIA Vulkan Extensions Library v{d}.{d}.{d}\n", .{
        nvvk.version.major,
        nvvk.version.minor,
        nvvk.version.patch,
    });
    std.debug.print("=========================================\n\n", .{});

    // Check NVIDIA GPU
    std.debug.print("NVIDIA GPU Detection:\n", .{});
    if (nvvk.isNvidiaGpu()) {
        std.debug.print("  [OK] NVIDIA GPU detected\n", .{});

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        if (nvvk.getNvidiaDriverVersion(gpa.allocator())) |version| {
            defer gpa.allocator().free(version);
            std.debug.print("  Driver version: {s}\n", .{version});
        }
    } else {
        std.debug.print("  [--] No NVIDIA GPU detected (or driver not loaded)\n", .{});
    }

    std.debug.print("\nSupported Extensions:\n", .{});
    std.debug.print("  - {s}\n", .{nvvk.extensions.low_latency2});
    std.debug.print("  - {s}\n", .{nvvk.extensions.diagnostic_checkpoints});
    std.debug.print("  - {s}\n", .{nvvk.extensions.diagnostics_config});

    std.debug.print("\nVulkan Loader:\n", .{});
    var loader = nvvk.Loader.init() catch |err| {
        std.debug.print("  [ERR] Failed to load Vulkan: {}\n", .{err});
        return;
    };
    defer loader.deinit();
    std.debug.print("  [OK] Vulkan loader initialized\n", .{});

    std.debug.print("\nC API Exports:\n", .{});
    std.debug.print("  Low Latency:\n", .{});
    std.debug.print("    nvvk_low_latency_init()\n", .{});
    std.debug.print("    nvvk_low_latency_enable()\n", .{});
    std.debug.print("    nvvk_low_latency_sleep()\n", .{});
    std.debug.print("    nvvk_low_latency_set_marker()\n", .{});
    std.debug.print("    nvvk_low_latency_begin_frame()\n", .{});
    std.debug.print("  Diagnostics:\n", .{});
    std.debug.print("    nvvk_diagnostics_init()\n", .{});
    std.debug.print("    nvvk_diagnostics_set_checkpoint()\n", .{});
    std.debug.print("    nvvk_diagnostics_set_tagged_checkpoint()\n", .{});

    std.debug.print("\nUsage:\n", .{});
    std.debug.print("  Zig:  const nvvk = @import(\"nvvk\");\n", .{});
    std.debug.print("  C:    #include <nvvk/nvvk_low_latency.h>\n", .{});
    std.debug.print("  Link: -lnvvk -lvulkan\n", .{});

    std.debug.print("\nReady for integration with DXVK/vkd3d-proton!\n", .{});
}
