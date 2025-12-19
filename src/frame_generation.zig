//! Frame Generation
//!
//! Main orchestration module for DLSS Frame Generation alternative.
//! Combines optical flow motion estimation with frame synthesis to
//! generate intermediate frames, effectively doubling frame rate.
//!
//! Pipeline:
//! 1. Push current frame to history
//! 2. Execute optical flow (motion vectors)
//! 3. Synthesize intermediate frame (warp + blend)
//! 4. Present: real -> generated -> real -> generated...
//!
//! Requires NVIDIA driver 590+ and VK_NV_optical_flow extension.

const std = @import("std");
const vk = @import("vulkan.zig");
const optical_flow = @import("optical_flow.zig");
const motion_vectors = @import("motion_vectors.zig");
const frame_synthesis = @import("frame_synthesis.zig");
const low_latency = @import("low_latency.zig");

/// Get current time in microseconds using monotonic clock
fn getTimeMicros() i128 {
    const ts = std.posix.clock_gettime(.MONOTONIC) catch return 0;
    return @as(i128, @intCast(ts.sec)) * 1_000_000 + @as(i128, @intCast(ts.nsec)) / 1000;
}

// =============================================================================
// Types
// =============================================================================

/// Frame generation mode
pub const FrameGenMode = enum {
    /// Disabled - pass through frames unchanged
    off,
    /// Performance - fast linear blend, ~1ms overhead
    performance,
    /// Balanced - bidirectional warp, ~2ms overhead
    balanced,
    /// Quality - full pipeline with disocclusion handling, ~3ms overhead
    quality,
};

/// Frame generation statistics
pub const FrameGenStats = struct {
    /// Total frames generated
    generated_frames: u64 = 0,
    /// Frames where generation was skipped (scene change, etc.)
    skipped_frames: u64 = 0,
    /// Average generation time in microseconds
    avg_gen_time_us: u64 = 0,
    /// Current confidence score (0.0-1.0)
    confidence: f32 = 1.0,
    /// Scene change detected in last frame
    scene_change_detected: bool = false,
};

/// Configuration for frame generation
pub const FrameGenConfig = struct {
    width: u32,
    height: u32,
    mode: FrameGenMode = .performance,
    /// Minimum confidence threshold to use generated frame
    confidence_threshold: f32 = 0.3,
    /// Scene change detection threshold
    scene_change_threshold: f32 = 0.7,
    /// Enable latency compensation (adjust timing for generated frames)
    latency_compensation: bool = true,
    /// Target frame time in microseconds (for pacing)
    target_frame_time_us: u64 = 16667, // 60 FPS default
};

/// Generated frame result
pub const GeneratedFrame = struct {
    /// The generated image view
    image_view: ?vk.VkImageView,
    /// The generated image
    image: ?vk.VkImage,
    /// Confidence score for this frame
    confidence: f32,
    /// Generation time in microseconds
    generation_time_us: u64,
    /// Frame ID (matches present ID from Reflex)
    frame_id: u64,
    /// Whether this frame should be presented
    should_present: bool,
};

/// Frame generation context
pub const FrameGenContext = struct {
    device: vk.VkDevice,
    allocator: std.mem.Allocator,

    // Sub-contexts
    mv_ctx: motion_vectors.MotionVectorContext,
    synthesis_ctx: frame_synthesis.FrameSynthesisContext,
    low_latency_ctx: ?*low_latency.LowLatencyContext,

    // Configuration
    config: FrameGenConfig,

    // State
    enabled: bool,
    current_frame_id: u64,
    stats: FrameGenStats,

    // Timing
    last_frame_time_us: u64,
    frame_times: [8]u64, // Ring buffer for averaging
    frame_time_idx: u8,

    // Scene change detection
    prev_frame_luminance: f32,

    // Dispatch table
    dispatch: ?*const vk.DeviceDispatch,

    /// Initialize frame generation context
    pub fn init(
        device: vk.VkDevice,
        config: FrameGenConfig,
        low_latency_ctx: ?*low_latency.LowLatencyContext,
        dispatch: ?*const vk.DeviceDispatch,
        allocator: std.mem.Allocator,
    ) FrameGenContext {
        const mv_config = motion_vectors.MotionVectorConfig{
            .width = config.width,
            .height = config.height,
            .grid_size = .@"4x4",
            .performance = switch (config.mode) {
                .off => .fast,
                .performance => .fast,
                .balanced => .medium,
                .quality => .slow,
            },
            .bidirectional = config.mode == .quality,
            .enable_cost = config.mode != .performance,
        };

        const synthesis_mode: frame_synthesis.QualityMode = switch (config.mode) {
            .off => .performance,
            .performance => .performance,
            .balanced => .balanced,
            .quality => .quality,
        };

        return .{
            .device = device,
            .allocator = allocator,
            .mv_ctx = motion_vectors.MotionVectorContext.init(device, mv_config, dispatch, allocator),
            .synthesis_ctx = frame_synthesis.FrameSynthesisContext.init(
                device,
                config.width,
                config.height,
                synthesis_mode,
                dispatch,
                allocator,
            ),
            .low_latency_ctx = low_latency_ctx,
            .config = config,
            .enabled = config.mode != .off,
            .current_frame_id = 0,
            .stats = .{},
            .last_frame_time_us = 0,
            .frame_times = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
            .frame_time_idx = 0,
            .prev_frame_luminance = 0.5,
            .dispatch = dispatch,
        };
    }

    /// Enable or disable frame generation
    pub fn setEnabled(self: *FrameGenContext, enabled: bool) void {
        self.enabled = enabled and self.config.mode != .off;
    }

    /// Set frame generation mode
    pub fn setMode(self: *FrameGenContext, mode: FrameGenMode) void {
        self.config.mode = mode;
        self.enabled = mode != .off;
    }

    /// Push a new frame and optionally generate an intermediate frame
    pub fn pushFrame(
        self: *FrameGenContext,
        cmd: vk.VkCommandBuffer,
        frame_image: motion_vectors.MotionVectorContext.FrameImage,
    ) !?GeneratedFrame {
        const start_time = getTimeMicros();

        // Always push to history
        const have_enough_frames = self.mv_ctx.pushFrame(frame_image);

        if (!self.enabled or !have_enough_frames) {
            return null;
        }

        self.current_frame_id += 1;

        // Execute motion vector estimation
        try self.mv_ctx.execute(cmd);

        // Get motion vectors
        const mvb = self.mv_ctx.getMotionVectors() orelse return null;

        // Check for scene change (basic luminance-based check)
        // In full implementation, use cost map variance
        const scene_change = self.detectSceneChange(mvb);
        self.stats.scene_change_detected = scene_change;

        if (scene_change) {
            self.stats.skipped_frames += 1;
            return null;
        }

        // Synthesize intermediate frame
        const prev_frame = self.mv_ctx.getPreviousFrame() orelse return null;
        const curr_frame = self.mv_ctx.getCurrentFrame() orelse return null;

        const output_view = try self.synthesis_ctx.synthesize(
            cmd,
            prev_frame.view,
            curr_frame.view,
            mvb,
        );

        const end_time = getTimeMicros();
        const gen_time: u64 = @intCast(@max(0, end_time - start_time));

        // Update statistics
        self.stats.generated_frames += 1;
        self.updateFrameTime(gen_time);

        return GeneratedFrame{
            .image_view = output_view,
            .image = self.synthesis_ctx.getOutputImage(),
            .confidence = self.calculateConfidence(mvb),
            .generation_time_us = gen_time,
            .frame_id = self.current_frame_id,
            .should_present = true,
        };
    }

    /// Get latency compensation in microseconds
    /// This value should be added to Reflex timing to account for
    /// the additional latency introduced by frame generation
    pub fn getLatencyCompensation(self: *const FrameGenContext) u64 {
        if (!self.config.latency_compensation) {
            return 0;
        }

        // Compensation = half frame time (generated frame shown at t+0.5)
        // Plus average generation overhead
        return (self.config.target_frame_time_us / 2) + self.stats.avg_gen_time_us;
    }

    /// Get current statistics
    pub fn getStats(self: *const FrameGenContext) FrameGenStats {
        return self.stats;
    }

    /// Get current frame ID
    pub fn getCurrentFrameId(self: *const FrameGenContext) u64 {
        return self.current_frame_id;
    }

    /// Cleanup resources
    pub fn deinit(self: *FrameGenContext) void {
        self.mv_ctx.deinit();
        self.synthesis_ctx.deinit();
    }

    // ==========================================================================
    // Private Methods
    // ==========================================================================

    fn detectSceneChange(self: *FrameGenContext, mvb: *const motion_vectors.MotionVectorBuffer) bool {
        _ = mvb;
        // Simple scene change detection based on cost map or motion magnitude
        // In full implementation:
        // - Check average cost from cost map
        // - Check motion vector variance
        // - Check luminance histogram difference

        // For now, always return false (no scene change)
        _ = self;
        return false;
    }

    fn calculateConfidence(self: *const FrameGenContext, mvb: *const motion_vectors.MotionVectorBuffer) f32 {
        _ = mvb;
        _ = self;
        // In full implementation, use cost map to calculate confidence
        // Lower cost = higher confidence

        // For performance mode, always return high confidence
        return 0.95;
    }

    fn updateFrameTime(self: *FrameGenContext, gen_time: u64) void {
        self.frame_times[self.frame_time_idx] = gen_time;
        self.frame_time_idx = (self.frame_time_idx + 1) % 8;

        // Calculate average
        var sum: u64 = 0;
        var count: u64 = 0;
        for (self.frame_times) |t| {
            if (t > 0) {
                sum += t;
                count += 1;
            }
        }
        if (count > 0) {
            self.stats.avg_gen_time_us = sum / count;
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "FrameGenMode" {
    const mode: FrameGenMode = .performance;
    try std.testing.expectEqual(FrameGenMode.performance, mode);
}

test "FrameGenConfig defaults" {
    const config = FrameGenConfig{
        .width = 1920,
        .height = 1080,
    };
    try std.testing.expectEqual(FrameGenMode.performance, config.mode);
    try std.testing.expectApproxEqRel(@as(f32, 0.3), config.confidence_threshold, 0.001);
    try std.testing.expect(config.latency_compensation);
}

test "FrameGenStats defaults" {
    const stats = FrameGenStats{};
    try std.testing.expectEqual(@as(u64, 0), stats.generated_frames);
    try std.testing.expectEqual(@as(u64, 0), stats.skipped_frames);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), stats.confidence, 0.001);
}

test "GeneratedFrame" {
    const frame = GeneratedFrame{
        .image_view = null,
        .image = null,
        .confidence = 0.95,
        .generation_time_us = 1500,
        .frame_id = 42,
        .should_present = true,
    };
    try std.testing.expect(frame.should_present);
    try std.testing.expectEqual(@as(u64, 42), frame.frame_id);
}
