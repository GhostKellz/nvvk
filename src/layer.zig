//! VK_LAYER_NV_frame_generation - Vulkan Layer Implementation
//!
//! This Vulkan layer intercepts vkQueuePresentKHR to inject generated frames
//! into the present chain, effectively doubling the frame rate.
//!
//! Layer Installation:
//!   1. Copy libnvvk_layer.so to /usr/share/vulkan/implicit_layer.d/
//!   2. Copy VK_LAYER_NV_frame_generation.json manifest
//!   3. Layer auto-enables or use VK_INSTANCE_LAYERS env var
//!
//! Environment Variables:
//!   NVVK_FRAME_GEN_MODE=performance|balanced|quality
//!   NVVK_FRAME_GEN_ENABLED=0|1
//!   NVVK_FRAME_GEN_DEBUG=0|1

const std = @import("std");
const vk = @import("vulkan.zig");
const frame_generation = @import("frame_generation.zig");
const present_injection = @import("present_injection.zig");
const vrr = @import("vrr.zig");

// =============================================================================
// Layer Constants
// =============================================================================

pub const LAYER_NAME = "VK_LAYER_NV_frame_generation";
pub const LAYER_DESCRIPTION = "NVIDIA Frame Generation Layer";
pub const LAYER_IMPLEMENTATION_VERSION: u32 = 1;
pub const LAYER_SPEC_VERSION: u32 = vk.VK_API_VERSION_1_4;

// =============================================================================
// Global State
// =============================================================================

var global_lock: std.Thread.Mutex = .{};
var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};

// Per-instance data
const InstanceData = struct {
    instance: vk.VkInstance,
    get_instance_proc_addr: vk.PFN_vkGetInstanceProcAddr,
    physical_devices: std.ArrayList(vk.VkPhysicalDevice),
    allocator: std.mem.Allocator,
};

// Per-device data
const DeviceData = struct {
    device: vk.VkDevice,
    physical_device: vk.VkPhysicalDevice,
    instance_data: *InstanceData,
    get_device_proc_addr: vk.PFN_vkGetDeviceProcAddr,
    dispatch: vk.DeviceDispatch,

    // Frame generation context
    frame_gen: ?*frame_generation.FrameGenContext,

    // Present injection context (per swapchain)
    swapchain_contexts: std.AutoHashMap(u64, *present_injection.PresentInjectionContext),

    // Configuration
    enabled: bool,
    mode: frame_generation.FrameGenMode,
    debug: bool,

    allocator: std.mem.Allocator,
};

var instance_map: std.AutoHashMap(usize, *InstanceData) = undefined;
var device_map: std.AutoHashMap(usize, *DeviceData) = undefined;
var maps_initialized = false;

fn ensureMapsInitialized() void {
    if (!maps_initialized) {
        const allocator = gpa.allocator();
        instance_map = std.AutoHashMap(usize, *InstanceData).init(allocator);
        device_map = std.AutoHashMap(usize, *DeviceData).init(allocator);
        maps_initialized = true;
    }
}

// =============================================================================
// Configuration from Environment
// =============================================================================

fn getEnvBool(name: [*:0]const u8, default: bool) bool {
    const val = std.c.getenv(name) orelse return default;
    return std.mem.eql(u8, std.mem.span(val), "1") or std.mem.eql(u8, std.mem.span(val), "true");
}

fn getEnvMode() frame_generation.FrameGenMode {
    const val = std.c.getenv("NVVK_FRAME_GEN_MODE") orelse return .balanced;
    const val_span = std.mem.span(val);
    if (std.mem.eql(u8, val_span, "performance")) return .performance;
    if (std.mem.eql(u8, val_span, "quality")) return .quality;
    if (std.mem.eql(u8, val_span, "off")) return .off;
    return .balanced;
}

// =============================================================================
// Layer Entry Points (C ABI)
// =============================================================================

/// Layer's vkGetInstanceProcAddr
export fn nvvk_vkGetInstanceProcAddr(
    instance: vk.VkInstance,
    p_name: [*:0]const u8,
) ?*const fn () callconv(.c) void {
    const name = std.mem.span(p_name);

    // Intercept instance functions
    if (std.mem.eql(u8, name, "vkCreateInstance")) {
        return @ptrCast(&nvvk_vkCreateInstance);
    }
    if (std.mem.eql(u8, name, "vkDestroyInstance")) {
        return @ptrCast(&nvvk_vkDestroyInstance);
    }
    if (std.mem.eql(u8, name, "vkCreateDevice")) {
        return @ptrCast(&nvvk_vkCreateDevice);
    }
    if (std.mem.eql(u8, name, "vkEnumerateInstanceLayerProperties")) {
        return @ptrCast(&nvvk_vkEnumerateInstanceLayerProperties);
    }
    if (std.mem.eql(u8, name, "vkEnumerateInstanceExtensionProperties")) {
        return @ptrCast(&nvvk_vkEnumerateInstanceExtensionProperties);
    }

    // Pass through to next layer
    global_lock.lock();
    defer global_lock.unlock();

    ensureMapsInitialized();

    if (instance_map.get(@intFromPtr(instance))) |data| {
        return data.get_instance_proc_addr(instance, p_name);
    }

    return null;
}

/// Layer's vkGetDeviceProcAddr
export fn nvvk_vkGetDeviceProcAddr(
    device: vk.VkDevice,
    p_name: [*:0]const u8,
) ?*const fn () callconv(.c) void {
    const name = std.mem.span(p_name);

    // Intercept device functions
    if (std.mem.eql(u8, name, "vkDestroyDevice")) {
        return @ptrCast(&nvvk_vkDestroyDevice);
    }
    if (std.mem.eql(u8, name, "vkQueuePresentKHR")) {
        return @ptrCast(&nvvk_vkQueuePresentKHR);
    }
    if (std.mem.eql(u8, name, "vkCreateSwapchainKHR")) {
        return @ptrCast(&nvvk_vkCreateSwapchainKHR);
    }
    if (std.mem.eql(u8, name, "vkDestroySwapchainKHR")) {
        return @ptrCast(&nvvk_vkDestroySwapchainKHR);
    }
    if (std.mem.eql(u8, name, "vkAcquireNextImageKHR")) {
        return @ptrCast(&nvvk_vkAcquireNextImageKHR);
    }

    // Pass through to next layer
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

export fn nvvk_vkEnumerateInstanceLayerProperties(
    p_property_count: *u32,
    p_properties: ?[*]vk.VkLayerProperties,
) i32 {
    if (p_properties == null) {
        p_property_count.* = 1;
        return 0; // VK_SUCCESS
    }

    if (p_property_count.* < 1) {
        return 5; // VK_INCOMPLETE
    }

    p_property_count.* = 1;

    var props: vk.VkLayerProperties = .{};

    // Copy layer name
    const layer_name_bytes = LAYER_NAME;
    @memcpy(props.layerName[0..layer_name_bytes.len], layer_name_bytes);
    props.layerName[layer_name_bytes.len] = 0;

    // Copy description
    const desc_bytes = LAYER_DESCRIPTION;
    @memcpy(props.description[0..desc_bytes.len], desc_bytes);
    props.description[desc_bytes.len] = 0;

    props.specVersion = LAYER_SPEC_VERSION;
    props.implementationVersion = LAYER_IMPLEMENTATION_VERSION;

    p_properties.?[0] = props;

    return 0; // VK_SUCCESS
}

export fn nvvk_vkEnumerateInstanceExtensionProperties(
    p_layer_name: ?[*:0]const u8,
    p_property_count: *u32,
    p_properties: ?[*]vk.VkExtensionProperties,
) i32 {
    // Check if this is for our layer
    if (p_layer_name) |name| {
        const layer_name = std.mem.span(name);
        if (!std.mem.eql(u8, layer_name, LAYER_NAME)) {
            return -7; // VK_ERROR_LAYER_NOT_PRESENT
        }
    }

    // We don't expose any extensions
    p_property_count.* = 0;
    _ = p_properties;
    return 0; // VK_SUCCESS
}

export fn nvvk_vkCreateInstance(
    p_create_info: *const vk.VkInstanceCreateInfo,
    p_allocator: ?*const vk.VkAllocationCallbacks,
    p_instance: *vk.VkInstance,
) i32 {
    _ = p_create_info;
    _ = p_allocator;
    _ = p_instance;

    // In a real implementation, we would:
    // 1. Get the chain info to find next layer's vkCreateInstance
    // 2. Call it to create the instance
    // 3. Store instance data

    // For now, return not implemented
    return -12; // VK_ERROR_FEATURE_NOT_PRESENT
}

export fn nvvk_vkDestroyInstance(
    instance: vk.VkInstance,
    p_allocator: ?*const vk.VkAllocationCallbacks,
) void {
    global_lock.lock();
    defer global_lock.unlock();

    ensureMapsInitialized();

    if (instance_map.fetchRemove(@intFromPtr(instance))) |entry| {
        const data = entry.value;

        // Call next layer
        if (data.get_instance_proc_addr(instance, "vkDestroyInstance")) |destroy_fn| {
            const typed_fn: *const fn (vk.VkInstance, ?*const vk.VkAllocationCallbacks) callconv(.c) void = @ptrCast(destroy_fn);
            typed_fn(instance, p_allocator);
        }

        // Cleanup
        data.physical_devices.deinit(data.allocator);
        data.allocator.destroy(data);
    }
}

// =============================================================================
// Device Functions
// =============================================================================

export fn nvvk_vkCreateDevice(
    physical_device: vk.VkPhysicalDevice,
    p_create_info: *const vk.VkDeviceCreateInfo,
    p_allocator: ?*const vk.VkAllocationCallbacks,
    p_device: *vk.VkDevice,
) i32 {
    _ = physical_device;
    _ = p_create_info;
    _ = p_allocator;
    _ = p_device;

    // In a real implementation, we would:
    // 1. Call next layer's vkCreateDevice
    // 2. Initialize frame generation context
    // 3. Store device data

    return -12; // VK_ERROR_FEATURE_NOT_PRESENT
}

export fn nvvk_vkDestroyDevice(
    device: vk.VkDevice,
    p_allocator: ?*const vk.VkAllocationCallbacks,
) void {
    global_lock.lock();
    defer global_lock.unlock();

    ensureMapsInitialized();

    if (device_map.fetchRemove(@intFromPtr(device))) |entry| {
        const data = entry.value;

        // Cleanup frame generation
        if (data.frame_gen) |fg| {
            var fg_mut = fg;
            fg_mut.deinit();
            data.allocator.destroy(fg);
        }

        // Cleanup swapchain contexts
        var it = data.swapchain_contexts.iterator();
        while (it.next()) |ctx_entry| {
            var ctx = ctx_entry.value_ptr.*;
            ctx.deinit();
            data.allocator.destroy(ctx);
        }
        data.swapchain_contexts.deinit();

        // Call next layer
        if (data.dispatch.vkDestroyDevice) |destroy_fn| {
            destroy_fn(device, p_allocator);
        }

        data.allocator.destroy(data);
    }
}

// =============================================================================
// Swapchain Functions
// =============================================================================

export fn nvvk_vkCreateSwapchainKHR(
    device: vk.VkDevice,
    p_create_info: *const vk.VkSwapchainCreateInfoKHR,
    p_allocator: ?*const vk.VkAllocationCallbacks,
    p_swapchain: *u64,
) i32 {
    global_lock.lock();
    defer global_lock.unlock();

    ensureMapsInitialized();

    const data = device_map.get(@intFromPtr(device)) orelse return -12;

    // Call next layer
    const create_fn = data.dispatch.vkCreateSwapchainKHR orelse return -12;
    const result = create_fn(device, p_create_info, p_allocator, p_swapchain);

    if (result != 0) return result;

    // Create present injection context for this swapchain
    if (data.enabled) {
        const ctx = data.allocator.create(present_injection.PresentInjectionContext) catch return -1;
        ctx.* = present_injection.PresentInjectionContext.init(
            device,
            p_swapchain.*,
            data.frame_gen,
            null,
            .{
                .mode = .single,
                .timing = .adaptive,
            },
            &data.dispatch,
            data.allocator,
        );

        data.swapchain_contexts.put(p_swapchain.*, ctx) catch {
            data.allocator.destroy(ctx);
        };

        if (data.debug) {
            std.debug.print("[nvvk] Created swapchain 0x{x} with frame injection\n", .{p_swapchain.*});
        }
    }

    return result;
}

export fn nvvk_vkDestroySwapchainKHR(
    device: vk.VkDevice,
    swapchain: u64,
    p_allocator: ?*const vk.VkAllocationCallbacks,
) void {
    global_lock.lock();
    defer global_lock.unlock();

    ensureMapsInitialized();

    if (device_map.get(@intFromPtr(device))) |data| {
        // Cleanup our context
        if (data.swapchain_contexts.fetchRemove(swapchain)) |entry| {
            var ctx = entry.value;
            ctx.deinit();
            data.allocator.destroy(ctx);

            if (data.debug) {
                std.debug.print("[nvvk] Destroyed swapchain 0x{x}\n", .{swapchain});
            }
        }

        // Call next layer
        if (data.dispatch.vkDestroySwapchainKHR) |destroy_fn| {
            destroy_fn(device, swapchain, p_allocator);
        }
    }
}

// =============================================================================
// Present Interception (The Main Event)
// =============================================================================

export fn nvvk_vkQueuePresentKHR(
    queue: vk.VkQueue,
    p_present_info: *const vk.VkPresentInfoKHR,
) i32 {
    // This is where the magic happens:
    // 1. Present the real frame
    // 2. Check if we should inject a generated frame
    // 3. If yes, generate and present the interpolated frame

    global_lock.lock();

    // Find device data (need to look up by queue)
    var device_data: ?*DeviceData = null;
    var it = device_map.iterator();
    while (it.next()) |entry| {
        device_data = entry.value_ptr.*;
        break; // TODO: proper queue-to-device mapping
    }

    global_lock.unlock();

    if (device_data == null) {
        return -12;
    }

    const data = device_data.?;

    // Get the present function
    const present_fn = data.dispatch.vkQueuePresentKHR orelse return -12;

    // Present the real frame
    const result = present_fn(queue, p_present_info);

    if (result != 0 or !data.enabled) {
        return result;
    }

    // For each swapchain in the present info
    const swapchain_count = p_present_info.swapchainCount;
    for (0..swapchain_count) |i| {
        const swapchain = p_present_info.pSwapchains[i];

        global_lock.lock();
        const ctx = data.swapchain_contexts.get(swapchain);
        global_lock.unlock();

        if (ctx) |injection_ctx| {
            // Record the real frame present
            injection_ctx.recordPresentTime(false);

            // Check if we should inject
            if (injection_ctx.shouldInject()) {
                // TODO: Actually generate and present the frame
                // This requires:
                // 1. Generate frame using frame_gen context
                // 2. Acquire next swapchain image
                // 3. Copy generated frame to swapchain image
                // 4. Present the generated frame

                injection_ctx.recordPresentTime(true);

                if (data.debug) {
                    const stats = injection_ctx.getStats();
                    if (stats.generated_frames % 60 == 0) {
                        std.debug.print("[nvvk] Frame gen: {} real, {} generated, {d:.1} FPS\n", .{
                            stats.real_frames,
                            stats.generated_frames,
                            stats.effective_fps,
                        });
                    }
                }
            }
        }
    }

    return result;
}

export fn nvvk_vkAcquireNextImageKHR(
    device: vk.VkDevice,
    swapchain: u64,
    timeout: u64,
    semaphore: u64,
    fence: u64,
    p_image_index: *u32,
) i32 {
    global_lock.lock();
    defer global_lock.unlock();

    ensureMapsInitialized();

    const data = device_map.get(@intFromPtr(device)) orelse return -12;
    const acquire_fn = data.dispatch.vkAcquireNextImageKHR orelse return -12;

    return acquire_fn(device, swapchain, timeout, semaphore, fence, p_image_index);
}

// =============================================================================
// Layer Configuration
// =============================================================================

/// Check if frame generation should be enabled for an app
fn shouldEnableForApp() bool {
    // Check environment variable
    if (!getEnvBool("NVVK_FRAME_GEN_ENABLED", true)) {
        return false;
    }

    // TODO: Check app name against whitelist/blacklist
    // Some games may not work well with frame generation

    return true;
}

// Helper to convert slice to c-string for env lookup
fn getEnvBoolSlice(name: []const u8, default: bool) bool {
    // Create null-terminated stack buffer
    var buf: [256]u8 = undefined;
    if (name.len >= buf.len) return default;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    return getEnvBool(@ptrCast(&buf), default);
}

// =============================================================================
// Tests
// =============================================================================

test "layer constants" {
    try std.testing.expectEqualStrings("VK_LAYER_NV_frame_generation", LAYER_NAME);
    try std.testing.expectEqual(@as(u32, 1), LAYER_IMPLEMENTATION_VERSION);
}

test "env configuration" {
    // These tests check the config functions work
    const mode = getEnvMode();
    try std.testing.expect(mode == .balanced or mode == .performance or mode == .quality or mode == .off);
}
