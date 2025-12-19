//! VK_NV_memory_decompression Extension Wrapper
//!
//! Provides GPU-accelerated memory decompression for faster asset loading.
//! This extension allows the GPU to decompress data directly without CPU involvement,
//! significantly improving load times for compressed textures and buffers.
//!
//! Supported compression methods:
//! - GDEFLATE 1.0 (GPU-optimized deflate)
//!
//! Requires NVIDIA driver 590+ and VK_NV_memory_decompression extension.

const std = @import("std");
const vk = @import("vulkan.zig");

// =============================================================================
// Extension Constants
// =============================================================================

pub const VK_NV_MEMORY_DECOMPRESSION_EXTENSION_NAME = "VK_NV_memory_decompression";
pub const VK_NV_MEMORY_DECOMPRESSION_SPEC_VERSION: u32 = 1;

// =============================================================================
// Types
// =============================================================================

/// Compression methods supported by the extension
pub const CompressionMethod = enum(u64) {
    gdeflate_1_0 = 0x00000001,
    _,

    pub fn toFlags(self: CompressionMethod) VkMemoryDecompressionMethodFlagsNV {
        return @intFromEnum(self);
    }
};

pub const VkMemoryDecompressionMethodFlagsNV = u64;
pub const VK_MEMORY_DECOMPRESSION_METHOD_GDEFLATE_1_0_BIT_NV: VkMemoryDecompressionMethodFlagsNV = 0x00000001;

/// Region to decompress
pub const VkDecompressMemoryRegionNV = extern struct {
    srcAddress: u64 = 0,
    dstAddress: u64 = 0,
    compressedSize: u64 = 0,
    decompressedSize: u64 = 0,
    decompressionMethod: VkMemoryDecompressionMethodFlagsNV = 0,
};

/// Physical device memory decompression properties
pub const VkPhysicalDeviceMemoryDecompressionPropertiesNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000427001),
    pNext: ?*anyopaque = null,
    decompressionMethods: VkMemoryDecompressionMethodFlagsNV = 0,
    maxDecompressionIndirectCount: u64 = 0,
};

/// Physical device memory decompression features
pub const VkPhysicalDeviceMemoryDecompressionFeaturesNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000427000),
    pNext: ?*anyopaque = null,
    memoryDecompression: vk.VkBool32 = vk.VK_FALSE,
};

// =============================================================================
// Function Pointer Types
// =============================================================================

pub const PFN_vkCmdDecompressMemoryNV = *const fn (
    vk.VkCommandBuffer,
    u32,
    [*]const VkDecompressMemoryRegionNV,
) callconv(.c) void;

pub const PFN_vkCmdDecompressMemoryIndirectCountNV = *const fn (
    vk.VkCommandBuffer,
    u64, // indirectCommandsAddress
    u64, // indirectCommandsCountAddress
    u32, // stride
) callconv(.c) void;

// =============================================================================
// Decompression Context
// =============================================================================

pub const DecompressionContext = struct {
    device: vk.VkDevice,
    vkCmdDecompressMemoryNV: ?PFN_vkCmdDecompressMemoryNV = null,
    vkCmdDecompressMemoryIndirectCountNV: ?PFN_vkCmdDecompressMemoryIndirectCountNV = null,

    pub fn init(device: vk.VkDevice, getDeviceProcAddr: vk.PFN_vkGetDeviceProcAddr) DecompressionContext {
        return .{
            .device = device,
            .vkCmdDecompressMemoryNV = @ptrCast(getDeviceProcAddr(device, "vkCmdDecompressMemoryNV")),
            .vkCmdDecompressMemoryIndirectCountNV = @ptrCast(getDeviceProcAddr(device, "vkCmdDecompressMemoryIndirectCountNV")),
        };
    }

    /// Check if memory decompression is supported
    pub fn isSupported(self: *const DecompressionContext) bool {
        return self.vkCmdDecompressMemoryNV != null;
    }

    /// Check if indirect decompression is supported
    pub fn hasIndirectSupport(self: *const DecompressionContext) bool {
        return self.vkCmdDecompressMemoryIndirectCountNV != null;
    }

    /// Decompress memory regions using GDEFLATE
    ///
    /// Parameters:
    ///   cmd - Command buffer to record into
    ///   regions - Array of decompression regions
    pub fn decompressMemory(
        self: *const DecompressionContext,
        cmd: vk.VkCommandBuffer,
        regions: []const DecompressionRegion,
    ) !void {
        const func = self.vkCmdDecompressMemoryNV orelse return error.ExtensionNotPresent;

        if (regions.len == 0) return;

        // Convert to Vulkan structs
        var vk_regions: [64]VkDecompressMemoryRegionNV = undefined;
        const count = @min(regions.len, 64);

        for (0..count) |i| {
            vk_regions[i] = regions[i].toVk();
        }

        func(cmd, @intCast(count), &vk_regions);
    }

    /// Decompress memory with indirect command buffer
    ///
    /// Allows the GPU to read decompression commands from a buffer,
    /// enabling fully GPU-driven asset streaming.
    pub fn decompressMemoryIndirect(
        self: *const DecompressionContext,
        cmd: vk.VkCommandBuffer,
        indirect_address: u64,
        count_address: u64,
        stride: u32,
    ) !void {
        const func = self.vkCmdDecompressMemoryIndirectCountNV orelse return error.ExtensionNotPresent;
        func(cmd, indirect_address, count_address, stride);
    }
};

/// High-level decompression region descriptor
pub const DecompressionRegion = struct {
    src_address: u64,
    dst_address: u64,
    compressed_size: u64,
    decompressed_size: u64,
    method: CompressionMethod = .gdeflate_1_0,

    pub fn toVk(self: DecompressionRegion) VkDecompressMemoryRegionNV {
        return .{
            .srcAddress = self.src_address,
            .dstAddress = self.dst_address,
            .compressedSize = self.compressed_size,
            .decompressedSize = self.decompressed_size,
            .decompressionMethod = self.method.toFlags(),
        };
    }

    /// Create from buffer device addresses
    pub fn fromBuffers(
        src_buffer_address: u64,
        src_offset: u64,
        dst_buffer_address: u64,
        dst_offset: u64,
        compressed_size: u64,
        decompressed_size: u64,
    ) DecompressionRegion {
        return .{
            .src_address = src_buffer_address + src_offset,
            .dst_address = dst_buffer_address + dst_offset,
            .compressed_size = compressed_size,
            .decompressed_size = decompressed_size,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "DecompressionRegion conversion" {
    const region = DecompressionRegion{
        .src_address = 0x1000,
        .dst_address = 0x2000,
        .compressed_size = 100,
        .decompressed_size = 500,
        .method = .gdeflate_1_0,
    };

    const vk_region = region.toVk();
    try std.testing.expectEqual(@as(u64, 0x1000), vk_region.srcAddress);
    try std.testing.expectEqual(@as(u64, 0x2000), vk_region.dstAddress);
    try std.testing.expectEqual(@as(u64, 100), vk_region.compressedSize);
    try std.testing.expectEqual(@as(u64, 500), vk_region.decompressedSize);
    try std.testing.expectEqual(@as(u64, 1), vk_region.decompressionMethod);
}

test "fromBuffers helper" {
    const region = DecompressionRegion.fromBuffers(
        0x10000, // src buffer
        0x100, // src offset
        0x20000, // dst buffer
        0x200, // dst offset
        1024,
        4096,
    );

    try std.testing.expectEqual(@as(u64, 0x10100), region.src_address);
    try std.testing.expectEqual(@as(u64, 0x20200), region.dst_address);
}
