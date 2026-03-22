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

// Image layout constants not in vulkan.zig
const VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL: u32 = 7;
const VK_IMAGE_LAYOUT_PRESENT_SRC_KHR: u32 = 1000001002;

// =============================================================================
// Layer Constants
// =============================================================================

pub const LAYER_NAME = "VK_LAYER_NV_frame_generation";
pub const LAYER_DESCRIPTION = "NVIDIA Frame Generation Layer";
pub const LAYER_IMPLEMENTATION_VERSION: u32 = 1;
pub const LAYER_SPEC_VERSION: u32 = vk.VK_API_VERSION_1_4;

// =============================================================================
// VkResult Constants (for readable error returns)
// =============================================================================

const VK_SUCCESS: i32 = 0;
const VK_INCOMPLETE: i32 = 5;
const VK_ERROR_OUT_OF_HOST_MEMORY: i32 = -1;
const VK_ERROR_LAYER_NOT_PRESENT: i32 = -6;
const VK_ERROR_FEATURE_NOT_PRESENT: i32 = -8;

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
const global_alloc = std.heap.smp_allocator;

// Queue-to-device mapping for proper multi-device support
var queue_to_device_map: std.AutoHashMap(usize, usize) = undefined;
var queue_map_initialized = false;

fn ensureQueueMapInitialized() void {
    if (!queue_map_initialized) {
        queue_to_device_map = std.AutoHashMap(usize, usize).init(global_alloc);
        queue_map_initialized = true;
    }
}

/// Register a queue with its parent device
fn registerQueueDevice(queue: vk.VkQueue, device: vk.VkDevice) void {
    ensureQueueMapInitialized();
    queue_to_device_map.put(@intFromPtr(queue), @intFromPtr(device)) catch {
        std.debug.print("[nvvk] Warning: Failed to register queue-device mapping\n", .{});
    };
}

/// Look up device data for a given queue
fn getDeviceForQueue(queue: vk.VkQueue) ?*DeviceData {
    ensureQueueMapInitialized();
    ensureMapsInitialized();

    // First try direct queue mapping
    if (queue_to_device_map.get(@intFromPtr(queue))) |device_ptr| {
        return device_map.get(device_ptr);
    }

    // Fallback: search all devices for a matching graphics queue
    var it = device_map.iterator();
    while (it.next()) |entry| {
        const data = entry.value_ptr.*;
        if (data.graphics_queue) |gq| {
            if (@intFromPtr(gq) == @intFromPtr(queue)) {
                // Cache the mapping for future lookups
                queue_to_device_map.put(@intFromPtr(queue), @intFromPtr(data.device)) catch {};
                return data;
            }
        }
    }

    // Last resort: return first device (legacy behavior for single-device setups)
    var fallback_it = device_map.iterator();
    if (fallback_it.next()) |entry| {
        return entry.value_ptr.*;
    }

    return null;
}

// Per-instance data
const InstanceData = struct {
    instance: vk.VkInstance,
    get_instance_proc_addr: vk.PFN_vkGetInstanceProcAddr,
    physical_devices: std.ArrayListUnmanaged(vk.VkPhysicalDevice),
    allocator: std.mem.Allocator,
};

/// Per-swapchain injection resources
const SwapchainInjectionResources = struct {
    images: []vk.VkImage,
    image_count: u32,
    width: u32,
    height: u32,
    format: u32,
    image_layouts: []u32,

    pub fn deinit(self: *SwapchainInjectionResources, allocator: std.mem.Allocator) void {
        if (self.images.len > 0) {
            allocator.free(self.images);
        }
        if (self.image_layouts.len > 0) {
            allocator.free(self.image_layouts);
        }
    }
};

// Per-device data
const DeviceData = struct {
    device: vk.VkDevice,
    physical_device: vk.VkPhysicalDevice,
    instance_data: ?*InstanceData,
    get_device_proc_addr: vk.PFN_vkGetDeviceProcAddr,
    dispatch: vk.DeviceDispatch,

    // Frame generation context
    frame_gen: ?*frame_generation.FrameGenContext,

    // Present injection context (per swapchain)
    swapchain_contexts: std.AutoHashMap(u64, *present_injection.PresentInjectionContext),

    // Per-swapchain resources for frame injection
    swapchain_resources: std.AutoHashMap(u64, SwapchainInjectionResources),

    // Last rendered image per swapchain (provided by host runtime)
    swapchain_sources: std.AutoHashMap(u64, vk.VkImage),
    swapchain_source_layouts: std.AutoHashMap(u64, u32),

    // Command pool for frame injection
    injection_cmd_pool: ?vk.VkCommandPool,
    injection_cmd_buffer: ?vk.VkCommandBuffer,
    injection_fence: vk.VkFence,

    // Graphics queue for submission
    graphics_queue: ?vk.VkQueue,
    queue_family_index: u32,

    // Configuration
    enabled: bool,
    mode: frame_generation.FrameGenMode,
    debug: bool,

    allocator: std.mem.Allocator,

    /// Initialize injection resources (command pool, command buffer, fence)
    pub fn initInjectionResources(self: *DeviceData) bool {
        if (self.injection_cmd_pool != null) return true; // Already initialized

        // Check if we have the required functions
        if (!self.dispatch.hasFrameInjection()) {
            if (self.debug) {
                std.debug.print("[nvvk] Frame injection functions not available\n", .{});
            }
            return false;
        }

        // Get graphics queue
        if (self.dispatch.vkGetDeviceQueue) |get_queue| {
            var queue: vk.VkQueue = undefined;
            get_queue(self.device, self.queue_family_index, 0, &queue);
            self.graphics_queue = queue;
            // Register queue-to-device mapping for multi-device support
            registerQueueDevice(queue, self.device);
        } else {
            return false;
        }

        // Create command pool
        const pool_info = vk.VkCommandPoolCreateInfo{
            .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = self.queue_family_index,
        };

        var cmd_pool: vk.VkCommandPool = undefined;
        if (self.dispatch.vkCreateCommandPool) |create_pool| {
            const result = create_pool(self.device, &pool_info, null, &cmd_pool);
            if (result != .success) {
                if (self.debug) {
                    std.debug.print("[nvvk] Failed to create command pool: {}\n", .{result});
                }
                return false;
            }
            self.injection_cmd_pool = cmd_pool;
        } else {
            return false;
        }

        // Allocate command buffer
        const alloc_info = vk.VkCommandBufferAllocateInfo{
            .commandPool = cmd_pool,
            .level = .primary,
            .commandBufferCount = 1,
        };

        var cmd_buffer: vk.VkCommandBuffer = undefined;
        if (self.dispatch.vkAllocateCommandBuffers) |alloc_cmd| {
            const result = alloc_cmd(self.device, &alloc_info, @ptrCast(&cmd_buffer));
            if (result != .success) {
                if (self.debug) {
                    std.debug.print("[nvvk] Failed to allocate command buffer: {}\n", .{result});
                }
                return false;
            }
            self.injection_cmd_buffer = cmd_buffer;
        } else {
            return false;
        }

        // Create fence for synchronization
        const fence_info = vk.VkFenceCreateInfo{};
        if (self.dispatch.vkCreateFence) |create_fence| {
            var fence: vk.VkFence = 0;
            const result = create_fence(self.device, &fence_info, null, &fence);
            if (result != .success) {
                if (self.debug) {
                    std.debug.print("[nvvk] Failed to create fence: {}\n", .{result});
                }
                return false;
            }
            self.injection_fence = fence;
        } else {
            return false;
        }

        if (self.debug) {
            std.debug.print("[nvvk] Injection resources initialized\n", .{});
        }
        return true;
    }

    /// Cleanup injection resources
    pub fn deinitInjectionResources(self: *DeviceData) void {
        if (self.injection_fence != 0) {
            if (self.dispatch.vkDestroyFence) |destroy_fence| {
                destroy_fence(self.device, self.injection_fence, null);
            }
            self.injection_fence = 0;
        }

        if (self.injection_cmd_buffer != null and self.injection_cmd_pool != null) {
            if (self.dispatch.vkFreeCommandBuffers) |free_cmd| {
                var buf = self.injection_cmd_buffer.?;
                free_cmd(self.device, self.injection_cmd_pool.?, 1, @ptrCast(&buf));
            }
            self.injection_cmd_buffer = null;
        }

        if (self.injection_cmd_pool != null) {
            if (self.dispatch.vkDestroyCommandPool) |destroy_pool| {
                destroy_pool(self.device, self.injection_cmd_pool.?, null);
            }
            self.injection_cmd_pool = null;
        }
    }
};

var instance_map: std.AutoHashMap(usize, *InstanceData) = undefined;
var device_map: std.AutoHashMap(usize, *DeviceData) = undefined;
var maps_initialized = false;

fn ensureMapsInitialized() void {
    if (!maps_initialized) {
        instance_map = std.AutoHashMap(usize, *InstanceData).init(global_alloc);
        device_map = std.AutoHashMap(usize, *DeviceData).init(global_alloc);
        maps_initialized = true;
    }
}

fn findInstanceLink(p_next: ?*const anyopaque) ?*vk.VkLayerInstanceLink {
    var chain: ?*const vk.VkLayerInstanceCreateInfo = @ptrCast(@alignCast(p_next));
    while (chain) |info| {
        if (info.sType == vk.VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO and info.function == .layer_link_info) {
            return info.pLayerInfo;
        }
        chain = @ptrCast(@alignCast(info.pNext));
    }
    return null;
}

fn findDeviceLink(p_next: ?*const anyopaque) ?*vk.VkLayerDeviceLink {
    var chain: ?*const vk.VkLayerDeviceCreateInfo = @ptrCast(@alignCast(p_next));
    while (chain) |info| {
        if (info.sType == vk.VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO and info.function == .layer_link_info) {
            return info.pLayerInfo;
        }
        chain = @ptrCast(@alignCast(info.pNext));
    }
    return null;
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
        return VK_SUCCESS;
    }

    if (p_property_count.* < 1) {
        return VK_INCOMPLETE;
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

    return VK_SUCCESS;
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
            return VK_ERROR_LAYER_NOT_PRESENT;
        }
    }

    // We don't expose any extensions
    p_property_count.* = 0;
    _ = p_properties;
    return VK_SUCCESS;
}

export fn nvvk_vkCreateInstance(
    p_create_info: *const vk.VkInstanceCreateInfo,
    p_allocator: ?*const vk.VkAllocationCallbacks,
    p_instance: *vk.VkInstance,
) i32 {
    global_lock.lock();
    ensureMapsInitialized();

    const link = findInstanceLink(p_create_info.pNext) orelse {
        global_lock.unlock();
        return VK_ERROR_FEATURE_NOT_PRESENT;
    };

    var chain_info: ?*vk.VkLayerInstanceCreateInfo = @ptrCast(@alignCast(@constCast(p_create_info.pNext)));
    while (chain_info) |info| {
        if (info.sType == vk.VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO and info.function == .layer_link_info and info.pLayerInfo != null) {
            info.pLayerInfo = info.pLayerInfo.?.pNext;
            break;
        }
        chain_info = @ptrCast(@alignCast(@constCast(info.pNext)));
    }

    const next_create = link.pfnNextCreateInstance;
    const result = next_create(p_create_info, p_allocator, p_instance);

    if (result != 0) {
        global_lock.unlock();
        return result;
    }

    var data = global_alloc.create(InstanceData) catch {
        global_lock.unlock();
        return result;
    };
    data.* = .{
        .instance = p_instance.*,
        .get_instance_proc_addr = link.pfnNextGetInstanceProcAddr,
        .physical_devices = .empty,
        .allocator = global_alloc,
    };

    instance_map.put(@intFromPtr(p_instance.*), data) catch {
        data.physical_devices.deinit(global_alloc);
        global_alloc.destroy(data);
    };

    global_lock.unlock();
    return result;
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
    global_lock.lock();
    ensureMapsInitialized();

    const link = findDeviceLink(p_create_info.pNext) orelse {
        global_lock.unlock();
        return VK_ERROR_FEATURE_NOT_PRESENT;
    };

    var chain_info: ?*vk.VkLayerDeviceCreateInfo = @ptrCast(@alignCast(@constCast(p_create_info.pNext)));
    while (chain_info) |info| {
        if (info.sType == vk.VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO and info.function == .layer_link_info and info.pLayerInfo != null) {
            info.pLayerInfo = info.pLayerInfo.?.pNext;
            break;
        }
        chain_info = @ptrCast(@alignCast(@constCast(info.pNext)));
    }

    const next_create = link.pfnNextCreateDevice;
    const result = next_create(physical_device, p_create_info, p_allocator, p_device);
    if (result != 0) {
        global_lock.unlock();
        return result;
    }

    var queue_family_index: u32 = 0;
    if (p_create_info.queueCreateInfoCount > 0) {
        if (p_create_info.pQueueCreateInfos) |queues| {
            queue_family_index = queues[0].queueFamilyIndex;
        }
    }

    const enabled = getEnvBool("NVVK_FRAME_GEN_ENABLED", true);
    const debug = getEnvBool("NVVK_FRAME_GEN_DEBUG", false);
    const mode = getEnvMode();

    var data = global_alloc.create(DeviceData) catch {
        global_lock.unlock();
        return result;
    };

    data.* = .{
        .device = p_device.*,
        .physical_device = physical_device,
        .instance_data = null,
        .get_device_proc_addr = link.pfnNextGetDeviceProcAddr,
        .dispatch = vk.DeviceDispatch.init(p_device.*, link.pfnNextGetDeviceProcAddr),
        .frame_gen = null,
        .swapchain_contexts = std.AutoHashMap(u64, *present_injection.PresentInjectionContext).init(global_alloc),
        .swapchain_resources = std.AutoHashMap(u64, SwapchainInjectionResources).init(global_alloc),
        .swapchain_sources = std.AutoHashMap(u64, vk.VkImage).init(global_alloc),
        .swapchain_source_layouts = std.AutoHashMap(u64, u32).init(global_alloc),
        .injection_cmd_pool = null,
        .injection_cmd_buffer = null,
        .injection_fence = 0,
        .graphics_queue = null,
        .queue_family_index = queue_family_index,
        .enabled = enabled,
        .mode = mode,
        .debug = debug,
        .allocator = global_alloc,
    };

    device_map.put(@intFromPtr(p_device.*), data) catch {
        data.swapchain_resources.deinit();
        data.swapchain_contexts.deinit();
        global_alloc.destroy(data);
    };

    global_lock.unlock();
    return result;
}

export fn nvvk_vkDestroyDevice(
    device: vk.VkDevice,
    p_allocator: ?*const vk.VkAllocationCallbacks,
) void {
    global_lock.lock();
    defer global_lock.unlock();

    ensureMapsInitialized();

    if (device_map.fetchRemove(@intFromPtr(device))) |entry| {
        var data = entry.value;

        // Cleanup injection resources (command pool, command buffer, fence)
        data.deinitInjectionResources();

        // Cleanup swapchain resources
        var res_it = data.swapchain_resources.iterator();
        while (res_it.next()) |res_entry| {
            var resources = res_entry.value_ptr.*;
            resources.deinit(data.allocator);
        }
        data.swapchain_resources.deinit();

        data.swapchain_sources.deinit();
        data.swapchain_source_layouts.deinit();

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

    const data = device_map.get(@intFromPtr(device)) orelse return VK_ERROR_FEATURE_NOT_PRESENT;

    // Call next layer
    const create_fn = data.dispatch.vkCreateSwapchainKHR orelse return VK_ERROR_FEATURE_NOT_PRESENT;
    const result = create_fn(device, p_create_info, p_allocator, p_swapchain);

    if (result != 0) return result;

    // Create present injection context for this swapchain
    if (data.enabled) {
        const ctx = data.allocator.create(present_injection.PresentInjectionContext) catch return VK_ERROR_OUT_OF_HOST_MEMORY;
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

        // Query and store swapchain images for frame injection
        if (data.dispatch.vkGetSwapchainImagesKHR) |get_images| {
            var image_count: u32 = 0;
            _ = get_images(device, p_swapchain.*, &image_count, null);

            if (image_count > 0) {
                const images = data.allocator.alloc(vk.VkImage, image_count) catch {
                    if (data.debug) {
                        std.debug.print("[nvvk] Failed to allocate swapchain images array\n", .{});
                    }
                    return result;
                };

                const img_result = get_images(device, p_swapchain.*, &image_count, images.ptr);
                if (img_result == 0) {
                    const layouts = data.allocator.alloc(u32, image_count) catch {
                        data.allocator.free(images);
                        return result;
                    };
                    @memset(layouts, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

                    const resources = SwapchainInjectionResources{
                        .images = images,
                        .image_count = image_count,
                        .width = p_create_info.imageExtent.width,
                        .height = p_create_info.imageExtent.height,
                        .format = p_create_info.imageFormat,
                        .image_layouts = layouts,
                    };
                    data.swapchain_resources.put(p_swapchain.*, resources) catch {
                        data.allocator.free(images);
                        data.allocator.free(layouts);
                    };

                    if (data.debug) {
                        std.debug.print("[nvvk] Stored {} swapchain images ({}x{})\n", .{
                            image_count,
                            p_create_info.imageExtent.width,
                            p_create_info.imageExtent.height,
                        });
                    }
                } else {
                    data.allocator.free(images);
                }
            }
        }

        // Initialize injection resources if not already done
        _ = data.initInjectionResources();

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

        // Cleanup swapchain resources
        if (data.swapchain_resources.fetchRemove(swapchain)) |entry| {
            var resources = entry.value;
            resources.deinit(data.allocator);

            if (data.debug) {
                std.debug.print("[nvvk] Cleaned up resources for swapchain 0x{x}\n", .{swapchain});
            }
        }

        // Clear source image tracking
        _ = data.swapchain_sources.remove(swapchain);
        _ = data.swapchain_source_layouts.remove(swapchain);

        // Call next layer
        if (data.dispatch.vkDestroySwapchainKHR) |destroy_fn| {
            destroy_fn(device, swapchain, p_allocator);
        }
    }
}

// =============================================================================
// External Integration Helpers (host runtimes)
// =============================================================================

/// Register an externally created swapchain and its images with the layer.
/// Allows host runtimes (ghostVK/primetime) to provide swapchain images so
/// frame injection can target them without relying on vkCreateSwapchain hooks.
export fn nvvk_register_swapchain_images(
    device: vk.VkDevice,
    swapchain: u64,
    images: [*]const vk.VkImage,
    image_count: u32,
    width: u32,
    height: u32,
    format: u32,
) bool {
    global_lock.lock();
    defer global_lock.unlock();

    ensureMapsInitialized();
    const data = device_map.get(@intFromPtr(device)) orelse return false;

    // Free any existing entry
    if (data.swapchain_resources.fetchRemove(swapchain)) |entry| {
        var res = entry.value;
        res.deinit(data.allocator);
    }

    const imgs = data.allocator.alloc(vk.VkImage, image_count) catch return false;
    const layouts = data.allocator.alloc(u32, image_count) catch {
        data.allocator.free(imgs);
        return false;
    };
    @memcpy(imgs, images[0..image_count]);
    @memset(layouts, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

    const resources = SwapchainInjectionResources{
        .images = imgs,
        .image_count = image_count,
        .width = width,
        .height = height,
        .format = format,
        .image_layouts = layouts,
    };

    data.swapchain_resources.put(swapchain, resources) catch {
        data.allocator.free(imgs);
        data.allocator.free(layouts);
        return false;
    };

    return true;
}

/// Notify the layer of the most recently rendered image for a swapchain.
/// The image/layout will be used as the source for frame injection copies.
export fn nvvk_notify_rendered_image(
    device: vk.VkDevice,
    swapchain: u64,
    image: vk.VkImage,
    layout: u32,
) void {
    global_lock.lock();
    defer global_lock.unlock();

    ensureMapsInitialized();
    const data = device_map.get(@intFromPtr(device)) orelse return;
    data.swapchain_sources.put(swapchain, image) catch {};
    data.swapchain_source_layouts.put(swapchain, layout) catch {};
}

// =============================================================================
// Frame Injection Implementation
// =============================================================================

/// Inject a generated frame into the swapchain
/// Returns true if injection succeeded, false otherwise
fn injectGeneratedFrame(
    data: *DeviceData,
    queue: vk.VkQueue,
    swapchain: u64,
    resources: *SwapchainInjectionResources,
    injection_ctx: *present_injection.PresentInjectionContext,
) bool {
    _ = injection_ctx;

    // Verify we have required resources
    const cmd_buffer = data.injection_cmd_buffer orelse return false;
    const cmd_pool = data.injection_cmd_pool orelse return false;
    const fence = data.injection_fence;
    if (fence == 0) return false;

    // Get required functions
    const acquire_fn = data.dispatch.vkAcquireNextImageKHR orelse return false;
    const begin_cmd = data.dispatch.vkBeginCommandBuffer orelse return false;
    const end_cmd = data.dispatch.vkEndCommandBuffer orelse return false;
    const submit_fn = data.dispatch.vkQueueSubmit orelse return false;
    const present_fn = data.dispatch.vkQueuePresentKHR orelse return false;
    const wait_fences = data.dispatch.vkWaitForFences orelse return false;
    const reset_fences = data.dispatch.vkResetFences orelse return false;
    const blit_image = data.dispatch.vkCmdBlitImage;
    const copy_image = data.dispatch.vkCmdCopyImage;

    // Need at least one copy function
    if (blit_image == null and copy_image == null) return false;

    // Check if frame generation context has a generated frame ready
    const frame_gen = data.frame_gen orelse return false;

    // Get the generated frame from frame_gen context
    // Note: This requires that pushFrame was called earlier with source frame data
    // For full integration, the layer needs to track rendered frames
    const gen_frame_image = frame_gen.synthesis_ctx.getOutputImage() orelse return false;

    // Step 1: Acquire next swapchain image
    var image_index: u32 = 0;
    const acquire_result = acquire_fn(
        data.device,
        swapchain,
        1_000_000_000, // 1 second timeout
        0, // No semaphore (we use fence)
        fence,
        &image_index,
    );

    if (acquire_result != 0) {
        if (data.debug) {
            std.debug.print("[nvvk] Failed to acquire swapchain image: {}\n", .{acquire_result});
        }
        return false;
    }

    // Wait for acquire fence
    var fence_arr = [_]vk.VkFence{fence};
    const wait_result = wait_fences(
        data.device,
        1,
        &fence_arr,
        vk.VK_TRUE,
        1_000_000_000,
    );
    if (wait_result != .success) {
        if (data.debug) {
            std.debug.print("[nvvk] Wait for fence failed: {}\n", .{wait_result});
        }
        return false;
    }

    // Reset fence for next use
    _ = reset_fences(data.device, 1, &fence_arr);

    // Get destination swapchain image
    if (image_index >= resources.image_count) return false;
    const dst_image = resources.images[image_index];
    const current_layout = resources.image_layouts[image_index];

    // Choose source image: prefer host-provided rendered image, else synthesized frame
    var src_image = gen_frame_image;
    var src_layout: u32 = vk.VK_IMAGE_LAYOUT_GENERAL;
    if (data.swapchain_sources.get(swapchain)) |img| {
        src_image = img;
        src_layout = data.swapchain_source_layouts.get(swapchain) orelse vk.VK_IMAGE_LAYOUT_GENERAL;
    }

    // Step 2: Record command buffer to copy generated frame to swapchain
    const begin_info = vk.VkCommandBufferBeginInfo{
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    // Reuse the single command buffer by resetting it between uses
    if (data.dispatch.vkResetCommandBuffer) |reset_cmd| {
        _ = reset_cmd(cmd_buffer, 0);
    } else if (data.dispatch.vkResetCommandPool) |reset_pool| {
        _ = reset_pool(data.device, cmd_pool, 0);
    }

    if (begin_cmd(cmd_buffer, &begin_info) != .success) {
        return false;
    }

    // Transition destination image to transfer dst layout
    const barrier_dst_pre = vk.VkImageMemoryBarrier{
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        .oldLayout = current_layout,
        .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .image = dst_image,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    if (data.dispatch.vkCmdPipelineBarrier) |barrier_fn| {
        var barriers = [_]vk.VkImageMemoryBarrier{barrier_dst_pre};
        barrier_fn(
            cmd_buffer,
            vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &barriers,
        );
    }

    // Copy/blit generated frame to swapchain image
    if (blit_image) |blit_fn| {
        const blit_region = vk.VkImageBlit{
            .srcSubresource = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .srcOffsets = .{
                .{ .x = 0, .y = 0, .z = 0 },
                .{
                    .x = @intCast(resources.width),
                    .y = @intCast(resources.height),
                    .z = 1,
                },
            },
            .dstSubresource = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .dstOffsets = .{
                .{ .x = 0, .y = 0, .z = 0 },
                .{
                    .x = @intCast(resources.width),
                    .y = @intCast(resources.height),
                    .z = 1,
                },
            },
        };

        var regions = [_]vk.VkImageBlit{blit_region};
        blit_fn(
            cmd_buffer,
            src_image,
            src_layout,
            dst_image,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &regions,
            .linear,
        );
    } else if (copy_image) |copy_fn| {
        const copy_region = vk.VkImageCopy{
            .srcSubresource = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .srcOffset = .{},
            .dstSubresource = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .dstOffset = .{},
            .extent = .{
                .width = resources.width,
                .height = resources.height,
                .depth = 1,
            },
        };

        var regions = [_]vk.VkImageCopy{copy_region};
        copy_fn(
            cmd_buffer,
            src_image,
            src_layout,
            dst_image,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &regions,
        );
    }

    // Transition destination to present layout
    const barrier_dst_post = vk.VkImageMemoryBarrier{
        .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        .dstAccessMask = 0,
        .oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .image = dst_image,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    if (data.dispatch.vkCmdPipelineBarrier) |barrier_fn| {
        var barriers = [_]vk.VkImageMemoryBarrier{barrier_dst_post};
        barrier_fn(
            cmd_buffer,
            vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &barriers,
        );
    }

    if (end_cmd(cmd_buffer) != .success) {
        return false;
    }

    // Step 3: Submit command buffer
    const submit_info = vk.VkSubmitInfo{
        .commandBufferCount = 1,
        .pCommandBuffers = @ptrCast(&cmd_buffer),
    };

    var submit_arr = [_]vk.VkSubmitInfo{submit_info};
    if (submit_fn(queue, 1, &submit_arr, 0) != .success) {
        if (data.debug) {
            std.debug.print("[nvvk] Submit failed for generated frame\n", .{});
        }
        return false;
    }

    // Wait for submit to complete (simple approach - could use semaphores for better perf)
    if (data.dispatch.vkQueueWaitIdle) |wait_idle| {
        _ = wait_idle(queue);
    }

    // Step 4: Present the generated frame
    var swapchains = [_]u64{swapchain};
    var indices = [_]u32{image_index};
    const gen_present_info = vk.VkPresentInfoKHR{
        .swapchainCount = 1,
        .pSwapchains = &swapchains,
        .pImageIndices = &indices,
    };

    const present_result = present_fn(queue, &gen_present_info);
    if (present_result != 0 and present_result != 1000001003) { // Success or suboptimal
        if (data.debug) {
            std.debug.print("[nvvk] Present failed for generated frame: {}\n", .{present_result});
        }
        return false;
    }

    // Track resulting layout for this image
    resources.image_layouts[image_index] = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    return true;
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

    // Find device data using proper queue-to-device mapping
    const device_data = getDeviceForQueue(queue);

    global_lock.unlock();

    if (device_data == null) {
        return VK_ERROR_FEATURE_NOT_PRESENT;
    }

    const data = device_data.?;

    // Get the present function
    const present_fn = data.dispatch.vkQueuePresentKHR orelse return VK_ERROR_FEATURE_NOT_PRESENT;

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
                // Attempt to inject a generated frame
                global_lock.lock();
                const resources = data.swapchain_resources.getPtr(swapchain);
                global_lock.unlock();

                if (resources != null and data.frame_gen != null) {
                    const inject_result = injectGeneratedFrame(
                        data,
                        queue,
                        swapchain,
                        resources.?,
                        injection_ctx,
                    );

                    if (inject_result) {
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

    const data = device_map.get(@intFromPtr(device)) orelse return VK_ERROR_FEATURE_NOT_PRESENT;
    const acquire_fn = data.dispatch.vkAcquireNextImageKHR orelse return VK_ERROR_FEATURE_NOT_PRESENT;

    return acquire_fn(device, swapchain, timeout, semaphore, fence, p_image_index);
}

// =============================================================================
// Layer Configuration
// =============================================================================

/// Known problematic apps that don't work well with frame generation
const default_blacklist = [_][]const u8{
    "mangohud_test", // Test app - not a real game
    "vulkaninfo", // Vulkan info tool
    "vkcube", // Vulkan demo cube
    "vkmark", // Vulkan benchmark
};

/// Get current process name from /proc/self/comm
fn getProcessName(buf: []u8) ?[]const u8 {
    const file = std.fs.openFileAbsolute("/proc/self/comm", .{}) catch return null;
    defer file.close();

    const bytes_read = file.read(buf) catch return null;
    if (bytes_read == 0) return null;

    // Remove trailing newline
    var len = bytes_read;
    while (len > 0 and (buf[len - 1] == '\n' or buf[len - 1] == '\r')) {
        len -= 1;
    }
    return buf[0..len];
}

/// Check if a name matches any entry in a comma-separated list
fn matchesEnvList(name: []const u8, env_name: [*:0]const u8) bool {
    const val = std.c.getenv(env_name) orelse return false;
    const list = std.mem.span(val);

    var iter = std.mem.splitScalar(u8, list, ',');
    while (iter.next()) |entry| {
        const trimmed = std.mem.trim(u8, entry, " \t");
        if (trimmed.len > 0 and std.mem.eql(u8, name, trimmed)) {
            return true;
        }
    }
    return false;
}

/// Check if frame generation should be enabled for an app
fn shouldEnableForApp() bool {
    // Check master enable/disable switch
    if (!getEnvBool("NVVK_FRAME_GEN_ENABLED", true)) {
        return false;
    }

    // Get process name
    var name_buf: [256]u8 = undefined;
    const process_name = getProcessName(&name_buf) orelse return true;

    // Check explicit whitelist (if set, ONLY these apps are enabled)
    const has_whitelist = std.c.getenv("NVVK_WHITELIST") != null;
    if (has_whitelist) {
        const on_whitelist = matchesEnvList(process_name, "NVVK_WHITELIST");
        if (!on_whitelist) {
            return false;
        }
        return true; // On whitelist, skip blacklist check
    }

    // Check explicit blacklist
    if (matchesEnvList(process_name, "NVVK_BLACKLIST")) {
        return false;
    }

    // Check default blacklist
    for (default_blacklist) |blocked| {
        if (std.mem.eql(u8, process_name, blocked)) {
            return false;
        }
    }

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
