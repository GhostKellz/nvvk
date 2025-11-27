//! VK_NV_device_diagnostic_checkpoints & VK_NV_device_diagnostics_config
//!
//! Provides GPU crash diagnostics and debugging capabilities:
//! - Command buffer checkpoints for locating GPU hangs
//! - Automatic checkpoint insertion
//! - Shader debug info and error reporting
//! - Resource tracking for debugging
//!
//! Requires NVIDIA driver 535+ and respective extensions.

const std = @import("std");
const vk = @import("vulkan.zig");

/// Diagnostic checkpoint context
pub const DiagnosticsContext = struct {
    device: vk.VkDevice,
    dispatch: *const vk.DeviceDispatch,

    pub fn init(device: vk.VkDevice, dispatch: *const vk.DeviceDispatch) DiagnosticsContext {
        return .{
            .device = device,
            .dispatch = dispatch,
        };
    }

    /// Check if diagnostic checkpoints are available
    pub fn isSupported(self: *const DiagnosticsContext) bool {
        return self.dispatch.hasDiagnosticCheckpoints();
    }

    /// Insert a checkpoint marker into a command buffer
    /// The marker pointer can be retrieved after a GPU hang to identify where execution stopped
    pub fn setCheckpoint(self: *const DiagnosticsContext, cmd: vk.VkCommandBuffer, marker: ?*const anyopaque) void {
        const func = self.dispatch.vkCmdSetCheckpointNV orelse return;
        func(cmd, marker);
    }

    /// Set checkpoint with a tagged marker
    pub fn setTaggedCheckpoint(self: *const DiagnosticsContext, cmd: vk.VkCommandBuffer, tag: CheckpointTag) void {
        self.setCheckpoint(cmd, @ptrFromInt(@intFromEnum(tag)));
    }

    /// Get checkpoint data from a queue after a hang
    pub fn getCheckpoints(self: *const DiagnosticsContext, queue: vk.VkQueue, allocator: std.mem.Allocator) vk.VulkanError![]CheckpointData {
        const func = self.dispatch.vkGetQueueCheckpointDataNV orelse return vk.VulkanError.ExtensionNotPresent;

        // Get count
        var count: u32 = 0;
        func(queue, &count, null);

        if (count == 0) {
            return &[_]CheckpointData{};
        }

        // Allocate and get data
        const vk_checkpoints = try allocator.alloc(vk.VkCheckpointDataNV, count);
        defer allocator.free(vk_checkpoints);

        // Initialize sType
        for (vk_checkpoints) |*c| {
            c.* = .{};
        }

        func(queue, &count, vk_checkpoints.ptr);

        // Convert to our type
        const checkpoints = try allocator.alloc(CheckpointData, count);
        for (vk_checkpoints, 0..) |c, i| {
            checkpoints[i] = CheckpointData.fromVk(c);
        }

        return checkpoints;
    }
};

/// Predefined checkpoint tags for common locations
pub const CheckpointTag = enum(usize) {
    frame_start = 0x1000,
    frame_end = 0x1001,
    draw_start = 0x2000,
    draw_end = 0x2001,
    compute_start = 0x3000,
    compute_end = 0x3001,
    transfer_start = 0x4000,
    transfer_end = 0x4001,
    render_pass_begin = 0x5000,
    render_pass_end = 0x5001,
    pipeline_bind = 0x6000,
    descriptor_bind = 0x6001,
    vertex_bind = 0x6002,
    index_bind = 0x6003,
    push_constants = 0x6004,
    barrier = 0x7000,
    clear = 0x7001,
    copy = 0x7002,
    blit = 0x7003,
    resolve = 0x7004,
    query_begin = 0x8000,
    query_end = 0x8001,
    timestamp = 0x8002,
    debug_marker_begin = 0x9000,
    debug_marker_end = 0x9001,
    _,

    pub fn fromPtr(ptr: ?*anyopaque) ?CheckpointTag {
        if (ptr) |p| {
            const val = @intFromPtr(p);
            return std.meta.intToEnum(CheckpointTag, val) catch null;
        }
        return null;
    }

    pub fn name(self: CheckpointTag) []const u8 {
        return switch (self) {
            .frame_start => "Frame Start",
            .frame_end => "Frame End",
            .draw_start => "Draw Start",
            .draw_end => "Draw End",
            .compute_start => "Compute Start",
            .compute_end => "Compute End",
            .transfer_start => "Transfer Start",
            .transfer_end => "Transfer End",
            .render_pass_begin => "Render Pass Begin",
            .render_pass_end => "Render Pass End",
            .pipeline_bind => "Pipeline Bind",
            .descriptor_bind => "Descriptor Bind",
            .vertex_bind => "Vertex Buffer Bind",
            .index_bind => "Index Buffer Bind",
            .push_constants => "Push Constants",
            .barrier => "Barrier",
            .clear => "Clear",
            .copy => "Copy",
            .blit => "Blit",
            .resolve => "Resolve",
            .query_begin => "Query Begin",
            .query_end => "Query End",
            .timestamp => "Timestamp",
            .debug_marker_begin => "Debug Marker Begin",
            .debug_marker_end => "Debug Marker End",
            _ => "Unknown",
        };
    }
};

/// Checkpoint data retrieved after a GPU hang
pub const CheckpointData = struct {
    stage: PipelineStage,
    marker: ?*anyopaque,
    tag: ?CheckpointTag,

    pub fn fromVk(c: vk.VkCheckpointDataNV) CheckpointData {
        return .{
            .stage = PipelineStage.fromFlags(c.stage),
            .marker = c.pCheckpointMarker,
            .tag = CheckpointTag.fromPtr(c.pCheckpointMarker),
        };
    }
};

/// Pipeline stage where checkpoint was recorded
pub const PipelineStage = enum {
    top_of_pipe,
    draw_indirect,
    vertex_input,
    vertex_shader,
    tessellation_control,
    tessellation_evaluation,
    geometry_shader,
    fragment_shader,
    early_fragment_tests,
    late_fragment_tests,
    color_attachment_output,
    compute_shader,
    transfer,
    bottom_of_pipe,
    host,
    all_graphics,
    all_commands,
    unknown,

    pub fn fromFlags(flags: vk.VkPipelineStageFlags) PipelineStage {
        if (flags & vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT != 0) return .compute_shader;
        if (flags & vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT != 0) return .fragment_shader;
        if (flags & vk.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT != 0) return .vertex_shader;
        if (flags & vk.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT != 0) return .vertex_input;
        if (flags & vk.VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT != 0) return .draw_indirect;
        if (flags & vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT != 0) return .top_of_pipe;
        if (flags & vk.VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT != 0) return .all_graphics;
        if (flags & vk.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT != 0) return .all_commands;
        return .unknown;
    }

    pub fn name(self: PipelineStage) []const u8 {
        return switch (self) {
            .top_of_pipe => "Top of Pipe",
            .draw_indirect => "Draw Indirect",
            .vertex_input => "Vertex Input",
            .vertex_shader => "Vertex Shader",
            .tessellation_control => "Tessellation Control",
            .tessellation_evaluation => "Tessellation Evaluation",
            .geometry_shader => "Geometry Shader",
            .fragment_shader => "Fragment Shader",
            .early_fragment_tests => "Early Fragment Tests",
            .late_fragment_tests => "Late Fragment Tests",
            .color_attachment_output => "Color Attachment Output",
            .compute_shader => "Compute Shader",
            .transfer => "Transfer",
            .bottom_of_pipe => "Bottom of Pipe",
            .host => "Host",
            .all_graphics => "All Graphics",
            .all_commands => "All Commands",
            .unknown => "Unknown",
        };
    }
};

/// Configuration for device diagnostics
pub const DiagnosticsConfig = struct {
    enable_shader_debug_info: bool = false,
    enable_resource_tracking: bool = false,
    enable_automatic_checkpoints: bool = false,
    enable_shader_error_reporting: bool = false,

    /// Full diagnostics (all features enabled)
    pub fn full() DiagnosticsConfig {
        return .{
            .enable_shader_debug_info = true,
            .enable_resource_tracking = true,
            .enable_automatic_checkpoints = true,
            .enable_shader_error_reporting = true,
        };
    }

    /// Minimal overhead (only automatic checkpoints)
    pub fn minimal() DiagnosticsConfig {
        return .{
            .enable_automatic_checkpoints = true,
        };
    }

    /// Convert to Vulkan flags
    pub fn toFlags(self: DiagnosticsConfig) vk.VkDeviceDiagnosticsConfigFlagsNV {
        var flags: vk.VkDeviceDiagnosticsConfigFlagsNV = 0;
        if (self.enable_shader_debug_info) {
            flags |= vk.VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_SHADER_DEBUG_INFO_BIT_NV;
        }
        if (self.enable_resource_tracking) {
            flags |= vk.VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_RESOURCE_TRACKING_BIT_NV;
        }
        if (self.enable_automatic_checkpoints) {
            flags |= vk.VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_AUTOMATIC_CHECKPOINTS_BIT_NV;
        }
        if (self.enable_shader_error_reporting) {
            flags |= vk.VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_SHADER_ERROR_REPORTING_BIT_NV;
        }
        return flags;
    }

    /// Create Vulkan structure for device creation pNext chain
    pub fn toVkStruct(self: DiagnosticsConfig) vk.VkDeviceDiagnosticsConfigCreateInfoNV {
        return .{
            .flags = self.toFlags(),
        };
    }
};

/// GPU crash dump format for serialization
pub const CrashDump = struct {
    timestamp_ns: i128,
    checkpoints: []CheckpointData,
    last_stage: PipelineStage,
    last_tag: ?CheckpointTag,

    pub fn generate(ctx: *const DiagnosticsContext, queue: vk.VkQueue, allocator: std.mem.Allocator) vk.VulkanError!CrashDump {
        const checkpoints = try ctx.getCheckpoints(queue, allocator);

        var last_stage = PipelineStage.unknown;
        var last_tag: ?CheckpointTag = null;

        if (checkpoints.len > 0) {
            const last = checkpoints[checkpoints.len - 1];
            last_stage = last.stage;
            last_tag = last.tag;
        }

        return .{
            .timestamp_ns = std.time.nanoTimestamp(),
            .checkpoints = checkpoints,
            .last_stage = last_stage,
            .last_tag = last_tag,
        };
    }

    pub fn deinit(self: *CrashDump, allocator: std.mem.Allocator) void {
        allocator.free(self.checkpoints);
    }

    /// Format crash dump as human-readable string
    pub fn format(self: *const CrashDump, allocator: std.mem.Allocator) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);
        const writer = list.writer();

        try writer.print("=== NVVK GPU Crash Dump ===\n", .{});
        try writer.print("Timestamp: {d} ns\n", .{self.timestamp_ns});
        try writer.print("Last Stage: {s}\n", .{self.last_stage.name()});
        if (self.last_tag) |tag| {
            try writer.print("Last Tag: {s}\n", .{tag.name()});
        }
        try writer.print("\nCheckpoints ({d}):\n", .{self.checkpoints.len});

        for (self.checkpoints, 0..) |cp, i| {
            try writer.print("  [{d}] Stage: {s}", .{ i, cp.stage.name() });
            if (cp.tag) |tag| {
                try writer.print(", Tag: {s}", .{tag.name()});
            }
            if (cp.marker) |m| {
                try writer.print(", Marker: 0x{x}", .{@intFromPtr(m)});
            }
            try writer.print("\n", .{});
        }

        return list.toOwnedSlice();
    }

    /// Write crash dump to file
    pub fn writeToFile(self: *const CrashDump, path: []const u8, allocator: std.mem.Allocator) !void {
        const formatted = try self.format(allocator);
        defer allocator.free(formatted);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(formatted);
    }
};

// =============================================================================
// Tests
// =============================================================================

test "DiagnosticsConfig flags" {
    const full = DiagnosticsConfig.full();
    const flags = full.toFlags();

    try std.testing.expect(flags & vk.VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_SHADER_DEBUG_INFO_BIT_NV != 0);
    try std.testing.expect(flags & vk.VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_RESOURCE_TRACKING_BIT_NV != 0);
    try std.testing.expect(flags & vk.VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_AUTOMATIC_CHECKPOINTS_BIT_NV != 0);
    try std.testing.expect(flags & vk.VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_SHADER_ERROR_REPORTING_BIT_NV != 0);

    const minimal = DiagnosticsConfig.minimal();
    const min_flags = minimal.toFlags();
    try std.testing.expectEqual(vk.VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_AUTOMATIC_CHECKPOINTS_BIT_NV, min_flags);
}

test "CheckpointTag conversion" {
    const tag = CheckpointTag.frame_start;
    const ptr: ?*anyopaque = @ptrFromInt(@intFromEnum(tag));

    const recovered = CheckpointTag.fromPtr(ptr);
    try std.testing.expectEqual(tag, recovered.?);
    try std.testing.expectEqualStrings("Frame Start", tag.name());
}

test "PipelineStage from flags" {
    const compute = PipelineStage.fromFlags(vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);
    try std.testing.expectEqual(PipelineStage.compute_shader, compute);

    const fragment = PipelineStage.fromFlags(vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
    try std.testing.expectEqual(PipelineStage.fragment_shader, fragment);
}
