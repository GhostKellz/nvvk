/*
 * nvvk - NVIDIA Vulkan Extensions Library for Linux Gaming
 *
 * C API header for integration with DXVK, vkd3d-proton, and other
 * Vulkan-based translation layers.
 *
 * Usage:
 *   #include <nvvk/nvvk.h>
 *   // Link with -lnvvk
 */

#ifndef NVVK_H
#define NVVK_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

/* Version */
#define NVVK_VERSION_MAJOR 0
#define NVVK_VERSION_MINOR 1
#define NVVK_VERSION_PATCH 0

/* Result codes */
typedef enum NvvkResult {
    NVVK_SUCCESS = 0,
    NVVK_ERROR_NOT_SUPPORTED = -1,
    NVVK_ERROR_INVALID_HANDLE = -2,
    NVVK_ERROR_OUT_OF_MEMORY = -3,
    NVVK_ERROR_DEVICE_LOST = -4,
    NVVK_ERROR_UNKNOWN = -5,
} NvvkResult;

/* Opaque handles */
typedef void* NvvkDevice;
typedef uint64_t NvvkSwapchain;
typedef uint64_t NvvkSemaphore;
typedef void* NvvkQueue;
typedef void* NvvkCommandBuffer;

/* Function pointer type for vkGetDeviceProcAddr */
typedef void* (*PFN_vkGetDeviceProcAddr)(void* device, const char* pName);

/* Get library version (encoded as major<<16 | minor<<8 | patch) */
uint32_t nvvk_get_version(void);

/* Check if running on NVIDIA GPU */
bool nvvk_is_nvidia_gpu(void);

/* Get extension names */
const char* nvvk_get_low_latency_extension_name(void);
const char* nvvk_get_diagnostic_checkpoints_extension_name(void);
const char* nvvk_get_diagnostics_config_extension_name(void);

#ifdef __cplusplus
}
#endif

#endif /* NVVK_H */
