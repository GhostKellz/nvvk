//! C ABI exports for nvvk library
//!
//! This module provides C-compatible function exports for integration
//! with C/C++ codebases like DXVK and vkd3d-proton.

const std = @import("std");
const nvvk = @import("nvvk");

// =============================================================================
// Type Aliases for C ABI
// =============================================================================

pub const NvvkDevice = *anyopaque;
pub const NvvkSwapchain = u64;
pub const NvvkSemaphore = u64;
pub const NvvkQueue = *anyopaque;
pub const NvvkCommandBuffer = *anyopaque;

pub const NvvkResult = enum(i32) {
    success = 0,
    error_not_supported = -1,
    error_invalid_handle = -2,
    error_out_of_memory = -3,
    error_device_lost = -4,
    error_unknown = -5,
};

pub const NvvkLatencyMarker = enum(i32) {
    simulation_start = 0,
    simulation_end = 1,
    rendersubmit_start = 2,
    rendersubmit_end = 3,
    present_start = 4,
    present_end = 5,
    input_sample = 6,
    trigger_flash = 7,
};

pub const NvvkCheckpointTag = enum(i32) {
    frame_start = 0x1000,
    frame_end = 0x1001,
    draw_start = 0x2000,
    draw_end = 0x2001,
    compute_start = 0x3000,
    compute_end = 0x3001,
    transfer_start = 0x4000,
    transfer_end = 0x4001,
};

// =============================================================================
// Opaque Context Handle
// =============================================================================

const LowLatencyHandle = struct {
    ctx: nvvk.LowLatencyContext,
    dispatch: nvvk.DeviceDispatch,
};

const DiagnosticsHandle = struct {
    ctx: nvvk.DiagnosticsContext,
    dispatch: nvvk.DeviceDispatch,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// =============================================================================
// Low Latency C API
// =============================================================================

/// Initialize low latency context for a swapchain
export fn nvvk_low_latency_init(
    device: NvvkDevice,
    swapchain: NvvkSwapchain,
    get_device_proc_addr: *const fn (*anyopaque, [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void,
) ?*LowLatencyHandle {
    const allocator = gpa.allocator();

    const handle = allocator.create(LowLatencyHandle) catch return null;

    const vk_device: nvvk.VkDevice = @ptrCast(device);
    handle.dispatch = nvvk.DeviceDispatch.init(vk_device, @ptrCast(get_device_proc_addr));
    handle.ctx = nvvk.LowLatencyContext.init(vk_device, swapchain, &handle.dispatch);

    return handle;
}

/// Destroy low latency context
export fn nvvk_low_latency_destroy(handle: ?*LowLatencyHandle) void {
    if (handle) |h| {
        gpa.allocator().destroy(h);
    }
}

/// Check if low latency is supported
export fn nvvk_low_latency_is_supported(handle: ?*const LowLatencyHandle) bool {
    if (handle) |h| {
        return h.ctx.isSupported();
    }
    return false;
}

/// Enable low latency mode
export fn nvvk_low_latency_enable(
    handle: ?*LowLatencyHandle,
    boost: bool,
    min_interval_us: u32,
) NvvkResult {
    const h = handle orelse return .error_invalid_handle;

    h.ctx.setMode(.{
        .enabled = true,
        .boost = boost,
        .min_interval_us = min_interval_us,
    }) catch |err| {
        return switch (err) {
            nvvk.VulkanError.ExtensionNotPresent => .error_not_supported,
            nvvk.VulkanError.DeviceLost => .error_device_lost,
            else => .error_unknown,
        };
    };

    return .success;
}

/// Disable low latency mode
export fn nvvk_low_latency_disable(handle: ?*LowLatencyHandle) NvvkResult {
    const h = handle orelse return .error_invalid_handle;

    h.ctx.setMode(nvvk.ModeConfig.disabled()) catch |err| {
        return switch (err) {
            nvvk.VulkanError.ExtensionNotPresent => .error_not_supported,
            else => .error_unknown,
        };
    };

    return .success;
}

/// Sleep until optimal frame start time
export fn nvvk_low_latency_sleep(
    handle: ?*LowLatencyHandle,
    semaphore: NvvkSemaphore,
    value: u64,
) NvvkResult {
    const h = handle orelse return .error_invalid_handle;

    h.ctx.sleep(semaphore, value) catch |err| {
        return switch (err) {
            nvvk.VulkanError.ExtensionNotPresent => .error_not_supported,
            nvvk.VulkanError.DeviceLost => .error_device_lost,
            else => .error_unknown,
        };
    };

    return .success;
}

/// Set latency marker
export fn nvvk_low_latency_set_marker(
    handle: ?*LowLatencyHandle,
    marker: NvvkLatencyMarker,
) void {
    const h = handle orelse return;

    const zig_marker: nvvk.Marker = switch (marker) {
        .simulation_start => .simulation_start,
        .simulation_end => .simulation_end,
        .rendersubmit_start => .rendersubmit_start,
        .rendersubmit_end => .rendersubmit_end,
        .present_start => .present_start,
        .present_end => .present_end,
        .input_sample => .input_sample,
        .trigger_flash => .trigger_flash,
    };

    h.ctx.setMarker(zig_marker);
}

/// Begin a new frame (increments present ID, sets simulation start marker)
export fn nvvk_low_latency_begin_frame(handle: ?*LowLatencyHandle) u64 {
    const h = handle orelse return 0;
    return h.ctx.beginFrame();
}

/// Mark end of simulation
export fn nvvk_low_latency_end_simulation(handle: ?*LowLatencyHandle) void {
    const h = handle orelse return;
    h.ctx.endSimulation();
}

/// Mark start of render submission
export fn nvvk_low_latency_begin_render_submit(handle: ?*LowLatencyHandle) void {
    const h = handle orelse return;
    h.ctx.beginRenderSubmit();
}

/// Mark end of render submission
export fn nvvk_low_latency_end_render_submit(handle: ?*LowLatencyHandle) void {
    const h = handle orelse return;
    h.ctx.endRenderSubmit();
}

/// Mark start of present
export fn nvvk_low_latency_begin_present(handle: ?*LowLatencyHandle) void {
    const h = handle orelse return;
    h.ctx.beginPresent();
}

/// Mark end of present
export fn nvvk_low_latency_end_present(handle: ?*LowLatencyHandle) void {
    const h = handle orelse return;
    h.ctx.endPresent();
}

// =============================================================================
// Diagnostics C API
// =============================================================================

/// Initialize diagnostics context
export fn nvvk_diagnostics_init(
    device: NvvkDevice,
    get_device_proc_addr: *const fn (*anyopaque, [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void,
) ?*DiagnosticsHandle {
    const allocator = gpa.allocator();

    const handle = allocator.create(DiagnosticsHandle) catch return null;

    const vk_device: nvvk.VkDevice = @ptrCast(device);
    handle.dispatch = nvvk.DeviceDispatch.init(vk_device, @ptrCast(get_device_proc_addr));
    handle.ctx = nvvk.DiagnosticsContext.init(vk_device, &handle.dispatch);

    return handle;
}

/// Destroy diagnostics context
export fn nvvk_diagnostics_destroy(handle: ?*DiagnosticsHandle) void {
    if (handle) |h| {
        gpa.allocator().destroy(h);
    }
}

/// Check if diagnostics are supported
export fn nvvk_diagnostics_is_supported(handle: ?*const DiagnosticsHandle) bool {
    if (handle) |h| {
        return h.ctx.isSupported();
    }
    return false;
}

/// Set checkpoint in command buffer
export fn nvvk_diagnostics_set_checkpoint(
    handle: ?*const DiagnosticsHandle,
    cmd: NvvkCommandBuffer,
    marker: ?*const anyopaque,
) void {
    const h = handle orelse return;
    h.ctx.setCheckpoint(@ptrCast(cmd), marker);
}

/// Set tagged checkpoint
export fn nvvk_diagnostics_set_tagged_checkpoint(
    handle: ?*const DiagnosticsHandle,
    cmd: NvvkCommandBuffer,
    tag: NvvkCheckpointTag,
) void {
    const h = handle orelse return;

    const zig_tag: nvvk.CheckpointTag = switch (tag) {
        .frame_start => .frame_start,
        .frame_end => .frame_end,
        .draw_start => .draw_start,
        .draw_end => .draw_end,
        .compute_start => .compute_start,
        .compute_end => .compute_end,
        .transfer_start => .transfer_start,
        .transfer_end => .transfer_end,
    };

    h.ctx.setTaggedCheckpoint(@ptrCast(cmd), zig_tag);
}

// =============================================================================
// Version and Info
// =============================================================================

/// Get library version (major.minor.patch encoded as uint32)
export fn nvvk_get_version() u32 {
    return (@as(u32, nvvk.version.major) << 16) |
        (@as(u32, nvvk.version.minor) << 8) |
        @as(u32, nvvk.version.patch);
}

/// Check if running on NVIDIA GPU
export fn nvvk_is_nvidia_gpu() bool {
    return nvvk.isNvidiaGpu();
}

/// Get extension name for low latency
export fn nvvk_get_low_latency_extension_name() [*:0]const u8 {
    return nvvk.extensions.low_latency2;
}

/// Get extension name for diagnostic checkpoints
export fn nvvk_get_diagnostic_checkpoints_extension_name() [*:0]const u8 {
    return nvvk.extensions.diagnostic_checkpoints;
}

/// Get extension name for diagnostics config
export fn nvvk_get_diagnostics_config_extension_name() [*:0]const u8 {
    return nvvk.extensions.diagnostics_config;
}
