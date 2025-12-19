//! Motion Vector Extraction
//!
//! Wraps VK_NV_optical_flow for motion vector generation.
//! Used by frame generation to estimate per-pixel motion between frames.
//!
//! Motion vectors are in screen-space pixel coordinates, encoded as
//! signed 16-bit fixed-point (S10.5 format).

const std = @import("std");
const vk = @import("vulkan.zig");
const optical_flow = @import("optical_flow.zig");

// =============================================================================
// Types
// =============================================================================

/// Motion vector buffer containing flow data
pub const MotionVectorBuffer = struct {
    /// Forward flow (frame N-1 -> frame N)
    forward: vk.VkImage,
    forward_view: vk.VkImageView,
    forward_memory: vk.VkDeviceMemory,

    /// Backward flow (frame N -> frame N-1), optional for quality modes
    backward: ?vk.VkImage = null,
    backward_view: ?vk.VkImageView = null,
    backward_memory: ?vk.VkDeviceMemory = null,

    /// Cost map for confidence weighting
    cost: ?vk.VkImage = null,
    cost_view: ?vk.VkImageView = null,
    cost_memory: ?vk.VkDeviceMemory = null,

    width: u32,
    height: u32,
    grid_size: optical_flow.GridSize,
};

/// Motion vector extraction context
pub const MotionVectorContext = struct {
    device: vk.VkDevice,
    allocator: std.mem.Allocator,

    // Optical flow session
    flow_ctx: ?optical_flow.OpticalFlowContext,

    // Motion vector output buffers
    mv_buffer: ?MotionVectorBuffer,

    // Frame history ring buffer (last 2 frames)
    frame_history: [2]?FrameImage,
    current_frame_idx: u8,

    // Configuration
    config: MotionVectorConfig,

    // Dispatch table
    dispatch: ?*const vk.DeviceDispatch,

    pub const FrameImage = struct {
        image: vk.VkImage,
        view: vk.VkImageView,
        memory: vk.VkDeviceMemory,
        width: u32,
        height: u32,
    };

    /// Initialize motion vector context
    pub fn init(
        device: vk.VkDevice,
        config: MotionVectorConfig,
        dispatch: ?*const vk.DeviceDispatch,
        allocator: std.mem.Allocator,
    ) MotionVectorContext {
        return .{
            .device = device,
            .allocator = allocator,
            .flow_ctx = null,
            .mv_buffer = null,
            .frame_history = .{ null, null },
            .current_frame_idx = 0,
            .config = config,
            .dispatch = dispatch,
        };
    }

    /// Check if optical flow is supported
    pub fn isSupported(self: *const MotionVectorContext) bool {
        if (self.flow_ctx) |ctx| {
            return ctx.vkCmdOpticalFlowExecuteNV != null;
        }
        return false;
    }

    /// Push a new frame into the history buffer
    /// Returns true if we have enough frames to compute motion vectors
    pub fn pushFrame(self: *MotionVectorContext, frame: FrameImage) bool {
        self.frame_history[self.current_frame_idx] = frame;
        self.current_frame_idx = (self.current_frame_idx + 1) % 2;

        // Need at least 2 frames for motion estimation
        return self.frame_history[0] != null and self.frame_history[1] != null;
    }

    /// Execute motion vector estimation
    /// Requires at least 2 frames in history
    pub fn execute(
        self: *MotionVectorContext,
        cmd: vk.VkCommandBuffer,
    ) !void {
        const flow = &(self.flow_ctx orelse return error.NotInitialized);

        // Get current and previous frame
        const prev_idx = (self.current_frame_idx + 1) % 2;
        const prev_frame = self.frame_history[prev_idx] orelse return error.InsufficientFrames;
        const curr_frame = self.frame_history[self.current_frame_idx] orelse return error.InsufficientFrames;

        // Bind input frames
        try flow.bindImage(
            .input,
            curr_frame.view,
            vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        );
        try flow.bindImage(
            .reference,
            prev_frame.view,
            vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        );

        // Bind output
        if (self.mv_buffer) |mvb| {
            try flow.bindImage(
                .flow_vector,
                mvb.forward_view,
                vk.VK_IMAGE_LAYOUT_GENERAL,
            );

            // Bind backward flow if enabled
            if (mvb.backward_view) |bv| {
                try flow.bindImage(
                    .backward_flow_vector,
                    bv,
                    vk.VK_IMAGE_LAYOUT_GENERAL,
                );
            }

            // Bind cost map if enabled
            if (mvb.cost_view) |cv| {
                try flow.bindImage(
                    .cost,
                    cv,
                    vk.VK_IMAGE_LAYOUT_GENERAL,
                );
            }
        }

        // Execute optical flow
        flow.execute(cmd, null, .{});
    }

    /// Get the computed motion vectors
    pub fn getMotionVectors(self: *const MotionVectorContext) ?*const MotionVectorBuffer {
        return if (self.mv_buffer) |*mvb| mvb else null;
    }

    /// Get previous frame image
    pub fn getPreviousFrame(self: *const MotionVectorContext) ?FrameImage {
        const prev_idx = (self.current_frame_idx + 1) % 2;
        return self.frame_history[prev_idx];
    }

    /// Get current frame image
    pub fn getCurrentFrame(self: *const MotionVectorContext) ?FrameImage {
        return self.frame_history[self.current_frame_idx];
    }

    /// Cleanup resources
    pub fn deinit(self: *MotionVectorContext) void {
        if (self.flow_ctx) |*ctx| {
            ctx.deinit();
        }
        // Note: Caller is responsible for destroying images/memory
    }
};

/// Configuration for motion vector extraction
pub const MotionVectorConfig = struct {
    width: u32,
    height: u32,
    grid_size: optical_flow.GridSize = .@"4x4",
    performance: optical_flow.PerformanceLevel = .fast,
    bidirectional: bool = false,
    enable_cost: bool = false,
};

// =============================================================================
// Utility Functions
// =============================================================================

/// Calculate motion vector buffer dimensions based on grid size
pub fn calculateMVDimensions(
    width: u32,
    height: u32,
    grid_size: optical_flow.GridSize,
) struct { width: u32, height: u32 } {
    const divisor: u32 = switch (grid_size) {
        .@"1x1" => 1,
        .@"2x2" => 2,
        .@"4x4" => 4,
        .@"8x8" => 8,
        .unknown => 4,
    };

    return .{
        .width = (width + divisor - 1) / divisor,
        .height = (height + divisor - 1) / divisor,
    };
}

/// Convert S10.5 fixed-point to float
pub fn s10_5ToFloat(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) / 32.0;
}

/// Convert float to S10.5 fixed-point
pub fn floatToS10_5(value: f32) i16 {
    return @intFromFloat(value * 32.0);
}

// =============================================================================
// Tests
// =============================================================================

test "calculateMVDimensions" {
    const dim_4x4 = calculateMVDimensions(1920, 1080, .@"4x4");
    try std.testing.expectEqual(@as(u32, 480), dim_4x4.width);
    try std.testing.expectEqual(@as(u32, 270), dim_4x4.height);

    const dim_2x2 = calculateMVDimensions(1920, 1080, .@"2x2");
    try std.testing.expectEqual(@as(u32, 960), dim_2x2.width);
    try std.testing.expectEqual(@as(u32, 540), dim_2x2.height);

    const dim_8x8 = calculateMVDimensions(1920, 1080, .@"8x8");
    try std.testing.expectEqual(@as(u32, 240), dim_8x8.width);
    try std.testing.expectEqual(@as(u32, 135), dim_8x8.height);
}

test "s10_5 conversion" {
    // Test positive values
    try std.testing.expectApproxEqRel(@as(f32, 1.0), s10_5ToFloat(32), 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.5), s10_5ToFloat(16), 0.001);

    // Test negative values
    try std.testing.expectApproxEqRel(@as(f32, -1.0), s10_5ToFloat(-32), 0.001);

    // Round trip
    try std.testing.expectEqual(@as(i16, 32), floatToS10_5(1.0));
    try std.testing.expectEqual(@as(i16, -32), floatToS10_5(-1.0));
}

test "MotionVectorConfig defaults" {
    const config = MotionVectorConfig{
        .width = 1920,
        .height = 1080,
    };
    try std.testing.expectEqual(optical_flow.GridSize.@"4x4", config.grid_size);
    try std.testing.expectEqual(optical_flow.PerformanceLevel.fast, config.performance);
    try std.testing.expect(!config.bidirectional);
    try std.testing.expect(!config.enable_cost);
}
