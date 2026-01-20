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
const frame_synthesis = @import("frame_synthesis.zig");

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

    /// Input frame dimensions
    width: u32,
    height: u32,

    /// Motion vector grid dimensions (derived from width/height and grid_size)
    grid_width: u32,
    grid_height: u32,

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

    // Dispatch tables
    dispatch: ?*const vk.DeviceDispatch,
    physical_device: ?vk.VkPhysicalDevice,
    instance_dispatch: ?*const vk.InstanceDispatch,

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
            .physical_device = null,
            .instance_dispatch = null,
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
        try flow.execute(cmd, null, .{});
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

    /// Create optical flow session and motion vector buffers
    /// Must be called after init() to set up GPU resources
    pub fn createResources(
        self: *MotionVectorContext,
        physical_device: vk.VkPhysicalDevice,
        instance_dispatch: *const vk.InstanceDispatch,
        get_instance_proc_addr: vk.PFN_vkGetInstanceProcAddr,
        get_device_proc_addr: vk.PFN_vkGetDeviceProcAddr,
    ) !void {
        const dispatch = self.dispatch orelse return error.NotInitialized;

        // Store for later use in memory allocation
        self.physical_device = physical_device;
        self.instance_dispatch = instance_dispatch;

        // Calculate motion vector grid dimensions
        const mv_dims = calculateMVDimensions(
            self.config.width,
            self.config.height,
            self.config.grid_size,
        );

        // Create optical flow context
        var flow_config = optical_flow.OpticalFlowConfig{
            .width = self.config.width,
            .height = self.config.height,
            .hint_grid_size = self.config.grid_size,
            .performance_level = self.config.performance,
            .output_grid_size = self.config.grid_size,
        };

        if (self.config.enable_cost) {
            flow_config.flags |= optical_flow.VK_OPTICAL_FLOW_SESSION_CREATE_ENABLE_COST_BIT_NV;
        }
        if (self.config.bidirectional) {
            flow_config.flags |= optical_flow.VK_OPTICAL_FLOW_SESSION_CREATE_BOTH_DIRECTIONS_BIT_NV;
        }

        self.flow_ctx = try optical_flow.OpticalFlowContext.init(
            self.device,
            physical_device,
            get_instance_proc_addr,
            get_device_proc_addr,
            flow_config,
        );

        // Create motion vector images
        // Format: R16G16_SFLOAT for motion vectors (closest to S10.5 fixed-point)
        const mv_format: u32 = vk.VK_FORMAT_R16G16_SFLOAT;

        // Forward flow image (required)
        const forward_image = try self.createFlowImage(dispatch, mv_dims.width, mv_dims.height, mv_format);

        // Backward flow image (optional, for quality mode)
        var backward_image: ?struct { image: vk.VkImage, view: vk.VkImageView, memory: vk.VkDeviceMemory } = null;
        if (self.config.bidirectional) {
            backward_image = try self.createFlowImage(dispatch, mv_dims.width, mv_dims.height, mv_format);
        }

        // Cost map (optional, for confidence weighting)
        var cost_image: ?struct { image: vk.VkImage, view: vk.VkImageView, memory: vk.VkDeviceMemory } = null;
        if (self.config.enable_cost) {
            // Cost map is single channel (R8_UNORM for 0-255 cost values)
            cost_image = try self.createFlowImage(dispatch, mv_dims.width, mv_dims.height, vk.VK_FORMAT_R8_UNORM);
        }

        self.mv_buffer = MotionVectorBuffer{
            .forward = forward_image.image,
            .forward_view = forward_image.view,
            .forward_memory = forward_image.memory,
            .backward = if (backward_image) |bi| bi.image else null,
            .backward_view = if (backward_image) |bi| bi.view else null,
            .backward_memory = if (backward_image) |bi| bi.memory else null,
            .cost = if (cost_image) |ci| ci.image else null,
            .cost_view = if (cost_image) |ci| ci.view else null,
            .cost_memory = if (cost_image) |ci| ci.memory else null,
            .width = self.config.width,
            .height = self.config.height,
            .grid_width = mv_dims.width,
            .grid_height = mv_dims.height,
            .grid_size = self.config.grid_size,
        };
    }

    /// Create a single flow image with memory
    fn createFlowImage(
        self: *MotionVectorContext,
        dispatch: *const vk.DeviceDispatch,
        width: u32,
        height: u32,
        format: u32,
    ) !struct { image: vk.VkImage, view: vk.VkImageView, memory: vk.VkDeviceMemory } {
        const device = self.device;
        const physical_device = self.physical_device orelse return error.NoPhysicalDevice;
        const instance_dispatch = self.instance_dispatch orelse return error.NoInstanceDispatch;

        const create_image = dispatch.vkCreateImage orelse return error.FunctionNotFound;
        const create_image_view = dispatch.vkCreateImageView orelse return error.FunctionNotFound;
        const get_mem_req = dispatch.vkGetImageMemoryRequirements orelse return error.FunctionNotFound;
        const alloc_memory = dispatch.vkAllocateMemory orelse return error.FunctionNotFound;
        const bind_image_memory = dispatch.vkBindImageMemory orelse return error.FunctionNotFound;

        // Create image
        const image_info = vk.VkImageCreateInfo{
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .format = format,
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
            .usage = vk.VK_IMAGE_USAGE_STORAGE_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        };

        var image: vk.VkImage = undefined;
        try vk.check(create_image(device, &image_info, null, &image));

        // Get memory requirements
        var mem_req: vk.VkMemoryRequirements = undefined;
        get_mem_req(device, image, &mem_req);

        // Find suitable device-local memory type
        const mem_type = try frame_synthesis.findMemoryType(
            physical_device,
            instance_dispatch,
            mem_req.memoryTypeBits,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );

        // Allocate memory (device local)
        const alloc_info = vk.VkMemoryAllocateInfo{
            .allocationSize = mem_req.size,
            .memoryTypeIndex = mem_type,
        };

        var memory: vk.VkDeviceMemory = undefined;
        try vk.check(alloc_memory(device, &alloc_info, null, &memory));

        // Bind memory
        try vk.check(bind_image_memory(device, image, memory, 0));

        // Create image view
        const view_info = vk.VkImageViewCreateInfo{
            .image = image,
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .components = .{},
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        var view: vk.VkImageView = undefined;
        try vk.check(create_image_view(device, &view_info, null, &view));

        return .{ .image = image, .view = view, .memory = memory };
    }

    /// Destroy motion vector buffer resources
    pub fn destroyResources(self: *MotionVectorContext) void {
        const dispatch = self.dispatch orelse return;
        const destroy_image = dispatch.vkDestroyImage orelse return;
        const destroy_view = dispatch.vkDestroyImageView orelse return;
        const free_memory = dispatch.vkFreeMemory orelse return;

        if (self.mv_buffer) |mvb| {
            destroy_view(dispatch.device, mvb.forward_view, null);
            destroy_image(dispatch.device, mvb.forward, null);
            free_memory(dispatch.device, mvb.forward_memory, null);

            if (mvb.backward_view) |v| destroy_view(dispatch.device, v, null);
            if (mvb.backward) |i| destroy_image(dispatch.device, i, null);
            if (mvb.backward_memory) |m| free_memory(dispatch.device, m, null);

            if (mvb.cost_view) |v| destroy_view(dispatch.device, v, null);
            if (mvb.cost) |i| destroy_image(dispatch.device, i, null);
            if (mvb.cost_memory) |m| free_memory(dispatch.device, m, null);

            self.mv_buffer = null;
        }
    }

    /// Cleanup resources
    pub fn deinit(self: *MotionVectorContext) void {
        self.destroyResources();
        if (self.flow_ctx) |*ctx| {
            ctx.deinit();
        }
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
