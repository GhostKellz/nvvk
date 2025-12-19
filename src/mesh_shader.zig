//! VK_NV_mesh_shader Extension Wrapper
//!
//! Provides mesh and task shader support for NVIDIA GPUs.
//! Mesh shaders replace the traditional vertex/geometry pipeline with a more
//! flexible compute-like model for geometry processing.
//!
//! Pipeline: Task Shader (optional) -> Mesh Shader -> Fragment Shader
//!
//! Benefits:
//! - GPU-driven culling and LOD selection
//! - Reduced CPU overhead for complex geometry
//! - Better utilization of GPU compute units
//!
//! Note: VK_EXT_mesh_shader is the cross-vendor successor, but VK_NV_mesh_shader
//! is still useful for NVIDIA-specific optimizations and older drivers.
//!
//! Requires NVIDIA driver 590+ and VK_NV_mesh_shader extension.

const std = @import("std");
const vk = @import("vulkan.zig");

// =============================================================================
// Extension Constants
// =============================================================================

pub const VK_NV_MESH_SHADER_EXTENSION_NAME = "VK_NV_mesh_shader";
pub const VK_NV_MESH_SHADER_SPEC_VERSION: u32 = 1;

// Shader stage bits
pub const VK_SHADER_STAGE_TASK_BIT_NV: u32 = 0x00000040;
pub const VK_SHADER_STAGE_MESH_BIT_NV: u32 = 0x00000080;

// Pipeline stage bits
pub const VK_PIPELINE_STAGE_TASK_SHADER_BIT_NV: u32 = 0x00080000;
pub const VK_PIPELINE_STAGE_MESH_SHADER_BIT_NV: u32 = 0x00100000;

// =============================================================================
// Types
// =============================================================================

/// Physical device mesh shader features
pub const VkPhysicalDeviceMeshShaderFeaturesNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000202000),
    pNext: ?*anyopaque = null,
    taskShader: vk.VkBool32 = vk.VK_FALSE,
    meshShader: vk.VkBool32 = vk.VK_FALSE,
};

/// Physical device mesh shader properties
pub const VkPhysicalDeviceMeshShaderPropertiesNV = extern struct {
    sType: vk.VkStructureType = @enumFromInt(1000202001),
    pNext: ?*anyopaque = null,
    maxDrawMeshTasksCount: u32 = 0,
    maxTaskWorkGroupInvocations: u32 = 0,
    maxTaskWorkGroupSize: [3]u32 = .{ 0, 0, 0 },
    maxTaskTotalMemorySize: u32 = 0,
    maxTaskOutputCount: u32 = 0,
    maxMeshWorkGroupInvocations: u32 = 0,
    maxMeshWorkGroupSize: [3]u32 = .{ 0, 0, 0 },
    maxMeshTotalMemorySize: u32 = 0,
    maxMeshOutputVertices: u32 = 0,
    maxMeshOutputPrimitives: u32 = 0,
    maxMeshMultiviewViewCount: u32 = 0,
    meshOutputPerVertexGranularity: u32 = 0,
    meshOutputPerPrimitiveGranularity: u32 = 0,
};

/// Draw mesh tasks indirect command
pub const VkDrawMeshTasksIndirectCommandNV = extern struct {
    taskCount: u32 = 0,
    firstTask: u32 = 0,
};

// =============================================================================
// Function Pointer Types
// =============================================================================

pub const PFN_vkCmdDrawMeshTasksNV = *const fn (
    vk.VkCommandBuffer,
    u32, // taskCount
    u32, // firstTask
) callconv(.c) void;

// VkBuffer is a non-dispatchable handle (u64)
pub const VkBuffer = u64;

pub const PFN_vkCmdDrawMeshTasksIndirectNV = *const fn (
    vk.VkCommandBuffer,
    VkBuffer,
    u64, // offset
    u32, // drawCount
    u32, // stride
) callconv(.c) void;

pub const PFN_vkCmdDrawMeshTasksIndirectCountNV = *const fn (
    vk.VkCommandBuffer,
    VkBuffer, // buffer
    u64, // offset
    VkBuffer, // countBuffer
    u64, // countBufferOffset
    u32, // maxDrawCount
    u32, // stride
) callconv(.c) void;

// =============================================================================
// Mesh Shader Context
// =============================================================================

pub const MeshShaderContext = struct {
    device: vk.VkDevice,
    vkCmdDrawMeshTasksNV: ?PFN_vkCmdDrawMeshTasksNV = null,
    vkCmdDrawMeshTasksIndirectNV: ?PFN_vkCmdDrawMeshTasksIndirectNV = null,
    vkCmdDrawMeshTasksIndirectCountNV: ?PFN_vkCmdDrawMeshTasksIndirectCountNV = null,

    pub fn init(device: vk.VkDevice, getDeviceProcAddr: vk.PFN_vkGetDeviceProcAddr) MeshShaderContext {
        return .{
            .device = device,
            .vkCmdDrawMeshTasksNV = @ptrCast(getDeviceProcAddr(device, "vkCmdDrawMeshTasksNV")),
            .vkCmdDrawMeshTasksIndirectNV = @ptrCast(getDeviceProcAddr(device, "vkCmdDrawMeshTasksIndirectNV")),
            .vkCmdDrawMeshTasksIndirectCountNV = @ptrCast(getDeviceProcAddr(device, "vkCmdDrawMeshTasksIndirectCountNV")),
        };
    }

    /// Check if mesh shaders are supported
    pub fn isSupported(self: *const MeshShaderContext) bool {
        return self.vkCmdDrawMeshTasksNV != null;
    }

    /// Check if indirect drawing is supported
    pub fn hasIndirectSupport(self: *const MeshShaderContext) bool {
        return self.vkCmdDrawMeshTasksIndirectNV != null;
    }

    /// Check if indirect count drawing is supported
    pub fn hasIndirectCountSupport(self: *const MeshShaderContext) bool {
        return self.vkCmdDrawMeshTasksIndirectCountNV != null;
    }

    /// Draw mesh tasks directly
    ///
    /// Parameters:
    ///   cmd - Command buffer to record into
    ///   task_count - Number of task shader workgroups to dispatch
    ///   first_task - First task index (usually 0)
    pub fn drawMeshTasks(
        self: *const MeshShaderContext,
        cmd: vk.VkCommandBuffer,
        task_count: u32,
        first_task: u32,
    ) !void {
        const func = self.vkCmdDrawMeshTasksNV orelse return error.ExtensionNotPresent;
        func(cmd, task_count, first_task);
    }

    /// Draw mesh tasks with parameters from a buffer
    ///
    /// Parameters:
    ///   cmd - Command buffer
    ///   buffer - Buffer containing VkDrawMeshTasksIndirectCommandNV structs
    ///   offset - Byte offset into buffer
    ///   draw_count - Number of draws
    ///   stride - Byte stride between commands
    pub fn drawMeshTasksIndirect(
        self: *const MeshShaderContext,
        cmd: vk.VkCommandBuffer,
        buffer: VkBuffer,
        offset: u64,
        draw_count: u32,
        stride: u32,
    ) !void {
        const func = self.vkCmdDrawMeshTasksIndirectNV orelse return error.ExtensionNotPresent;
        func(cmd, buffer, offset, draw_count, stride);
    }

    /// Draw mesh tasks with count from a buffer (GPU-driven rendering)
    ///
    /// The actual draw count is read from count_buffer at runtime,
    /// allowing fully GPU-driven culling and draw submission.
    pub fn drawMeshTasksIndirectCount(
        self: *const MeshShaderContext,
        cmd: vk.VkCommandBuffer,
        buffer: VkBuffer,
        offset: u64,
        count_buffer: VkBuffer,
        count_offset: u64,
        max_draw_count: u32,
        stride: u32,
    ) !void {
        const func = self.vkCmdDrawMeshTasksIndirectCountNV orelse return error.ExtensionNotPresent;
        func(cmd, buffer, offset, count_buffer, count_offset, max_draw_count, stride);
    }
};

/// Mesh shader properties for query
pub const MeshShaderProperties = struct {
    max_draw_mesh_tasks_count: u32,
    max_task_work_group_invocations: u32,
    max_task_work_group_size: [3]u32,
    max_task_total_memory_size: u32,
    max_task_output_count: u32,
    max_mesh_work_group_invocations: u32,
    max_mesh_work_group_size: [3]u32,
    max_mesh_total_memory_size: u32,
    max_mesh_output_vertices: u32,
    max_mesh_output_primitives: u32,
    max_mesh_multiview_view_count: u32,

    pub fn fromVk(props: VkPhysicalDeviceMeshShaderPropertiesNV) MeshShaderProperties {
        return .{
            .max_draw_mesh_tasks_count = props.maxDrawMeshTasksCount,
            .max_task_work_group_invocations = props.maxTaskWorkGroupInvocations,
            .max_task_work_group_size = props.maxTaskWorkGroupSize,
            .max_task_total_memory_size = props.maxTaskTotalMemorySize,
            .max_task_output_count = props.maxTaskOutputCount,
            .max_mesh_work_group_invocations = props.maxMeshWorkGroupInvocations,
            .max_mesh_work_group_size = props.maxMeshWorkGroupSize,
            .max_mesh_total_memory_size = props.maxMeshTotalMemorySize,
            .max_mesh_output_vertices = props.maxMeshOutputVertices,
            .max_mesh_output_primitives = props.maxMeshOutputPrimitives,
            .max_mesh_multiview_view_count = props.maxMeshMultiviewViewCount,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "VkDrawMeshTasksIndirectCommandNV size" {
    // Must be 8 bytes for proper buffer alignment
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(VkDrawMeshTasksIndirectCommandNV));
}

test "shader stage bits" {
    // Verify stage bits don't overlap with standard stages
    try std.testing.expect(VK_SHADER_STAGE_TASK_BIT_NV & 0x3F == 0);
    try std.testing.expect(VK_SHADER_STAGE_MESH_BIT_NV & 0x3F == 0);
}
