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
pub const memory_decompression = @import("memory_decompression.zig");
pub const mesh_shader = @import("mesh_shader.zig");
pub const ray_tracing = @import("ray_tracing.zig");
pub const optical_flow = @import("optical_flow.zig");
pub const ray_tracing_reorder = @import("ray_tracing_reorder.zig");
pub const cuda_interop = @import("cuda_interop.zig");
pub const displacement_micromap = @import("displacement_micromap.zig");

// Frame generation modules (Phase 3)
pub const motion_vectors = @import("motion_vectors.zig");
pub const frame_synthesis = @import("frame_synthesis.zig");
pub const frame_generation = @import("frame_generation.zig");
pub const present_injection = @import("present_injection.zig");

// VRR integration (via nvsync)
pub const vrr = @import("vrr.zig");

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
pub const ThreadSafeLowLatencyContext = low_latency.ThreadSafeLowLatencyContext;
pub const ModeConfig = low_latency.ModeConfig;
pub const Marker = low_latency.Marker;
pub const FrameTimings = low_latency.FrameTimings;
pub const FramePacer = low_latency.FramePacer;
pub const LatencyStats = low_latency.LatencyStats;

pub const DiagnosticsContext = diagnostics.DiagnosticsContext;
pub const DiagnosticsConfig = diagnostics.DiagnosticsConfig;
pub const CheckpointTag = diagnostics.CheckpointTag;
pub const CheckpointData = diagnostics.CheckpointData;
pub const CrashDump = diagnostics.CrashDump;
pub const PipelineStage = diagnostics.PipelineStage;

pub const DecompressionContext = memory_decompression.DecompressionContext;
pub const DecompressionRegion = memory_decompression.DecompressionRegion;
pub const CompressionMethod = memory_decompression.CompressionMethod;

pub const MeshShaderContext = mesh_shader.MeshShaderContext;
pub const MeshShaderProperties = mesh_shader.MeshShaderProperties;

pub const RayTracingContext = ray_tracing.RayTracingContext;
pub const RayTracingProperties = ray_tracing.RayTracingProperties;
pub const ShaderBindingTable = ray_tracing.ShaderBindingTable;

pub const OpticalFlowContext = optical_flow.OpticalFlowContext;
pub const OpticalFlowConfig = optical_flow.OpticalFlowConfig;
pub const OpticalFlowProperties = optical_flow.OpticalFlowProperties;

pub const InvocationReorderProperties = ray_tracing_reorder.InvocationReorderProperties;
pub const InvocationReorderConfig = ray_tracing_reorder.InvocationReorderConfig;

pub const ComputeCapability = cuda_interop.ComputeCapability;
pub const LaunchConfig = cuda_interop.LaunchConfig;

pub const DisplacementMicromapProperties = displacement_micromap.DisplacementMicromapProperties;
pub const DisplacementConfig = displacement_micromap.DisplacementConfig;

// Frame generation exports
pub const MotionVectorContext = motion_vectors.MotionVectorContext;
pub const MotionVectorConfig = motion_vectors.MotionVectorConfig;
pub const MotionVectorBuffer = motion_vectors.MotionVectorBuffer;
pub const FrameSynthesisContext = frame_synthesis.FrameSynthesisContext;
pub const FrameGenContext = frame_generation.FrameGenContext;
pub const FrameGenConfig = frame_generation.FrameGenConfig;
pub const FrameGenMode = frame_generation.FrameGenMode;
pub const FrameGenStats = frame_generation.FrameGenStats;
pub const GeneratedFrame = frame_generation.GeneratedFrame;

// Present injection exports
pub const PresentInjectionContext = present_injection.PresentInjectionContext;
pub const InjectionConfig = present_injection.InjectionConfig;
pub const InjectionMode = present_injection.InjectionMode;
pub const TimingMode = present_injection.TimingMode;
pub const InjectionStats = present_injection.InjectionStats;

// VRR exports
pub const VrrConfig = vrr.VrrConfig;
pub const VrrSource = vrr.VrrSource;
pub const VrrStatus = vrr.VrrStatus;
pub const LfcState = vrr.LfcState;

/// Library version
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 4,
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

/// Recommended minimum driver version for optimal nvvk functionality
pub const recommended_driver = struct {
    pub const major: u32 = 590;
    pub const minor: u32 = 48;
    pub const patch: u32 = 1;
    pub const string = "590.48.01";
};

/// Parsed driver version
pub const DriverVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,

    /// Parse version string (e.g., "590.48.01") into components
    pub fn parse(version_str: []const u8) ?DriverVersion {
        var parts = std.mem.splitScalar(u8, version_str, '.');
        const major_str = parts.next() orelse return null;
        const minor_str = parts.next() orelse return null;
        const patch_str = parts.next() orelse "0";

        return .{
            .major = std.fmt.parseInt(u32, major_str, 10) catch return null,
            .minor = std.fmt.parseInt(u32, minor_str, 10) catch return null,
            .patch = std.fmt.parseInt(u32, patch_str, 10) catch 0,
        };
    }

    /// Check if this version meets or exceeds the recommended version
    pub fn meetsRecommended(self: DriverVersion) bool {
        if (self.major > recommended_driver.major) return true;
        if (self.major < recommended_driver.major) return false;
        if (self.minor > recommended_driver.minor) return true;
        if (self.minor < recommended_driver.minor) return false;
        return self.patch >= recommended_driver.patch;
    }

    /// Check if this version has the swapchain recreation fix (590+)
    pub fn hasSwapchainFix(self: DriverVersion) bool {
        return self.major >= 590;
    }

    /// Check if this version has improved Wayland 1.20+ support (590+)
    pub fn hasWayland120Support(self: DriverVersion) bool {
        return self.major >= 590;
    }

    /// Check if this version has the DPI reporting fix (590+)
    pub fn hasDpiFix(self: DriverVersion) bool {
        return self.major >= 590;
    }

    /// Check if this version has EGL multisample fixes (590+)
    pub fn hasEglMultisampleFix(self: DriverVersion) bool {
        return self.major >= 590;
    }
};

/// Get current driver version as parsed struct
pub fn getDriverVersion(allocator: std.mem.Allocator) ?DriverVersion {
    const version_str = getNvidiaDriverVersion(allocator) orelse return null;
    defer allocator.free(version_str);
    return DriverVersion.parse(version_str);
}

/// Check if current driver meets recommended version
pub fn isDriverRecommended(allocator: std.mem.Allocator) bool {
    const ver = getDriverVersion(allocator) orelse return false;
    return ver.meetsRecommended();
}

// =============================================================================
// Extension support queries
// =============================================================================

/// Extension names as C strings
pub const ext_names = struct {
    pub const low_latency2 = vulkan.VK_NV_LOW_LATENCY_2_EXTENSION_NAME;
    pub const diagnostic_checkpoints = vulkan.VK_NV_DEVICE_DIAGNOSTIC_CHECKPOINTS_EXTENSION_NAME;
    pub const diagnostics_config = vulkan.VK_NV_DEVICE_DIAGNOSTICS_CONFIG_EXTENSION_NAME;
    pub const mem_decompression = @import("memory_decompression.zig").VK_NV_MEMORY_DECOMPRESSION_EXTENSION_NAME;
    pub const mesh_shdr = @import("mesh_shader.zig").VK_NV_MESH_SHADER_EXTENSION_NAME;
    pub const ray_trace = @import("ray_tracing.zig").VK_NV_RAY_TRACING_EXTENSION_NAME;

    /// Get all extension names as a slice
    pub fn all() []const [*:0]const u8 {
        return &[_][*:0]const u8{
            low_latency2,
            diagnostic_checkpoints,
            diagnostics_config,
            mem_decompression,
            mesh_shdr,
            ray_trace,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "version" {
    try std.testing.expectEqual(@as(u8, 0), version.major);
    try std.testing.expectEqual(@as(u8, 4), version.minor);
    try std.testing.expectEqual(@as(u8, 0), version.patch);
}

test "extension names" {
    const exts = ext_names.all();
    try std.testing.expectEqual(@as(usize, 6), exts.len);
}

test "DriverVersion parsing" {
    const v1 = DriverVersion.parse("590.48.01").?;
    try std.testing.expectEqual(@as(u32, 590), v1.major);
    try std.testing.expectEqual(@as(u32, 48), v1.minor);
    try std.testing.expectEqual(@as(u32, 1), v1.patch);

    const v2 = DriverVersion.parse("535.183.01").?;
    try std.testing.expectEqual(@as(u32, 535), v2.major);
    try std.testing.expect(!v2.meetsRecommended());

    const v3 = DriverVersion.parse("590.48.01").?;
    try std.testing.expect(v3.meetsRecommended());
    try std.testing.expect(v3.hasSwapchainFix());
    try std.testing.expect(v3.hasWayland120Support());
    try std.testing.expect(v3.hasDpiFix());
}

test "DriverVersion 590+ feature checks" {
    const old = DriverVersion{ .major = 535, .minor = 183, .patch = 1 };
    try std.testing.expect(!old.hasSwapchainFix());
    try std.testing.expect(!old.hasWayland120Support());

    const new = DriverVersion{ .major = 590, .minor = 48, .patch = 1 };
    try std.testing.expect(new.hasSwapchainFix());
    try std.testing.expect(new.hasWayland120Support());
    try std.testing.expect(new.hasDpiFix());
    try std.testing.expect(new.hasEglMultisampleFix());
}

test {
    // Run all module tests
    std.testing.refAllDecls(@This());
}
