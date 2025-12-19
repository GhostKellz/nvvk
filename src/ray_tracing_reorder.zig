//! VK_NV_ray_tracing_invocation_reorder Extension Wrapper
//!
//! Provides Shader Execution Reordering (SER) for ray tracing pipelines.
//! This extension allows the GPU to reorder shader invocations for better
//! cache locality and memory access patterns, significantly improving RT performance.
//!
//! Key benefits:
//! - 20-30% performance improvement in ray tracing workloads
//! - Better memory access patterns for complex scenes
//! - Improved cache utilization during ray traversal
//!
//! Requires NVIDIA driver 590+ and VK_NV_ray_tracing_invocation_reorder extension.
//! Also requires VK_KHR_ray_tracing_pipeline.
//!
//! Note: VK_EXT_ray_tracing_invocation_reorder is the multi-vendor successor,
//! but VK_NV is still useful for NVIDIA-specific optimizations on Ada/Blackwell.

const std = @import("std");
const vk = @import("vulkan.zig");

// =============================================================================
// Extension Constants
// =============================================================================

pub const VK_NV_RAY_TRACING_INVOCATION_REORDER_EXTENSION_NAME = "VK_NV_ray_tracing_invocation_reorder";
pub const VK_NV_RAY_TRACING_INVOCATION_REORDER_SPEC_VERSION: u32 = 1;

// Structure types
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_INVOCATION_REORDER_FEATURES_NV: u32 = 1000490000;
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_INVOCATION_REORDER_PROPERTIES_NV: u32 = 1000490001;

// =============================================================================
// Enums
// =============================================================================

/// Reordering mode hint
pub const ReorderMode = enum(u32) {
    /// No reordering
    none = 0,
    /// Reorder for better locality
    reorder = 1,
};

/// Reordering hint from device properties
pub const ReorderingHint = enum(u32) {
    /// Implementation does not indicate a preference
    unknown = 0,
    /// Implementation will likely reorder
    reorder = 1,
    /// Implementation will likely not reorder
    no_reorder = 2,
};

// =============================================================================
// Vulkan Structures
// =============================================================================

pub const VkPhysicalDeviceRayTracingInvocationReorderFeaturesNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_INVOCATION_REORDER_FEATURES_NV,
    pNext: ?*anyopaque = null,
    rayTracingInvocationReorder: u32 = 0,
};

pub const VkPhysicalDeviceRayTracingInvocationReorderPropertiesNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_INVOCATION_REORDER_PROPERTIES_NV,
    pNext: ?*anyopaque = null,
    rayTracingInvocationReorderReorderingHint: u32 = 0,
};

// =============================================================================
// High-Level Wrapper
// =============================================================================

/// Ray tracing invocation reorder properties
pub const InvocationReorderProperties = struct {
    /// Whether invocation reordering is supported
    supported: bool,
    /// Hint about whether the implementation will actually reorder
    reordering_hint: ReorderingHint,

    pub fn fromVk(
        features: VkPhysicalDeviceRayTracingInvocationReorderFeaturesNV,
        props: VkPhysicalDeviceRayTracingInvocationReorderPropertiesNV,
    ) InvocationReorderProperties {
        return .{
            .supported = features.rayTracingInvocationReorder != 0,
            .reordering_hint = @enumFromInt(props.rayTracingInvocationReorderReorderingHint),
        };
    }

    /// Check if reordering is likely to happen
    pub fn willReorder(self: InvocationReorderProperties) bool {
        return self.supported and self.reordering_hint == .reorder;
    }
};

/// Configuration for enabling invocation reorder in pipeline creation
pub const InvocationReorderConfig = struct {
    /// Enable invocation reordering
    enabled: bool = true,
    /// Reorder mode to use
    mode: ReorderMode = .reorder,

    /// Create a disabled config
    pub fn disabled() InvocationReorderConfig {
        return .{
            .enabled = false,
            .mode = .none,
        };
    }
};

// =============================================================================
// Helper Functions
// =============================================================================

/// Check if invocation reorder is available on the system
/// This is a quick check without Vulkan instance - just checks driver version
pub fn isAvailable(allocator: std.mem.Allocator) bool {
    const root = @import("root.zig");
    const ver = root.getDriverVersion(allocator) orelse return false;
    // SER requires Ada or newer (RTX 40 series) and driver 525+
    // Best performance on 590+
    return ver.major >= 525;
}

// =============================================================================
// Tests
// =============================================================================

test "extension constants" {
    try std.testing.expectEqualStrings(
        "VK_NV_ray_tracing_invocation_reorder",
        VK_NV_RAY_TRACING_INVOCATION_REORDER_EXTENSION_NAME,
    );
    try std.testing.expectEqual(@as(u32, 1), VK_NV_RAY_TRACING_INVOCATION_REORDER_SPEC_VERSION);
}

test "reorder mode enum" {
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(ReorderMode.none));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(ReorderMode.reorder));
}

test "config defaults" {
    const config = InvocationReorderConfig{};
    try std.testing.expect(config.enabled);
    try std.testing.expectEqual(ReorderMode.reorder, config.mode);

    const disabled = InvocationReorderConfig.disabled();
    try std.testing.expect(!disabled.enabled);
}

test "properties will reorder" {
    const props_yes = InvocationReorderProperties{
        .supported = true,
        .reordering_hint = .reorder,
    };
    try std.testing.expect(props_yes.willReorder());

    const props_no = InvocationReorderProperties{
        .supported = true,
        .reordering_hint = .no_reorder,
    };
    try std.testing.expect(!props_no.willReorder());

    const props_unsupported = InvocationReorderProperties{
        .supported = false,
        .reordering_hint = .reorder,
    };
    try std.testing.expect(!props_unsupported.willReorder());
}
