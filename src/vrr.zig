//! VRR (Variable Refresh Rate) Integration Module
//!
//! Bridge module between nvsync display detection and nvvk frame pacing.
//! Provides VRR configuration for present injection timing.
//!
//! Features:
//! - Query display VRR capabilities via nvsync
//! - Configure injection timing to match display VRR range
//! - LFC (Low Framerate Compensation) awareness
//! - Multiple detection backends: DRM, NVIDIA, Wayland

const std = @import("std");
const nvsync = @import("nvsync");

// =============================================================================
// VRR Configuration
// =============================================================================

/// Source of VRR configuration data
pub const VrrSource = enum {
    /// DRM/KMS sysfs detection
    drm,
    /// NVIDIA driver detection
    nvidia,
    /// Wayland compositor protocol
    wayland,
    /// Manual user configuration
    manual,
    /// No VRR detected
    none,

    pub fn name(self: VrrSource) []const u8 {
        return switch (self) {
            .drm => "DRM/KMS",
            .nvidia => "NVIDIA",
            .wayland => "Wayland",
            .manual => "Manual",
            .none => "None",
        };
    }
};

/// VRR configuration for frame pacing
pub const VrrConfig = struct {
    /// Minimum refresh rate (Hz)
    min_hz: u32 = 48,
    /// Maximum refresh rate (Hz)
    max_hz: u32 = 144,
    /// Low Framerate Compensation supported
    lfc_supported: bool = false,
    /// Detection source
    source: VrrSource = .none,
    /// VRR is enabled on display
    enabled: bool = false,
    /// Display name/connector
    display_name: ?[]const u8 = null,

    /// Get default VRR configuration (conservative values)
    pub fn default() VrrConfig {
        return .{
            .min_hz = 40,
            .max_hz = 144,
            .lfc_supported = false,
            .source = .manual,
            .enabled = false,
            .display_name = null,
        };
    }

    /// Get minimum interval in microseconds
    pub fn minIntervalUs(self: VrrConfig) u64 {
        return @as(u64, @intFromFloat(1_000_000.0 / @as(f32, @floatFromInt(self.max_hz))));
    }

    /// Get maximum interval in microseconds
    pub fn maxIntervalUs(self: VrrConfig) u64 {
        return @as(u64, @intFromFloat(1_000_000.0 / @as(f32, @floatFromInt(self.min_hz))));
    }

    /// Check if a target FPS is within VRR range
    pub fn isInRange(self: VrrConfig, fps: u32) bool {
        return fps >= self.min_hz and fps <= self.max_hz;
    }

    /// Get effective minimum Hz accounting for LFC
    pub fn effectiveMinHz(self: VrrConfig) u32 {
        if (self.lfc_supported) {
            // LFC doubles frames below min_hz, so effective minimum is min_hz/2
            return self.min_hz / 2;
        }
        return self.min_hz;
    }

    /// Check if LFC would be active at given FPS
    pub fn isLfcActive(self: VrrConfig, current_fps: u32) bool {
        return self.lfc_supported and current_fps < self.min_hz;
    }

    /// Calculate optimal injection interval for given frame time
    pub fn calculateInjectionInterval(self: VrrConfig, avg_frame_time_us: u64) u64 {
        const half_interval = avg_frame_time_us / 2;
        const min_interval = self.minIntervalUs() / 2;
        const max_interval = self.maxIntervalUs() / 2;

        return std.math.clamp(half_interval, min_interval, max_interval);
    }
};

// =============================================================================
// VRR Detection
// =============================================================================

/// Query VRR configuration from system
pub fn queryDisplay(allocator: std.mem.Allocator, display_name: ?[]const u8) !?VrrConfig {
    var manager = nvsync.DisplayManager.init(allocator);
    defer manager.deinit();

    try manager.scan();

    // Find the requested display or use first VRR-capable display
    var target_display: ?*const nvsync.Display = null;

    if (display_name) |name| {
        for (manager.displays.items) |*d| {
            if (std.mem.indexOf(u8, d.name, name) != null) {
                target_display = d;
                break;
            }
        }
    } else {
        // Find first VRR-capable display
        for (manager.displays.items) |*d| {
            if (d.vrr_capable or d.gsync_capable or d.gsync_compatible) {
                target_display = d;
                break;
            }
        }
    }

    if (target_display) |display| {
        // Determine source based on detection method
        const source: VrrSource = if (manager.nvidia_detected)
            .nvidia
        else if (manager.compositor != null)
            .wayland
        else
            .drm;

        return .{
            .min_hz = display.min_hz,
            .max_hz = display.max_hz,
            .lfc_supported = display.lfc_supported,
            .source = source,
            .enabled = display.vrr_enabled,
            .display_name = try allocator.dupe(u8, display.name),
        };
    }

    return null;
}

/// Query first available VRR display
pub fn queryFirstDisplay(allocator: std.mem.Allocator) !?VrrConfig {
    return queryDisplay(allocator, null);
}

/// Check if any VRR display is available
pub fn isVrrAvailable(allocator: std.mem.Allocator) bool {
    const config = queryFirstDisplay(allocator) catch return false;
    if (config) |cfg| {
        if (cfg.display_name) |name| {
            allocator.free(name);
        }
        return true;
    }
    return false;
}

/// Get system VRR status summary
pub const VrrStatus = struct {
    nvidia_detected: bool,
    display_count: usize,
    vrr_capable_count: usize,
    vrr_enabled_count: usize,
    compositor: ?[]const u8,
    is_wayland: bool,
};

pub fn getSystemStatus(allocator: std.mem.Allocator) !VrrStatus {
    const status = try nvsync.getSystemStatus(allocator);

    return .{
        .nvidia_detected = status.nvidia_detected,
        .display_count = status.display_count,
        .vrr_capable_count = status.vrr_capable_count,
        .vrr_enabled_count = status.vrr_enabled_count,
        .compositor = status.compositor,
        .is_wayland = status.is_wayland,
    };
}

// =============================================================================
// LFC Handling
// =============================================================================

/// LFC state tracker for frame pacing
pub const LfcState = struct {
    active: bool = false,
    transition_frame: u64 = 0,
    doubled_frames: u64 = 0,

    /// Update LFC state based on current FPS
    pub fn update(self: *LfcState, current_fps: u32, config: VrrConfig, frame_number: u64) void {
        const should_be_active = config.isLfcActive(current_fps);

        if (should_be_active and !self.active) {
            // Entering LFC
            self.active = true;
            self.transition_frame = frame_number;
        } else if (!should_be_active and self.active) {
            // Exiting LFC
            self.active = false;
            self.transition_frame = frame_number;
        }

        if (self.active) {
            self.doubled_frames += 1;
        }
    }

    /// Check if frame injection should be paused during LFC
    pub fn shouldPauseInjection(self: LfcState) bool {
        // During LFC, the display driver handles frame doubling
        // We should pause injection to avoid conflicts
        return self.active;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "VrrConfig defaults" {
    const config = VrrConfig.default();
    try std.testing.expectEqual(@as(u32, 40), config.min_hz);
    try std.testing.expectEqual(@as(u32, 144), config.max_hz);
    try std.testing.expect(!config.lfc_supported);
    try std.testing.expectEqual(VrrSource.manual, config.source);
}

test "VrrConfig intervals" {
    const config = VrrConfig{
        .min_hz = 48,
        .max_hz = 144,
        .lfc_supported = true,
        .source = .drm,
        .enabled = true,
    };

    // 144 Hz = ~6944 us
    try std.testing.expectApproxEqAbs(@as(f32, 6944.0), @as(f32, @floatFromInt(config.minIntervalUs())), 5.0);

    // 48 Hz = ~20833 us
    try std.testing.expectApproxEqAbs(@as(f32, 20833.0), @as(f32, @floatFromInt(config.maxIntervalUs())), 5.0);
}

test "VrrConfig LFC" {
    const config = VrrConfig{
        .min_hz = 48,
        .max_hz = 144,
        .lfc_supported = true,
        .source = .drm,
        .enabled = true,
    };

    try std.testing.expectEqual(@as(u32, 24), config.effectiveMinHz());
    try std.testing.expect(config.isLfcActive(30));
    try std.testing.expect(!config.isLfcActive(60));
}

test "VrrConfig range check" {
    const config = VrrConfig{
        .min_hz = 48,
        .max_hz = 144,
        .lfc_supported = false,
        .source = .drm,
        .enabled = true,
    };

    try std.testing.expect(config.isInRange(60));
    try std.testing.expect(config.isInRange(144));
    try std.testing.expect(!config.isInRange(30));
    try std.testing.expect(!config.isInRange(165));
}

test "VrrConfig injection interval" {
    const config = VrrConfig{
        .min_hz = 48,
        .max_hz = 144,
        .lfc_supported = false,
        .source = .drm,
        .enabled = true,
    };

    // At 60 FPS (16667 us), injection at half = 8333 us
    const interval = config.calculateInjectionInterval(16667);
    try std.testing.expectEqual(@as(u64, 8333), interval);

    // At 30 FPS (33333 us), clamped to max/2 = ~10416 us
    const slow_interval = config.calculateInjectionInterval(33333);
    try std.testing.expect(slow_interval <= config.maxIntervalUs() / 2);
}

test "LfcState transitions" {
    const config = VrrConfig{
        .min_hz = 48,
        .max_hz = 144,
        .lfc_supported = true,
        .source = .drm,
        .enabled = true,
    };

    var state = LfcState{};

    // Start above VRR min
    state.update(60, config, 0);
    try std.testing.expect(!state.active);
    try std.testing.expect(!state.shouldPauseInjection());

    // Drop below VRR min - enter LFC
    state.update(30, config, 1);
    try std.testing.expect(state.active);
    try std.testing.expect(state.shouldPauseInjection());

    // Stay in LFC
    state.update(35, config, 2);
    try std.testing.expect(state.active);

    // Return above min - exit LFC
    state.update(60, config, 3);
    try std.testing.expect(!state.active);
}

test "VrrSource names" {
    try std.testing.expectEqualStrings("DRM/KMS", VrrSource.drm.name());
    try std.testing.expectEqualStrings("NVIDIA", VrrSource.nvidia.name());
    try std.testing.expectEqualStrings("Wayland", VrrSource.wayland.name());
}
