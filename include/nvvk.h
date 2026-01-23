/**
 * nvvk - NVIDIA Vulkan Extensions Library for Linux Gaming
 *
 * C API header for integration with external projects.
 * This file provides the C ABI exports for frame injection and layer integration.
 *
 * Usage:
 *   #include <nvvk.h>
 *   // Link with -lnvvk
 */

#ifndef NVVK_H
#define NVVK_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

/* Vulkan handle types (opaque pointers) */
typedef void* VkDevice;
typedef void* VkImage;
typedef uint64_t VkSwapchainKHR;

/* ============================================================================
 * Frame Injection API
 *
 * These functions allow host runtimes (like ghostVK/primetime) to register
 * their swapchain images with the nvvk layer for frame injection.
 * ============================================================================ */

/**
 * Register swapchain images with the nvvk layer for frame injection.
 *
 * Call this after creating a swapchain to enable frame generation for it.
 * The layer will use these images as targets for injecting generated frames.
 *
 * @param device       The Vulkan device handle
 * @param swapchain    The swapchain handle (as uint64_t)
 * @param images       Array of swapchain VkImage handles
 * @param image_count  Number of images in the array
 * @param width        Swapchain image width
 * @param height       Swapchain image height
 * @param format       Swapchain image format (VkFormat as uint32_t)
 * @return             true on success, false on failure
 */
bool nvvk_register_swapchain_images(
    VkDevice device,
    VkSwapchainKHR swapchain,
    const VkImage* images,
    uint32_t image_count,
    uint32_t width,
    uint32_t height,
    uint32_t format
);

/**
 * Notify the layer of the most recently rendered image for a swapchain.
 *
 * Call this after rendering to an image but before presenting it.
 * The layer uses this information to select the source for frame injection.
 *
 * @param device       The Vulkan device handle
 * @param swapchain    The swapchain handle (as uint64_t)
 * @param image        The most recently rendered VkImage
 * @param layout       Current image layout (VkImageLayout as uint32_t)
 *                     Typically VK_IMAGE_LAYOUT_PRESENT_SRC_KHR (1000001002)
 */
void nvvk_notify_rendered_image(
    VkDevice device,
    VkSwapchainKHR swapchain,
    VkImage image,
    uint32_t layout
);

/* ============================================================================
 * Layer Constants
 * ============================================================================ */

#define NVVK_LAYER_NAME "VK_LAYER_NV_frame_generation"
#define NVVK_LAYER_DESCRIPTION "NVIDIA Frame Generation Layer"
#define NVVK_LAYER_VERSION 1

/* Common image layouts for convenience */
#define NVVK_IMAGE_LAYOUT_UNDEFINED 0
#define NVVK_IMAGE_LAYOUT_GENERAL 1
#define NVVK_IMAGE_LAYOUT_PRESENT_SRC_KHR 1000001002
#define NVVK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL 7

/* ============================================================================
 * Environment Variables
 *
 * NVVK_FRAME_GEN_ENABLED=0|1  - Master enable/disable (default: 1)
 * NVVK_FRAME_GEN_MODE=off|performance|balanced|quality (default: balanced)
 * NVVK_FRAME_GEN_DEBUG=0|1    - Enable debug output (default: 0)
 * NVVK_WHITELIST=app1,app2    - Only enable for these apps (comma-separated)
 * NVVK_BLACKLIST=app1,app2    - Disable for these apps (comma-separated)
 * ============================================================================ */

#ifdef __cplusplus
}
#endif

#endif /* NVVK_H */
