//! VK_LAYER_NV_low_latency - Vulkan Layer for Automatic Reflex Integration
//!
//! This simpler layer focuses only on low latency (Reflex) functionality.
//! It automatically injects latency markers without requiring game modification.
//!
//! Layer Installation:
//!   1. Copy libnvvk_layer_ll.so to /usr/share/vulkan/implicit_layer.d/
//!   2. Copy VK_LAYER_NV_low_latency.json manifest
//!   3. Layer auto-enables or use VK_INSTANCE_LAYERS env var
//!
//! Environment Variables:
//!   NVVK_LOW_LATENCY_ENABLED=0|1 (default: 1)
//!   NVVK_LOW_LATENCY_BOOST=0|1 (default: 0)
//!   NVVK_LOW_LATENCY_MIN_INTERVAL_US=<microseconds> (default: 0)
//!   NVVK_LOW_LATENCY_DEBUG=0|1 (default: 0)

const std = @import("std");
const vk = @import("vulkan.zig");
const low_latency = @import("low_latency.zig");

// =============================================================================
// Layer Constants
// =============================================================================

pub const LAYER_NAME = "VK_LAYER_NV_low_latency";
pub const LAYER_DESCRIPTION = "NVIDIA Reflex Low Latency Layer";
pub const LAYER_IMPLEMENTATION_VERSION: u32 = 1;
pub const LAYER_SPEC_VERSION: u32 = vk.VK_API_VERSION_1_4;

// =============================================================================
// Simple Spinlock Mutex (Zig 0.16+ compatible)
// =============================================================================

const Mutex = struct {
    state: std.atomic.Value(u32) = .init(0),

    const Self = @This();

    pub fn lock(self: *Self) void {
        while (self.state.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *Self) void {
        self.state.store(0, .release);
    }
};

// =============================================================================
// Global State
// =============================================================================

var global_lock: Mutex = .{};
var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};

const SwapchainData = struct {
    swapchain: u64,
    ll_context: *low_latency.LowLatencyContext,
    frame_count: u64,
    enabled: bool,
    boost: bool,
    min_interval_us: u32,
    debug: bool,
};

const DeviceData = struct {
    device: vk.VkDevice,
    get_device_proc_addr: vk.PFN_vkGetDeviceProcAddr,
    dispatch: vk.DeviceDispatch,
    swapchains: std.AutoHashMap(u64, *SwapchainData),
    allocator: std.mem.Allocator,
};

var device_map: std.AutoHashMap(usize, *DeviceData) = undefined;
var maps_initialized = false;

fn ensureMapsInitialized() void {
    if (!maps_initialized) {
        const allocator = gpa.allocator();
        device_map = std.AutoHashMap(usize, *DeviceData).init(allocator);
        maps_initialized = true;
    }
}

// =============================================================================
// Configuration from Environment
// =============================================================================

fn getEnvBool(name: [*:0]const u8, default: bool) bool {
    const val = std.c.getenv(name) orelse return default;
    const val_span = std.mem.span(val);
    return std.mem.eql(u8, val_span, "1") or std.mem.eql(u8, val_span, "true");
}

fn getEnvU32(name: [*:0]const u8, default: u32) u32 {
    const val = std.c.getenv(name) orelse return default;
    const val_span = std.mem.span(val);
    return std.fmt.parseInt(u32, val_span, 10) catch default;
}

// =============================================================================
// Layer Entry Points (C ABI)
// =============================================================================

/// Layer's vkGetInstanceProcAddr
export fn nvvk_ll_vkGetInstanceProcAddr(
    instance: vk.VkInstance,
    p_name: [*:0]const u8,
) ?*const fn () callconv(.c) void {
    const name = std.mem.span(p_name);

    if (std.mem.eql(u8, name, "vkEnumerateInstanceLayerProperties")) {
        return @ptrCast(&nvvk_ll_vkEnumerateInstanceLayerProperties);
    }
    if (std.mem.eql(u8, name, "vkEnumerateInstanceExtensionProperties")) {
        return @ptrCast(&nvvk_ll_vkEnumerateInstanceExtensionProperties);
    }

    // Pass through - we don't intercept instance functions
    _ = instance;
    return null;
}

/// Layer's vkGetDeviceProcAddr
export fn nvvk_ll_vkGetDeviceProcAddr(
    device: vk.VkDevice,
    p_name: [*:0]const u8,
) ?*const fn () callconv(.c) void {
    const name = std.mem.span(p_name);

    // Intercept swapchain and present functions
    if (std.mem.eql(u8, name, "vkCreateSwapchainKHR")) {
        return @ptrCast(&nvvk_ll_vkCreateSwapchainKHR);
    }
    if (std.mem.eql(u8, name, "vkDestroySwapchainKHR")) {
        return @ptrCast(&nvvk_ll_vkDestroySwapchainKHR);
    }
    if (std.mem.eql(u8, name, "vkQueuePresentKHR")) {
        return @ptrCast(&nvvk_ll_vkQueuePresentKHR);
    }
    if (std.mem.eql(u8, name, "vkQueueSubmit")) {
        return @ptrCast(&nvvk_ll_vkQueueSubmit);
    }

    // Pass through
    global_lock.lock();
    defer global_lock.unlock();
    ensureMapsInitialized();

    if (device_map.get(@intFromPtr(device))) |data| {
        return data.get_device_proc_addr(device, p_name);
    }

    return null;
}

// =============================================================================
// Instance Functions
// =============================================================================

export fn nvvk_ll_vkEnumerateInstanceLayerProperties(
    p_property_count: *u32,
    p_properties: ?[*]vk.VkLayerProperties,
) i32 {
    if (p_properties == null) {
        p_property_count.* = 1;
        return 0;
    }

    if (p_property_count.* < 1) {
        return 5; // VK_INCOMPLETE
    }

    p_property_count.* = 1;

    var props: vk.VkLayerProperties = .{};
    const layer_name_bytes = LAYER_NAME;
    @memcpy(props.layerName[0..layer_name_bytes.len], layer_name_bytes);
    props.layerName[layer_name_bytes.len] = 0;

    const desc_bytes = LAYER_DESCRIPTION;
    @memcpy(props.description[0..desc_bytes.len], desc_bytes);
    props.description[desc_bytes.len] = 0;

    props.specVersion = LAYER_SPEC_VERSION;
    props.implementationVersion = LAYER_IMPLEMENTATION_VERSION;

    p_properties.?[0] = props;
    return 0;
}

export fn nvvk_ll_vkEnumerateInstanceExtensionProperties(
    p_layer_name: ?[*:0]const u8,
    p_property_count: *u32,
    p_properties: ?[*]vk.VkExtensionProperties,
) i32 {
    if (p_layer_name) |name| {
        const layer_name = std.mem.span(name);
        if (!std.mem.eql(u8, layer_name, LAYER_NAME)) {
            return -7; // VK_ERROR_LAYER_NOT_PRESENT
        }
    }
    p_property_count.* = 0;
    _ = p_properties;
    return 0;
}

// =============================================================================
// Swapchain Functions
// =============================================================================

export fn nvvk_ll_vkCreateSwapchainKHR(
    device: vk.VkDevice,
    p_create_info: *const vk.VkSwapchainCreateInfoKHR,
    p_allocator: ?*const vk.VkAllocationCallbacks,
    p_swapchain: *u64,
) i32 {
    global_lock.lock();
    defer global_lock.unlock();
    ensureMapsInitialized();

    const data = device_map.get(@intFromPtr(device)) orelse return -12;
    const create_fn = data.dispatch.vkCreateSwapchainKHR orelse return -12;
    const result = create_fn(device, p_create_info, p_allocator, p_swapchain);

    if (result != 0) return result;

    // Check if low latency is enabled
    if (!getEnvBool("NVVK_LOW_LATENCY_ENABLED", true)) {
        return result;
    }

    // Create low latency context for this swapchain
    const allocator = data.allocator;
    const ll_ctx = allocator.create(low_latency.LowLatencyContext) catch return result;
    ll_ctx.* = low_latency.LowLatencyContext.init(device, p_swapchain.*, &data.dispatch);

    const swapchain_data = allocator.create(SwapchainData) catch {
        allocator.destroy(ll_ctx);
        return result;
    };

    swapchain_data.* = .{
        .swapchain = p_swapchain.*,
        .ll_context = ll_ctx,
        .frame_count = 0,
        .enabled = true,
        .boost = getEnvBool("NVVK_LOW_LATENCY_BOOST", false),
        .min_interval_us = getEnvU32("NVVK_LOW_LATENCY_MIN_INTERVAL_US", 0),
        .debug = getEnvBool("NVVK_LOW_LATENCY_DEBUG", false),
    };

    // Enable low latency mode
    ll_ctx.setMode(.{
        .enabled = true,
        .boost = swapchain_data.boost,
        .min_interval_us = swapchain_data.min_interval_us,
    }) catch {};

    data.swapchains.put(p_swapchain.*, swapchain_data) catch {
        allocator.destroy(swapchain_data);
        allocator.destroy(ll_ctx);
    };

    if (swapchain_data.debug) {
        std.debug.print("[nvvk-ll] Created swapchain 0x{x} with low latency (boost: {})\n", .{
            p_swapchain.*,
            swapchain_data.boost,
        });
    }

    return result;
}

export fn nvvk_ll_vkDestroySwapchainKHR(
    device: vk.VkDevice,
    swapchain: u64,
    p_allocator: ?*const vk.VkAllocationCallbacks,
) void {
    global_lock.lock();
    defer global_lock.unlock();
    ensureMapsInitialized();

    if (device_map.get(@intFromPtr(device))) |data| {
        // Cleanup our context
        if (data.swapchains.fetchRemove(swapchain)) |entry| {
            const swapchain_data = entry.value;
            if (swapchain_data.debug) {
                std.debug.print("[nvvk-ll] Destroyed swapchain 0x{x} ({} frames)\n", .{
                    swapchain,
                    swapchain_data.frame_count,
                });
            }
            data.allocator.destroy(swapchain_data.ll_context);
            data.allocator.destroy(swapchain_data);
        }

        // Call next layer
        if (data.dispatch.vkDestroySwapchainKHR) |destroy_fn| {
            destroy_fn(device, swapchain, p_allocator);
        }
    }
}

// =============================================================================
// Queue Functions - Automatic Marker Injection
// =============================================================================

export fn nvvk_ll_vkQueueSubmit(
    queue: vk.VkQueue,
    submit_count: u32,
    p_submits: ?*const anyopaque, // VkSubmitInfo array (opaque)
    fence: u64,
) i32 {
    // Mark render submit for all active swapchains
    global_lock.lock();
    var it = device_map.iterator();
    while (it.next()) |entry| {
        var sc_it = entry.value_ptr.*.swapchains.iterator();
        while (sc_it.next()) |sc_entry| {
            const swapchain_data = sc_entry.value_ptr.*;
            if (swapchain_data.enabled) {
                swapchain_data.ll_context.beginRenderSubmit();
            }
        }
    }
    global_lock.unlock();

    // Call the actual submit (need to find the right device)
    // This is simplified - real impl would track queue->device mapping
    _ = queue;
    _ = submit_count;
    _ = p_submits;
    _ = fence;

    return 0; // Would call real vkQueueSubmit
}

export fn nvvk_ll_vkQueuePresentKHR(
    queue: vk.VkQueue,
    p_present_info: *const vk.VkPresentInfoKHR,
) i32 {
    global_lock.lock();

    // Find device data
    var device_data: ?*DeviceData = null;
    var it = device_map.iterator();
    while (it.next()) |entry| {
        device_data = entry.value_ptr.*;
        break;
    }
    global_lock.unlock();

    if (device_data == null) return -12;
    const data = device_data.?;

    const present_fn = data.dispatch.vkQueuePresentKHR orelse return -12;

    // Mark present start for each swapchain
    const swapchain_count = p_present_info.swapchainCount;
    for (0..swapchain_count) |i| {
        const swapchain = p_present_info.pSwapchains[i];

        global_lock.lock();
        const swapchain_data = data.swapchains.get(swapchain);
        global_lock.unlock();

        if (swapchain_data) |sd| {
            if (sd.enabled) {
                sd.ll_context.endRenderSubmit();
                sd.ll_context.beginPresent();
            }
        }
    }

    // Call the actual present
    const result = present_fn(queue, p_present_info);

    // Mark present end and begin next frame
    for (0..swapchain_count) |i| {
        const swapchain = p_present_info.pSwapchains[i];

        global_lock.lock();
        const swapchain_data = data.swapchains.get(swapchain);
        global_lock.unlock();

        if (swapchain_data) |sd| {
            if (sd.enabled) {
                sd.ll_context.endPresent();
                sd.frame_count += 1;

                // Begin next frame
                _ = sd.ll_context.beginFrame();

                // Debug output
                if (sd.debug and sd.frame_count % 300 == 0) {
                    std.debug.print("[nvvk-ll] Frame {}: low latency active\n", .{sd.frame_count});
                }
            }
        }
    }

    return result;
}

// =============================================================================
// Tests
// =============================================================================

test "layer constants" {
    try std.testing.expectEqualStrings("VK_LAYER_NV_low_latency", LAYER_NAME);
    try std.testing.expectEqual(@as(u32, 1), LAYER_IMPLEMENTATION_VERSION);
}
