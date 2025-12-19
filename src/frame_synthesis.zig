//! Frame Synthesis
//!
//! Generates intermediate frames using motion vectors.
//! Performance mode: Simple forward warp with linear blend.
//! Quality mode: Bidirectional warp with confidence weighting (future).
//!
//! The synthesized frame is inserted between real frames to double
//! the effective frame rate.

const std = @import("std");
const vk = @import("vulkan.zig");
const motion_vectors = @import("motion_vectors.zig");

// =============================================================================
// Types
// =============================================================================

/// Quality mode for frame synthesis
pub const QualityMode = enum {
    /// Fast linear blend (default for performance mode)
    performance,
    /// Bidirectional warp with cost-weighted blend
    balanced,
    /// High quality with disocclusion handling
    quality,
};

/// Frame synthesis context
pub const FrameSynthesisContext = struct {
    device: ?vk.VkDevice,
    allocator: std.mem.Allocator,

    // Compute pipelines (optional until created)
    warp_pipeline: ?vk.VkPipeline = null,
    warp_pipeline_layout: ?vk.VkPipelineLayout = null,
    blend_pipeline: ?vk.VkPipeline = null,
    blend_pipeline_layout: ?vk.VkPipelineLayout = null,

    // Descriptor resources
    descriptor_pool: ?vk.VkDescriptorPool = null,
    descriptor_set_layout: ?vk.VkDescriptorSetLayout = null,
    descriptor_set: ?vk.VkDescriptorSet = null,

    // Output image
    output_image: ?vk.VkImage = null,
    output_view: ?vk.VkImageView = null,
    output_memory: ?vk.VkDeviceMemory = null,

    // Scratch buffers for warping
    warp_scratch: ?vk.VkImage = null,
    warp_scratch_view: ?vk.VkImageView = null,
    warp_scratch_memory: ?vk.VkDeviceMemory = null,

    // Quality mode resources (bidirectional warp + confidence blend)
    quality_pipeline: ?QualityPipeline = null,

    // Configuration
    width: u32,
    height: u32,
    mode: QualityMode,

    // Frame timing for interpolation factor
    interpolation_factor: f32,

    // Quality mode parameters
    cost_scale: f32 = 0.004, // 1/255 default
    min_confidence: f32 = 0.1,
    occlusion_threshold: f32 = 128.0,

    // Dispatch table
    dispatch: ?*const vk.DeviceDispatch,

    /// Initialize frame synthesis
    pub fn init(
        device: ?vk.VkDevice,
        width: u32,
        height: u32,
        mode: QualityMode,
        dispatch: ?*const vk.DeviceDispatch,
        allocator: std.mem.Allocator,
    ) FrameSynthesisContext {
        return .{
            .device = device,
            .allocator = allocator,
            .width = width,
            .height = height,
            .mode = mode,
            .interpolation_factor = 0.5, // Default to midpoint
            .dispatch = dispatch,
        };
    }

    /// Set interpolation factor (0.0 = frame N-1, 1.0 = frame N)
    pub fn setInterpolationFactor(self: *FrameSynthesisContext, factor: f32) void {
        self.interpolation_factor = std.math.clamp(factor, 0.0, 1.0);
    }

    /// Synthesize an intermediate frame
    /// Performance mode: Linear blend with forward warp
    pub fn synthesize(
        self: *FrameSynthesisContext,
        cmd: vk.VkCommandBuffer,
        prev_frame: vk.VkImageView,
        curr_frame: vk.VkImageView,
        mv_buffer: *const motion_vectors.MotionVectorBuffer,
    ) !vk.VkImageView {
        _ = cmd;
        _ = prev_frame;
        _ = curr_frame;
        _ = mv_buffer;

        // In full implementation:
        // 1. Forward warp prev_frame using motion vectors * (1 - factor)
        // 2. Forward warp curr_frame using motion vectors * (-factor)
        // 3. Linear blend the two warped images

        // For performance mode (simple implementation):
        // - Single forward warp of prev_frame
        // - Alpha blend with curr_frame based on interpolation factor

        return self.output_view;
    }

    /// Get the output image view
    pub fn getOutputView(self: *const FrameSynthesisContext) ?vk.VkImageView {
        return self.output_view;
    }

    /// Get the output image
    pub fn getOutputImage(self: *const FrameSynthesisContext) ?vk.VkImage {
        return self.output_image;
    }

    /// Cleanup resources
    pub fn deinit(self: *FrameSynthesisContext) void {
        _ = self;
        // Note: Caller is responsible for destroying Vulkan resources
    }
};

/// Push constants for warp shader
pub const WarpPushConstants = extern struct {
    /// Motion vector scale (based on grid size)
    mv_scale_x: f32,
    mv_scale_y: f32,
    /// Interpolation factor (0.0 = prev, 1.0 = curr)
    interpolation: f32,
    /// Direction (-1.0 for backward, 1.0 for forward)
    direction: f32,
};

/// Push constants for linear blend shader (performance mode)
pub const BlendPushConstants = extern struct {
    /// Blend weight for warped frame
    weight: f32,
    /// Reserved for future use
    _reserved: [3]f32 = .{ 0, 0, 0 },
};

/// Push constants for confidence blend shader (quality mode)
pub const ConfidenceBlendPushConstants = extern struct {
    /// Interpolation factor (0.0 = prev, 1.0 = curr)
    interpolation: f32,
    /// Scale factor for cost -> confidence mapping
    cost_scale: f32,
    /// Minimum confidence threshold
    min_confidence: f32,
    /// Reserved
    _reserved: f32 = 0,
};

/// Push constants for occlusion fill shader
pub const OcclusionFillPushConstants = extern struct {
    /// Cost threshold for occlusion detection
    occlusion_threshold: f32,
    /// Search radius for neighbor fill
    fill_radius: f32,
    /// Interpolation factor
    interpolation: f32,
    /// Reserved
    _reserved: f32 = 0,
};

/// Quality mode pipeline resources
pub const QualityPipeline = struct {
    // Additional pipelines for quality mode
    backward_warp_pipeline: ?vk.VkPipeline = null,
    confidence_blend_pipeline: ?vk.VkPipeline = null,
    occlusion_fill_pipeline: ?vk.VkPipeline = null,

    // Additional images for bidirectional warping
    backward_warped: ?vk.VkImage = null,
    backward_warped_view: ?vk.VkImageView = null,
    backward_warped_memory: ?vk.VkDeviceMemory = null,

    // Filled output after occlusion handling
    filled_output: ?vk.VkImage = null,
    filled_output_view: ?vk.VkImageView = null,
    filled_output_memory: ?vk.VkDeviceMemory = null,
};

// =============================================================================
// Shader Binding Layout
// =============================================================================

/// Descriptor binding indices for synthesis shaders
pub const BindingIndex = struct {
    pub const input_prev: u32 = 0;
    pub const input_curr: u32 = 1;
    pub const motion_vectors: u32 = 2;
    pub const cost_map: u32 = 3;
    pub const output: u32 = 4;
    pub const scratch: u32 = 5;
};

/// Create descriptor set layout for frame synthesis
pub fn createDescriptorSetLayout(device: vk.VkDevice, dispatch: *const vk.DeviceDispatch) !vk.VkDescriptorSetLayout {
    const bindings = [_]vk.VkDescriptorSetLayoutBinding{
        // Input previous frame
        .{
            .binding = BindingIndex.input_prev,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = null,
        },
        // Input current frame
        .{
            .binding = BindingIndex.input_curr,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = null,
        },
        // Motion vectors
        .{
            .binding = BindingIndex.motion_vectors,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = null,
        },
        // Cost map (optional)
        .{
            .binding = BindingIndex.cost_map,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = null,
        },
        // Output image
        .{
            .binding = BindingIndex.output,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = null,
        },
    };

    var layout: vk.VkDescriptorSetLayout = undefined;
    const create_info = vk.VkDescriptorSetLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .bindingCount = bindings.len,
        .pBindings = &bindings,
    };

    try vk.check(dispatch.vkCreateDescriptorSetLayout(device, &create_info, null, &layout));
    return layout;
}

// =============================================================================
// Tests
// =============================================================================

test "QualityMode" {
    const perf: QualityMode = .performance;
    try std.testing.expectEqual(QualityMode.performance, perf);
}

test "WarpPushConstants size" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(WarpPushConstants));
}

test "BlendPushConstants size" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(BlendPushConstants));
}

test "ConfidenceBlendPushConstants size" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(ConfidenceBlendPushConstants));
}

test "OcclusionFillPushConstants size" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(OcclusionFillPushConstants));
}

test "QualityPipeline defaults" {
    const qp = QualityPipeline{};
    try std.testing.expect(qp.backward_warp_pipeline == null);
    try std.testing.expect(qp.confidence_blend_pipeline == null);
}

test "BindingIndex values" {
    try std.testing.expectEqual(@as(u32, 0), BindingIndex.input_prev);
    try std.testing.expectEqual(@as(u32, 4), BindingIndex.output);
}
