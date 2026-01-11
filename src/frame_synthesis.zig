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
    physical_device: ?vk.VkPhysicalDevice = null,
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

    // Dispatch tables
    dispatch: ?*const vk.DeviceDispatch,
    instance_dispatch: ?*const vk.InstanceDispatch = null,

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

    /// Create GPU resources (pipelines, images, descriptors)
    pub fn createResources(
        self: *FrameSynthesisContext,
        physical_device: vk.VkPhysicalDevice,
        instance_dispatch: *const vk.InstanceDispatch,
    ) !void {
        const device = self.device orelse return error.NoDevice;
        const dispatch = self.dispatch orelse return error.NoDispatch;

        // Store for later use
        self.physical_device = physical_device;
        self.instance_dispatch = instance_dispatch;

        // Create descriptor set layout
        self.descriptor_set_layout = try createDescriptorSetLayout(device, dispatch);

        // Create pipeline layout with push constants
        const push_constant_range = vk.VkPushConstantRange{
            .stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT,
            .offset = 0,
            .size = @sizeOf(WarpPushConstants),
        };

        const layout_info = vk.VkPipelineLayoutCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = 1,
            .pSetLayouts = @ptrCast(&self.descriptor_set_layout),
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &push_constant_range,
        };

        const create_layout_fn = dispatch.vkCreatePipelineLayout orelse return error.FunctionNotFound;
        try vk.check(create_layout_fn(device, &layout_info, null, &self.warp_pipeline_layout));
        self.blend_pipeline_layout = self.warp_pipeline_layout; // Same layout

        // Load shader modules
        const warp_shader = try loadShaderModule(device, dispatch, @embedFile("../shaders/forward_warp.spv"));
        defer if (dispatch.vkDestroyShaderModule) |destroy_fn| destroy_fn(device, warp_shader, null);

        const blend_shader = try loadShaderModule(device, dispatch, @embedFile("../shaders/linear_blend.spv"));
        defer if (dispatch.vkDestroyShaderModule) |destroy_fn| destroy_fn(device, blend_shader, null);

        // Create warp compute pipeline
        self.warp_pipeline = try createComputePipeline(device, dispatch, warp_shader, self.warp_pipeline_layout.?);

        // Create blend compute pipeline
        self.blend_pipeline = try createComputePipeline(device, dispatch, blend_shader, self.blend_pipeline_layout.?);

        // Create output image
        try self.createOutputImage();

        // Create descriptor pool and set
        try self.createDescriptorResources();
    }

    fn createOutputImage(self: *FrameSynthesisContext) !void {
        const device = self.device orelse return error.NoDevice;
        const dispatch = self.dispatch orelse return error.NoDispatch;
        const physical_device = self.physical_device orelse return error.NoPhysicalDevice;
        const instance_dispatch = self.instance_dispatch orelse return error.NoInstanceDispatch;

        const create_image_fn = dispatch.vkCreateImage orelse return error.FunctionNotFound;
        const get_mem_reqs_fn = dispatch.vkGetImageMemoryRequirements orelse return error.FunctionNotFound;
        const alloc_memory_fn = dispatch.vkAllocateMemory orelse return error.FunctionNotFound;
        const bind_memory_fn = dispatch.vkBindImageMemory orelse return error.FunctionNotFound;
        const create_view_fn = dispatch.vkCreateImageView orelse return error.FunctionNotFound;

        const image_info = vk.VkImageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .extent = .{ .width = self.width, .height = self.height, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
            .usage = vk.VK_IMAGE_USAGE_STORAGE_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT | vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        };

        try vk.check(create_image_fn(device, &image_info, null, &self.output_image));

        // Allocate memory
        var mem_reqs: vk.VkMemoryRequirements = undefined;
        get_mem_reqs_fn(device, self.output_image.?, &mem_reqs);

        const mem_type = try findMemoryType(physical_device, instance_dispatch, mem_reqs.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

        const alloc_info = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = mem_reqs.size,
            .memoryTypeIndex = mem_type,
        };

        try vk.check(alloc_memory_fn(device, &alloc_info, null, &self.output_memory));
        try vk.check(bind_memory_fn(device, self.output_image.?, self.output_memory.?, 0));

        // Create image view
        const view_info = vk.VkImageViewCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = self.output_image.?,
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .components = .{ .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY },
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        try vk.check(create_view_fn(device, &view_info, null, &self.output_view));
    }

    fn createDescriptorResources(self: *FrameSynthesisContext) !void {
        const device = self.device orelse return error.NoDevice;
        const dispatch = self.dispatch orelse return error.NoDispatch;

        const create_pool_fn = dispatch.vkCreateDescriptorPool orelse return error.FunctionNotFound;
        const alloc_sets_fn = dispatch.vkAllocateDescriptorSets orelse return error.FunctionNotFound;

        // Create descriptor pool
        const pool_sizes = [_]vk.VkDescriptorPoolSize{
            .{ .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 4 },
            .{ .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = 2 },
        };

        const pool_info = vk.VkDescriptorPoolCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .maxSets = 2,
            .poolSizeCount = pool_sizes.len,
            .pPoolSizes = &pool_sizes,
        };

        try vk.check(create_pool_fn(device, &pool_info, null, &self.descriptor_pool));

        // Allocate descriptor set
        const alloc_info = vk.VkDescriptorSetAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = null,
            .descriptorPool = self.descriptor_pool.?,
            .descriptorSetCount = 1,
            .pSetLayouts = @ptrCast(&self.descriptor_set_layout),
        };

        try vk.check(alloc_sets_fn(device, &alloc_info, &self.descriptor_set));
    }

    /// Create quality mode resources (bidirectional warp, confidence blend, occlusion fill)
    /// Called automatically if mode is .balanced or .quality
    pub fn createQualityResources(self: *FrameSynthesisContext) !void {
        if (self.mode == .performance) return;

        const device = self.device orelse return error.NoDevice;
        const dispatch = self.dispatch orelse return error.NoDispatch;
        const pipeline_layout = self.warp_pipeline_layout orelse return error.NoPipelineLayout;

        // Load quality mode shaders
        const backward_warp_shader = try loadShaderModule(device, dispatch, @embedFile("../shaders/backward_warp.spv"));
        defer if (dispatch.vkDestroyShaderModule) |destroy_fn| destroy_fn(device, backward_warp_shader, null);

        const confidence_blend_shader = try loadShaderModule(device, dispatch, @embedFile("../shaders/confidence_blend.spv"));
        defer if (dispatch.vkDestroyShaderModule) |destroy_fn| destroy_fn(device, confidence_blend_shader, null);

        const occlusion_fill_shader = try loadShaderModule(device, dispatch, @embedFile("../shaders/occlusion_fill.spv"));
        defer if (dispatch.vkDestroyShaderModule) |destroy_fn| destroy_fn(device, occlusion_fill_shader, null);

        // Create quality pipelines
        var qp = QualityPipeline{};

        qp.backward_warp_pipeline = try createComputePipeline(device, dispatch, backward_warp_shader, pipeline_layout);
        qp.confidence_blend_pipeline = try createComputePipeline(device, dispatch, confidence_blend_shader, pipeline_layout);

        // Occlusion fill only needed for quality mode
        if (self.mode == .quality) {
            qp.occlusion_fill_pipeline = try createComputePipeline(device, dispatch, occlusion_fill_shader, pipeline_layout);
        }

        // Create additional images for bidirectional warping
        if (self.physical_device != null and self.instance_dispatch != null) {
            try self.createQualityImages(&qp);
        }

        self.quality_pipeline = qp;
    }

    fn createQualityImages(self: *FrameSynthesisContext, qp: *QualityPipeline) !void {
        const device = self.device orelse return error.NoDevice;
        const dispatch = self.dispatch orelse return error.NoDispatch;
        const physical_device = self.physical_device orelse return error.NoPhysicalDevice;
        const instance_dispatch = self.instance_dispatch orelse return error.NoInstanceDispatch;

        const create_image_fn = dispatch.vkCreateImage orelse return error.FunctionNotFound;
        const get_mem_reqs_fn = dispatch.vkGetImageMemoryRequirements orelse return error.FunctionNotFound;
        const alloc_memory_fn = dispatch.vkAllocateMemory orelse return error.FunctionNotFound;
        const bind_memory_fn = dispatch.vkBindImageMemory orelse return error.FunctionNotFound;
        const create_view_fn = dispatch.vkCreateImageView orelse return error.FunctionNotFound;

        const image_info = vk.VkImageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .extent = .{ .width = self.width, .height = self.height, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
            .usage = vk.VK_IMAGE_USAGE_STORAGE_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        };

        // Backward warped image
        try vk.check(create_image_fn(device, &image_info, null, &qp.backward_warped));

        var mem_reqs: vk.VkMemoryRequirements = undefined;
        get_mem_reqs_fn(device, qp.backward_warped.?, &mem_reqs);

        const mem_type = try findMemoryType(physical_device, instance_dispatch, mem_reqs.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

        const alloc_info = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = mem_reqs.size,
            .memoryTypeIndex = mem_type,
        };

        try vk.check(alloc_memory_fn(device, &alloc_info, null, &qp.backward_warped_memory));
        try vk.check(bind_memory_fn(device, qp.backward_warped.?, qp.backward_warped_memory.?, 0));

        const view_info = vk.VkImageViewCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = qp.backward_warped.?,
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .components = .{ .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY },
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        try vk.check(create_view_fn(device, &view_info, null, &qp.backward_warped_view));

        // Filled output image (for quality mode occlusion fill)
        if (self.mode == .quality) {
            try vk.check(create_image_fn(device, &image_info, null, &qp.filled_output));
            get_mem_reqs_fn(device, qp.filled_output.?, &mem_reqs);
            try vk.check(alloc_memory_fn(device, &alloc_info, null, &qp.filled_output_memory));
            try vk.check(bind_memory_fn(device, qp.filled_output.?, qp.filled_output_memory.?, 0));

            var filled_view_info = view_info;
            filled_view_info.image = qp.filled_output.?;
            try vk.check(create_view_fn(device, &filled_view_info, null, &qp.filled_output_view));
        }
    }

    /// Synthesize using quality mode (bidirectional warp + confidence blend)
    pub fn synthesizeQuality(
        self: *FrameSynthesisContext,
        cmd: vk.VkCommandBuffer,
        prev_frame: vk.VkImageView,
        curr_frame: vk.VkImageView,
        mv_buffer: *const motion_vectors.MotionVectorBuffer,
        sampler: vk.VkSampler,
    ) !vk.VkImageView {
        // Fall back to performance mode if quality resources not available
        const qp = self.quality_pipeline orelse return self.synthesize(cmd, prev_frame, curr_frame, mv_buffer, sampler);
        const backward_pipeline = qp.backward_warp_pipeline orelse return self.synthesize(cmd, prev_frame, curr_frame, mv_buffer, sampler);
        const confidence_pipeline = qp.confidence_blend_pipeline orelse return self.synthesize(cmd, prev_frame, curr_frame, mv_buffer, sampler);
        const backward_mv_view = mv_buffer.backward_view orelse return self.synthesize(cmd, prev_frame, curr_frame, mv_buffer, sampler);

        const device = self.device orelse return error.NoDevice;
        const dispatch = self.dispatch orelse return error.NoDispatch;
        const output_image = self.output_image orelse return error.NoOutputImage;
        const descriptor_set = self.descriptor_set orelse return error.NoDescriptorSet;
        const pipeline_layout = self.warp_pipeline_layout orelse return error.NoPipelineLayout;
        const warp_pipeline = self.warp_pipeline orelse return error.NoPipeline;

        // Get function pointers
        const bind_pipeline = dispatch.vkCmdBindPipeline orelse return error.FunctionNotFound;
        const bind_descriptors = dispatch.vkCmdBindDescriptorSets orelse return error.FunctionNotFound;
        const push_constants = dispatch.vkCmdPushConstants orelse return error.FunctionNotFound;
        const dispatch_compute = dispatch.vkCmdDispatch orelse return error.FunctionNotFound;
        const update_descriptors = dispatch.vkUpdateDescriptorSets orelse return error.FunctionNotFound;

        // Calculate dispatch size
        const workgroup_size: u32 = 8;
        const group_count_x = (self.width + workgroup_size - 1) / workgroup_size;
        const group_count_y = (self.height + workgroup_size - 1) / workgroup_size;

        const mv_scale_x: f32 = @as(f32, @floatFromInt(mv_buffer.grid_width)) / @as(f32, @floatFromInt(self.width));
        const mv_scale_y: f32 = @as(f32, @floatFromInt(mv_buffer.grid_height)) / @as(f32, @floatFromInt(self.height));

        // Update descriptors for forward flow
        const image_infos = [_]vk.VkDescriptorImageInfo{
            .{ .sampler = sampler, .imageView = prev_frame, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = sampler, .imageView = curr_frame, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = sampler, .imageView = mv_buffer.forward_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = sampler, .imageView = mv_buffer.cost_view orelse mv_buffer.forward_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
        };

        const output_info = vk.VkDescriptorImageInfo{
            .sampler = null,
            .imageView = self.output_view.?,
            .imageLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };

        const writes = [_]vk.VkWriteDescriptorSet{
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = descriptor_set,
                .dstBinding = BindingIndex.input_prev,
                .dstArrayElement = 0,
                .descriptorCount = 4,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos,
                .pBufferInfo = null,
                .pTexelBufferView = null,
            },
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = descriptor_set,
                .dstBinding = BindingIndex.output,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                .pImageInfo = @ptrCast(&output_info),
                .pBufferInfo = null,
                .pTexelBufferView = null,
            },
        };

        update_descriptors(device, 2, &writes, 0, null);

        // Transition output image
        transitionImageLayout(cmd, dispatch, output_image, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_GENERAL, 0, vk.VK_ACCESS_SHADER_WRITE_BIT, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);

        // Step 1: Forward warp previous frame
        bind_pipeline(cmd, vk.VK_PIPELINE_BIND_POINT_COMPUTE, warp_pipeline);
        bind_descriptors(cmd, vk.VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout, 0, 1, @ptrCast(&descriptor_set), 0, null);

        const forward_constants = WarpPushConstants{
            .mv_scale_x = mv_scale_x,
            .mv_scale_y = mv_scale_y,
            .interpolation = self.interpolation_factor,
            .direction = 1.0,
        };
        push_constants(cmd, pipeline_layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(WarpPushConstants), @ptrCast(&forward_constants));
        dispatch_compute(cmd, group_count_x, group_count_y, 1);

        // Barrier
        transitionImageLayout(cmd, dispatch, output_image, vk.VK_IMAGE_LAYOUT_GENERAL, vk.VK_IMAGE_LAYOUT_GENERAL, vk.VK_ACCESS_SHADER_WRITE_BIT, vk.VK_ACCESS_SHADER_READ_BIT, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);

        // Step 2: Backward warp current frame (to backward_warped)
        if (qp.backward_warped) |bw_image| {
            transitionImageLayout(cmd, dispatch, bw_image, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_GENERAL, 0, vk.VK_ACCESS_SHADER_WRITE_BIT, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);

            // Update descriptor to use backward motion vectors for this warp
            const backward_image_infos = [_]vk.VkDescriptorImageInfo{
                .{ .sampler = sampler, .imageView = curr_frame, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
                .{ .sampler = sampler, .imageView = prev_frame, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
                .{ .sampler = sampler, .imageView = backward_mv_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
                .{ .sampler = sampler, .imageView = mv_buffer.cost_view orelse backward_mv_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            };

            const backward_output_info = vk.VkDescriptorImageInfo{
                .sampler = null,
                .imageView = qp.backward_warped_view.?,
                .imageLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
            };

            const backward_writes = [_]vk.VkWriteDescriptorSet{
                .{
                    .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .pNext = null,
                    .dstSet = descriptor_set,
                    .dstBinding = BindingIndex.input_prev,
                    .dstArrayElement = 0,
                    .descriptorCount = 4,
                    .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .pImageInfo = &backward_image_infos,
                    .pBufferInfo = null,
                    .pTexelBufferView = null,
                },
                .{
                    .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .pNext = null,
                    .dstSet = descriptor_set,
                    .dstBinding = BindingIndex.output,
                    .dstArrayElement = 0,
                    .descriptorCount = 1,
                    .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                    .pImageInfo = @ptrCast(&backward_output_info),
                    .pBufferInfo = null,
                    .pTexelBufferView = null,
                },
            };

            update_descriptors(device, 2, &backward_writes, 0, null);

            bind_pipeline(cmd, vk.VK_PIPELINE_BIND_POINT_COMPUTE, backward_pipeline);

            const backward_constants = WarpPushConstants{
                .mv_scale_x = mv_scale_x,
                .mv_scale_y = mv_scale_y,
                .interpolation = 1.0 - self.interpolation_factor,
                .direction = -1.0,
            };
            push_constants(cmd, pipeline_layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(WarpPushConstants), @ptrCast(&backward_constants));
            dispatch_compute(cmd, group_count_x, group_count_y, 1);

            transitionImageLayout(cmd, dispatch, bw_image, vk.VK_IMAGE_LAYOUT_GENERAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vk.VK_ACCESS_SHADER_WRITE_BIT, vk.VK_ACCESS_SHADER_READ_BIT, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);

            // Restore descriptors for confidence blend (forward warped + backward warped -> output)
            const blend_image_infos = [_]vk.VkDescriptorImageInfo{
                .{ .sampler = sampler, .imageView = self.output_view.?, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
                .{ .sampler = sampler, .imageView = qp.backward_warped_view.?, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
                .{ .sampler = sampler, .imageView = mv_buffer.forward_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
                .{ .sampler = sampler, .imageView = mv_buffer.cost_view orelse mv_buffer.forward_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            };

            const blend_writes = [_]vk.VkWriteDescriptorSet{
                .{
                    .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .pNext = null,
                    .dstSet = descriptor_set,
                    .dstBinding = BindingIndex.input_prev,
                    .dstArrayElement = 0,
                    .descriptorCount = 4,
                    .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .pImageInfo = &blend_image_infos,
                    .pBufferInfo = null,
                    .pTexelBufferView = null,
                },
                .{
                    .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .pNext = null,
                    .dstSet = descriptor_set,
                    .dstBinding = BindingIndex.output,
                    .dstArrayElement = 0,
                    .descriptorCount = 1,
                    .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                    .pImageInfo = @ptrCast(&output_info),
                    .pBufferInfo = null,
                    .pTexelBufferView = null,
                },
            };

            update_descriptors(device, 2, &blend_writes, 0, null);
        }

        // Step 3: Confidence blend (uses cost map to weight forward vs backward)
        bind_pipeline(cmd, vk.VK_PIPELINE_BIND_POINT_COMPUTE, confidence_pipeline);

        const confidence_constants = ConfidenceBlendPushConstants{
            .interpolation = self.interpolation_factor,
            .cost_scale = self.cost_scale,
            .min_confidence = self.min_confidence,
        };
        push_constants(cmd, pipeline_layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(ConfidenceBlendPushConstants), @ptrCast(&confidence_constants));
        dispatch_compute(cmd, group_count_x, group_count_y, 1);

        // Step 4: Occlusion fill (quality mode only)
        if (self.mode == .quality) {
            if (qp.occlusion_fill_pipeline) |fill_pipeline| {
                transitionImageLayout(cmd, dispatch, output_image, vk.VK_IMAGE_LAYOUT_GENERAL, vk.VK_IMAGE_LAYOUT_GENERAL, vk.VK_ACCESS_SHADER_WRITE_BIT, vk.VK_ACCESS_SHADER_READ_BIT | vk.VK_ACCESS_SHADER_WRITE_BIT, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);

                bind_pipeline(cmd, vk.VK_PIPELINE_BIND_POINT_COMPUTE, fill_pipeline);

                const fill_constants = OcclusionFillPushConstants{
                    .occlusion_threshold = self.occlusion_threshold,
                    .fill_radius = 2.0,
                    .interpolation = self.interpolation_factor,
                };
                push_constants(cmd, pipeline_layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(OcclusionFillPushConstants), @ptrCast(&fill_constants));
                dispatch_compute(cmd, group_count_x, group_count_y, 1);
            }
        }

        // Final transition
        transitionImageLayout(cmd, dispatch, output_image, vk.VK_IMAGE_LAYOUT_GENERAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vk.VK_ACCESS_SHADER_WRITE_BIT, vk.VK_ACCESS_SHADER_READ_BIT, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);

        return self.output_view.?;
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
        sampler: vk.VkSampler,
    ) !vk.VkImageView {
        const device = self.device orelse return error.NoDevice;
        const dispatch = self.dispatch orelse return error.NoDispatch;
        const output_image = self.output_image orelse return error.NoOutputImage;
        const descriptor_set = self.descriptor_set orelse return error.NoDescriptorSet;
        const warp_pipeline = self.warp_pipeline orelse return error.NoPipeline;
        const blend_pipeline = self.blend_pipeline orelse return error.NoPipeline;
        const pipeline_layout = self.warp_pipeline_layout orelse return error.NoPipelineLayout;

        // Get function pointers
        const bind_pipeline = dispatch.vkCmdBindPipeline orelse return error.FunctionNotFound;
        const bind_descriptors = dispatch.vkCmdBindDescriptorSets orelse return error.FunctionNotFound;
        const push_constants = dispatch.vkCmdPushConstants orelse return error.FunctionNotFound;
        const dispatch_compute = dispatch.vkCmdDispatch orelse return error.FunctionNotFound;
        const update_descriptors = dispatch.vkUpdateDescriptorSets orelse return error.FunctionNotFound;

        // Update descriptor set with current frame views
        const image_infos = [_]vk.VkDescriptorImageInfo{
            // Binding 0: Previous frame
            .{ .sampler = sampler, .imageView = prev_frame, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            // Binding 1: Current frame
            .{ .sampler = sampler, .imageView = curr_frame, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            // Binding 2: Motion vectors (forward flow)
            .{ .sampler = sampler, .imageView = mv_buffer.forward_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            // Binding 3: Cost map (use forward flow as placeholder if no cost map)
            .{ .sampler = sampler, .imageView = mv_buffer.cost_view orelse mv_buffer.forward_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
        };

        const output_info = vk.VkDescriptorImageInfo{
            .sampler = null,
            .imageView = self.output_view.?,
            .imageLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };

        const writes = [_]vk.VkWriteDescriptorSet{
            // Input samplers
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = descriptor_set,
                .dstBinding = BindingIndex.input_prev,
                .dstArrayElement = 0,
                .descriptorCount = 4, // All 4 input bindings
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos,
                .pBufferInfo = null,
                .pTexelBufferView = null,
            },
            // Output storage image
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = descriptor_set,
                .dstBinding = BindingIndex.output,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                .pImageInfo = @ptrCast(&output_info),
                .pBufferInfo = null,
                .pTexelBufferView = null,
            },
        };

        update_descriptors(device, 2, &writes, 0, null);

        // Transition output image to general layout for compute write
        transitionImageLayout(
            cmd,
            dispatch,
            output_image,
            vk.VK_IMAGE_LAYOUT_UNDEFINED,
            vk.VK_IMAGE_LAYOUT_GENERAL,
            0,
            vk.VK_ACCESS_SHADER_WRITE_BIT,
            vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        );

        // Calculate dispatch size (8x8 workgroups)
        const workgroup_size: u32 = 8;
        const group_count_x = (self.width + workgroup_size - 1) / workgroup_size;
        const group_count_y = (self.height + workgroup_size - 1) / workgroup_size;

        // Calculate motion vector scale based on grid
        const mv_scale_x: f32 = @as(f32, @floatFromInt(mv_buffer.grid_width)) / @as(f32, @floatFromInt(self.width));
        const mv_scale_y: f32 = @as(f32, @floatFromInt(mv_buffer.grid_height)) / @as(f32, @floatFromInt(self.height));

        // Step 1: Forward warp previous frame
        bind_pipeline(cmd, vk.VK_PIPELINE_BIND_POINT_COMPUTE, warp_pipeline);
        bind_descriptors(cmd, vk.VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout, 0, 1, @ptrCast(&descriptor_set), 0, null);

        const warp_constants = WarpPushConstants{
            .mv_scale_x = mv_scale_x,
            .mv_scale_y = mv_scale_y,
            .interpolation = self.interpolation_factor,
            .direction = 1.0, // Forward warp
        };
        push_constants(cmd, pipeline_layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(WarpPushConstants), @ptrCast(&warp_constants));
        dispatch_compute(cmd, group_count_x, group_count_y, 1);

        // Memory barrier between warp and blend
        transitionImageLayout(
            cmd,
            dispatch,
            output_image,
            vk.VK_IMAGE_LAYOUT_GENERAL,
            vk.VK_IMAGE_LAYOUT_GENERAL,
            vk.VK_ACCESS_SHADER_WRITE_BIT,
            vk.VK_ACCESS_SHADER_READ_BIT | vk.VK_ACCESS_SHADER_WRITE_BIT,
            vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        );

        // Step 2: Blend warped frame with current frame
        bind_pipeline(cmd, vk.VK_PIPELINE_BIND_POINT_COMPUTE, blend_pipeline);

        const blend_constants = BlendPushConstants{
            .weight = 1.0 - self.interpolation_factor,
            ._reserved = .{ 0, 0, 0 },
        };
        push_constants(cmd, pipeline_layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(BlendPushConstants), @ptrCast(&blend_constants));
        dispatch_compute(cmd, group_count_x, group_count_y, 1);

        // Transition output to shader read for presentation
        transitionImageLayout(
            cmd,
            dispatch,
            output_image,
            vk.VK_IMAGE_LAYOUT_GENERAL,
            vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            vk.VK_ACCESS_SHADER_WRITE_BIT,
            vk.VK_ACCESS_SHADER_READ_BIT,
            vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        );

        return self.output_view.?;
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
        const device = self.device orelse return;
        const dispatch = self.dispatch orelse return;

        // Destroy pipelines
        if (self.warp_pipeline) |p| dispatch.vkDestroyPipeline.?(device, p, null);
        if (self.blend_pipeline) |p| dispatch.vkDestroyPipeline.?(device, p, null);

        // Destroy pipeline layout
        if (self.warp_pipeline_layout) |l| dispatch.vkDestroyPipelineLayout.?(device, l, null);

        // Destroy descriptor resources
        if (self.descriptor_pool) |p| dispatch.vkDestroyDescriptorPool.?(device, p, null);
        if (self.descriptor_set_layout) |l| dispatch.vkDestroyDescriptorSetLayout.?(device, l, null);

        // Destroy output image
        if (self.output_view) |v| dispatch.vkDestroyImageView.?(device, v, null);
        if (self.output_image) |i| dispatch.vkDestroyImage.?(device, i, null);
        if (self.output_memory) |m| dispatch.vkFreeMemory.?(device, m, null);

        // Destroy scratch image
        if (self.warp_scratch_view) |v| dispatch.vkDestroyImageView.?(device, v, null);
        if (self.warp_scratch) |i| dispatch.vkDestroyImage.?(device, i, null);
        if (self.warp_scratch_memory) |m| dispatch.vkFreeMemory.?(device, m, null);
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

    const create_fn = dispatch.vkCreateDescriptorSetLayout orelse return error.FunctionNotFound;
    try vk.check(create_fn(device, &create_info, null, &layout));
    return layout;
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Load shader module from SPIR-V bytecode
pub fn loadShaderModule(
    device: vk.VkDevice,
    dispatch: *const vk.DeviceDispatch,
    spirv: []const u8,
) !vk.VkShaderModule {
    const create_fn = dispatch.vkCreateShaderModule orelse return error.FunctionNotFound;

    // SPIR-V requires 4-byte alignment
    const code_ptr: [*]const u32 = @ptrCast(@alignCast(spirv.ptr));

    const create_info = vk.VkShaderModuleCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = spirv.len,
        .pCode = code_ptr,
    };

    var shader_module: vk.VkShaderModule = undefined;
    try vk.check(create_fn(device, &create_info, null, &shader_module));
    return shader_module;
}

/// Create a compute pipeline from a shader module
pub fn createComputePipeline(
    device: vk.VkDevice,
    dispatch: *const vk.DeviceDispatch,
    shader_module: vk.VkShaderModule,
    layout: vk.VkPipelineLayout,
) !vk.VkPipeline {
    const create_fn = dispatch.vkCreateComputePipelines orelse return error.FunctionNotFound;

    const stage_info = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = vk.VK_SHADER_STAGE_COMPUTE_BIT,
        .module = shader_module,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const create_info = vk.VkComputePipelineCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = stage_info,
        .layout = layout,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    var pipeline: vk.VkPipeline = undefined;
    try vk.check(create_fn(device, null, 1, @ptrCast(&create_info), null, @ptrCast(&pipeline)));
    return pipeline;
}

/// Find a suitable memory type index
pub fn findMemoryType(
    physical_device: vk.VkPhysicalDevice,
    instance_dispatch: *const vk.InstanceDispatch,
    type_filter: u32,
    properties: u32,
) !u32 {
    const get_props_fn = instance_dispatch.vkGetPhysicalDeviceMemoryProperties orelse return error.FunctionNotFound;

    var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
    get_props_fn(physical_device, &mem_props);

    var i: u32 = 0;
    while (i < mem_props.memoryTypeCount) : (i += 1) {
        const type_match = (type_filter & (@as(u32, 1) << @intCast(i))) != 0;
        const prop_match = (mem_props.memoryTypes[i].propertyFlags & properties) == properties;

        if (type_match and prop_match) {
            return i;
        }
    }

    return error.NoSuitableMemoryType;
}

/// Transition image layout using a pipeline barrier
pub fn transitionImageLayout(
    cmd: vk.VkCommandBuffer,
    dispatch: *const vk.DeviceDispatch,
    image: vk.VkImage,
    old_layout: u32,
    new_layout: u32,
    src_access: u32,
    dst_access: u32,
    src_stage: u32,
    dst_stage: u32,
) void {
    const barrier_fn = dispatch.vkCmdPipelineBarrier orelse return;

    const barrier = vk.VkImageMemoryBarrier{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = src_access,
        .dstAccessMask = dst_access,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = 0xFFFFFFFF,
        .dstQueueFamilyIndex = 0xFFFFFFFF,
        .image = image,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    barrier_fn(cmd, src_stage, dst_stage, 0, 0, null, 0, null, 1, @ptrCast(&barrier));
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
