//! VK_NV_low_latency2 Extension Wrapper
//!
//! Provides NVIDIA Reflex integration for reduced input-to-display latency.
//! This extension allows applications to reduce rendering latency by:
//! - Enabling low latency mode on swapchains
//! - Setting frame timing markers
//! - Sleeping to optimize frame pacing
//! - Collecting latency timing data
//!
//! Requires NVIDIA driver 535+ and VK_NV_low_latency2 extension.

const std = @import("std");
const vk = @import("vulkan.zig");

/// Low latency context for a swapchain
pub const LowLatencyContext = struct {
    device: vk.VkDevice,
    swapchain: vk.VkSwapchainKHR_T,
    dispatch: *const vk.DeviceDispatch,
    enabled: bool = false,
    boost_enabled: bool = false,
    min_interval_us: u32 = 0,
    current_present_id: u64 = 0,

    /// Initialize low latency context for a swapchain
    pub fn init(
        device: vk.VkDevice,
        swapchain: vk.VkSwapchainKHR_T,
        dispatch: *const vk.DeviceDispatch,
    ) LowLatencyContext {
        return .{
            .device = device,
            .swapchain = swapchain,
            .dispatch = dispatch,
        };
    }

    /// Check if VK_NV_low_latency2 is available
    pub fn isSupported(self: *const LowLatencyContext) bool {
        return self.dispatch.hasLowLatency2();
    }

    /// Enable or disable low latency mode
    pub fn setMode(self: *LowLatencyContext, config: ModeConfig) vk.VulkanError!void {
        const func = self.dispatch.vkSetLatencySleepModeNV orelse return vk.VulkanError.ExtensionNotPresent;

        const info = vk.VkLatencySleepModeInfoNV{
            .lowLatencyMode = if (config.enabled) vk.VK_TRUE else vk.VK_FALSE,
            .lowLatencyBoost = if (config.boost) vk.VK_TRUE else vk.VK_FALSE,
            .minimumIntervalUs = config.min_interval_us,
        };

        const result = func(self.device, self.swapchain, &info);
        try vk.check(result);

        self.enabled = config.enabled;
        self.boost_enabled = config.boost;
        self.min_interval_us = config.min_interval_us;
    }

    /// Sleep until the optimal time to start the next frame
    /// This reduces input latency by minimizing the time between input sampling and display
    pub fn sleep(self: *LowLatencyContext, semaphore: vk.VkSemaphore_T, value: u64) vk.VulkanError!void {
        const func = self.dispatch.vkLatencySleepNV orelse return vk.VulkanError.ExtensionNotPresent;

        const info = vk.VkLatencySleepInfoNV{
            .signalSemaphore = semaphore,
            .value = value,
        };

        const result = func(self.device, self.swapchain, &info);
        try vk.check(result);
    }

    /// Set a latency marker for the current frame
    pub fn setMarker(self: *LowLatencyContext, marker: Marker) void {
        const func = self.dispatch.vkSetLatencyMarkerNV orelse return;

        const info = vk.VkSetLatencyMarkerInfoNV{
            .presentID = self.current_present_id,
            .marker = marker.toVk(),
        };

        func(self.device, self.swapchain, &info);
    }

    /// Set marker with explicit present ID
    pub fn setMarkerWithId(self: *LowLatencyContext, marker: Marker, present_id: u64) void {
        const func = self.dispatch.vkSetLatencyMarkerNV orelse return;

        const info = vk.VkSetLatencyMarkerInfoNV{
            .presentID = present_id,
            .marker = marker.toVk(),
        };

        func(self.device, self.swapchain, &info);
    }

    /// Get latency timing data for recent frames
    pub fn getTimings(self: *LowLatencyContext, allocator: std.mem.Allocator) vk.VulkanError![]FrameTimings {
        const func = self.dispatch.vkGetLatencyTimingsNV orelse return vk.VulkanError.ExtensionNotPresent;

        // First call to get count
        var info = vk.VkGetLatencyMarkerInfoNV{
            .timingCount = 0,
            .pTimings = null,
        };
        func(self.device, self.swapchain, &info);

        if (info.timingCount == 0) {
            return &[_]FrameTimings{};
        }

        // Allocate and get timings
        const vk_timings = try allocator.alloc(vk.VkLatencyTimingsFrameReportNV, info.timingCount);
        defer allocator.free(vk_timings);

        // Initialize sType for each entry
        for (vk_timings) |*t| {
            t.* = .{};
        }

        info.pTimings = vk_timings.ptr;
        func(self.device, self.swapchain, &info);

        // Convert to our type
        const timings = try allocator.alloc(FrameTimings, info.timingCount);
        for (vk_timings, 0..) |t, i| {
            timings[i] = FrameTimings.fromVk(t);
        }

        return timings;
    }

    /// Begin a new frame (increments present ID and sets simulation start marker)
    pub fn beginFrame(self: *LowLatencyContext) u64 {
        self.current_present_id += 1;
        self.setMarker(.simulation_start);
        return self.current_present_id;
    }

    /// Mark end of simulation/game logic
    pub fn endSimulation(self: *LowLatencyContext) void {
        self.setMarker(.simulation_end);
    }

    /// Mark start of render submission
    pub fn beginRenderSubmit(self: *LowLatencyContext) void {
        self.setMarker(.rendersubmit_start);
    }

    /// Mark end of render submission
    pub fn endRenderSubmit(self: *LowLatencyContext) void {
        self.setMarker(.rendersubmit_end);
    }

    /// Mark start of present
    pub fn beginPresent(self: *LowLatencyContext) void {
        self.setMarker(.present_start);
    }

    /// Mark end of present
    pub fn endPresent(self: *LowLatencyContext) void {
        self.setMarker(.present_end);
    }

    /// Mark input sample point
    pub fn markInputSample(self: *LowLatencyContext) void {
        self.setMarker(.input_sample);
    }

    /// Trigger flash for latency measurement tools
    pub fn triggerFlash(self: *LowLatencyContext) void {
        self.setMarker(.trigger_flash);
    }
};

/// Configuration for low latency mode
pub const ModeConfig = struct {
    enabled: bool = true,
    boost: bool = false,
    min_interval_us: u32 = 0,

    /// Create config for maximum performance (low latency + boost)
    pub fn maxPerformance() ModeConfig {
        return .{
            .enabled = true,
            .boost = true,
            .min_interval_us = 0,
        };
    }

    /// Create config targeting a specific framerate
    pub fn targetFps(fps: u32) ModeConfig {
        const interval = if (fps > 0) 1_000_000 / fps else 0;
        return .{
            .enabled = true,
            .boost = false,
            .min_interval_us = interval,
        };
    }

    /// Disabled config
    pub fn disabled() ModeConfig {
        return .{
            .enabled = false,
            .boost = false,
            .min_interval_us = 0,
        };
    }
};

/// Latency markers for frame timing
pub const Marker = enum {
    simulation_start,
    simulation_end,
    rendersubmit_start,
    rendersubmit_end,
    present_start,
    present_end,
    input_sample,
    trigger_flash,
    out_of_band_rendersubmit_start,
    out_of_band_rendersubmit_end,
    out_of_band_present_start,
    out_of_band_present_end,

    pub fn toVk(self: Marker) vk.VkLatencyMarkerNV {
        return switch (self) {
            .simulation_start => .simulation_start,
            .simulation_end => .simulation_end,
            .rendersubmit_start => .rendersubmit_start,
            .rendersubmit_end => .rendersubmit_end,
            .present_start => .present_start,
            .present_end => .present_end,
            .input_sample => .input_sample,
            .trigger_flash => .trigger_flash,
            .out_of_band_rendersubmit_start => .out_of_band_rendersubmit_start,
            .out_of_band_rendersubmit_end => .out_of_band_rendersubmit_end,
            .out_of_band_present_start => .out_of_band_present_start,
            .out_of_band_present_end => .out_of_band_present_end,
        };
    }
};

/// Frame timing data from the driver
pub const FrameTimings = struct {
    present_id: u64,
    input_sample_time_us: u64,
    sim_start_time_us: u64,
    sim_end_time_us: u64,
    render_submit_start_time_us: u64,
    render_submit_end_time_us: u64,
    present_start_time_us: u64,
    present_end_time_us: u64,
    driver_start_time_us: u64,
    driver_end_time_us: u64,
    os_render_queue_start_time_us: u64,
    os_render_queue_end_time_us: u64,
    gpu_render_start_time_us: u64,
    gpu_render_end_time_us: u64,

    pub fn fromVk(t: vk.VkLatencyTimingsFrameReportNV) FrameTimings {
        return .{
            .present_id = t.presentID,
            .input_sample_time_us = t.inputSampleTimeUs,
            .sim_start_time_us = t.simStartTimeUs,
            .sim_end_time_us = t.simEndTimeUs,
            .render_submit_start_time_us = t.renderSubmitStartTimeUs,
            .render_submit_end_time_us = t.renderSubmitEndTimeUs,
            .present_start_time_us = t.presentStartTimeUs,
            .present_end_time_us = t.presentEndTimeUs,
            .driver_start_time_us = t.driverStartTimeUs,
            .driver_end_time_us = t.driverEndTimeUs,
            .os_render_queue_start_time_us = t.osRenderQueueStartTimeUs,
            .os_render_queue_end_time_us = t.osRenderQueueEndTimeUs,
            .gpu_render_start_time_us = t.gpuRenderStartTimeUs,
            .gpu_render_end_time_us = t.gpuRenderEndTimeUs,
        };
    }

    /// Calculate total input-to-display latency in microseconds
    pub fn totalLatencyUs(self: *const FrameTimings) u64 {
        if (self.input_sample_time_us == 0 or self.present_end_time_us == 0) {
            return 0;
        }
        return self.present_end_time_us - self.input_sample_time_us;
    }

    /// Calculate simulation time in microseconds
    pub fn simTimeUs(self: *const FrameTimings) u64 {
        if (self.sim_start_time_us == 0 or self.sim_end_time_us == 0) {
            return 0;
        }
        return self.sim_end_time_us - self.sim_start_time_us;
    }

    /// Calculate GPU render time in microseconds
    pub fn gpuRenderTimeUs(self: *const FrameTimings) u64 {
        if (self.gpu_render_start_time_us == 0 or self.gpu_render_end_time_us == 0) {
            return 0;
        }
        return self.gpu_render_end_time_us - self.gpu_render_start_time_us;
    }

    /// Calculate driver overhead in microseconds
    pub fn driverTimeUs(self: *const FrameTimings) u64 {
        if (self.driver_start_time_us == 0 or self.driver_end_time_us == 0) {
            return 0;
        }
        return self.driver_end_time_us - self.driver_start_time_us;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "ModeConfig presets" {
    const max = ModeConfig.maxPerformance();
    try std.testing.expect(max.enabled);
    try std.testing.expect(max.boost);
    try std.testing.expectEqual(@as(u32, 0), max.min_interval_us);

    const fps60 = ModeConfig.targetFps(60);
    try std.testing.expect(fps60.enabled);
    try std.testing.expect(!fps60.boost);
    try std.testing.expectEqual(@as(u32, 16666), fps60.min_interval_us);

    const disabled = ModeConfig.disabled();
    try std.testing.expect(!disabled.enabled);
}

test "FrameTimings calculations" {
    const timings = FrameTimings{
        .present_id = 1,
        .input_sample_time_us = 1000,
        .sim_start_time_us = 1100,
        .sim_end_time_us = 2100,
        .render_submit_start_time_us = 2200,
        .render_submit_end_time_us = 2300,
        .present_start_time_us = 2400,
        .present_end_time_us = 5000,
        .driver_start_time_us = 2500,
        .driver_end_time_us = 2800,
        .os_render_queue_start_time_us = 2900,
        .os_render_queue_end_time_us = 3500,
        .gpu_render_start_time_us = 3600,
        .gpu_render_end_time_us = 4800,
    };

    try std.testing.expectEqual(@as(u64, 4000), timings.totalLatencyUs());
    try std.testing.expectEqual(@as(u64, 1000), timings.simTimeUs());
    try std.testing.expectEqual(@as(u64, 1200), timings.gpuRenderTimeUs());
    try std.testing.expectEqual(@as(u64, 300), timings.driverTimeUs());
}
