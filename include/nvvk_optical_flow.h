/*
 * nvvk - NVIDIA Vulkan Extensions Library
 *
 * Optical Flow API (VK_NV_optical_flow)
 *
 * Provides GPU-accelerated optical flow estimation for motion vector generation.
 * Foundation for frame generation (DLSS FG alternative) on Linux.
 *
 * Key capabilities:
 * - Motion vector estimation between frame pairs
 * - Bidirectional flow support
 * - Multiple grid sizes (1x1, 2x2, 4x4, 8x8)
 * - Cost map output for quality assessment
 *
 * Requires:
 * - NVIDIA driver 590+
 * - VK_NV_optical_flow extension
 */

#ifndef NVVK_OPTICAL_FLOW_H
#define NVVK_OPTICAL_FLOW_H

#ifdef __cplusplus
extern "C" {
#endif

#include "nvvk.h"

/* Extension name */
#define NVVK_OPTICAL_FLOW_EXTENSION_NAME "VK_NV_optical_flow"

/* Grid size for optical flow output */
typedef enum NvvkOpticalFlowGridSize {
    NVVK_OPTICAL_FLOW_GRID_UNKNOWN = 0,
    NVVK_OPTICAL_FLOW_GRID_1X1 = 0x00000001,
    NVVK_OPTICAL_FLOW_GRID_2X2 = 0x00000002,
    NVVK_OPTICAL_FLOW_GRID_4X4 = 0x00000004,
    NVVK_OPTICAL_FLOW_GRID_8X8 = 0x00000008,
} NvvkOpticalFlowGridSize;

/* Performance level selection */
typedef enum NvvkOpticalFlowPerformance {
    NVVK_OPTICAL_FLOW_PERF_UNKNOWN = 0,
    NVVK_OPTICAL_FLOW_PERF_SLOW = 1,    /* Highest quality */
    NVVK_OPTICAL_FLOW_PERF_MEDIUM = 2,  /* Balanced */
    NVVK_OPTICAL_FLOW_PERF_FAST = 3,    /* Lowest latency */
} NvvkOpticalFlowPerformance;

/* Session binding points */
typedef enum NvvkOpticalFlowBindingPoint {
    NVVK_OPTICAL_FLOW_BIND_INPUT = 0,
    NVVK_OPTICAL_FLOW_BIND_REFERENCE = 1,
    NVVK_OPTICAL_FLOW_BIND_HINT = 2,
    NVVK_OPTICAL_FLOW_BIND_FLOW_VECTOR = 3,
    NVVK_OPTICAL_FLOW_BIND_BACKWARD_FLOW_VECTOR = 4,
    NVVK_OPTICAL_FLOW_BIND_COST = 5,
    NVVK_OPTICAL_FLOW_BIND_BACKWARD_COST = 6,
    NVVK_OPTICAL_FLOW_BIND_GLOBAL_FLOW = 7,
} NvvkOpticalFlowBindingPoint;

/* Optical flow properties */
typedef struct NvvkOpticalFlowProperties {
    uint32_t supported_output_grid_sizes;  /* Bitmask of NvvkOpticalFlowGridSize */
    uint32_t supported_hint_grid_sizes;    /* Bitmask of NvvkOpticalFlowGridSize */
    bool hint_supported;
    bool cost_supported;
    bool bidirectional_supported;
    bool global_flow_supported;
    uint32_t min_width;
    uint32_t min_height;
    uint32_t max_width;
    uint32_t max_height;
    uint32_t max_regions_of_interest;
} NvvkOpticalFlowProperties;

/* Optical flow session configuration */
typedef struct NvvkOpticalFlowConfig {
    uint32_t width;
    uint32_t height;
    uint32_t image_format;                 /* VkFormat for input images */
    NvvkOpticalFlowGridSize output_grid_size;
    NvvkOpticalFlowGridSize hint_grid_size;
    NvvkOpticalFlowPerformance performance_level;
    bool bidirectional;
    bool enable_cost;
    bool enable_global_flow;
} NvvkOpticalFlowConfig;

/* Opaque optical flow context handle */
typedef struct NvvkOpticalFlowContext* nvvk_optical_flow_ctx_t;

/*
 * Check if optical flow is supported on the device.
 *
 * Parameters:
 *   physical_device - VkPhysicalDevice handle
 *
 * Returns:
 *   true if VK_NV_optical_flow is available
 */
bool nvvk_optical_flow_is_supported(NvvkDevice physical_device);

/*
 * Query optical flow properties for a physical device.
 *
 * Parameters:
 *   physical_device - VkPhysicalDevice handle
 *   props - Output properties structure
 *
 * Returns:
 *   NVVK_SUCCESS on success
 */
NvvkResult nvvk_optical_flow_get_properties(
    NvvkDevice physical_device,
    NvvkOpticalFlowProperties* props
);

/*
 * Create optical flow session.
 *
 * Parameters:
 *   device - VkDevice handle
 *   config - Session configuration
 *   get_device_proc_addr - vkGetDeviceProcAddr function
 *
 * Returns:
 *   Context handle on success, NULL on failure
 */
nvvk_optical_flow_ctx_t nvvk_optical_flow_create(
    NvvkDevice device,
    const NvvkOpticalFlowConfig* config,
    PFN_nvvkGetDeviceProcAddr get_device_proc_addr
);

/*
 * Destroy optical flow session.
 */
void nvvk_optical_flow_destroy(nvvk_optical_flow_ctx_t ctx);

/*
 * Bind image to optical flow session.
 *
 * Parameters:
 *   ctx - Optical flow context
 *   binding_point - Which binding to update
 *   image_view - VkImageView handle
 *   image_layout - VkImageLayout
 *
 * Returns:
 *   NVVK_SUCCESS on success
 */
NvvkResult nvvk_optical_flow_bind_image(
    nvvk_optical_flow_ctx_t ctx,
    NvvkOpticalFlowBindingPoint binding_point,
    uint64_t image_view,
    uint32_t image_layout
);

/*
 * Execute optical flow estimation.
 *
 * Parameters:
 *   ctx - Optical flow context
 *   cmd - VkCommandBuffer to record into
 *   disable_temporal_hints - Set to true to ignore previous frame hints
 *
 * Returns:
 *   NVVK_SUCCESS on success
 */
NvvkResult nvvk_optical_flow_execute(
    nvvk_optical_flow_ctx_t ctx,
    NvvkCommandBuffer cmd,
    bool disable_temporal_hints
);

/*
 * Get extension name.
 */
const char* nvvk_optical_flow_get_extension_name(void);

/*
 * Example usage:
 *
 *   // Check support
 *   if (nvvk_optical_flow_is_supported(physical_device)) {
 *       NvvkOpticalFlowConfig config = {
 *           .width = 1920,
 *           .height = 1080,
 *           .output_grid_size = NVVK_OPTICAL_FLOW_GRID_4X4,
 *           .performance_level = NVVK_OPTICAL_FLOW_PERF_FAST,
 *       };
 *
 *       nvvk_optical_flow_ctx_t of = nvvk_optical_flow_create(
 *           device, &config, vkGetDeviceProcAddr);
 *
 *       // Bind input and reference images
 *       nvvk_optical_flow_bind_image(of, NVVK_OPTICAL_FLOW_BIND_INPUT,
 *           current_frame_view, VK_IMAGE_LAYOUT_GENERAL);
 *       nvvk_optical_flow_bind_image(of, NVVK_OPTICAL_FLOW_BIND_REFERENCE,
 *           previous_frame_view, VK_IMAGE_LAYOUT_GENERAL);
 *
 *       // Execute
 *       nvvk_optical_flow_execute(of, cmd, false);
 *
 *       nvvk_optical_flow_destroy(of);
 *   }
 */

#ifdef __cplusplus
}
#endif

#endif /* NVVK_OPTICAL_FLOW_H */
