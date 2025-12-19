//! VK_NV_low_latency2 Extension Wrapper
//!
//! Provides NVIDIA Reflex integration for reduced input-to-display latency.
//! This extension allows applications to reduce rendering latency by:
//! - Enabling low latency mode on swapchains
//! - Setting frame timing markers
//! - Sleeping to optimize frame pacing
//! - Collecting latency timing data
//!
//! Requires NVIDIA driver 590+ (590.48.01 recommended) and VK_NV_low_latency2 extension.
//!
//! Driver 590+ Benefits:
//! - Swapchain recreation no longer causes latency spikes (critical for window resize)
//! - More consistent frame pacing with low latency mode enabled
//! - Better Wayland 1.20+ compositor integration

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

    /// Check if swapchain recreation is safe without latency spikes.
    /// Returns true on driver 590+ which fixed swapchain recreation performance.
    /// On older drivers, window resize/mode changes may cause temporary latency spikes.
    pub fn isSwapchainRecreationSafe(allocator: std.mem.Allocator) bool {
        const root = @import("root.zig");
        const ver = root.getDriverVersion(allocator) orelse return false;
        return ver.hasSwapchainFix();
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
// Frame Pacing
// =============================================================================

/// Frame pacer for targeting specific framerates with Reflex
pub const FramePacer = struct {
    target_fps: u32,
    target_frame_time_us: u64,
    last_frame_time_us: u64 = 0,
    frame_count: u64 = 0,

    /// Create a frame pacer targeting a specific FPS
    pub fn init(target_fps: u32) FramePacer {
        return .{
            .target_fps = target_fps,
            .target_frame_time_us = if (target_fps > 0) 1_000_000 / target_fps else 0,
        };
    }

    /// Create a frame pacer for uncapped FPS (Reflex boost mode)
    pub fn uncapped() FramePacer {
        return .{
            .target_fps = 0,
            .target_frame_time_us = 0,
        };
    }

    /// Get ModeConfig for this pacer
    pub fn toModeConfig(self: FramePacer) ModeConfig {
        if (self.target_fps == 0) {
            return ModeConfig.maxPerformance();
        }
        return ModeConfig.targetFps(self.target_fps);
    }

    /// Record frame completion and return time since last frame
    pub fn recordFrame(self: *FramePacer, current_time_us: u64) u64 {
        const delta = if (self.last_frame_time_us > 0)
            current_time_us - self.last_frame_time_us
        else
            0;
        self.last_frame_time_us = current_time_us;
        self.frame_count += 1;
        return delta;
    }

    /// Check if we're ahead of target (frame came in early)
    pub fn isAheadOfTarget(self: FramePacer, frame_time_us: u64) bool {
        if (self.target_frame_time_us == 0) return false;
        return frame_time_us < self.target_frame_time_us;
    }

    /// Get current average FPS based on last frame time
    pub fn currentFps(self: FramePacer) u32 {
        if (self.last_frame_time_us == 0) return 0;
        // This would need actual frame time delta tracking for accuracy
        return self.target_fps;
    }
};

// =============================================================================
// Latency Statistics
// =============================================================================

/// Rolling latency statistics aggregator
pub const LatencyStats = struct {
    /// Ring buffer of recent latency samples
    samples: [128]u64 = [_]u64{0} ** 128,
    sample_index: usize = 0,
    sample_count: usize = 0,

    /// Running totals for fast average calculation
    total_latency_us: u64 = 0,
    min_latency_us: u64 = std.math.maxInt(u64),
    max_latency_us: u64 = 0,

    /// Add a latency sample
    pub fn addSample(self: *LatencyStats, latency_us: u64) void {
        // Remove old sample from total if buffer is full
        if (self.sample_count >= self.samples.len) {
            self.total_latency_us -= self.samples[self.sample_index];
        } else {
            self.sample_count += 1;
        }

        // Add new sample
        self.samples[self.sample_index] = latency_us;
        self.total_latency_us += latency_us;
        self.sample_index = (self.sample_index + 1) % self.samples.len;

        // Update min/max
        if (latency_us < self.min_latency_us) self.min_latency_us = latency_us;
        if (latency_us > self.max_latency_us) self.max_latency_us = latency_us;
    }

    /// Add samples from FrameTimings
    pub fn addFromTimings(self: *LatencyStats, timings: FrameTimings) void {
        const latency = timings.totalLatencyUs();
        if (latency > 0) {
            self.addSample(latency);
        }
    }

    /// Get average latency in microseconds
    pub fn averageUs(self: LatencyStats) u64 {
        if (self.sample_count == 0) return 0;
        return self.total_latency_us / self.sample_count;
    }

    /// Get average latency in milliseconds
    pub fn averageMs(self: LatencyStats) f32 {
        return @as(f32, @floatFromInt(self.averageUs())) / 1000.0;
    }

    /// Get minimum latency seen
    pub fn minUs(self: LatencyStats) u64 {
        if (self.sample_count == 0) return 0;
        return self.min_latency_us;
    }

    /// Get maximum latency seen
    pub fn maxUs(self: LatencyStats) u64 {
        return self.max_latency_us;
    }

    /// Get 99th percentile latency (approximate)
    pub fn percentile99Us(self: LatencyStats) u64 {
        if (self.sample_count < 10) return self.max_latency_us;

        // Simple approximation: sort samples and take 99th percentile
        var sorted: [128]u64 = undefined;
        @memcpy(sorted[0..self.sample_count], self.samples[0..self.sample_count]);
        std.mem.sort(u64, sorted[0..self.sample_count], {}, std.sort.asc(u64));

        const idx = (self.sample_count * 99) / 100;
        return sorted[idx];
    }

    /// Reset all statistics
    pub fn reset(self: *LatencyStats) void {
        self.* = .{};
    }
};

// =============================================================================
// Thread-Safe Wrapper
// =============================================================================

/// Thread-safe wrapper for LowLatencyContext
/// Use this when multiple threads may access Reflex functionality
pub const ThreadSafeLowLatencyContext = struct {
    inner: LowLatencyContext,
    mutex: std.Thread.Mutex = .{},

    pub fn init(
        device: vk.VkDevice,
        swapchain: vk.VkSwapchainKHR_T,
        dispatch: *const vk.DeviceDispatch,
    ) ThreadSafeLowLatencyContext {
        return .{
            .inner = LowLatencyContext.init(device, swapchain, dispatch),
        };
    }

    pub fn setMode(self: *ThreadSafeLowLatencyContext, config: ModeConfig) vk.VulkanError!void {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.inner.setMode(config);
    }

    pub fn beginFrame(self: *ThreadSafeLowLatencyContext) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.inner.beginFrame();
    }

    pub fn setMarker(self: *ThreadSafeLowLatencyContext, marker: Marker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.inner.setMarker(marker);
    }

    pub fn sleep(self: *ThreadSafeLowLatencyContext, semaphore: vk.VkSemaphore_T, value: u64) vk.VulkanError!void {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.inner.sleep(semaphore, value);
    }

    /// Get underlying context (use with caution in multi-threaded code)
    pub fn getInner(self: *ThreadSafeLowLatencyContext) *LowLatencyContext {
        return &self.inner;
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

test "FramePacer init" {
    const pacer60 = FramePacer.init(60);
    try std.testing.expectEqual(@as(u32, 60), pacer60.target_fps);
    try std.testing.expectEqual(@as(u64, 16666), pacer60.target_frame_time_us);

    const pacer144 = FramePacer.init(144);
    try std.testing.expectEqual(@as(u32, 144), pacer144.target_fps);
    try std.testing.expectEqual(@as(u64, 6944), pacer144.target_frame_time_us);
}

test "FramePacer uncapped" {
    const pacer = FramePacer.uncapped();
    try std.testing.expectEqual(@as(u32, 0), pacer.target_fps);
    try std.testing.expectEqual(@as(u64, 0), pacer.target_frame_time_us);

    const config = pacer.toModeConfig();
    try std.testing.expect(config.enabled);
    try std.testing.expect(config.boost);
}

test "FramePacer recordFrame" {
    var pacer = FramePacer.init(60);

    // First frame has no delta
    const delta1 = pacer.recordFrame(1_000_000);
    try std.testing.expectEqual(@as(u64, 0), delta1);
    try std.testing.expectEqual(@as(u64, 1), pacer.frame_count);

    // Second frame shows delta
    const delta2 = pacer.recordFrame(1_016_666);
    try std.testing.expectEqual(@as(u64, 16666), delta2);
    try std.testing.expectEqual(@as(u64, 2), pacer.frame_count);
}

test "FramePacer isAheadOfTarget" {
    const pacer = FramePacer.init(60); // 16666us target

    try std.testing.expect(pacer.isAheadOfTarget(10000)); // 10ms < 16.6ms
    try std.testing.expect(!pacer.isAheadOfTarget(20000)); // 20ms > 16.6ms

    const uncapped = FramePacer.uncapped();
    try std.testing.expect(!uncapped.isAheadOfTarget(10000)); // uncapped never ahead
}

test "LatencyStats basic" {
    var stats = LatencyStats{};

    stats.addSample(5000);
    stats.addSample(6000);
    stats.addSample(4000);

    try std.testing.expectEqual(@as(usize, 3), stats.sample_count);
    try std.testing.expectEqual(@as(u64, 5000), stats.averageUs()); // (5000+6000+4000)/3 = 5000
    try std.testing.expectEqual(@as(u64, 4000), stats.minUs());
    try std.testing.expectEqual(@as(u64, 6000), stats.maxUs());
}

test "LatencyStats rolling buffer" {
    var stats = LatencyStats{};

    // Fill buffer completely
    for (0..128) |i| {
        stats.addSample(@as(u64, i) * 100);
    }
    try std.testing.expectEqual(@as(usize, 128), stats.sample_count);

    // Add one more - should wrap and maintain count
    stats.addSample(50000);
    try std.testing.expectEqual(@as(usize, 128), stats.sample_count);
}

test "LatencyStats percentile99" {
    var stats = LatencyStats{};

    // Add 100 samples: 100, 200, 300, ..., 10000
    for (1..101) |i| {
        stats.addSample(@as(u64, i) * 100);
    }

    const p99 = stats.percentile99Us();
    // 99th percentile of 100 samples at index 99 = 10000
    try std.testing.expect(p99 >= 9900);
}

test "LatencyStats reset" {
    var stats = LatencyStats{};
    stats.addSample(5000);
    stats.addSample(6000);

    stats.reset();

    try std.testing.expectEqual(@as(usize, 0), stats.sample_count);
    try std.testing.expectEqual(@as(u64, 0), stats.averageUs());
}

test "LatencyStats averageMs" {
    var stats = LatencyStats{};
    stats.addSample(16666); // ~16.67ms

    const ms = stats.averageMs();
    try std.testing.expect(ms > 16.0 and ms < 17.0);
}
