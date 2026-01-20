//! Vulkan Validation Layer Integration
//!
//! Provides utilities for enabling and configuring Vulkan validation layers
//! during development and debugging. Automatically enabled when NVVK_DEBUG=1.

const std = @import("std");
const vk = @import("vulkan.zig");

// =============================================================================
// Validation Layer Constants
// =============================================================================

/// Standard Khronos validation layer name
pub const VALIDATION_LAYER_NAME: [*:0]const u8 = "VK_LAYER_KHRONOS_validation";

/// Debug utils extension for custom debug callbacks
pub const DEBUG_UTILS_EXTENSION: [*:0]const u8 = "VK_EXT_debug_utils";

/// Structure types for debug utils
pub const VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT: u32 = 1000128004;
pub const VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT: u32 = 1000128000;
pub const VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT: u32 = 1000128002;

// =============================================================================
// Debug Message Types
// =============================================================================

/// Debug message severity flags (VkDebugUtilsMessageSeverityFlagsEXT)
pub const DebugSeverity = packed struct(u32) {
    verbose: bool = false, // bit 0: 0x00000001
    _reserved1: u3 = 0, // bits 1-3
    info: bool = false, // bit 4: 0x00000010
    _reserved2: u3 = 0, // bits 5-7
    warning: bool = false, // bit 8: 0x00000100
    _reserved3: u3 = 0, // bits 9-11
    error_bit: bool = false, // bit 12: 0x00001000
    _reserved4: u19 = 0, // bits 13-31

    pub const all: DebugSeverity = .{
        .verbose = true,
        .info = true,
        .warning = true,
        .error_bit = true,
    };

    pub const warnings_and_errors: DebugSeverity = .{
        .warning = true,
        .error_bit = true,
    };

    pub const errors_only: DebugSeverity = .{
        .error_bit = true,
    };
};

/// Debug message type flags (VkDebugUtilsMessageTypeFlagsEXT)
pub const DebugType = packed struct(u32) {
    general: bool = false, // bit 0: 0x00000001
    validation: bool = false, // bit 1: 0x00000002
    performance: bool = false, // bit 2: 0x00000004
    device_address_binding: bool = false, // bit 3: 0x00000008
    _reserved: u28 = 0, // bits 4-31

    pub const all: DebugType = .{
        .general = true,
        .validation = true,
        .performance = true,
        .device_address_binding = true,
    };

    pub const validation_only: DebugType = .{
        .validation = true,
    };

    pub const validation_and_performance: DebugType = .{
        .validation = true,
        .performance = true,
    };
};

// =============================================================================
// Debug Utils Structures
// =============================================================================

/// Debug messenger callback data
pub const VkDebugUtilsMessengerCallbackDataEXT = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    pMessageIdName: ?[*:0]const u8 = null,
    messageIdNumber: i32 = 0,
    pMessage: ?[*:0]const u8 = null,
    queueLabelCount: u32 = 0,
    pQueueLabels: ?*const anyopaque = null,
    cmdBufLabelCount: u32 = 0,
    pCmdBufLabels: ?*const anyopaque = null,
    objectCount: u32 = 0,
    pObjects: ?*const anyopaque = null,
};

/// Debug messenger create info
pub const VkDebugUtilsMessengerCreateInfoEXT = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    messageSeverity: DebugSeverity = DebugSeverity.warnings_and_errors,
    messageType: DebugType = DebugType.all,
    pfnUserCallback: ?PFN_vkDebugUtilsMessengerCallbackEXT = null,
    pUserData: ?*anyopaque = null,
};

/// Object name info for debug labeling
pub const VkDebugUtilsObjectNameInfoEXT = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
    pNext: ?*const anyopaque = null,
    objectType: u32 = 0,
    objectHandle: u64 = 0,
    pObjectName: ?[*:0]const u8 = null,
};

/// Debug messenger handle
pub const VkDebugUtilsMessengerEXT = u64;

// =============================================================================
// Function Pointer Types
// =============================================================================

pub const PFN_vkDebugUtilsMessengerCallbackEXT = *const fn (
    messageSeverity: DebugSeverity,
    messageTypes: DebugType,
    pCallbackData: *const VkDebugUtilsMessengerCallbackDataEXT,
    pUserData: ?*anyopaque,
) callconv(.c) u32;

pub const PFN_vkCreateDebugUtilsMessengerEXT = *const fn (
    instance: vk.VkInstance,
    pCreateInfo: *const VkDebugUtilsMessengerCreateInfoEXT,
    pAllocator: ?*const vk.VkAllocationCallbacks,
    pMessenger: *VkDebugUtilsMessengerEXT,
) callconv(.c) i32;

pub const PFN_vkDestroyDebugUtilsMessengerEXT = *const fn (
    instance: vk.VkInstance,
    messenger: VkDebugUtilsMessengerEXT,
    pAllocator: ?*const vk.VkAllocationCallbacks,
) callconv(.c) void;

pub const PFN_vkSetDebugUtilsObjectNameEXT = *const fn (
    device: vk.VkDevice,
    pNameInfo: *const VkDebugUtilsObjectNameInfoEXT,
) callconv(.c) i32;

// =============================================================================
// Validation Context
// =============================================================================

/// Validation layer context for managing debug output
pub const ValidationContext = struct {
    instance: vk.VkInstance,
    messenger: VkDebugUtilsMessengerEXT,
    create_messenger: ?PFN_vkCreateDebugUtilsMessengerEXT,
    destroy_messenger: ?PFN_vkDestroyDebugUtilsMessengerEXT,
    set_object_name: ?PFN_vkSetDebugUtilsObjectNameEXT,
    enabled: bool,
    error_count: std.atomic.Value(u64),
    warning_count: std.atomic.Value(u64),

    /// Initialize validation context
    pub fn init(
        instance: vk.VkInstance,
        getInstanceProcAddr: vk.PFN_vkGetInstanceProcAddr,
        severity: DebugSeverity,
        types: DebugType,
    ) !ValidationContext {
        var ctx = ValidationContext{
            .instance = instance,
            .messenger = 0,
            .create_messenger = @ptrCast(getInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT")),
            .destroy_messenger = @ptrCast(getInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT")),
            .set_object_name = null,
            .enabled = false,
            .error_count = std.atomic.Value(u64).init(0),
            .warning_count = std.atomic.Value(u64).init(0),
        };

        if (ctx.create_messenger == null or ctx.destroy_messenger == null) {
            return ctx; // Extension not available, validation disabled
        }

        const create_info = VkDebugUtilsMessengerCreateInfoEXT{
            .messageSeverity = severity,
            .messageType = types,
            .pfnUserCallback = &defaultDebugCallback,
            .pUserData = &ctx,
        };

        const result = ctx.create_messenger.?(instance, &create_info, null, &ctx.messenger);
        if (result == 0) {
            ctx.enabled = true;
        }

        return ctx;
    }

    /// Initialize with device for object naming
    pub fn initDevice(
        self: *ValidationContext,
        device: vk.VkDevice,
        getDeviceProcAddr: vk.PFN_vkGetDeviceProcAddr,
    ) void {
        self.set_object_name = @ptrCast(getDeviceProcAddr(device, "vkSetDebugUtilsObjectNameEXT"));
    }

    /// Cleanup validation context
    pub fn deinit(self: *ValidationContext) void {
        if (self.enabled and self.destroy_messenger != null) {
            self.destroy_messenger.?(self.instance, self.messenger, null);
            self.enabled = false;
        }
    }

    /// Set debug name for a Vulkan object
    pub fn setObjectName(
        self: *const ValidationContext,
        device: vk.VkDevice,
        object_type: u32,
        object_handle: u64,
        name: [*:0]const u8,
    ) void {
        if (self.set_object_name) |set_name| {
            const name_info = VkDebugUtilsObjectNameInfoEXT{
                .objectType = object_type,
                .objectHandle = object_handle,
                .pObjectName = name,
            };
            _ = set_name(device, &name_info);
        }
    }

    /// Get error statistics
    pub fn getStats(self: *const ValidationContext) ValidationStats {
        return .{
            .enabled = self.enabled,
            .error_count = self.error_count.load(.acquire),
            .warning_count = self.warning_count.load(.acquire),
        };
    }
};

/// Validation statistics
pub const ValidationStats = struct {
    enabled: bool,
    error_count: u64,
    warning_count: u64,
};

// =============================================================================
// Default Debug Callback
// =============================================================================

fn defaultDebugCallback(
    severity: DebugSeverity,
    types: DebugType,
    callback_data: *const VkDebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.c) u32 {
    _ = types;

    // Update counters if we have a context
    if (user_data) |ptr| {
        const ctx: *ValidationContext = @ptrCast(@alignCast(ptr));
        if (severity.error_bit) {
            _ = ctx.error_count.fetchAdd(1, .monotonic);
        } else if (severity.warning) {
            _ = ctx.warning_count.fetchAdd(1, .monotonic);
        }
    }

    // Format severity prefix
    const prefix: []const u8 = if (severity.error_bit)
        "[ERROR]"
    else if (severity.warning)
        "[WARN]"
    else if (severity.info)
        "[INFO]"
    else
        "[VERBOSE]";

    // Print message
    if (callback_data.pMessage) |msg| {
        std.debug.print("{s} Vulkan: {s}\n", .{ prefix, std.mem.span(msg) });
    }

    // Return VK_FALSE to not abort the call
    return 0;
}

// =============================================================================
// Utility Functions
// =============================================================================

/// Check if validation layers should be enabled (via NVVK_DEBUG env)
pub fn shouldEnableValidation() bool {
    const debug_env = std.c.getenv("NVVK_DEBUG") orelse return false;
    const val = std.mem.span(debug_env);
    return std.mem.eql(u8, val, "1") or std.mem.eql(u8, val, "true");
}

/// Check if a layer is available
pub fn isLayerAvailable(
    layer_name: [*:0]const u8,
    available_layers: []const vk.VkLayerProperties,
) bool {
    const name = std.mem.span(layer_name);
    for (available_layers) |layer| {
        const available_name = std.mem.sliceTo(&layer.layerName, 0);
        if (std.mem.eql(u8, name, available_name)) {
            return true;
        }
    }
    return false;
}

/// Common Vulkan object types for setObjectName
pub const ObjectType = struct {
    pub const instance: u32 = 1;
    pub const physical_device: u32 = 2;
    pub const device: u32 = 3;
    pub const queue: u32 = 4;
    pub const semaphore: u32 = 5;
    pub const command_buffer: u32 = 6;
    pub const fence: u32 = 7;
    pub const device_memory: u32 = 8;
    pub const buffer: u32 = 9;
    pub const image: u32 = 10;
    pub const swapchain_khr: u32 = 1000001000;
    pub const surface_khr: u32 = 1000000000;
};

// =============================================================================
// Tests
// =============================================================================

test "DebugSeverity presets" {
    const all = DebugSeverity.all;
    try std.testing.expect(all.verbose);
    try std.testing.expect(all.info);
    try std.testing.expect(all.warning);
    try std.testing.expect(all.error_bit);

    const errors = DebugSeverity.errors_only;
    try std.testing.expect(!errors.verbose);
    try std.testing.expect(errors.error_bit);
}

test "DebugType presets" {
    const all = DebugType.all;
    try std.testing.expect(all.general);
    try std.testing.expect(all.validation);
    try std.testing.expect(all.performance);

    const val = DebugType.validation_only;
    try std.testing.expect(val.validation);
    try std.testing.expect(!val.general);
}

test "ValidationStats" {
    const stats = ValidationStats{
        .enabled = true,
        .error_count = 5,
        .warning_count = 10,
    };
    try std.testing.expect(stats.enabled);
    try std.testing.expectEqual(@as(u64, 5), stats.error_count);
}

test "ObjectType constants" {
    try std.testing.expectEqual(@as(u32, 3), ObjectType.device);
    try std.testing.expectEqual(@as(u32, 10), ObjectType.image);
}
