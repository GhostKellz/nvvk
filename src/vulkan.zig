//! Vulkan type definitions and function bindings for NVIDIA extensions.
//!
//! This module provides minimal Vulkan bindings focused on NVIDIA-specific
//! extensions. It dynamically loads function pointers at runtime.

const std = @import("std");

// =============================================================================
// Core Vulkan Types
// =============================================================================

pub const VkResult = enum(i32) {
    success = 0,
    not_ready = 1,
    timeout = 2,
    event_set = 3,
    event_reset = 4,
    incomplete = 5,
    error_out_of_host_memory = -1,
    error_out_of_device_memory = -2,
    error_initialization_failed = -3,
    error_device_lost = -4,
    error_memory_map_failed = -5,
    error_layer_not_present = -6,
    error_extension_not_present = -7,
    error_feature_not_present = -8,
    error_incompatible_driver = -9,
    error_too_many_objects = -10,
    error_format_not_supported = -11,
    error_fragmented_pool = -12,
    error_unknown = -13,
    error_surface_lost_khr = -1000000000,
    error_native_window_in_use_khr = -1000000001,
    suboptimal_khr = 1000001003,
    error_out_of_date_khr = -1000001004,
    _,

    pub fn isSuccess(self: VkResult) bool {
        return @intFromEnum(self) >= 0;
    }

    pub fn toError(self: VkResult) ?VulkanError {
        return switch (self) {
            .success, .not_ready, .timeout, .event_set, .event_reset, .incomplete, .suboptimal_khr => null,
            .error_out_of_host_memory => VulkanError.OutOfHostMemory,
            .error_out_of_device_memory => VulkanError.OutOfDeviceMemory,
            .error_initialization_failed => VulkanError.InitializationFailed,
            .error_device_lost => VulkanError.DeviceLost,
            .error_memory_map_failed => VulkanError.MemoryMapFailed,
            .error_layer_not_present => VulkanError.LayerNotPresent,
            .error_extension_not_present => VulkanError.ExtensionNotPresent,
            .error_feature_not_present => VulkanError.FeatureNotPresent,
            .error_incompatible_driver => VulkanError.IncompatibleDriver,
            .error_too_many_objects => VulkanError.TooManyObjects,
            .error_format_not_supported => VulkanError.FormatNotSupported,
            .error_fragmented_pool => VulkanError.FragmentedPool,
            .error_unknown => VulkanError.Unknown,
            .error_surface_lost_khr => VulkanError.SurfaceLost,
            .error_native_window_in_use_khr => VulkanError.NativeWindowInUse,
            .error_out_of_date_khr => VulkanError.OutOfDate,
            _ => VulkanError.Unknown,
        };
    }
};

pub const VulkanError = error{
    OutOfHostMemory,
    OutOfDeviceMemory,
    InitializationFailed,
    DeviceLost,
    MemoryMapFailed,
    LayerNotPresent,
    ExtensionNotPresent,
    FeatureNotPresent,
    IncompatibleDriver,
    TooManyObjects,
    FormatNotSupported,
    FragmentedPool,
    Unknown,
    SurfaceLost,
    NativeWindowInUse,
    OutOfDate,
    LoaderError,
    FunctionNotFound,
};

/// Check VkResult and return error if failed
pub fn check(result: VkResult) VulkanError!void {
    if (result.toError()) |err| {
        return err;
    }
}

// Opaque handle types
pub const VkInstance = *opaque {};
pub const VkPhysicalDevice = *opaque {};
pub const VkDevice = *opaque {};
pub const VkQueue = *opaque {};
pub const VkSemaphore = *opaque {};
pub const VkSwapchainKHR = *opaque {};

// Non-dispatchable handles (64-bit)
pub const VkSemaphore_T = u64;
pub const VkSwapchainKHR_T = u64;

// =============================================================================
// VK_NV_low_latency2 Types (Extension #506)
// =============================================================================

pub const VK_NV_LOW_LATENCY_2_EXTENSION_NAME = "VK_NV_low_latency2";
pub const VK_NV_LOW_LATENCY_2_SPEC_VERSION: u32 = 2;

/// Latency markers for frame timing
pub const VkLatencyMarkerNV = enum(i32) {
    simulation_start = 0,
    simulation_end = 1,
    rendersubmit_start = 2,
    rendersubmit_end = 3,
    present_start = 4,
    present_end = 5,
    input_sample = 6,
    trigger_flash = 7,
    out_of_band_rendersubmit_start = 8,
    out_of_band_rendersubmit_end = 9,
    out_of_band_present_start = 10,
    out_of_band_present_end = 11,
    _,
};

/// Out-of-band queue type
pub const VkOutOfBandQueueTypeNV = enum(i32) {
    render = 0,
    present = 1,
    _,
};

/// Structure for setting latency sleep mode
pub const VkLatencySleepModeInfoNV = extern struct {
    sType: VkStructureType = .latency_sleep_mode_info_nv,
    pNext: ?*const anyopaque = null,
    lowLatencyMode: VkBool32 = VK_FALSE,
    lowLatencyBoost: VkBool32 = VK_FALSE,
    minimumIntervalUs: u32 = 0,
};

/// Structure for latency sleep
pub const VkLatencySleepInfoNV = extern struct {
    sType: VkStructureType = .latency_sleep_info_nv,
    pNext: ?*const anyopaque = null,
    signalSemaphore: VkSemaphore_T = 0,
    value: u64 = 0,
};

/// Structure for setting latency markers
pub const VkSetLatencyMarkerInfoNV = extern struct {
    sType: VkStructureType = .set_latency_marker_info_nv,
    pNext: ?*const anyopaque = null,
    presentID: u64 = 0,
    marker: VkLatencyMarkerNV = .simulation_start,
};

/// Single timing entry
pub const VkLatencyTimingsFrameReportNV = extern struct {
    sType: VkStructureType = .latency_timings_frame_report_nv,
    pNext: ?*anyopaque = null,
    presentID: u64 = 0,
    inputSampleTimeUs: u64 = 0,
    simStartTimeUs: u64 = 0,
    simEndTimeUs: u64 = 0,
    renderSubmitStartTimeUs: u64 = 0,
    renderSubmitEndTimeUs: u64 = 0,
    presentStartTimeUs: u64 = 0,
    presentEndTimeUs: u64 = 0,
    driverStartTimeUs: u64 = 0,
    driverEndTimeUs: u64 = 0,
    osRenderQueueStartTimeUs: u64 = 0,
    osRenderQueueEndTimeUs: u64 = 0,
    gpuRenderStartTimeUs: u64 = 0,
    gpuRenderEndTimeUs: u64 = 0,
};

/// Container for latency timings
pub const VkGetLatencyMarkerInfoNV = extern struct {
    sType: VkStructureType = .get_latency_marker_info_nv,
    pNext: ?*const anyopaque = null,
    timingCount: u32 = 0,
    pTimings: ?[*]VkLatencyTimingsFrameReportNV = null,
};

/// Submission info for latency
pub const VkLatencySubmissionPresentIdNV = extern struct {
    sType: VkStructureType = .latency_submission_present_id_nv,
    pNext: ?*const anyopaque = null,
    presentID: u64 = 0,
};

/// Swapchain latency creation info
pub const VkSwapchainLatencyCreateInfoNV = extern struct {
    sType: VkStructureType = .swapchain_latency_create_info_nv,
    pNext: ?*const anyopaque = null,
    latencyModeEnable: VkBool32 = VK_FALSE,
};

/// Out-of-band queue info
pub const VkOutOfBandQueueTypeInfoNV = extern struct {
    sType: VkStructureType = .out_of_band_queue_type_info_nv,
    pNext: ?*const anyopaque = null,
    queueType: VkOutOfBandQueueTypeNV = .render,
};

// =============================================================================
// VK_NV_device_diagnostic_checkpoints Types
// =============================================================================

pub const VK_NV_DEVICE_DIAGNOSTIC_CHECKPOINTS_EXTENSION_NAME = "VK_NV_device_diagnostic_checkpoints";
pub const VK_NV_DEVICE_DIAGNOSTIC_CHECKPOINTS_SPEC_VERSION: u32 = 2;

/// Checkpoint data retrieved after GPU hang
pub const VkCheckpointDataNV = extern struct {
    sType: VkStructureType = .checkpoint_data_nv,
    pNext: ?*anyopaque = null,
    stage: VkPipelineStageFlags = 0,
    pCheckpointMarker: ?*anyopaque = null,
};

/// Queue family checkpoint properties
pub const VkQueueFamilyCheckpointPropertiesNV = extern struct {
    sType: VkStructureType = .queue_family_checkpoint_properties_nv,
    pNext: ?*anyopaque = null,
    checkpointExecutionStageMask: VkPipelineStageFlags = 0,
};

// =============================================================================
// VK_NV_device_diagnostics_config Types
// =============================================================================

pub const VK_NV_DEVICE_DIAGNOSTICS_CONFIG_EXTENSION_NAME = "VK_NV_device_diagnostics_config";
pub const VK_NV_DEVICE_DIAGNOSTICS_CONFIG_SPEC_VERSION: u32 = 2;

/// Diagnostic config flags
pub const VkDeviceDiagnosticsConfigFlagsNV = u32;
pub const VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_SHADER_DEBUG_INFO_BIT_NV: VkDeviceDiagnosticsConfigFlagsNV = 0x00000001;
pub const VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_RESOURCE_TRACKING_BIT_NV: VkDeviceDiagnosticsConfigFlagsNV = 0x00000002;
pub const VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_AUTOMATIC_CHECKPOINTS_BIT_NV: VkDeviceDiagnosticsConfigFlagsNV = 0x00000004;
pub const VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_SHADER_ERROR_REPORTING_BIT_NV: VkDeviceDiagnosticsConfigFlagsNV = 0x00000008;

/// Device diagnostics config create info
pub const VkDeviceDiagnosticsConfigCreateInfoNV = extern struct {
    sType: VkStructureType = .device_diagnostics_config_create_info_nv,
    pNext: ?*const anyopaque = null,
    flags: VkDeviceDiagnosticsConfigFlagsNV = 0,
};

// =============================================================================
// Common Vulkan Types
// =============================================================================

pub const VkBool32 = u32;
pub const VK_TRUE: VkBool32 = 1;
pub const VK_FALSE: VkBool32 = 0;

pub const VkPipelineStageFlags = u32;
pub const VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT: VkPipelineStageFlags = 0x00000001;
pub const VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT: VkPipelineStageFlags = 0x00000002;
pub const VK_PIPELINE_STAGE_VERTEX_INPUT_BIT: VkPipelineStageFlags = 0x00000004;
pub const VK_PIPELINE_STAGE_VERTEX_SHADER_BIT: VkPipelineStageFlags = 0x00000008;
pub const VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT: VkPipelineStageFlags = 0x00000080;
pub const VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT: VkPipelineStageFlags = 0x00000800;
pub const VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT: VkPipelineStageFlags = 0x00008000;
pub const VK_PIPELINE_STAGE_ALL_COMMANDS_BIT: VkPipelineStageFlags = 0x00010000;

pub const VkStructureType = enum(i32) {
    application_info = 0,
    instance_create_info = 1,
    device_queue_create_info = 2,
    device_create_info = 3,
    // VK_NV_low_latency2
    latency_sleep_mode_info_nv = 1000505000,
    latency_sleep_info_nv = 1000505001,
    set_latency_marker_info_nv = 1000505002,
    latency_timings_frame_report_nv = 1000505003,
    get_latency_marker_info_nv = 1000505004,
    latency_submission_present_id_nv = 1000505005,
    swapchain_latency_create_info_nv = 1000505006,
    out_of_band_queue_type_info_nv = 1000505007,
    // VK_NV_device_diagnostic_checkpoints
    checkpoint_data_nv = 1000206000,
    queue_family_checkpoint_properties_nv = 1000206001,
    // VK_NV_device_diagnostics_config
    physical_device_diagnostics_config_features_nv = 1000300000,
    device_diagnostics_config_create_info_nv = 1000300001,
    _,
};

pub const VkCommandBuffer = *opaque {};

// =============================================================================
// Function Pointer Types (use .c for Zig 0.16+)
// =============================================================================

// Core Vulkan
pub const PFN_vkGetInstanceProcAddr = *const fn (VkInstance, [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void;
pub const PFN_vkGetDeviceProcAddr = *const fn (VkDevice, [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void;

// VK_NV_low_latency2
pub const PFN_vkSetLatencySleepModeNV = *const fn (VkDevice, VkSwapchainKHR_T, *const VkLatencySleepModeInfoNV) callconv(.c) VkResult;
pub const PFN_vkLatencySleepNV = *const fn (VkDevice, VkSwapchainKHR_T, *const VkLatencySleepInfoNV) callconv(.c) VkResult;
pub const PFN_vkSetLatencyMarkerNV = *const fn (VkDevice, VkSwapchainKHR_T, *const VkSetLatencyMarkerInfoNV) callconv(.c) void;
pub const PFN_vkGetLatencyTimingsNV = *const fn (VkDevice, VkSwapchainKHR_T, *VkGetLatencyMarkerInfoNV) callconv(.c) void;
pub const PFN_vkQueueNotifyOutOfBandNV = *const fn (VkQueue, *const VkOutOfBandQueueTypeInfoNV) callconv(.c) void;

// VK_NV_device_diagnostic_checkpoints
pub const PFN_vkCmdSetCheckpointNV = *const fn (VkCommandBuffer, ?*const anyopaque) callconv(.c) void;
pub const PFN_vkGetQueueCheckpointDataNV = *const fn (VkQueue, *u32, ?[*]VkCheckpointDataNV) callconv(.c) void;

// =============================================================================
// Dynamic Loader
// =============================================================================

pub const Loader = struct {
    handle: std.DynLib,
    vkGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,

    pub fn init() VulkanError!Loader {
        var handle = std.DynLib.open("libvulkan.so.1") catch
            std.DynLib.open("libvulkan.so") catch
            return VulkanError.LoaderError;

        const proc_addr = handle.lookup(PFN_vkGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse {
            handle.close();
            return VulkanError.FunctionNotFound;
        };

        return .{
            .handle = handle,
            .vkGetInstanceProcAddr = proc_addr,
        };
    }

    pub fn deinit(self: *Loader) void {
        self.handle.close();
    }

    pub fn getInstanceProcAddr(self: *const Loader, instance: ?VkInstance, name: [*:0]const u8) ?*const fn () callconv(.c) void {
        if (instance) |inst| {
            return self.vkGetInstanceProcAddr(inst, name);
        }
        // For null instance, get global function
        return self.vkGetInstanceProcAddr(@ptrFromInt(0), name);
    }
};

/// Device-level function dispatch table for NVIDIA extensions
pub const DeviceDispatch = struct {
    device: VkDevice,
    // VK_NV_low_latency2
    vkSetLatencySleepModeNV: ?PFN_vkSetLatencySleepModeNV = null,
    vkLatencySleepNV: ?PFN_vkLatencySleepNV = null,
    vkSetLatencyMarkerNV: ?PFN_vkSetLatencyMarkerNV = null,
    vkGetLatencyTimingsNV: ?PFN_vkGetLatencyTimingsNV = null,
    vkQueueNotifyOutOfBandNV: ?PFN_vkQueueNotifyOutOfBandNV = null,
    // VK_NV_device_diagnostic_checkpoints
    vkCmdSetCheckpointNV: ?PFN_vkCmdSetCheckpointNV = null,
    vkGetQueueCheckpointDataNV: ?PFN_vkGetQueueCheckpointDataNV = null,

    pub fn init(device: VkDevice, getDeviceProcAddr: PFN_vkGetDeviceProcAddr) DeviceDispatch {
        return .{
            .device = device,
            .vkSetLatencySleepModeNV = @ptrCast(getDeviceProcAddr(device, "vkSetLatencySleepModeNV")),
            .vkLatencySleepNV = @ptrCast(getDeviceProcAddr(device, "vkLatencySleepNV")),
            .vkSetLatencyMarkerNV = @ptrCast(getDeviceProcAddr(device, "vkSetLatencyMarkerNV")),
            .vkGetLatencyTimingsNV = @ptrCast(getDeviceProcAddr(device, "vkGetLatencyTimingsNV")),
            .vkQueueNotifyOutOfBandNV = @ptrCast(getDeviceProcAddr(device, "vkQueueNotifyOutOfBandNV")),
            .vkCmdSetCheckpointNV = @ptrCast(getDeviceProcAddr(device, "vkCmdSetCheckpointNV")),
            .vkGetQueueCheckpointDataNV = @ptrCast(getDeviceProcAddr(device, "vkGetQueueCheckpointDataNV")),
        };
    }

    pub fn hasLowLatency2(self: *const DeviceDispatch) bool {
        return self.vkSetLatencySleepModeNV != null and
            self.vkLatencySleepNV != null and
            self.vkSetLatencyMarkerNV != null and
            self.vkGetLatencyTimingsNV != null;
    }

    pub fn hasDiagnosticCheckpoints(self: *const DeviceDispatch) bool {
        return self.vkCmdSetCheckpointNV != null and
            self.vkGetQueueCheckpointDataNV != null;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "VkResult conversion" {
    const success = VkResult.success;
    try std.testing.expect(success.isSuccess());
    try std.testing.expect(success.toError() == null);

    const err = VkResult.error_device_lost;
    try std.testing.expect(!err.isSuccess());
    try std.testing.expectEqual(VulkanError.DeviceLost, err.toError().?);
}

test "structure sizes" {
    // Ensure structures are correctly sized for C ABI
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(VkLatencySleepModeInfoNV));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(VkLatencySleepInfoNV));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(VkSetLatencyMarkerInfoNV));
}
