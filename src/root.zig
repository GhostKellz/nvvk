//! nvvk - NVIDIA Vulkan Extensions Library for Linux Gaming
//!
//! A Zig library providing optimized NVIDIA Vulkan extension wrappers
//! with C ABI exports for integration with DXVK, vkd3d-proton, and
//! other Vulkan-based translation layers.
//!
//! ## Features
//!
//! - **VK_NV_low_latency2**: NVIDIA Reflex integration for reduced input latency
//! - **VK_NV_device_diagnostic_checkpoints**: GPU crash debugging
//! - **VK_NV_device_diagnostics_config**: Enhanced GPU diagnostics
//!
//! ## Example
//!
//! ```zig
//! const nvvk = @import("nvvk");
//!
//! // Initialize with your Vulkan device
//! var dispatch = nvvk.DeviceDispatch.init(device, getDeviceProcAddr);
//!
//! // Create low latency context for your swapchain
//! var ll = nvvk.LowLatencyContext.init(device, swapchain, &dispatch);
//!
//! // Enable low latency mode
//! try ll.setMode(.{ .enabled = true, .boost = true });
//!
//! // In render loop
//! _ = ll.beginFrame();
//! // ... game logic ...
//! ll.endSimulation();
//! ll.beginRenderSubmit();
//! // ... submit commands ...
//! ll.endRenderSubmit();
//! ```

const std = @import("std");

// Re-export modules
pub const vulkan = @import("vulkan.zig");
pub const low_latency = @import("low_latency.zig");
pub const diagnostics = @import("diagnostics.zig");

// Re-export commonly used types
pub const VkResult = vulkan.VkResult;
pub const VulkanError = vulkan.VulkanError;
pub const VkDevice = vulkan.VkDevice;
pub const VkInstance = vulkan.VkInstance;
pub const VkQueue = vulkan.VkQueue;
pub const VkSwapchainKHR_T = vulkan.VkSwapchainKHR_T;
pub const VkSemaphore_T = vulkan.VkSemaphore_T;
pub const VkCommandBuffer = vulkan.VkCommandBuffer;

pub const Loader = vulkan.Loader;
pub const DeviceDispatch = vulkan.DeviceDispatch;

pub const LowLatencyContext = low_latency.LowLatencyContext;
pub const ModeConfig = low_latency.ModeConfig;
pub const Marker = low_latency.Marker;
pub const FrameTimings = low_latency.FrameTimings;

pub const DiagnosticsContext = diagnostics.DiagnosticsContext;
pub const DiagnosticsConfig = diagnostics.DiagnosticsConfig;
pub const CheckpointTag = diagnostics.CheckpointTag;
pub const CheckpointData = diagnostics.CheckpointData;
pub const CrashDump = diagnostics.CrashDump;
pub const PipelineStage = diagnostics.PipelineStage;

/// Library version
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

/// Check if running on NVIDIA GPU (basic check via driver name)
pub fn isNvidiaGpu() bool {
    // This is a simplified check - in production, query physical device properties
    const driver_path = "/proc/driver/nvidia/version";
    const file = std.fs.openFileAbsolute(driver_path, .{}) catch return false;
    file.close();
    return true;
}

/// Get NVIDIA driver version from /proc
pub fn getNvidiaDriverVersion(allocator: std.mem.Allocator) ?[]const u8 {
    const file = std.fs.openFileAbsolute("/proc/driver/nvidia/version", .{}) catch return null;
    defer file.close();

    // Read into a fixed buffer
    var buffer: [4096]u8 = undefined;
    const bytes_read = file.read(&buffer) catch return null;
    const content = buffer[0..bytes_read];

    // Parse version from first line (e.g., "NVRM version: NVIDIA UNIX x86_64 Kernel Module  560.35.03...")
    var lines = std.mem.splitScalar(u8, content, '\n');
    const first_line = lines.first();

    // Find version number pattern (xxx.xx.xx)
    var i: usize = 0;
    while (i < first_line.len) : (i += 1) {
        if (std.ascii.isDigit(first_line[i])) {
            var end = i;
            while (end < first_line.len and (std.ascii.isDigit(first_line[end]) or first_line[end] == '.')) {
                end += 1;
            }
            if (end > i + 5) { // Reasonable version string length
                const version_str = allocator.dupe(u8, first_line[i..end]) catch return null;
                return version_str;
            }
        }
    }

    return null;
}

// =============================================================================
// Extension support queries
// =============================================================================

/// Extension names
pub const extensions = struct {
    pub const low_latency2 = vulkan.VK_NV_LOW_LATENCY_2_EXTENSION_NAME;
    pub const diagnostic_checkpoints = vulkan.VK_NV_DEVICE_DIAGNOSTIC_CHECKPOINTS_EXTENSION_NAME;
    pub const diagnostics_config = vulkan.VK_NV_DEVICE_DIAGNOSTICS_CONFIG_EXTENSION_NAME;

    /// Get all extension names as a slice
    pub fn all() []const [*:0]const u8 {
        return &[_][*:0]const u8{
            low_latency2,
            diagnostic_checkpoints,
            diagnostics_config,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "version" {
    try std.testing.expectEqual(@as(u8, 0), version.major);
    try std.testing.expectEqual(@as(u8, 1), version.minor);
    try std.testing.expectEqual(@as(u8, 0), version.patch);
}

test "extension names" {
    const exts = extensions.all();
    try std.testing.expectEqual(@as(usize, 3), exts.len);
}

test {
    // Run all module tests
    std.testing.refAllDecls(@This());
}
