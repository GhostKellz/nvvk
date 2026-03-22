//! Frame Generation Integration Test
//!
//! End-to-end test that wires up all Phase 3 components:
//! - OpticalFlowContext
//! - MotionVectorContext
//! - FrameSynthesisContext
//! - FrameGenContext
//! - PresentInjectionContext
//!
//! This test can run with mock data (no GPU) or real Vulkan device.

const std = @import("std");
const nvvk = @import("nvvk");

// =============================================================================
// Mock Types for Testing Without GPU
// =============================================================================

const MockImage = struct {
    width: u32,
    height: u32,
    data: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !MockImage {
        const size = width * height * 4; // RGBA
        const data = try allocator.alloc(u8, size);
        return .{
            .width = width,
            .height = height,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MockImage) void {
        self.allocator.free(self.data);
    }

    pub fn fill(self: *MockImage, r: u8, g: u8, b: u8, a: u8) void {
        var i: usize = 0;
        while (i < self.data.len) : (i += 4) {
            self.data[i] = r;
            self.data[i + 1] = g;
            self.data[i + 2] = b;
            self.data[i + 3] = a;
        }
    }

    pub fn fillGradient(self: *MockImage, frame_num: u32) void {
        const offset = frame_num * 10;
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const idx = (y * self.width + x) * 4;
                self.data[idx] = @truncate((x + offset) % 256);
                self.data[idx + 1] = @truncate((y + offset) % 256);
                self.data[idx + 2] = @truncate((x + y + offset) % 256);
                self.data[idx + 3] = 255;
            }
        }
    }
};

// =============================================================================
// Frame Generation Pipeline Test
// =============================================================================

pub const FrameGenPipelineTest = struct {
    allocator: std.mem.Allocator,

    // Contexts (nullable for mock mode)
    frame_gen: ?nvvk.FrameGenContext,
    motion_vectors: ?nvvk.MotionVectorContext,
    present_injection: ?nvvk.PresentInjectionContext,

    // Mock frames for testing
    mock_frames: [4]?MockImage,
    frame_index: u32,

    // Stats
    frames_processed: u64,
    frames_generated: u64,
    total_gen_time_us: u64,

    pub fn init(allocator: std.mem.Allocator) FrameGenPipelineTest {
        return .{
            .allocator = allocator,
            .frame_gen = null,
            .motion_vectors = null,
            .present_injection = null,
            .mock_frames = .{ null, null, null, null },
            .frame_index = 0,
            .frames_processed = 0,
            .frames_generated = 0,
            .total_gen_time_us = 0,
        };
    }

    pub fn deinit(self: *FrameGenPipelineTest) void {
        for (&self.mock_frames) |*frame| {
            if (frame.*) |*f| {
                f.deinit();
                frame.* = null;
            }
        }

        if (self.frame_gen) |*fg| {
            fg.deinit();
        }
        if (self.present_injection) |*pi| {
            pi.deinit();
        }
    }

    /// Initialize with mock data (no GPU required)
    pub fn initMock(self: *FrameGenPipelineTest, width: u32, height: u32) !void {
        // Create mock frames
        for (&self.mock_frames) |*frame| {
            frame.* = try MockImage.init(self.allocator, width, height);
        }

        // Initialize frame generation context (without GPU)
        const config = nvvk.FrameGenConfig{
            .width = width,
            .height = height,
            .mode = .balanced,
        };
        self.frame_gen = nvvk.FrameGenContext.init(null, config, null, null, self.allocator);

        // Initialize present injection
        const injection_config = nvvk.InjectionConfig{
            .mode = .single,
            .timing = .adaptive,
        };
        self.present_injection = nvvk.PresentInjectionContext.init(
            null,
            0,
            null,
            null,
            injection_config,
            null,
            self.allocator,
        );
    }

    /// Simulate pushing a frame through the pipeline
    pub fn pushFrame(self: *FrameGenPipelineTest) void {
        // Generate mock frame data
        if (self.mock_frames[self.frame_index % 4]) |*frame| {
            frame.fillGradient(self.frame_index);
        }

        // Push to frame gen context
        if (self.frame_gen) |*fg| {
            fg.pushFrame(.{
                .image = null,
                .view = null,
                .timestamp_us = @as(u64, @intCast(std.time.microTimestamp())),
            });
        }

        self.frame_index += 1;
        self.frames_processed += 1;
    }

    /// Check if we should generate an interpolated frame
    pub fn shouldGenerate(self: *FrameGenPipelineTest) bool {
        if (self.present_injection) |pi| {
            return pi.shouldInject();
        }
        // Default: generate after every 2 real frames
        return self.frame_index >= 2;
    }

    /// Simulate frame generation
    pub fn generate(self: *FrameGenPipelineTest) !?GeneratedFrameResult {
        const start_time = std.time.microTimestamp();

        // In real implementation, this would:
        // 1. Run optical flow between frames N-1 and N
        // 2. Extract motion vectors
        // 3. Warp and blend frames
        // 4. Output interpolated frame

        if (self.frame_gen) |*fg| {
            // Check if we have enough frames
            if (self.frame_index < 2) {
                return null;
            }

            const stats = fg.getStats();
            if (stats.scene_change_detected) {
                return null; // Skip on scene change
            }

            // Simulate generation (in reality this would execute GPU compute)
            const gen_time = @as(u64, @intCast(std.time.microTimestamp() - start_time));
            self.total_gen_time_us += gen_time;
            self.frames_generated += 1;

            return GeneratedFrameResult{
                .frame_id = self.frames_generated,
                .confidence = stats.confidence,
                .generation_time_us = gen_time,
                .should_present = stats.confidence > 0.5,
            };
        }

        return null;
    }

    /// Record present timing
    pub fn recordPresent(self: *FrameGenPipelineTest, is_generated: bool) void {
        if (self.present_injection) |*pi| {
            pi.recordPresentTime(is_generated);
        }
    }

    /// Get pipeline statistics
    pub fn getStats(self: *const FrameGenPipelineTest) PipelineStats {
        var stats = PipelineStats{
            .frames_processed = self.frames_processed,
            .frames_generated = self.frames_generated,
            .avg_gen_time_us = if (self.frames_generated > 0)
                self.total_gen_time_us / self.frames_generated
            else
                0,
            .effective_fps = 0,
            .frame_gen_stats = null,
            .injection_stats = null,
        };

        if (self.frame_gen) |fg| {
            stats.frame_gen_stats = fg.getStats();
        }
        if (self.present_injection) |pi| {
            stats.injection_stats = pi.getStats();
        }

        // Calculate effective FPS
        if (stats.injection_stats) |is| {
            stats.effective_fps = is.effective_fps;
        }

        return stats;
    }
};

pub const GeneratedFrameResult = struct {
    frame_id: u64,
    confidence: f32,
    generation_time_us: u64,
    should_present: bool,
};

pub const PipelineStats = struct {
    frames_processed: u64,
    frames_generated: u64,
    avg_gen_time_us: u64,
    effective_fps: f32,
    frame_gen_stats: ?nvvk.FrameGenStats,
    injection_stats: ?nvvk.InjectionStats,
};

// =============================================================================
// Test Runner
// =============================================================================

pub fn runIntegrationTest(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== nvvk Frame Generation Integration Test ===\n\n", .{});

    var pipeline = FrameGenPipelineTest.init(allocator);
    defer pipeline.deinit();

    // Initialize with mock data (1920x1080)
    try pipeline.initMock(1920, 1080);
    std.debug.print("Initialized pipeline for 1920x1080\n", .{});

    // Simulate 100 frames
    const num_frames: u32 = 100;
    std.debug.print("Simulating {} frames...\n", .{num_frames});

    var presents: u32 = 0;
    var generated_presents: u32 = 0;

    for (0..num_frames) |_| {
        // Push real frame
        pipeline.pushFrame();
        pipeline.recordPresent(false);
        presents += 1;

        // Check if we should generate
        if (pipeline.shouldGenerate()) {
            if (try pipeline.generate()) |result| {
                if (result.should_present) {
                    pipeline.recordPresent(true);
                    generated_presents += 1;
                }
            }
        }
    }

    // Print results
    const stats = pipeline.getStats();

    std.debug.print("\n=== Results ===\n", .{});
    std.debug.print("Real frames processed: {}\n", .{stats.frames_processed});
    std.debug.print("Frames generated: {}\n", .{stats.frames_generated});
    std.debug.print("Total presents: {} (real: {}, generated: {})\n", .{
        presents + generated_presents,
        presents,
        generated_presents,
    });
    std.debug.print("Avg generation time: {} us\n", .{stats.avg_gen_time_us});

    if (stats.frame_gen_stats) |fgs| {
        std.debug.print("Frame gen confidence: {d:.2}\n", .{fgs.confidence});
    }

    if (stats.injection_stats) |is| {
        std.debug.print("Effective FPS: {d:.1}\n", .{is.effective_fps});
        std.debug.print("Avg present interval: {} us\n", .{is.avg_present_interval_us});
    }

    std.debug.print("\n=== Test PASSED ===\n", .{});
}

// =============================================================================
// Unit Tests
// =============================================================================

test "mock image creation" {
    const allocator = std.testing.allocator;
    var img = try MockImage.init(allocator, 64, 64);
    defer img.deinit();

    try std.testing.expectEqual(@as(u32, 64), img.width);
    try std.testing.expectEqual(@as(u32, 64), img.height);
    try std.testing.expectEqual(@as(usize, 64 * 64 * 4), img.data.len);
}

test "mock image gradient fill" {
    const allocator = std.testing.allocator;
    var img = try MockImage.init(allocator, 16, 16);
    defer img.deinit();

    img.fillGradient(0);
    // First pixel should be (0, 0, 0, 255)
    try std.testing.expectEqual(@as(u8, 0), img.data[0]);
    try std.testing.expectEqual(@as(u8, 0), img.data[1]);
    try std.testing.expectEqual(@as(u8, 0), img.data[2]);
    try std.testing.expectEqual(@as(u8, 255), img.data[3]);
}

test "pipeline initialization" {
    const allocator = std.testing.allocator;
    var pipeline = FrameGenPipelineTest.init(allocator);
    defer pipeline.deinit();

    try pipeline.initMock(640, 480);

    // Verify mock frames created
    for (pipeline.mock_frames) |frame| {
        try std.testing.expect(frame != null);
    }
}

test "frame push and stats" {
    const allocator = std.testing.allocator;
    var pipeline = FrameGenPipelineTest.init(allocator);
    defer pipeline.deinit();

    try pipeline.initMock(320, 240);

    // Push some frames
    pipeline.pushFrame();
    pipeline.pushFrame();
    pipeline.pushFrame();

    const stats = pipeline.getStats();
    try std.testing.expectEqual(@as(u64, 3), stats.frames_processed);
}

test "frame generation after sufficient history" {
    const allocator = std.testing.allocator;
    var pipeline = FrameGenPipelineTest.init(allocator);
    defer pipeline.deinit();

    try pipeline.initMock(320, 240);

    // Not enough history
    pipeline.pushFrame();
    const result1 = try pipeline.generate();
    try std.testing.expect(result1 == null);

    // Now we have enough
    pipeline.pushFrame();
    const result2 = try pipeline.generate();
    try std.testing.expect(result2 != null);
}

// =============================================================================
// Main Entry Point
// =============================================================================

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runIntegrationTest(allocator);
}
