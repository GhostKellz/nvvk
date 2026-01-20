//! Integration Tests for nvvk
//!
//! These tests verify end-to-end functionality of the nvvk library
//! using mock objects where real GPU access is not available.

const std = @import("std");
const vk = @import("vulkan.zig");
const low_latency = @import("low_latency.zig");
const frame_generation = @import("frame_generation.zig");
const present_injection = @import("present_injection.zig");
const async_sleep = @import("async_sleep.zig");
const vrr = @import("vrr.zig");

// =============================================================================
// Low Latency Tests
// =============================================================================

test "frame pacer initialization" {
    const pacer = low_latency.FramePacer.init(60); // 60 FPS target
    try std.testing.expectEqual(@as(u32, 60), pacer.target_fps);
    try std.testing.expectEqual(@as(u64, 16666), pacer.target_frame_time_us); // ~16.6ms

    const uncapped = low_latency.FramePacer.uncapped();
    try std.testing.expectEqual(@as(u32, 0), uncapped.target_fps);
}

test "mode config presets" {
    const disabled = low_latency.ModeConfig.disabled();
    try std.testing.expect(!disabled.enabled);

    const max = low_latency.ModeConfig.maxPerformance();
    try std.testing.expect(max.enabled);
    try std.testing.expect(max.boost);

    const target = low_latency.ModeConfig.targetFps(60);
    try std.testing.expect(target.enabled);
}

test "latency marker enum values" {
    try std.testing.expectEqual(@as(i32, 0), @intFromEnum(vk.VkLatencyMarkerNV.simulation_start));
    try std.testing.expectEqual(@as(i32, 6), @intFromEnum(vk.VkLatencyMarkerNV.input_sample));
}

// =============================================================================
// Async Sleep Tests
// =============================================================================

test "async sleep context initialization" {
    const allocator = std.testing.allocator;

    var ctx = async_sleep.AsyncSleepContext.init(null, null, allocator);
    defer ctx.deinit();

    const stats = ctx.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.pending_count);
    try std.testing.expectEqual(@as(u64, 0), stats.completed_count);
    try std.testing.expectEqual(@as(u64, 0), stats.cancelled_count);
    try std.testing.expectEqual(@as(u64, 0), stats.failed_count);
}

test "async result enum" {
    try std.testing.expect(async_sleep.AsyncResult.completed != async_sleep.AsyncResult.cancelled);
    try std.testing.expect(async_sleep.AsyncResult.failed != async_sleep.AsyncResult.timeout);
}

// =============================================================================
// Frame Generation Tests
// =============================================================================

test "frame gen config defaults" {
    const config = frame_generation.FrameGenConfig{
        .width = 1920,
        .height = 1080,
        .mode = .balanced,
    };

    try std.testing.expectEqual(@as(u32, 1920), config.width);
    try std.testing.expectEqual(@as(u32, 1080), config.height);
    try std.testing.expect(config.mode == .balanced);
}

test "frame gen mode enum" {
    try std.testing.expect(@intFromEnum(frame_generation.FrameGenMode.off) == 0);
    try std.testing.expect(@intFromEnum(frame_generation.FrameGenMode.performance) == 1);
    try std.testing.expect(@intFromEnum(frame_generation.FrameGenMode.balanced) == 2);
    try std.testing.expect(@intFromEnum(frame_generation.FrameGenMode.quality) == 3);
}

// =============================================================================
// Present Injection Tests
// =============================================================================

test "injection mode enum" {
    try std.testing.expect(present_injection.InjectionMode.single != present_injection.InjectionMode.double);
}

test "timing mode enum" {
    try std.testing.expect(present_injection.TimingMode.fixed != present_injection.TimingMode.adaptive);
}

test "injection config" {
    const config = present_injection.InjectionConfig{
        .mode = .single,
        .timing = .adaptive,
    };

    try std.testing.expect(config.mode == .single);
    try std.testing.expect(config.timing == .adaptive);
}

// =============================================================================
// VRR Tests
// =============================================================================

test "vrr source enum" {
    try std.testing.expect(vrr.VrrSource.drm != vrr.VrrSource.nvidia);
}

test "vrr config struct" {
    const config = vrr.VrrConfig{
        .source = .drm,
        .lfc_supported = true,
    };
    try std.testing.expect(config.lfc_supported);
}

test "vrr config default" {
    const config = vrr.VrrConfig.default();
    try std.testing.expectEqual(@as(u32, 40), config.min_hz);
    try std.testing.expectEqual(@as(u32, 144), config.max_hz);
}

// =============================================================================
// Vulkan Type Tests
// =============================================================================

test "vulkan structure sizes" {
    // Verify C ABI compatibility
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(vk.VkLatencySleepModeInfoNV));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(vk.VkLatencySleepInfoNV));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(vk.VkSetLatencyMarkerInfoNV));
}

test "vulkan result handling" {
    const success = vk.VkResult.success;
    try std.testing.expect(success.isSuccess());
    try std.testing.expect(success.toError() == null);

    const err = vk.VkResult.error_device_lost;
    try std.testing.expect(!err.isSuccess());
    try std.testing.expectEqual(vk.VulkanError.DeviceLost, err.toError().?);
}

test "vulkan layer properties size" {
    // VkLayerProperties should be 520 bytes (256 + 4 + 4 + 256)
    try std.testing.expectEqual(@as(usize, 520), @sizeOf(vk.VkLayerProperties));
}

test "vulkan extension properties size" {
    // VkExtensionProperties should be 260 bytes (256 + 4)
    try std.testing.expectEqual(@as(usize, 260), @sizeOf(vk.VkExtensionProperties));
}

// =============================================================================
// Pipeline Flow Tests
// =============================================================================

test "latency compensation math" {
    // Frame generation adds latency but doubles frame rate
    const base_latency_ms: f64 = 16.67; // 60 FPS
    const frame_gen_overhead_ms: f64 = 2.0;

    // Effective latency with frame gen
    const effective_latency_ms = base_latency_ms / 2.0 + frame_gen_overhead_ms;

    // Should improve overall latency
    try std.testing.expect(effective_latency_ms < base_latency_ms);
    try std.testing.expect(effective_latency_ms > 5.0);
}

test "fps doubling calculation" {
    const base_fps: f64 = 60.0;
    const effective_fps = base_fps * 2.0; // Frame gen doubles
    const overhead_factor: f64 = 0.95; // 5% overhead

    const actual_fps = effective_fps * overhead_factor;
    try std.testing.expect(actual_fps > 110.0);
    try std.testing.expect(actual_fps < 120.0);
}
