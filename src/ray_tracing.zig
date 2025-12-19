//! VK_NV_ray_tracing Extension Wrapper (Legacy)
//!
//! Provides legacy NVIDIA ray tracing support for older games and drivers.
//! This extension predates the cross-vendor VK_KHR_ray_tracing_pipeline and
//! is still useful for compatibility with older applications.
//!
//! Note: For new development, prefer VK_KHR_ray_tracing_pipeline.
//! This wrapper exists for compatibility with games that target VK_NV_ray_tracing.
//!
//! Requires NVIDIA driver 590+ and VK_NV_ray_tracing extension.

const std = @import("std");
const vk = @import("vulkan.zig");

// =============================================================================
// Extension Constants
// =============================================================================

pub const VK_NV_RAY_TRACING_EXTENSION_NAME = "VK_NV_ray_tracing";
pub const VK_NV_RAY_TRACING_SPEC_VERSION: u32 = 3;

// Shader stage bits
pub const VK_SHADER_STAGE_RAYGEN_BIT_NV: u32 = 0x00000100;
pub const VK_SHADER_STAGE_ANY_HIT_BIT_NV: u32 = 0x00000200;
pub const VK_SHADER_STAGE_CLOSEST_HIT_BIT_NV: u32 = 0x00000400;
pub const VK_SHADER_STAGE_MISS_BIT_NV: u32 = 0x00000800;
pub const VK_SHADER_STAGE_INTERSECTION_BIT_NV: u32 = 0x00001000;
pub const VK_SHADER_STAGE_CALLABLE_BIT_NV: u32 = 0x00002000;

// Pipeline stage bits
pub const VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_NV: u32 = 0x00200000;
pub const VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_NV: u32 = 0x02000000;

// Buffer usage bits
pub const VK_BUFFER_USAGE_RAY_TRACING_BIT_NV: u32 = 0x00000400;

// Geometry flags
pub const VK_GEOMETRY_OPAQUE_BIT_NV: u32 = 0x00000001;
pub const VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_NV: u32 = 0x00000002;

// Acceleration structure type
pub const VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_NV: u32 = 0;
pub const VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_NV: u32 = 1;

// Build flags
pub const VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_NV: u32 = 0x00000001;
pub const VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_COMPACTION_BIT_NV: u32 = 0x00000002;
pub const VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_NV: u32 = 0x00000004;
pub const VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_NV: u32 = 0x00000008;
pub const VK_BUILD_ACCELERATION_STRUCTURE_LOW_MEMORY_BIT_NV: u32 = 0x00000010;

// =============================================================================
// Types
// =============================================================================

pub const VkAccelerationStructureNV = u64;

pub const VkGeometryTypeNV = enum(u32) {
    triangles = 0,
    aabbs = 1,
    _,
};

pub const VkAccelerationStructureTypeNV = enum(u32) {
    top_level = 0,
    bottom_level = 1,
    _,
};

pub const VkCopyAccelerationStructureModeNV = enum(u32) {
    clone = 0,
    compact = 1,
    _,
};

pub const VkAccelerationStructureMemoryRequirementsTypeNV = enum(u32) {
    object = 0,
    build_scratch = 1,
    update_scratch = 2,
    _,
};

/// Ray tracing shader group type
pub const VkRayTracingShaderGroupTypeNV = enum(u32) {
    general = 0,
    triangles_hit_group = 1,
    procedural_hit_group = 2,
    _,
};

/// Physical device ray tracing properties
pub const VkPhysicalDeviceRayTracingPropertiesNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165009),
    pNext: ?*anyopaque = null,
    shaderGroupHandleSize: u32 = 0,
    maxRecursionDepth: u32 = 0,
    maxShaderGroupStride: u32 = 0,
    shaderGroupBaseAlignment: u32 = 0,
    maxGeometryCount: u64 = 0,
    maxInstanceCount: u64 = 0,
    maxTriangleCount: u64 = 0,
    maxDescriptorSetAccelerationStructures: u32 = 0,
};

/// Geometry triangles data
pub const VkGeometryTrianglesNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165004),
    pNext: ?*const anyopaque = null,
    vertexData: u64 = 0, // VkBuffer
    vertexOffset: u64 = 0,
    vertexCount: u32 = 0,
    vertexStride: u64 = 0,
    vertexFormat: u32 = 0, // VkFormat
    indexData: u64 = 0, // VkBuffer
    indexOffset: u64 = 0,
    indexCount: u32 = 0,
    indexType: u32 = 0, // VkIndexType
    transformData: u64 = 0, // VkBuffer
    transformOffset: u64 = 0,
};

/// Geometry AABBs data
pub const VkGeometryAABBNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165005),
    pNext: ?*const anyopaque = null,
    aabbData: u64 = 0, // VkBuffer
    numAABBs: u32 = 0,
    stride: u32 = 0,
    offset: u64 = 0,
};

/// Geometry data union
pub const VkGeometryDataNV = extern struct {
    triangles: VkGeometryTrianglesNV = .{},
    aabbs: VkGeometryAABBNV = .{},
};

/// Geometry descriptor
pub const VkGeometryNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165003),
    pNext: ?*const anyopaque = null,
    geometryType: VkGeometryTypeNV = .triangles,
    geometry: VkGeometryDataNV = .{},
    flags: u32 = 0, // VkGeometryFlagsNV
};

/// Acceleration structure info
pub const VkAccelerationStructureInfoNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165012),
    pNext: ?*const anyopaque = null,
    @"type": VkAccelerationStructureTypeNV = .top_level,
    flags: u32 = 0, // VkBuildAccelerationStructureFlagsNV
    instanceCount: u32 = 0,
    geometryCount: u32 = 0,
    pGeometries: ?[*]const VkGeometryNV = null,
};

/// Acceleration structure create info
pub const VkAccelerationStructureCreateInfoNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165001),
    pNext: ?*const anyopaque = null,
    compactedSize: u64 = 0,
    info: VkAccelerationStructureInfoNV = .{},
};

/// Acceleration structure memory requirements info
pub const VkAccelerationStructureMemoryRequirementsInfoNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165008),
    pNext: ?*const anyopaque = null,
    @"type": VkAccelerationStructureMemoryRequirementsTypeNV = .object,
    accelerationStructure: VkAccelerationStructureNV = 0,
};

/// Bind acceleration structure memory info
pub const VkBindAccelerationStructureMemoryInfoNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165006),
    pNext: ?*const anyopaque = null,
    accelerationStructure: VkAccelerationStructureNV = 0,
    memory: u64 = 0, // VkDeviceMemory
    memoryOffset: u64 = 0,
    deviceIndexCount: u32 = 0,
    pDeviceIndices: ?[*]const u32 = null,
};

/// Ray tracing shader group create info
pub const VkRayTracingShaderGroupCreateInfoNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165011),
    pNext: ?*const anyopaque = null,
    @"type": VkRayTracingShaderGroupTypeNV = .general,
    generalShader: u32 = ~@as(u32, 0), // VK_SHADER_UNUSED_NV
    closestHitShader: u32 = ~@as(u32, 0),
    anyHitShader: u32 = ~@as(u32, 0),
    intersectionShader: u32 = ~@as(u32, 0),
};

/// Ray tracing pipeline create info
pub const VkRayTracingPipelineCreateInfoNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000165000),
    pNext: ?*const anyopaque = null,
    flags: u32 = 0, // VkPipelineCreateFlags
    stageCount: u32 = 0,
    pStages: ?*const anyopaque = null, // VkPipelineShaderStageCreateInfo*
    groupCount: u32 = 0,
    pGroups: ?[*]const VkRayTracingShaderGroupCreateInfoNV = null,
    maxRecursionDepth: u32 = 0,
    layout: u64 = 0, // VkPipelineLayout
    basePipelineHandle: u64 = 0, // VkPipeline
    basePipelineIndex: i32 = 0,
};

// =============================================================================
// Function Pointer Types
// =============================================================================

pub const PFN_vkCreateAccelerationStructureNV = *const fn (
    vk.VkDevice,
    *const VkAccelerationStructureCreateInfoNV,
    ?*const anyopaque, // VkAllocationCallbacks
    *VkAccelerationStructureNV,
) callconv(.c) vk.VkResult;

pub const PFN_vkDestroyAccelerationStructureNV = *const fn (
    vk.VkDevice,
    VkAccelerationStructureNV,
    ?*const anyopaque, // VkAllocationCallbacks
) callconv(.c) void;

pub const PFN_vkGetAccelerationStructureMemoryRequirementsNV = *const fn (
    vk.VkDevice,
    *const VkAccelerationStructureMemoryRequirementsInfoNV,
    *anyopaque, // VkMemoryRequirements2*
) callconv(.c) void;

pub const PFN_vkBindAccelerationStructureMemoryNV = *const fn (
    vk.VkDevice,
    u32, // bindInfoCount
    [*]const VkBindAccelerationStructureMemoryInfoNV,
) callconv(.c) vk.VkResult;

pub const PFN_vkCmdBuildAccelerationStructureNV = *const fn (
    vk.VkCommandBuffer,
    *const VkAccelerationStructureInfoNV,
    u64, // instanceData (VkBuffer)
    u64, // instanceOffset
    vk.VkBool32, // update
    VkAccelerationStructureNV, // dst
    VkAccelerationStructureNV, // src
    u64, // scratch (VkBuffer)
    u64, // scratchOffset
) callconv(.c) void;

pub const PFN_vkCmdCopyAccelerationStructureNV = *const fn (
    vk.VkCommandBuffer,
    VkAccelerationStructureNV, // dst
    VkAccelerationStructureNV, // src
    VkCopyAccelerationStructureModeNV,
) callconv(.c) void;

pub const PFN_vkCmdTraceRaysNV = *const fn (
    vk.VkCommandBuffer,
    u64, // raygenShaderBindingTableBuffer
    u64, // raygenShaderBindingOffset
    u64, // missShaderBindingTableBuffer
    u64, // missShaderBindingOffset
    u64, // missShaderBindingStride
    u64, // hitShaderBindingTableBuffer
    u64, // hitShaderBindingOffset
    u64, // hitShaderBindingStride
    u64, // callableShaderBindingTableBuffer
    u64, // callableShaderBindingOffset
    u64, // callableShaderBindingStride
    u32, // width
    u32, // height
    u32, // depth
) callconv(.c) void;

pub const PFN_vkCreateRayTracingPipelinesNV = *const fn (
    vk.VkDevice,
    u64, // pipelineCache
    u32, // createInfoCount
    [*]const VkRayTracingPipelineCreateInfoNV,
    ?*const anyopaque, // VkAllocationCallbacks
    [*]u64, // pPipelines
) callconv(.c) vk.VkResult;

pub const PFN_vkGetRayTracingShaderGroupHandlesNV = *const fn (
    vk.VkDevice,
    u64, // pipeline
    u32, // firstGroup
    u32, // groupCount
    usize, // dataSize
    [*]u8, // pData
) callconv(.c) vk.VkResult;

pub const PFN_vkGetAccelerationStructureHandleNV = *const fn (
    vk.VkDevice,
    VkAccelerationStructureNV,
    usize, // dataSize
    [*]u8, // pData
) callconv(.c) vk.VkResult;

pub const PFN_vkCompileDeferredNV = *const fn (
    vk.VkDevice,
    u64, // pipeline
    u32, // shader
) callconv(.c) vk.VkResult;

// =============================================================================
// Ray Tracing Context
// =============================================================================

pub const RayTracingContext = struct {
    device: vk.VkDevice,
    vkCreateAccelerationStructureNV: ?PFN_vkCreateAccelerationStructureNV = null,
    vkDestroyAccelerationStructureNV: ?PFN_vkDestroyAccelerationStructureNV = null,
    vkGetAccelerationStructureMemoryRequirementsNV: ?PFN_vkGetAccelerationStructureMemoryRequirementsNV = null,
    vkBindAccelerationStructureMemoryNV: ?PFN_vkBindAccelerationStructureMemoryNV = null,
    vkCmdBuildAccelerationStructureNV: ?PFN_vkCmdBuildAccelerationStructureNV = null,
    vkCmdCopyAccelerationStructureNV: ?PFN_vkCmdCopyAccelerationStructureNV = null,
    vkCmdTraceRaysNV: ?PFN_vkCmdTraceRaysNV = null,
    vkCreateRayTracingPipelinesNV: ?PFN_vkCreateRayTracingPipelinesNV = null,
    vkGetRayTracingShaderGroupHandlesNV: ?PFN_vkGetRayTracingShaderGroupHandlesNV = null,
    vkGetAccelerationStructureHandleNV: ?PFN_vkGetAccelerationStructureHandleNV = null,
    vkCompileDeferredNV: ?PFN_vkCompileDeferredNV = null,

    pub fn init(device: vk.VkDevice, getDeviceProcAddr: vk.PFN_vkGetDeviceProcAddr) RayTracingContext {
        return .{
            .device = device,
            .vkCreateAccelerationStructureNV = @ptrCast(getDeviceProcAddr(device, "vkCreateAccelerationStructureNV")),
            .vkDestroyAccelerationStructureNV = @ptrCast(getDeviceProcAddr(device, "vkDestroyAccelerationStructureNV")),
            .vkGetAccelerationStructureMemoryRequirementsNV = @ptrCast(getDeviceProcAddr(device, "vkGetAccelerationStructureMemoryRequirementsNV")),
            .vkBindAccelerationStructureMemoryNV = @ptrCast(getDeviceProcAddr(device, "vkBindAccelerationStructureMemoryNV")),
            .vkCmdBuildAccelerationStructureNV = @ptrCast(getDeviceProcAddr(device, "vkCmdBuildAccelerationStructureNV")),
            .vkCmdCopyAccelerationStructureNV = @ptrCast(getDeviceProcAddr(device, "vkCmdCopyAccelerationStructureNV")),
            .vkCmdTraceRaysNV = @ptrCast(getDeviceProcAddr(device, "vkCmdTraceRaysNV")),
            .vkCreateRayTracingPipelinesNV = @ptrCast(getDeviceProcAddr(device, "vkCreateRayTracingPipelinesNV")),
            .vkGetRayTracingShaderGroupHandlesNV = @ptrCast(getDeviceProcAddr(device, "vkGetRayTracingShaderGroupHandlesNV")),
            .vkGetAccelerationStructureHandleNV = @ptrCast(getDeviceProcAddr(device, "vkGetAccelerationStructureHandleNV")),
            .vkCompileDeferredNV = @ptrCast(getDeviceProcAddr(device, "vkCompileDeferredNV")),
        };
    }

    /// Check if ray tracing is supported
    pub fn isSupported(self: *const RayTracingContext) bool {
        return self.vkCmdTraceRaysNV != null;
    }

    /// Check if acceleration structure operations are supported
    pub fn hasAccelerationStructureSupport(self: *const RayTracingContext) bool {
        return self.vkCreateAccelerationStructureNV != null;
    }

    /// Create an acceleration structure
    pub fn createAccelerationStructure(
        self: *const RayTracingContext,
        create_info: *const VkAccelerationStructureCreateInfoNV,
    ) !VkAccelerationStructureNV {
        const func = self.vkCreateAccelerationStructureNV orelse return error.ExtensionNotPresent;
        var accel_struct: VkAccelerationStructureNV = 0;
        const result = func(self.device, create_info, null, &accel_struct);
        if (result != .success) return error.AccelerationStructureCreationFailed;
        return accel_struct;
    }

    /// Destroy an acceleration structure
    pub fn destroyAccelerationStructure(
        self: *const RayTracingContext,
        accel_struct: VkAccelerationStructureNV,
    ) void {
        const func = self.vkDestroyAccelerationStructureNV orelse return;
        func(self.device, accel_struct, null);
    }

    /// Build acceleration structure
    pub fn buildAccelerationStructure(
        self: *const RayTracingContext,
        cmd: vk.VkCommandBuffer,
        info: *const VkAccelerationStructureInfoNV,
        instance_data: u64,
        instance_offset: u64,
        update: bool,
        dst: VkAccelerationStructureNV,
        src: VkAccelerationStructureNV,
        scratch: u64,
        scratch_offset: u64,
    ) !void {
        const func = self.vkCmdBuildAccelerationStructureNV orelse return error.ExtensionNotPresent;
        func(
            cmd,
            info,
            instance_data,
            instance_offset,
            if (update) vk.VK_TRUE else vk.VK_FALSE,
            dst,
            src,
            scratch,
            scratch_offset,
        );
    }

    /// Copy acceleration structure
    pub fn copyAccelerationStructure(
        self: *const RayTracingContext,
        cmd: vk.VkCommandBuffer,
        dst: VkAccelerationStructureNV,
        src: VkAccelerationStructureNV,
        mode: VkCopyAccelerationStructureModeNV,
    ) !void {
        const func = self.vkCmdCopyAccelerationStructureNV orelse return error.ExtensionNotPresent;
        func(cmd, dst, src, mode);
    }

    /// Trace rays
    pub fn traceRays(
        self: *const RayTracingContext,
        cmd: vk.VkCommandBuffer,
        sbt: ShaderBindingTable,
        width: u32,
        height: u32,
        depth: u32,
    ) !void {
        const func = self.vkCmdTraceRaysNV orelse return error.ExtensionNotPresent;
        func(
            cmd,
            sbt.raygen_buffer,
            sbt.raygen_offset,
            sbt.miss_buffer,
            sbt.miss_offset,
            sbt.miss_stride,
            sbt.hit_buffer,
            sbt.hit_offset,
            sbt.hit_stride,
            sbt.callable_buffer,
            sbt.callable_offset,
            sbt.callable_stride,
            width,
            height,
            depth,
        );
    }
};

/// Shader binding table descriptor for ray tracing dispatch
pub const ShaderBindingTable = struct {
    raygen_buffer: u64 = 0,
    raygen_offset: u64 = 0,
    miss_buffer: u64 = 0,
    miss_offset: u64 = 0,
    miss_stride: u64 = 0,
    hit_buffer: u64 = 0,
    hit_offset: u64 = 0,
    hit_stride: u64 = 0,
    callable_buffer: u64 = 0,
    callable_offset: u64 = 0,
    callable_stride: u64 = 0,

    /// Create SBT with all groups in a single buffer
    pub fn fromSingleBuffer(
        buffer: u64,
        raygen_offset: u64,
        miss_offset: u64,
        miss_stride: u64,
        hit_offset: u64,
        hit_stride: u64,
    ) ShaderBindingTable {
        return .{
            .raygen_buffer = buffer,
            .raygen_offset = raygen_offset,
            .miss_buffer = buffer,
            .miss_offset = miss_offset,
            .miss_stride = miss_stride,
            .hit_buffer = buffer,
            .hit_offset = hit_offset,
            .hit_stride = hit_stride,
        };
    }
};

/// Ray tracing properties for query
pub const RayTracingProperties = struct {
    shader_group_handle_size: u32,
    max_recursion_depth: u32,
    max_shader_group_stride: u32,
    shader_group_base_alignment: u32,
    max_geometry_count: u64,
    max_instance_count: u64,
    max_triangle_count: u64,
    max_descriptor_set_acceleration_structures: u32,

    pub fn fromVk(props: VkPhysicalDeviceRayTracingPropertiesNV) RayTracingProperties {
        return .{
            .shader_group_handle_size = props.shaderGroupHandleSize,
            .max_recursion_depth = props.maxRecursionDepth,
            .max_shader_group_stride = props.maxShaderGroupStride,
            .shader_group_base_alignment = props.shaderGroupBaseAlignment,
            .max_geometry_count = props.maxGeometryCount,
            .max_instance_count = props.maxInstanceCount,
            .max_triangle_count = props.maxTriangleCount,
            .max_descriptor_set_acceleration_structures = props.maxDescriptorSetAccelerationStructures,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "shader stage bits" {
    // Verify ray tracing stage bits are in expected range
    try std.testing.expect(VK_SHADER_STAGE_RAYGEN_BIT_NV >= 0x100);
    try std.testing.expect(VK_SHADER_STAGE_CALLABLE_BIT_NV <= 0x10000);
}

test "ShaderBindingTable from single buffer" {
    const sbt = ShaderBindingTable.fromSingleBuffer(
        0x10000, // buffer
        0, // raygen offset
        32, // miss offset
        32, // miss stride
        64, // hit offset
        32, // hit stride
    );

    try std.testing.expectEqual(@as(u64, 0x10000), sbt.raygen_buffer);
    try std.testing.expectEqual(@as(u64, 0x10000), sbt.miss_buffer);
    try std.testing.expectEqual(@as(u64, 0x10000), sbt.hit_buffer);
    try std.testing.expectEqual(@as(u64, 32), sbt.miss_offset);
    try std.testing.expectEqual(@as(u64, 64), sbt.hit_offset);
}
