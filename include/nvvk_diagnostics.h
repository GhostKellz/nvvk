/*
 * nvvk - NVIDIA Vulkan Extensions Library
 *
 * VK_NV_device_diagnostic_checkpoints & VK_NV_device_diagnostics_config
 *
 * Provides GPU crash diagnostics and debugging:
 * - Command buffer checkpoints for locating GPU hangs
 * - Tagged checkpoints for common operations
 * - Checkpoint retrieval after device lost
 */

#ifndef NVVK_DIAGNOSTICS_H
#define NVVK_DIAGNOSTICS_H

#ifdef __cplusplus
extern "C" {
#endif

#include "nvvk.h"

/* Predefined checkpoint tags */
typedef enum NvvkCheckpointTag {
    NVVK_CHECKPOINT_FRAME_START = 0x1000,
    NVVK_CHECKPOINT_FRAME_END = 0x1001,
    NVVK_CHECKPOINT_DRAW_START = 0x2000,
    NVVK_CHECKPOINT_DRAW_END = 0x2001,
    NVVK_CHECKPOINT_COMPUTE_START = 0x3000,
    NVVK_CHECKPOINT_COMPUTE_END = 0x3001,
    NVVK_CHECKPOINT_TRANSFER_START = 0x4000,
    NVVK_CHECKPOINT_TRANSFER_END = 0x4001,
} NvvkCheckpointTag;

/* Diagnostics config flags (for device creation) */
typedef enum NvvkDiagnosticsConfigFlags {
    NVVK_DIAGNOSTICS_CONFIG_ENABLE_SHADER_DEBUG_INFO = 0x00000001,
    NVVK_DIAGNOSTICS_CONFIG_ENABLE_RESOURCE_TRACKING = 0x00000002,
    NVVK_DIAGNOSTICS_CONFIG_ENABLE_AUTOMATIC_CHECKPOINTS = 0x00000004,
    NVVK_DIAGNOSTICS_CONFIG_ENABLE_SHADER_ERROR_REPORTING = 0x00000008,
} NvvkDiagnosticsConfigFlags;

/* Opaque diagnostics context handle */
typedef struct NvvkDiagnosticsContext* nvvk_diagnostics_ctx_t;

/*
 * Initialize diagnostics context.
 *
 * Parameters:
 *   device - VkDevice handle
 *   get_device_proc_addr - vkGetDeviceProcAddr function pointer
 *
 * Returns:
 *   Context handle on success, NULL on failure
 */
nvvk_diagnostics_ctx_t nvvk_diagnostics_init(
    NvvkDevice device,
    PFN_vkGetDeviceProcAddr get_device_proc_addr
);

/*
 * Destroy diagnostics context.
 */
void nvvk_diagnostics_destroy(nvvk_diagnostics_ctx_t ctx);

/*
 * Check if diagnostic checkpoints are supported.
 */
bool nvvk_diagnostics_is_supported(nvvk_diagnostics_ctx_t ctx);

/*
 * Insert a checkpoint marker into a command buffer.
 * The marker pointer can be retrieved after a GPU hang.
 *
 * Parameters:
 *   ctx - Diagnostics context
 *   cmd - VkCommandBuffer handle
 *   marker - User-defined pointer (stored by driver, retrieved on hang)
 */
void nvvk_diagnostics_set_checkpoint(
    nvvk_diagnostics_ctx_t ctx,
    NvvkCommandBuffer cmd,
    const void* marker
);

/*
 * Insert a tagged checkpoint (uses predefined tag values).
 */
void nvvk_diagnostics_set_tagged_checkpoint(
    nvvk_diagnostics_ctx_t ctx,
    NvvkCommandBuffer cmd,
    NvvkCheckpointTag tag
);

/*
 * Get diagnostics config flags for full debugging.
 * Chain the returned VkDeviceDiagnosticsConfigCreateInfoNV into device creation.
 *
 * Returns flags value for VkDeviceDiagnosticsConfigCreateInfoNV.flags
 */
static inline uint32_t nvvk_diagnostics_get_full_config_flags(void) {
    return NVVK_DIAGNOSTICS_CONFIG_ENABLE_SHADER_DEBUG_INFO |
           NVVK_DIAGNOSTICS_CONFIG_ENABLE_RESOURCE_TRACKING |
           NVVK_DIAGNOSTICS_CONFIG_ENABLE_AUTOMATIC_CHECKPOINTS |
           NVVK_DIAGNOSTICS_CONFIG_ENABLE_SHADER_ERROR_REPORTING;
}

/*
 * Get diagnostics config flags for minimal overhead.
 * Only enables automatic checkpoints.
 */
static inline uint32_t nvvk_diagnostics_get_minimal_config_flags(void) {
    return NVVK_DIAGNOSTICS_CONFIG_ENABLE_AUTOMATIC_CHECKPOINTS;
}

/*
 * Example usage for GPU hang debugging:
 *
 *   // Enable diagnostics at device creation:
 *   VkDeviceDiagnosticsConfigCreateInfoNV diagConfig = {
 *       .sType = VK_STRUCTURE_TYPE_DEVICE_DIAGNOSTICS_CONFIG_CREATE_INFO_NV,
 *       .flags = nvvk_diagnostics_get_minimal_config_flags(),
 *   };
 *   // Chain into VkDeviceCreateInfo.pNext
 *
 *   // Initialize context after device creation:
 *   nvvk_diagnostics_ctx_t diagCtx = nvvk_diagnostics_init(device, vkGetDeviceProcAddr);
 *
 *   // Insert checkpoints in command buffers:
 *   nvvk_diagnostics_set_tagged_checkpoint(diagCtx, cmd, NVVK_CHECKPOINT_DRAW_START);
 *   vkCmdDraw(...);
 *   nvvk_diagnostics_set_tagged_checkpoint(diagCtx, cmd, NVVK_CHECKPOINT_DRAW_END);
 *
 *   // On VK_ERROR_DEVICE_LOST:
 *   // Query queue checkpoints via vkGetQueueCheckpointDataNV
 *   // to identify where the GPU hung
 */

#ifdef __cplusplus
}
#endif

#endif /* NVVK_DIAGNOSTICS_H */
