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
pub const VkImageView = *opaque {};
pub const VkImage = *opaque {};
pub const VkDeviceMemory = *opaque {};
pub const VkPipeline = *opaque {};
pub const VkPipelineLayout = *opaque {};
pub const VkDescriptorPool = *opaque {};
pub const VkDescriptorSetLayout = *opaque {};
pub const VkDescriptorSet = *opaque {};
pub const VkSampler = *opaque {};
pub const VkBuffer = *opaque {};
pub const VkCommandBuffer = *opaque {};

// Basic Vulkan structures
pub const VkOffset2D = extern struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const VkExtent2D = extern struct {
    width: u32 = 0,
    height: u32 = 0,
};

pub const VkRect2D = extern struct {
    offset: VkOffset2D = .{},
    extent: VkExtent2D = .{},
};

// Callback function types for allocators
pub const PFN_vkAllocationFunction = ?*const fn (
    pUserData: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocationScope: i32,
) callconv(.c) ?*anyopaque;

pub const PFN_vkReallocationFunction = ?*const fn (
    pUserData: ?*anyopaque,
    pOriginal: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocationScope: i32,
) callconv(.c) ?*anyopaque;

pub const PFN_vkFreeFunction = ?*const fn (
    pUserData: ?*anyopaque,
    pMemory: ?*anyopaque,
) callconv(.c) void;

pub const PFN_vkInternalAllocationNotification = ?*const fn (
    pUserData: ?*anyopaque,
    size: usize,
    allocationType: i32,
    allocationScope: i32,
) callconv(.c) void;

pub const PFN_vkInternalFreeNotification = ?*const fn (
    pUserData: ?*anyopaque,
    size: usize,
    allocationType: i32,
    allocationScope: i32,
) callconv(.c) void;

/// Custom memory allocator callbacks
pub const VkAllocationCallbacks = extern struct {
    pUserData: ?*anyopaque = null,
    pfnAllocation: PFN_vkAllocationFunction = null,
    pfnReallocation: PFN_vkReallocationFunction = null,
    pfnFree: PFN_vkFreeFunction = null,
    pfnInternalAllocation: PFN_vkInternalAllocationNotification = null,
    pfnInternalFree: PFN_vkInternalFreeNotification = null,
};

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
    descriptor_set_layout_create_info = 32,
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

// Descriptor types
pub const VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: u32 = 1;
pub const VK_DESCRIPTOR_TYPE_STORAGE_IMAGE: u32 = 3;

// Shader stage flags
pub const VK_SHADER_STAGE_COMPUTE_BIT: u32 = 0x00000020;

// Image layouts
pub const VK_IMAGE_LAYOUT_UNDEFINED: u32 = 0;
pub const VK_IMAGE_LAYOUT_GENERAL: u32 = 1;
pub const VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL: u32 = 5;

// Structure type constants
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO: u32 = 32;
pub const VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO: u32 = 30;
pub const VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO: u32 = 16;
pub const VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO: u32 = 29;
pub const VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO: u32 = 18;
pub const VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO: u32 = 14;
pub const VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO: u32 = 15;
pub const VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO: u32 = 5;
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO: u32 = 33;
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO: u32 = 34;
pub const VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET: u32 = 35;
pub const VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER: u32 = 45;

// Image types
pub const VK_IMAGE_TYPE_2D: u32 = 1;
pub const VK_IMAGE_VIEW_TYPE_2D: u32 = 1;
pub const VK_FORMAT_R8_UNORM: u32 = 9;
pub const VK_FORMAT_R8G8B8A8_UNORM: u32 = 37;
pub const VK_FORMAT_R16G16_SFLOAT: u32 = 83; // Motion vectors
pub const VK_SAMPLE_COUNT_1_BIT: u32 = 1;
pub const VK_IMAGE_TILING_OPTIMAL: u32 = 0;
pub const VK_IMAGE_USAGE_STORAGE_BIT: u32 = 0x00000008;
pub const VK_IMAGE_USAGE_SAMPLED_BIT: u32 = 0x00000004;
pub const VK_IMAGE_USAGE_TRANSFER_SRC_BIT: u32 = 0x00000001;
pub const VK_IMAGE_USAGE_TRANSFER_DST_BIT: u32 = 0x00000002;
pub const VK_SHARING_MODE_EXCLUSIVE: u32 = 0;
pub const VK_IMAGE_ASPECT_COLOR_BIT: u32 = 1;
pub const VK_COMPONENT_SWIZZLE_IDENTITY: u32 = 0;
pub const VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT: u32 = 0x00000001;
pub const VK_PIPELINE_BIND_POINT_COMPUTE: u32 = 1;
pub const VK_ACCESS_SHADER_READ_BIT: u32 = 0x00000020;
pub const VK_ACCESS_SHADER_WRITE_BIT: u32 = 0x00000040;

/// Descriptor set layout binding
pub const VkDescriptorSetLayoutBinding = extern struct {
    binding: u32,
    descriptorType: u32,
    descriptorCount: u32,
    stageFlags: u32,
    pImmutableSamplers: ?*const VkSampler,
};

/// Descriptor set layout create info
pub const VkDescriptorSetLayoutCreateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    bindingCount: u32,
    pBindings: ?[*]const VkDescriptorSetLayoutBinding,
};

/// Push constant range
pub const VkPushConstantRange = extern struct {
    stageFlags: u32,
    offset: u32,
    size: u32,
};

/// Pipeline layout create info
pub const VkPipelineLayoutCreateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    setLayoutCount: u32 = 0,
    pSetLayouts: ?[*]const VkDescriptorSetLayout = null,
    pushConstantRangeCount: u32 = 0,
    pPushConstantRanges: ?[*]const VkPushConstantRange = null,
};

/// Shader module create info
pub const VkShaderModuleCreateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    codeSize: usize,
    pCode: [*]const u32,
};

/// Pipeline shader stage create info
pub const VkPipelineShaderStageCreateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    stage: u32,
    module: VkShaderModule,
    pName: [*:0]const u8,
    pSpecializationInfo: ?*const anyopaque = null,
};

/// Compute pipeline create info
pub const VkComputePipelineCreateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    stage: VkPipelineShaderStageCreateInfo,
    layout: VkPipelineLayout,
    basePipelineHandle: ?VkPipeline = null,
    basePipelineIndex: i32 = -1,
};

/// Extent 3D
pub const VkExtent3D = extern struct {
    width: u32,
    height: u32,
    depth: u32,
};

/// Image create info
pub const VkImageCreateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    imageType: u32,
    format: u32,
    extent: VkExtent3D,
    mipLevels: u32,
    arrayLayers: u32,
    samples: u32,
    tiling: u32,
    usage: u32,
    sharingMode: u32,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
    initialLayout: u32,
};

/// Component mapping
pub const VkComponentMapping = extern struct {
    r: u32 = VK_COMPONENT_SWIZZLE_IDENTITY,
    g: u32 = VK_COMPONENT_SWIZZLE_IDENTITY,
    b: u32 = VK_COMPONENT_SWIZZLE_IDENTITY,
    a: u32 = VK_COMPONENT_SWIZZLE_IDENTITY,
};

/// Image subresource range
pub const VkImageSubresourceRange = extern struct {
    aspectMask: u32,
    baseMipLevel: u32,
    levelCount: u32,
    baseArrayLayer: u32,
    layerCount: u32,
};

/// Image view create info
pub const VkImageViewCreateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    image: VkImage,
    viewType: u32,
    format: u32,
    components: VkComponentMapping = .{},
    subresourceRange: VkImageSubresourceRange,
};

/// Memory requirements
pub const VkMemoryRequirements = extern struct {
    size: u64,
    alignment: u64,
    memoryTypeBits: u32,
};

/// Memory allocate info
pub const VkMemoryAllocateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    pNext: ?*const anyopaque = null,
    allocationSize: u64,
    memoryTypeIndex: u32,
};

/// Memory type
pub const VkMemoryType = extern struct {
    propertyFlags: u32,
    heapIndex: u32,
};

/// Memory heap
pub const VkMemoryHeap = extern struct {
    size: u64,
    flags: u32,
};

/// Physical device memory properties
pub const VkPhysicalDeviceMemoryProperties = extern struct {
    memoryTypeCount: u32,
    memoryTypes: [32]VkMemoryType,
    memoryHeapCount: u32,
    memoryHeaps: [16]VkMemoryHeap,
};

/// Descriptor pool size
pub const VkDescriptorPoolSize = extern struct {
    descriptorType: u32,
    descriptorCount: u32,
};

/// Descriptor pool create info
pub const VkDescriptorPoolCreateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    maxSets: u32,
    poolSizeCount: u32,
    pPoolSizes: [*]const VkDescriptorPoolSize,
};

/// Descriptor set allocate info
pub const VkDescriptorSetAllocateInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    pNext: ?*const anyopaque = null,
    descriptorPool: VkDescriptorPool,
    descriptorSetCount: u32,
    pSetLayouts: [*]const VkDescriptorSetLayout,
};

/// Descriptor image info
pub const VkDescriptorImageInfo = extern struct {
    sampler: ?VkSampler = null,
    imageView: VkImageView,
    imageLayout: u32,
};

/// Write descriptor set
pub const VkWriteDescriptorSet = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    pNext: ?*const anyopaque = null,
    dstSet: VkDescriptorSet,
    dstBinding: u32,
    dstArrayElement: u32 = 0,
    descriptorCount: u32,
    descriptorType: u32,
    pImageInfo: ?[*]const VkDescriptorImageInfo = null,
    pBufferInfo: ?*const anyopaque = null,
    pTexelBufferView: ?*const anyopaque = null,
};

/// Image subresource layers
pub const VkImageSubresourceLayers = extern struct {
    aspectMask: u32,
    mipLevel: u32,
    baseArrayLayer: u32,
    layerCount: u32,
};

/// Image memory barrier
pub const VkImageMemoryBarrier = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: ?*const anyopaque = null,
    srcAccessMask: u32,
    dstAccessMask: u32,
    oldLayout: u32,
    newLayout: u32,
    srcQueueFamilyIndex: u32 = 0xFFFFFFFF, // VK_QUEUE_FAMILY_IGNORED
    dstQueueFamilyIndex: u32 = 0xFFFFFFFF,
    image: VkImage,
    subresourceRange: VkImageSubresourceRange,
};

/// Shader module handle
pub const VkShaderModule = *opaque {};

/// Pipeline cache handle (optional)
pub const VkPipelineCache = ?*opaque {};

/// Fence handle
pub const VkFence = u64;

// =============================================================================
// Layer and Extension Properties
// =============================================================================

/// API version constants
pub const VK_API_VERSION_1_0: u32 = (1 << 22) | (0 << 12);
pub const VK_API_VERSION_1_1: u32 = (1 << 22) | (1 << 12);
pub const VK_API_VERSION_1_2: u32 = (1 << 22) | (2 << 12);
pub const VK_API_VERSION_1_3: u32 = (1 << 22) | (3 << 12);
pub const VK_API_VERSION_1_4: u32 = (1 << 22) | (4 << 12);

/// Minimum required API version for nvvk
pub const NVVK_MIN_API_VERSION: u32 = VK_API_VERSION_1_3;
/// Recommended API version for full feature support
pub const NVVK_RECOMMENDED_API_VERSION: u32 = VK_API_VERSION_1_4;

/// Make API version from components
pub fn makeApiVersion(variant: u32, major: u32, minor: u32, patch: u32) u32 {
    return (variant << 29) | (major << 22) | (minor << 12) | patch;
}

/// Extract major version from API version
pub fn apiVersionMajor(version: u32) u32 {
    return (version >> 22) & 0x7F;
}

/// Extract minor version from API version
pub fn apiVersionMinor(version: u32) u32 {
    return (version >> 12) & 0x3FF;
}

/// Extract patch version from API version
pub fn apiVersionPatch(version: u32) u32 {
    return version & 0xFFF;
}

/// Layer properties structure
pub const VkLayerProperties = extern struct {
    layerName: [256]u8 = [_]u8{0} ** 256,
    specVersion: u32 = 0,
    implementationVersion: u32 = 0,
    description: [256]u8 = [_]u8{0} ** 256,
};

/// Extension properties structure
pub const VkExtensionProperties = extern struct {
    extensionName: [256]u8 = [_]u8{0} ** 256,
    specVersion: u32 = 0,
};

// =============================================================================
// Instance and Device Creation
// =============================================================================

/// Application info structure
pub const VkApplicationInfo = extern struct {
    sType: VkStructureType = .application_info,
    pNext: ?*const anyopaque = null,
    pApplicationName: ?[*:0]const u8 = null,
    applicationVersion: u32 = 0,
    pEngineName: ?[*:0]const u8 = null,
    engineVersion: u32 = 0,
    apiVersion: u32 = 0,
};

/// Instance create info structure
pub const VkInstanceCreateInfo = extern struct {
    sType: VkStructureType = .instance_create_info,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    pApplicationInfo: ?*const VkApplicationInfo = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
};

/// Device queue create info
pub const VkDeviceQueueCreateInfo = extern struct {
    sType: VkStructureType = .device_queue_create_info,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueFamilyIndex: u32 = 0,
    queueCount: u32 = 0,
    pQueuePriorities: ?[*]const f32 = null,
};

/// Physical device features (simplified)
pub const VkPhysicalDeviceFeatures = extern struct {
    robustBufferAccess: VkBool32 = VK_FALSE,
    // ... many more fields, but we use zeroed struct
    _padding: [224]u8 = [_]u8{0} ** 224, // Pad to correct size
};

/// Device create info structure
pub const VkDeviceCreateInfo = extern struct {
    sType: VkStructureType = .device_create_info,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueCreateInfoCount: u32 = 0,
    pQueueCreateInfos: ?[*]const VkDeviceQueueCreateInfo = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
    pEnabledFeatures: ?*const VkPhysicalDeviceFeatures = null,
};

// =============================================================================
// Swapchain Types (VK_KHR_swapchain)
// =============================================================================

/// Color space enum
pub const VkColorSpaceKHR = enum(i32) {
    srgb_nonlinear_khr = 0,
    _,
};

/// Present mode enum
pub const VkPresentModeKHR = enum(i32) {
    immediate_khr = 0,
    mailbox_khr = 1,
    fifo_khr = 2,
    fifo_relaxed_khr = 3,
    _,
};

/// Surface transform flags
pub const VkSurfaceTransformFlagsKHR = u32;

/// Composite alpha flags
pub const VkCompositeAlphaFlagsKHR = u32;

/// Image usage flags
pub const VkImageUsageFlags = u32;

/// Swapchain create info
pub const VkSwapchainCreateInfoKHR = extern struct {
    sType: u32 = 1000001000, // VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    surface: u64 = 0, // VkSurfaceKHR
    minImageCount: u32 = 0,
    imageFormat: u32 = 0,
    imageColorSpace: i32 = 0,
    imageExtent: VkExtent2D = .{},
    imageArrayLayers: u32 = 1,
    imageUsage: u32 = 0,
    imageSharingMode: u32 = 0,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
    preTransform: u32 = 0,
    compositeAlpha: u32 = 0,
    presentMode: i32 = 0,
    clipped: VkBool32 = VK_TRUE,
    oldSwapchain: u64 = 0, // VkSwapchainKHR
};

/// Present info structure
pub const VkPresentInfoKHR = extern struct {
    sType: u32 = 1000001001, // VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const u64 = null, // VkSemaphore handles
    swapchainCount: u32 = 0,
    pSwapchains: [*]const u64 = undefined, // VkSwapchainKHR handles
    pImageIndices: [*]const u32 = undefined,
    pResults: ?[*]i32 = null, // VkResult array
};

// =============================================================================
// Vulkan 1.4 Promoted Extensions
// =============================================================================

// VK_KHR_push_descriptor (promoted to core in Vulkan 1.4)
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PUSH_DESCRIPTOR_PROPERTIES: u32 = 1000080000;
pub const VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT: u32 = 0x00000001;
pub const VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS: u32 = 1;

/// Physical device push descriptor properties (Vulkan 1.4 core)
pub const VkPhysicalDevicePushDescriptorProperties = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PUSH_DESCRIPTOR_PROPERTIES,
    pNext: ?*anyopaque = null,
    maxPushDescriptors: u32 = 0,
};

// VK_KHR_maintenance6 (promoted to core in Vulkan 1.4)
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_6_FEATURES: u32 = 1000545000;
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_6_PROPERTIES: u32 = 1000545001;
pub const VK_STRUCTURE_TYPE_BIND_MEMORY_STATUS: u32 = 1000545002;
pub const VK_STRUCTURE_TYPE_BIND_DESCRIPTOR_SETS_INFO: u32 = 1000545003;
pub const VK_STRUCTURE_TYPE_PUSH_CONSTANTS_INFO: u32 = 1000545004;
pub const VK_STRUCTURE_TYPE_PUSH_DESCRIPTOR_SET_INFO: u32 = 1000545005;
pub const VK_STRUCTURE_TYPE_PUSH_DESCRIPTOR_SET_WITH_TEMPLATE_INFO: u32 = 1000545006;

/// Physical device maintenance 6 features (Vulkan 1.4 core)
pub const VkPhysicalDeviceMaintenance6Features = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_6_FEATURES,
    pNext: ?*anyopaque = null,
    maintenance6: VkBool32 = VK_FALSE,
};

/// Physical device maintenance 6 properties (Vulkan 1.4 core)
pub const VkPhysicalDeviceMaintenance6Properties = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_6_PROPERTIES,
    pNext: ?*anyopaque = null,
    blockTexelViewCompatibleMultipleLayers: VkBool32 = VK_FALSE,
    maxCombinedImageSamplerDescriptorCount: u32 = 0,
    fragmentShadingRateClampCombinerInputs: VkBool32 = VK_FALSE,
};

/// Push descriptor set info (Vulkan 1.4 core)
pub const VkPushDescriptorSetInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PUSH_DESCRIPTOR_SET_INFO,
    pNext: ?*const anyopaque = null,
    stageFlags: u32 = 0,
    layout: VkPipelineLayout = undefined,
    set: u32 = 0,
    descriptorWriteCount: u32 = 0,
    pDescriptorWrites: ?[*]const VkWriteDescriptorSet = null,
};

/// Push constants info (Vulkan 1.4 core)
pub const VkPushConstantsInfo = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PUSH_CONSTANTS_INFO,
    pNext: ?*const anyopaque = null,
    layout: VkPipelineLayout = undefined,
    stageFlags: u32 = 0,
    offset: u32 = 0,
    size: u32 = 0,
    pValues: ?*const anyopaque = null,
};

// VK_KHR_dynamic_rendering_local_read (promoted to core in Vulkan 1.4)
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_LOCAL_READ_FEATURES: u32 = 1000232000;
pub const VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_LOCATION_INFO: u32 = 1000232001;
pub const VK_STRUCTURE_TYPE_RENDERING_INPUT_ATTACHMENT_INDEX_INFO: u32 = 1000232002;

/// Physical device dynamic rendering local read features (Vulkan 1.4 core)
pub const VkPhysicalDeviceDynamicRenderingLocalReadFeatures = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_LOCAL_READ_FEATURES,
    pNext: ?*anyopaque = null,
    dynamicRenderingLocalRead: VkBool32 = VK_FALSE,
};

// Vulkan 1.4 scalar block layout (promoted from VK_EXT_scalar_block_layout)
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES: u32 = 1000221000;

/// Physical device scalar block layout features (Vulkan 1.4 core)
pub const VkPhysicalDeviceScalarBlockLayoutFeatures = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES,
    pNext: ?*anyopaque = null,
    scalarBlockLayout: VkBool32 = VK_FALSE,
};

// =============================================================================
// Vulkan 1.4 Feature Detection
// =============================================================================

/// Check if an API version supports Vulkan 1.4 features
pub fn supportsVulkan14(api_version: u32) bool {
    return api_version >= VK_API_VERSION_1_4;
}

/// Check if an API version supports Vulkan 1.3 features
pub fn supportsVulkan13(api_version: u32) bool {
    return api_version >= VK_API_VERSION_1_3;
}

/// Get recommended features string for a given API version
pub fn getFeatureSetName(api_version: u32) []const u8 {
    if (api_version >= VK_API_VERSION_1_4) return "Vulkan 1.4 (full)";
    if (api_version >= VK_API_VERSION_1_3) return "Vulkan 1.3 (compatible)";
    if (api_version >= VK_API_VERSION_1_2) return "Vulkan 1.2 (limited)";
    return "Vulkan 1.1 or below (unsupported)";
}

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

// Core Vulkan functions
pub const PFN_vkCreateDescriptorSetLayout = *const fn (VkDevice, *const VkDescriptorSetLayoutCreateInfo, ?*const VkAllocationCallbacks, *VkDescriptorSetLayout) callconv(.c) VkResult;
pub const PFN_vkDestroyDescriptorSetLayout = *const fn (VkDevice, VkDescriptorSetLayout, ?*const VkAllocationCallbacks) callconv(.c) void;
pub const PFN_vkCreatePipelineLayout = *const fn (VkDevice, *const VkPipelineLayoutCreateInfo, ?*const VkAllocationCallbacks, *VkPipelineLayout) callconv(.c) VkResult;
pub const PFN_vkDestroyPipelineLayout = *const fn (VkDevice, VkPipelineLayout, ?*const VkAllocationCallbacks) callconv(.c) void;
pub const PFN_vkCreateShaderModule = *const fn (VkDevice, *const VkShaderModuleCreateInfo, ?*const VkAllocationCallbacks, *VkShaderModule) callconv(.c) VkResult;
pub const PFN_vkDestroyShaderModule = *const fn (VkDevice, VkShaderModule, ?*const VkAllocationCallbacks) callconv(.c) void;
pub const PFN_vkCreateComputePipelines = *const fn (VkDevice, VkPipelineCache, u32, [*]const VkComputePipelineCreateInfo, ?*const VkAllocationCallbacks, [*]VkPipeline) callconv(.c) VkResult;
pub const PFN_vkDestroyPipeline = *const fn (VkDevice, VkPipeline, ?*const VkAllocationCallbacks) callconv(.c) void;
pub const PFN_vkCreateImage = *const fn (VkDevice, *const VkImageCreateInfo, ?*const VkAllocationCallbacks, *VkImage) callconv(.c) VkResult;
pub const PFN_vkDestroyImage = *const fn (VkDevice, VkImage, ?*const VkAllocationCallbacks) callconv(.c) void;
pub const PFN_vkGetImageMemoryRequirements = *const fn (VkDevice, VkImage, *VkMemoryRequirements) callconv(.c) void;
pub const PFN_vkAllocateMemory = *const fn (VkDevice, *const VkMemoryAllocateInfo, ?*const VkAllocationCallbacks, *VkDeviceMemory) callconv(.c) VkResult;
pub const PFN_vkFreeMemory = *const fn (VkDevice, VkDeviceMemory, ?*const VkAllocationCallbacks) callconv(.c) void;
pub const PFN_vkBindImageMemory = *const fn (VkDevice, VkImage, VkDeviceMemory, u64) callconv(.c) VkResult;
pub const PFN_vkCreateImageView = *const fn (VkDevice, *const VkImageViewCreateInfo, ?*const VkAllocationCallbacks, *VkImageView) callconv(.c) VkResult;
pub const PFN_vkDestroyImageView = *const fn (VkDevice, VkImageView, ?*const VkAllocationCallbacks) callconv(.c) void;
pub const PFN_vkCreateDescriptorPool = *const fn (VkDevice, *const VkDescriptorPoolCreateInfo, ?*const VkAllocationCallbacks, *VkDescriptorPool) callconv(.c) VkResult;
pub const PFN_vkDestroyDescriptorPool = *const fn (VkDevice, VkDescriptorPool, ?*const VkAllocationCallbacks) callconv(.c) void;
pub const PFN_vkAllocateDescriptorSets = *const fn (VkDevice, *const VkDescriptorSetAllocateInfo, *VkDescriptorSet) callconv(.c) VkResult;
/// Copy descriptor set structure (stub for now)
pub const VkCopyDescriptorSet = extern struct {
    sType: u32 = 36, // VK_STRUCTURE_TYPE_COPY_DESCRIPTOR_SET
    pNext: ?*const anyopaque = null,
    srcSet: VkDescriptorSet,
    srcBinding: u32,
    srcArrayElement: u32,
    dstSet: VkDescriptorSet,
    dstBinding: u32,
    dstArrayElement: u32,
    descriptorCount: u32,
};

pub const PFN_vkUpdateDescriptorSets = *const fn (VkDevice, u32, [*]const VkWriteDescriptorSet, u32, ?[*]const VkCopyDescriptorSet) callconv(.c) void;
pub const PFN_vkGetPhysicalDeviceMemoryProperties = *const fn (VkPhysicalDevice, *VkPhysicalDeviceMemoryProperties) callconv(.c) void;

// Command buffer functions
pub const PFN_vkCmdBindPipeline = *const fn (VkCommandBuffer, u32, VkPipeline) callconv(.c) void;
pub const PFN_vkCmdBindDescriptorSets = *const fn (VkCommandBuffer, u32, VkPipelineLayout, u32, u32, [*]const VkDescriptorSet, u32, ?[*]const u32) callconv(.c) void;
pub const PFN_vkCmdPushConstants = *const fn (VkCommandBuffer, VkPipelineLayout, u32, u32, u32, *const anyopaque) callconv(.c) void;
pub const PFN_vkCmdDispatch = *const fn (VkCommandBuffer, u32, u32, u32) callconv(.c) void;
pub const PFN_vkCmdPipelineBarrier = *const fn (VkCommandBuffer, u32, u32, u32, u32, ?*const anyopaque, u32, ?*const anyopaque, u32, ?[*]const VkImageMemoryBarrier) callconv(.c) void;

// Vulkan 1.4 push descriptors (promoted from VK_KHR_push_descriptor)
pub const PFN_vkCmdPushDescriptorSet = *const fn (VkCommandBuffer, u32, VkPipelineLayout, u32, u32, [*]const VkWriteDescriptorSet) callconv(.c) void;

// Device lifecycle
pub const PFN_vkDestroyDevice = *const fn (VkDevice, ?*const VkAllocationCallbacks) callconv(.c) void;

// Swapchain functions (VK_KHR_swapchain)
pub const PFN_vkCreateSwapchainKHR = *const fn (VkDevice, *const VkSwapchainCreateInfoKHR, ?*const VkAllocationCallbacks, *u64) callconv(.c) i32;
pub const PFN_vkDestroySwapchainKHR = *const fn (VkDevice, u64, ?*const VkAllocationCallbacks) callconv(.c) void;
pub const PFN_vkAcquireNextImageKHR = *const fn (VkDevice, u64, u64, u64, u64, *u32) callconv(.c) i32;
pub const PFN_vkQueuePresentKHR = *const fn (VkQueue, *const VkPresentInfoKHR) callconv(.c) i32;

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

/// Instance-level function dispatch table
pub const InstanceDispatch = struct {
    instance: VkInstance,
    vkGetPhysicalDeviceMemoryProperties: ?PFN_vkGetPhysicalDeviceMemoryProperties = null,

    pub fn init(instance: VkInstance, loader: *const Loader) InstanceDispatch {
        return .{
            .instance = instance,
            .vkGetPhysicalDeviceMemoryProperties = @ptrCast(loader.getInstanceProcAddr(instance, "vkGetPhysicalDeviceMemoryProperties")),
        };
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
    // Core Vulkan functions
    vkCreateDescriptorSetLayout: ?PFN_vkCreateDescriptorSetLayout = null,
    vkDestroyDescriptorSetLayout: ?PFN_vkDestroyDescriptorSetLayout = null,
    vkCreatePipelineLayout: ?PFN_vkCreatePipelineLayout = null,
    vkDestroyPipelineLayout: ?PFN_vkDestroyPipelineLayout = null,
    vkCreateShaderModule: ?PFN_vkCreateShaderModule = null,
    vkDestroyShaderModule: ?PFN_vkDestroyShaderModule = null,
    vkCreateComputePipelines: ?PFN_vkCreateComputePipelines = null,
    vkDestroyPipeline: ?PFN_vkDestroyPipeline = null,
    vkCreateImage: ?PFN_vkCreateImage = null,
    vkDestroyImage: ?PFN_vkDestroyImage = null,
    vkGetImageMemoryRequirements: ?PFN_vkGetImageMemoryRequirements = null,
    vkAllocateMemory: ?PFN_vkAllocateMemory = null,
    vkFreeMemory: ?PFN_vkFreeMemory = null,
    vkBindImageMemory: ?PFN_vkBindImageMemory = null,
    vkCreateImageView: ?PFN_vkCreateImageView = null,
    vkDestroyImageView: ?PFN_vkDestroyImageView = null,
    vkCreateDescriptorPool: ?PFN_vkCreateDescriptorPool = null,
    vkDestroyDescriptorPool: ?PFN_vkDestroyDescriptorPool = null,
    vkAllocateDescriptorSets: ?PFN_vkAllocateDescriptorSets = null,
    vkUpdateDescriptorSets: ?PFN_vkUpdateDescriptorSets = null,
    // Command buffer functions
    vkCmdBindPipeline: ?PFN_vkCmdBindPipeline = null,
    vkCmdBindDescriptorSets: ?PFN_vkCmdBindDescriptorSets = null,
    vkCmdPushConstants: ?PFN_vkCmdPushConstants = null,
    vkCmdDispatch: ?PFN_vkCmdDispatch = null,
    vkCmdPipelineBarrier: ?PFN_vkCmdPipelineBarrier = null,
    // Vulkan 1.4 push descriptors
    vkCmdPushDescriptorSet: ?PFN_vkCmdPushDescriptorSet = null,
    // Device lifecycle
    vkDestroyDevice: ?PFN_vkDestroyDevice = null,
    // Swapchain functions
    vkCreateSwapchainKHR: ?PFN_vkCreateSwapchainKHR = null,
    vkDestroySwapchainKHR: ?PFN_vkDestroySwapchainKHR = null,
    vkAcquireNextImageKHR: ?PFN_vkAcquireNextImageKHR = null,
    vkQueuePresentKHR: ?PFN_vkQueuePresentKHR = null,

    pub fn init(device: VkDevice, getDeviceProcAddr: PFN_vkGetDeviceProcAddr) DeviceDispatch {
        return .{
            .device = device,
            // NVIDIA extensions
            .vkSetLatencySleepModeNV = @ptrCast(getDeviceProcAddr(device, "vkSetLatencySleepModeNV")),
            .vkLatencySleepNV = @ptrCast(getDeviceProcAddr(device, "vkLatencySleepNV")),
            .vkSetLatencyMarkerNV = @ptrCast(getDeviceProcAddr(device, "vkSetLatencyMarkerNV")),
            .vkGetLatencyTimingsNV = @ptrCast(getDeviceProcAddr(device, "vkGetLatencyTimingsNV")),
            .vkQueueNotifyOutOfBandNV = @ptrCast(getDeviceProcAddr(device, "vkQueueNotifyOutOfBandNV")),
            .vkCmdSetCheckpointNV = @ptrCast(getDeviceProcAddr(device, "vkCmdSetCheckpointNV")),
            .vkGetQueueCheckpointDataNV = @ptrCast(getDeviceProcAddr(device, "vkGetQueueCheckpointDataNV")),
            // Core Vulkan
            .vkCreateDescriptorSetLayout = @ptrCast(getDeviceProcAddr(device, "vkCreateDescriptorSetLayout")),
            .vkDestroyDescriptorSetLayout = @ptrCast(getDeviceProcAddr(device, "vkDestroyDescriptorSetLayout")),
            .vkCreatePipelineLayout = @ptrCast(getDeviceProcAddr(device, "vkCreatePipelineLayout")),
            .vkDestroyPipelineLayout = @ptrCast(getDeviceProcAddr(device, "vkDestroyPipelineLayout")),
            .vkCreateShaderModule = @ptrCast(getDeviceProcAddr(device, "vkCreateShaderModule")),
            .vkDestroyShaderModule = @ptrCast(getDeviceProcAddr(device, "vkDestroyShaderModule")),
            .vkCreateComputePipelines = @ptrCast(getDeviceProcAddr(device, "vkCreateComputePipelines")),
            .vkDestroyPipeline = @ptrCast(getDeviceProcAddr(device, "vkDestroyPipeline")),
            .vkCreateImage = @ptrCast(getDeviceProcAddr(device, "vkCreateImage")),
            .vkDestroyImage = @ptrCast(getDeviceProcAddr(device, "vkDestroyImage")),
            .vkGetImageMemoryRequirements = @ptrCast(getDeviceProcAddr(device, "vkGetImageMemoryRequirements")),
            .vkAllocateMemory = @ptrCast(getDeviceProcAddr(device, "vkAllocateMemory")),
            .vkFreeMemory = @ptrCast(getDeviceProcAddr(device, "vkFreeMemory")),
            .vkBindImageMemory = @ptrCast(getDeviceProcAddr(device, "vkBindImageMemory")),
            .vkCreateImageView = @ptrCast(getDeviceProcAddr(device, "vkCreateImageView")),
            .vkDestroyImageView = @ptrCast(getDeviceProcAddr(device, "vkDestroyImageView")),
            .vkCreateDescriptorPool = @ptrCast(getDeviceProcAddr(device, "vkCreateDescriptorPool")),
            .vkDestroyDescriptorPool = @ptrCast(getDeviceProcAddr(device, "vkDestroyDescriptorPool")),
            .vkAllocateDescriptorSets = @ptrCast(getDeviceProcAddr(device, "vkAllocateDescriptorSets")),
            .vkUpdateDescriptorSets = @ptrCast(getDeviceProcAddr(device, "vkUpdateDescriptorSets")),
            // Command buffer
            .vkCmdBindPipeline = @ptrCast(getDeviceProcAddr(device, "vkCmdBindPipeline")),
            .vkCmdBindDescriptorSets = @ptrCast(getDeviceProcAddr(device, "vkCmdBindDescriptorSets")),
            .vkCmdPushConstants = @ptrCast(getDeviceProcAddr(device, "vkCmdPushConstants")),
            .vkCmdDispatch = @ptrCast(getDeviceProcAddr(device, "vkCmdDispatch")),
            .vkCmdPipelineBarrier = @ptrCast(getDeviceProcAddr(device, "vkCmdPipelineBarrier")),
            // Vulkan 1.4 push descriptors
            .vkCmdPushDescriptorSet = @ptrCast(getDeviceProcAddr(device, "vkCmdPushDescriptorSet")),
            // Device lifecycle
            .vkDestroyDevice = @ptrCast(getDeviceProcAddr(device, "vkDestroyDevice")),
            // Swapchain functions
            .vkCreateSwapchainKHR = @ptrCast(getDeviceProcAddr(device, "vkCreateSwapchainKHR")),
            .vkDestroySwapchainKHR = @ptrCast(getDeviceProcAddr(device, "vkDestroySwapchainKHR")),
            .vkAcquireNextImageKHR = @ptrCast(getDeviceProcAddr(device, "vkAcquireNextImageKHR")),
            .vkQueuePresentKHR = @ptrCast(getDeviceProcAddr(device, "vkQueuePresentKHR")),
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

    /// Check if Vulkan 1.4 push descriptors are supported
    pub fn hasPushDescriptors(self: *const DeviceDispatch) bool {
        return self.vkCmdPushDescriptorSet != null;
    }

    pub fn hasComputePipelines(self: *const DeviceDispatch) bool {
        return self.vkCreateComputePipelines != null and
            self.vkCreateShaderModule != null and
            self.vkCmdDispatch != null;
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
