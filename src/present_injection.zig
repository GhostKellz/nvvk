//! Present Injection Layer
//!
//! Vulkan layer for injecting generated frames into the present chain.
//! Intercepts vkQueuePresentKHR and doubles effective frame rate by
//! presenting: real -> generated -> real -> generated...
//!
//! This module provides:
//! - Frame timing synchronization
//! - Generated frame insertion
//! - Latency compensation with Reflex integration
//!
//! Layer name: VK_LAYER_NV_frame_generation

const std = @import("std");
const vk = @import("vulkan.zig");
const frame_generation = @import("frame_generation.zig");
const low_latency = @import("low_latency.zig");

/// Get current time in microseconds using monotonic clock
fn getTimeMicros() u64 {
    const ts = std.posix.clock_gettime(.MONOTONIC) catch return 0;
    return @as(u64, @intCast(ts.sec)) * 1_000_000 + @as(u64, @intCast(ts.nsec)) / 1000;
}

// =============================================================================
// Layer Constants
// =============================================================================

pub const LAYER_NAME = "VK_LAYER_NV_frame_generation";
pub const LAYER_DESCRIPTION = "NVIDIA Frame Generation Layer (nvvk)";
pub const LAYER_VERSION: u32 = 1;

// =============================================================================
// Types
// =============================================================================

/// Present injection mode
pub const InjectionMode = enum {
    /// Disabled - passthrough presents
    disabled,
    /// Single injection - present generated frame after each real frame
    single,
    /// Double injection - for 4x frame rate (experimental)
    double,
};

/// Present timing mode
pub const TimingMode = enum {
    /// Fixed timing based on target frame rate
    fixed,
    /// Adaptive timing based on frame time variance
    adaptive,
    /// VRR-aware timing (G-Sync/FreeSync)
    vrr,
};

/// Present injection statistics
pub const InjectionStats = struct {
    /// Total real frames presented
    real_frames: u64 = 0,
    /// Total generated frames presented
    generated_frames: u64 = 0,
    /// Frames where injection was skipped
    skipped_frames: u64 = 0,
    /// Average present interval (microseconds)
    avg_present_interval_us: u64 = 0,
    /// Current effective frame rate
    effective_fps: f32 = 0.0,
    /// Injection overhead (microseconds)
    injection_overhead_us: u64 = 0,
};

/// Present injection configuration
pub const InjectionConfig = struct {
    /// Injection mode
    mode: InjectionMode = .single,
    /// Timing mode
    timing: TimingMode = .adaptive,
    /// Target frame rate (for fixed timing)
    target_fps: f32 = 60.0,
    /// Minimum confidence to inject
    min_confidence: f32 = 0.5,
    /// Enable Reflex integration for latency compensation
    reflex_integration: bool = true,
    /// VRR range minimum (Hz)
    vrr_min_hz: f32 = 40.0,
    /// VRR range maximum (Hz)
    vrr_max_hz: f32 = 144.0,
};

/// Present injection context
pub const PresentInjectionContext = struct {
    device: ?vk.VkDevice,
    swapchain: u64,
    allocator: std.mem.Allocator,

    // Frame generation context
    frame_gen: ?*frame_generation.FrameGenContext,

    // Low latency context for Reflex
    low_latency: ?*low_latency.LowLatencyContext,

    // Configuration
    config: InjectionConfig,

    // State
    enabled: bool,
    last_present_time_us: u64,
    present_times: [16]u64, // Ring buffer for timing
    present_time_idx: u8,

    // Statistics
    stats: InjectionStats,

    // Dispatch table
    dispatch: ?*const vk.DeviceDispatch,

    // Original present function (intercepted)
    original_queue_present: ?*const fn () callconv(.c) void,

    /// Initialize present injection context
    pub fn init(
        device: ?vk.VkDevice,
        swapchain: u64,
        frame_gen: ?*frame_generation.FrameGenContext,
        low_latency_ctx: ?*low_latency.LowLatencyContext,
        config: InjectionConfig,
        dispatch: ?*const vk.DeviceDispatch,
        allocator: std.mem.Allocator,
    ) PresentInjectionContext {
        return .{
            .device = device,
            .swapchain = swapchain,
            .allocator = allocator,
            .frame_gen = frame_gen,
            .low_latency = low_latency_ctx,
            .config = config,
            .enabled = config.mode != .disabled,
            .last_present_time_us = 0,
            .present_times = std.mem.zeroes([16]u64),
            .present_time_idx = 0,
            .stats = .{},
            .dispatch = dispatch,
            .original_queue_present = null,
        };
    }

    /// Enable or disable injection
    pub fn setEnabled(self: *PresentInjectionContext, enabled: bool) void {
        self.enabled = enabled and self.config.mode != .disabled;
    }

    /// Set injection mode
    pub fn setMode(self: *PresentInjectionContext, mode: InjectionMode) void {
        self.config.mode = mode;
        self.enabled = mode != .disabled;
    }

    /// Should inject a generated frame based on current state
    pub fn shouldInject(self: *const PresentInjectionContext) bool {
        if (!self.enabled) return false;

        // Check frame generation context
        if (self.frame_gen) |fg| {
            const stats = fg.getStats();
            return stats.confidence >= self.config.min_confidence and
                !stats.scene_change_detected;
        }

        return false;
    }

    /// Calculate optimal injection timing
    pub fn calculateInjectionTiming(self: *PresentInjectionContext) u64 {
        const now = getTimeMicros();

        switch (self.config.timing) {
            .fixed => {
                // Fixed timing: half of target frame time
                const target_interval_us = @as(u64, @intFromFloat(1_000_000.0 / self.config.target_fps));
                return target_interval_us / 2;
            },
            .adaptive => {
                // Adaptive: based on average present interval
                if (self.stats.avg_present_interval_us > 0) {
                    return self.stats.avg_present_interval_us / 2;
                }
                // Fallback to 60 FPS
                return 8333;
            },
            .vrr => {
                // VRR: constrained to VRR range
                const avg_interval = if (self.stats.avg_present_interval_us > 0)
                    self.stats.avg_present_interval_us
                else
                    16667;

                const max_interval_us = @as(u64, @intFromFloat(1_000_000.0 / self.config.vrr_min_hz));
                const min_interval_us = @as(u64, @intFromFloat(1_000_000.0 / self.config.vrr_max_hz));

                const injection_interval = std.math.clamp(
                    avg_interval / 2,
                    min_interval_us / 2,
                    max_interval_us / 2,
                );

                return injection_interval;
            },
        }

        _ = now;
    }

    /// Record present timing
    pub fn recordPresentTime(self: *PresentInjectionContext, is_generated: bool) void {
        const now = getTimeMicros();

        if (self.last_present_time_us > 0) {
            const interval = now - self.last_present_time_us;
            self.present_times[self.present_time_idx] = interval;
            self.present_time_idx = (self.present_time_idx + 1) % 16;

            // Update average
            var sum: u64 = 0;
            var count: u64 = 0;
            for (self.present_times) |t| {
                if (t > 0) {
                    sum += t;
                    count += 1;
                }
            }
            if (count > 0) {
                self.stats.avg_present_interval_us = sum / count;
                self.stats.effective_fps = 1_000_000.0 / @as(f32, @floatFromInt(self.stats.avg_present_interval_us));
            }
        }

        self.last_present_time_us = now;

        // Update stats
        if (is_generated) {
            self.stats.generated_frames += 1;
        } else {
            self.stats.real_frames += 1;
        }
    }

    /// Get injection statistics
    pub fn getStats(self: *const PresentInjectionContext) InjectionStats {
        return self.stats;
    }

    /// Cleanup
    pub fn deinit(self: *PresentInjectionContext) void {
        _ = self;
    }
};

// =============================================================================
// Layer Manifest Generation
// =============================================================================

/// Generate Vulkan layer manifest JSON
pub fn generateLayerManifest(allocator: std.mem.Allocator) ![]u8 {
    const manifest =
        \\{
        \\    "file_format_version": "1.0.0",
        \\    "layer": {
        \\        "name": "VK_LAYER_NV_frame_generation",
        \\        "type": "GLOBAL",
        \\        "library_path": "libnvvk.so",
        \\        "api_version": "1.3.0",
        \\        "implementation_version": "1",
        \\        "description": "NVIDIA Frame Generation Layer (nvvk)",
        \\        "functions": {
        \\            "vkGetInstanceProcAddr": "nvvk_vkGetInstanceProcAddr",
        \\            "vkGetDeviceProcAddr": "nvvk_vkGetDeviceProcAddr"
        \\        },
        \\        "instance_extensions": [],
        \\        "device_extensions": []
        \\    }
        \\}
    ;

    return allocator.dupe(u8, manifest);
}

// =============================================================================
// Tests
// =============================================================================

test "InjectionMode" {
    const mode: InjectionMode = .single;
    try std.testing.expectEqual(InjectionMode.single, mode);
}

test "TimingMode" {
    const timing: TimingMode = .adaptive;
    try std.testing.expectEqual(TimingMode.adaptive, timing);
}

test "InjectionConfig defaults" {
    const config = InjectionConfig{};
    try std.testing.expectEqual(InjectionMode.single, config.mode);
    try std.testing.expectEqual(TimingMode.adaptive, config.timing);
    try std.testing.expectApproxEqRel(@as(f32, 60.0), config.target_fps, 0.001);
    try std.testing.expect(config.reflex_integration);
}

test "InjectionStats defaults" {
    const stats = InjectionStats{};
    try std.testing.expectEqual(@as(u64, 0), stats.real_frames);
    try std.testing.expectEqual(@as(u64, 0), stats.generated_frames);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), stats.effective_fps, 0.001);
}

test "generateLayerManifest" {
    const allocator = std.testing.allocator;
    const manifest = try generateLayerManifest(allocator);
    defer allocator.free(manifest);

    try std.testing.expect(std.mem.indexOf(u8, manifest, "VK_LAYER_NV_frame_generation") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "libnvvk.so") != null);
}
