//! VK_NV_optical_flow Extension Wrapper
//!
//! Provides GPU-accelerated optical flow estimation for motion vector generation.
//! This is the foundation for frame generation (DLSS FG alternative) on Linux.
//!
//! Key capabilities:
//! - Motion vector estimation between frame pairs
//! - Bidirectional flow support
//! - Multiple grid sizes (1x1, 2x2, 4x4, 8x8)
//! - Cost map output for quality assessment
//! - Global flow estimation
//!
//! Requires NVIDIA driver 590+ and VK_NV_optical_flow extension.
//! Uses NVIDIA Optical Flow SDK Version 5 under the hood.

const std = @import("std");
const vk = @import("vulkan.zig");

// =============================================================================
// Extension Constants
// =============================================================================

pub const VK_NV_OPTICAL_FLOW_EXTENSION_NAME = "VK_NV_optical_flow";
pub const VK_NV_OPTICAL_FLOW_SPEC_VERSION: u32 = 1;

// Structure types
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_OPTICAL_FLOW_FEATURES_NV: u32 = 1000464000;
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_OPTICAL_FLOW_PROPERTIES_NV: u32 = 1000464001;
pub const VK_STRUCTURE_TYPE_OPTICAL_FLOW_IMAGE_FORMAT_INFO_NV: u32 = 1000464002;
pub const VK_STRUCTURE_TYPE_OPTICAL_FLOW_IMAGE_FORMAT_PROPERTIES_NV: u32 = 1000464003;
pub const VK_STRUCTURE_TYPE_OPTICAL_FLOW_SESSION_CREATE_INFO_NV: u32 = 1000464004;
pub const VK_STRUCTURE_TYPE_OPTICAL_FLOW_EXECUTE_INFO_NV: u32 = 1000464005;
pub const VK_STRUCTURE_TYPE_OPTICAL_FLOW_SESSION_CREATE_PRIVATE_DATA_INFO_NV: u32 = 1000464010;

// Object type
pub const VK_OBJECT_TYPE_OPTICAL_FLOW_SESSION_NV: u32 = 1000464000;

// Format for optical flow output
pub const VK_FORMAT_R16G16_S10_5_NV: u32 = 1000464000;

// =============================================================================
// Enums and Flags
// =============================================================================

/// Grid size for optical flow output
pub const GridSize = enum(u32) {
    unknown = 0,
    @"1x1" = 0x00000001,
    @"2x2" = 0x00000002,
    @"4x4" = 0x00000004,
    @"8x8" = 0x00000008,
};

/// Usage flags for optical flow images
pub const UsageFlags = packed struct(u32) {
    input: bool = false,
    output: bool = false,
    hint: bool = false,
    cost: bool = false,
    global_flow: bool = false,
    _padding: u27 = 0,
};

/// Performance level selection
pub const PerformanceLevel = enum(u32) {
    unknown = 0,
    slow = 1,
    medium = 2,
    fast = 3,
};

/// Session binding points
pub const SessionBindingPoint = enum(u32) {
    input = 0,
    reference = 1,
    hint = 2,
    flow_vector = 3,
    backward_flow_vector = 4,
    cost = 5,
    backward_cost = 6,
    global_flow = 7,
};

/// Execute flags
pub const ExecuteFlags = packed struct(u32) {
    disable_temporal_hints: bool = false,
    _padding: u31 = 0,
};

// =============================================================================
// Vulkan Structures
// =============================================================================

pub const VkOpticalFlowSessionNV = *opaque {};

pub const VkPhysicalDeviceOpticalFlowFeaturesNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_OPTICAL_FLOW_FEATURES_NV,
    pNext: ?*anyopaque = null,
    opticalFlow: u32 = 0,
};

pub const VkPhysicalDeviceOpticalFlowPropertiesNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_OPTICAL_FLOW_PROPERTIES_NV,
    pNext: ?*anyopaque = null,
    supportedOutputGridSizes: u32 = 0,
    supportedHintGridSizes: u32 = 0,
    hintSupported: u32 = 0,
    costSupported: u32 = 0,
    bidirectionalFlowSupported: u32 = 0,
    globalFlowSupported: u32 = 0,
    minWidth: u32 = 0,
    minHeight: u32 = 0,
    maxWidth: u32 = 0,
    maxHeight: u32 = 0,
    maxNumRegionsOfInterest: u32 = 0,
};

pub const VkOpticalFlowImageFormatInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_OPTICAL_FLOW_IMAGE_FORMAT_INFO_NV,
    pNext: ?*const anyopaque = null,
    usage: u32 = 0,
};

pub const VkOpticalFlowImageFormatPropertiesNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_OPTICAL_FLOW_IMAGE_FORMAT_PROPERTIES_NV,
    pNext: ?*const anyopaque = null,
    format: u32 = 0,
};

pub const VkOpticalFlowSessionCreateInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_OPTICAL_FLOW_SESSION_CREATE_INFO_NV,
    pNext: ?*anyopaque = null,
    width: u32 = 0,
    height: u32 = 0,
    imageFormat: u32 = 0,
    flowVectorFormat: u32 = 0,
    costFormat: u32 = 0,
    outputGridSize: u32 = 0,
    hintGridSize: u32 = 0,
    performanceLevel: u32 = 0,
    flags: u32 = 0,
};

pub const VkOpticalFlowExecuteInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_OPTICAL_FLOW_EXECUTE_INFO_NV,
    pNext: ?*anyopaque = null,
    flags: u32 = 0,
    regionCount: u32 = 0,
    pRegions: ?*const vk.VkRect2D = null,
};

// =============================================================================
// Function Types
// =============================================================================

pub const PFN_vkGetPhysicalDeviceOpticalFlowImageFormatsNV = *const fn (
    physicalDevice: vk.VkPhysicalDevice,
    pOpticalFlowImageFormatInfo: *const VkOpticalFlowImageFormatInfoNV,
    pFormatCount: *u32,
    pImageFormatProperties: ?[*]VkOpticalFlowImageFormatPropertiesNV,
) callconv(.c) i32;

pub const PFN_vkCreateOpticalFlowSessionNV = *const fn (
    device: vk.VkDevice,
    pCreateInfo: *const VkOpticalFlowSessionCreateInfoNV,
    pAllocator: ?*const vk.VkAllocationCallbacks,
    pSession: *VkOpticalFlowSessionNV,
) callconv(.c) i32;

pub const PFN_vkDestroyOpticalFlowSessionNV = *const fn (
    device: vk.VkDevice,
    session: VkOpticalFlowSessionNV,
    pAllocator: ?*const vk.VkAllocationCallbacks,
) callconv(.c) void;

pub const PFN_vkBindOpticalFlowSessionImageNV = *const fn (
    device: vk.VkDevice,
    session: VkOpticalFlowSessionNV,
    bindingPoint: u32,
    view: vk.VkImageView,
    layout: u32,
) callconv(.c) i32;

pub const PFN_vkCmdOpticalFlowExecuteNV = *const fn (
    commandBuffer: vk.VkCommandBuffer,
    session: VkOpticalFlowSessionNV,
    pExecuteInfo: *const VkOpticalFlowExecuteInfoNV,
) callconv(.c) void;

// =============================================================================
// High-Level Wrapper
// =============================================================================

/// Optical flow session context
pub const OpticalFlowContext = struct {
    device: vk.VkDevice,
    session: VkOpticalFlowSessionNV,
    width: u32,
    height: u32,
    output_grid_size: GridSize,
    performance_level: PerformanceLevel,
    bidirectional: bool,

    // Function pointers
    vkDestroyOpticalFlowSessionNV: ?PFN_vkDestroyOpticalFlowSessionNV,
    vkBindOpticalFlowSessionImageNV: ?PFN_vkBindOpticalFlowSessionImageNV,
    vkCmdOpticalFlowExecuteNV: ?PFN_vkCmdOpticalFlowExecuteNV,

    /// Destroy the optical flow session
    pub fn deinit(self: *OpticalFlowContext) void {
        if (self.vkDestroyOpticalFlowSessionNV) |destroy| {
            destroy(self.device, self.session, null);
        }
    }

    /// Bind an image to a specific binding point
    pub fn bindImage(
        self: *OpticalFlowContext,
        binding_point: SessionBindingPoint,
        image_view: vk.VkImageView,
        layout: u32,
    ) !void {
        const bind = self.vkBindOpticalFlowSessionImageNV orelse
            return error.ExtensionNotLoaded;

        const result = bind(
            self.device,
            self.session,
            @intFromEnum(binding_point),
            image_view,
            layout,
        );
        try vk.check(result);
    }

    /// Execute optical flow estimation
    pub fn execute(
        self: *OpticalFlowContext,
        cmd: vk.VkCommandBuffer,
        regions: ?[]const vk.VkRect2D,
        flags: ExecuteFlags,
    ) void {
        const exec = self.vkCmdOpticalFlowExecuteNV orelse return;

        const info = VkOpticalFlowExecuteInfoNV{
            .flags = @bitCast(flags),
            .regionCount = if (regions) |r| @intCast(r.len) else 0,
            .pRegions = if (regions) |r| r.ptr else null,
        };

        exec(cmd, self.session, &info);
    }
};

/// Configuration for creating an optical flow session
pub const OpticalFlowConfig = struct {
    width: u32,
    height: u32,
    image_format: u32 = 0, // VK_FORMAT_B8G8R8A8_UNORM typically
    output_grid_size: GridSize = .@"4x4",
    hint_grid_size: GridSize = .unknown,
    performance_level: PerformanceLevel = .fast,
    bidirectional: bool = false,
    enable_cost: bool = false,
    enable_global_flow: bool = false,
};

/// Query optical flow properties for a physical device
pub const OpticalFlowProperties = struct {
    supported_output_grid_sizes: u32,
    supported_hint_grid_sizes: u32,
    hint_supported: bool,
    cost_supported: bool,
    bidirectional_supported: bool,
    global_flow_supported: bool,
    min_width: u32,
    min_height: u32,
    max_width: u32,
    max_height: u32,
    max_regions_of_interest: u32,

    pub fn fromVk(props: VkPhysicalDeviceOpticalFlowPropertiesNV) OpticalFlowProperties {
        return .{
            .supported_output_grid_sizes = props.supportedOutputGridSizes,
            .supported_hint_grid_sizes = props.supportedHintGridSizes,
            .hint_supported = props.hintSupported != 0,
            .cost_supported = props.costSupported != 0,
            .bidirectional_supported = props.bidirectionalFlowSupported != 0,
            .global_flow_supported = props.globalFlowSupported != 0,
            .min_width = props.minWidth,
            .min_height = props.minHeight,
            .max_width = props.maxWidth,
            .max_height = props.maxHeight,
            .max_regions_of_interest = props.maxNumRegionsOfInterest,
        };
    }

    /// Check if a grid size is supported for output
    pub fn supportsOutputGridSize(self: OpticalFlowProperties, size: GridSize) bool {
        return (self.supported_output_grid_sizes & @intFromEnum(size)) != 0;
    }

    /// Check if a grid size is supported for hints
    pub fn supportsHintGridSize(self: OpticalFlowProperties, size: GridSize) bool {
        return (self.supported_hint_grid_sizes & @intFromEnum(size)) != 0;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "extension constants" {
    try std.testing.expectEqualStrings("VK_NV_optical_flow", VK_NV_OPTICAL_FLOW_EXTENSION_NAME);
    try std.testing.expectEqual(@as(u32, 1), VK_NV_OPTICAL_FLOW_SPEC_VERSION);
}

test "grid size enum" {
    try std.testing.expectEqual(@as(u32, 0x00000001), @intFromEnum(GridSize.@"1x1"));
    try std.testing.expectEqual(@as(u32, 0x00000004), @intFromEnum(GridSize.@"4x4"));
}

test "usage flags" {
    const flags = UsageFlags{ .input = true, .output = true };
    const raw: u32 = @bitCast(flags);
    try std.testing.expectEqual(@as(u32, 0b00000011), raw);
}

test "config defaults" {
    const config = OpticalFlowConfig{
        .width = 1920,
        .height = 1080,
    };
    try std.testing.expectEqual(GridSize.@"4x4", config.output_grid_size);
    try std.testing.expectEqual(PerformanceLevel.fast, config.performance_level);
}
