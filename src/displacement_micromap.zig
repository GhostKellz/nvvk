//! VK_NV_displacement_micromap Extension Wrapper
//!
//! Provides displacement micromap support for ray tracing acceleration structures.
//! Micromaps allow adding fine geometric detail to triangles without increasing
//! the base geometry complexity, improving RT performance with detailed surfaces.
//!
//! Key capabilities:
//! - Displacement maps for ray tracing triangles
//! - Compressed in-memory format for efficiency
//! - Subtriangle vertex displacement along defined vectors
//! - Multiple compression formats for different quality/size tradeoffs
//!
//! Requires NVIDIA driver 590+, Ada Lovelace (RTX 40) or newer for best performance.
//! Also requires VK_EXT_opacity_micromap and VK_KHR_acceleration_structure.
//!
//! Workflow:
//! 1. Create micromap with displacement data
//! 2. Attach to acceleration structure triangles via pNext chain
//! 3. Ray trace with fine-grained displacement detail

const std = @import("std");
const vk = @import("vulkan.zig");

// =============================================================================
// Extension Constants
// =============================================================================

pub const VK_NV_DISPLACEMENT_MICROMAP_EXTENSION_NAME = "VK_NV_displacement_micromap";
pub const VK_NV_DISPLACEMENT_MICROMAP_SPEC_VERSION: u32 = 2;

// Structure types
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DISPLACEMENT_MICROMAP_FEATURES_NV: u32 = 1000397000;
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DISPLACEMENT_MICROMAP_PROPERTIES_NV: u32 = 1000397001;
pub const VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_TRIANGLES_DISPLACEMENT_MICROMAP_NV: u32 = 1000397002;

// Micromap type
pub const VK_MICROMAP_TYPE_DISPLACEMENT_MICROMAP_NV: u32 = 1000397000;

// Pipeline create flag
pub const VK_PIPELINE_CREATE_RAY_TRACING_DISPLACEMENT_MICROMAP_BIT_NV: u32 = 0x10000000;

// Build acceleration structure flag
pub const VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_DISPLACEMENT_MICROMAP_UPDATE_NV: u32 = 0x00000200;

// =============================================================================
// Enums
// =============================================================================

/// Displacement micromap format
pub const DisplacementFormat = enum(u32) {
    /// 64 triangles in 64 bytes (uncompressed, subdivision level 3)
    /// 45 displacement values as 11-bit unorm
    @"64_triangles_64_bytes" = 1,
    /// 256 triangles in 128 bytes (compressed)
    @"256_triangles_128_bytes" = 2,
    /// 1024 triangles in 128 bytes (compressed, highest compression)
    @"1024_triangles_128_bytes" = 3,
};

/// Displacement bias and scale mode
pub const DisplacementBiasAndScaleFormat = enum(u32) {
    none = 0,
    fp16 = 1,
    fp32 = 2,
};

// =============================================================================
// Vulkan Structures
// =============================================================================

pub const VkPhysicalDeviceDisplacementMicromapFeaturesNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DISPLACEMENT_MICROMAP_FEATURES_NV,
    pNext: ?*anyopaque = null,
    displacementMicromap: u32 = 0,
};

pub const VkPhysicalDeviceDisplacementMicromapPropertiesNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DISPLACEMENT_MICROMAP_PROPERTIES_NV,
    pNext: ?*anyopaque = null,
    maxDisplacementMicromapSubdivisionLevel: u32 = 0,
};

pub const VkAccelerationStructureTrianglesDisplacementMicromapNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_TRIANGLES_DISPLACEMENT_MICROMAP_NV,
    pNext: ?*anyopaque = null,
    displacementBiasAndScaleFormat: u32 = 0,
    displacementVectorFormat: u32 = 0,
    displacementBiasAndScaleBuffer: u64 = 0, // VkDeviceOrHostAddressConstKHR
    displacementBiasAndScaleStride: u64 = 0,
    displacementVectorBuffer: u64 = 0, // VkDeviceOrHostAddressConstKHR
    displacementVectorStride: u64 = 0,
    displacedMicromapPrimitiveFlags: u64 = 0, // VkDeviceOrHostAddressConstKHR
    displacedMicromapPrimitiveFlagsStride: u64 = 0,
    indexType: u32 = 0,
    indexBuffer: u64 = 0, // VkDeviceOrHostAddressConstKHR
    indexStride: u64 = 0,
    baseTriangle: u32 = 0,
    usageCountsCount: u32 = 0,
    pUsageCounts: ?*const anyopaque = null, // VkMicromapUsageEXT*
    ppUsageCounts: ?*const ?*const anyopaque = null,
    micromap: u64 = 0, // VkMicromapEXT
};

// =============================================================================
// High-Level Wrapper
// =============================================================================

/// Displacement micromap properties
pub const DisplacementMicromapProperties = struct {
    /// Whether displacement micromaps are supported
    supported: bool,
    /// Maximum subdivision level supported
    max_subdivision_level: u32,

    pub fn fromVk(
        features: VkPhysicalDeviceDisplacementMicromapFeaturesNV,
        props: VkPhysicalDeviceDisplacementMicromapPropertiesNV,
    ) DisplacementMicromapProperties {
        return .{
            .supported = features.displacementMicromap != 0,
            .max_subdivision_level = props.maxDisplacementMicromapSubdivisionLevel,
        };
    }

    /// Get maximum triangles at max subdivision
    pub fn maxTrianglesAtMaxSubdivision(self: DisplacementMicromapProperties) u32 {
        // Each subdivision level quadruples the triangle count
        // Level 0 = 1, Level 1 = 4, Level 2 = 16, Level 3 = 64, etc.
        return @as(u32, 1) << (@as(u5, @intCast(self.max_subdivision_level)) * 2);
    }
};

/// Configuration for displacement micromap
pub const DisplacementConfig = struct {
    /// Displacement format to use
    format: DisplacementFormat = .@"64_triangles_64_bytes",
    /// Bias and scale format
    bias_scale_format: DisplacementBiasAndScaleFormat = .fp16,
    /// Subdivision level (0-5 typically)
    subdivision_level: u32 = 3,

    /// Estimate memory usage per triangle in bytes
    pub fn bytesPerTriangle(self: DisplacementConfig) u32 {
        return switch (self.format) {
            .@"64_triangles_64_bytes" => 1, // 64 bytes / 64 triangles
            .@"256_triangles_128_bytes" => 1, // 128 bytes / 256 triangles = 0.5, round up
            .@"1024_triangles_128_bytes" => 1, // 128 bytes / 1024 triangles = 0.125, round up
        };
    }

    /// Get triangles per micromap block
    pub fn trianglesPerBlock(self: DisplacementConfig) u32 {
        return switch (self.format) {
            .@"64_triangles_64_bytes" => 64,
            .@"256_triangles_128_bytes" => 256,
            .@"1024_triangles_128_bytes" => 1024,
        };
    }

    /// Get block size in bytes
    pub fn blockSizeBytes(self: DisplacementConfig) u32 {
        return switch (self.format) {
            .@"64_triangles_64_bytes" => 64,
            .@"256_triangles_128_bytes" => 128,
            .@"1024_triangles_128_bytes" => 128,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "extension constants" {
    try std.testing.expectEqualStrings(
        "VK_NV_displacement_micromap",
        VK_NV_DISPLACEMENT_MICROMAP_EXTENSION_NAME,
    );
}

test "displacement format" {
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(DisplacementFormat.@"64_triangles_64_bytes"));
    try std.testing.expectEqual(@as(u32, 3), @intFromEnum(DisplacementFormat.@"1024_triangles_128_bytes"));
}

test "config calculations" {
    const config = DisplacementConfig{};
    try std.testing.expectEqual(@as(u32, 64), config.trianglesPerBlock());
    try std.testing.expectEqual(@as(u32, 64), config.blockSizeBytes());

    const compressed = DisplacementConfig{ .format = .@"1024_triangles_128_bytes" };
    try std.testing.expectEqual(@as(u32, 1024), compressed.trianglesPerBlock());
    try std.testing.expectEqual(@as(u32, 128), compressed.blockSizeBytes());
}

test "properties max triangles" {
    const props = DisplacementMicromapProperties{
        .supported = true,
        .max_subdivision_level = 3,
    };
    try std.testing.expectEqual(@as(u32, 64), props.maxTrianglesAtMaxSubdivision()); // 4^3 = 64

    const props5 = DisplacementMicromapProperties{
        .supported = true,
        .max_subdivision_level = 5,
    };
    try std.testing.expectEqual(@as(u32, 1024), props5.maxTrianglesAtMaxSubdivision()); // 4^5 = 1024
}
