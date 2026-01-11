/*
 * nvvk - NVIDIA Vulkan Extensions Library
 *
 * Displacement Micromap API (VK_NV_displacement_micromap)
 *
 * Provides displacement micromap support for ray tracing acceleration structures.
 * Micromaps allow adding fine geometric detail to triangles without increasing
 * the base geometry complexity, improving RT performance with detailed surfaces.
 *
 * Key capabilities:
 * - Displacement maps for ray tracing triangles
 * - Compressed in-memory format for efficiency
 * - Subtriangle vertex displacement along defined vectors
 * - Multiple compression formats for quality/size tradeoffs
 *
 * Requires:
 * - NVIDIA driver 590+
 * - VK_NV_displacement_micromap extension
 * - VK_EXT_opacity_micromap (dependency)
 * - VK_KHR_acceleration_structure (dependency)
 * - RTX 40+ series GPU recommended
 */

#ifndef NVVK_DISPLACEMENT_H
#define NVVK_DISPLACEMENT_H

#ifdef __cplusplus
extern "C" {
#endif

#include "nvvk.h"

/* Extension name */
#define NVVK_DISPLACEMENT_MICROMAP_EXTENSION_NAME "VK_NV_displacement_micromap"

/* Displacement micromap format */
typedef enum NvvkDisplacementFormat {
    /* 64 triangles in 64 bytes (uncompressed, subdivision level 3) */
    NVVK_DISPLACEMENT_64_TRIANGLES_64_BYTES = 1,
    /* 256 triangles in 128 bytes (compressed) */
    NVVK_DISPLACEMENT_256_TRIANGLES_128_BYTES = 2,
    /* 1024 triangles in 128 bytes (highest compression) */
    NVVK_DISPLACEMENT_1024_TRIANGLES_128_BYTES = 3,
} NvvkDisplacementFormat;

/* Displacement bias and scale format */
typedef enum NvvkDisplacementBiasScaleFormat {
    NVVK_DISPLACEMENT_BIAS_SCALE_NONE = 0,
    NVVK_DISPLACEMENT_BIAS_SCALE_FP16 = 1,
    NVVK_DISPLACEMENT_BIAS_SCALE_FP32 = 2,
} NvvkDisplacementBiasScaleFormat;

/* Displacement micromap properties */
typedef struct NvvkDisplacementMicromapProperties {
    bool supported;                     /* Whether displacement micromaps are supported */
    uint32_t max_subdivision_level;     /* Maximum subdivision level (typically 5) */
} NvvkDisplacementMicromapProperties;

/* Displacement micromap configuration */
typedef struct NvvkDisplacementConfig {
    NvvkDisplacementFormat format;
    NvvkDisplacementBiasScaleFormat bias_scale_format;
    uint32_t subdivision_level;          /* 0-5 typically */
} NvvkDisplacementConfig;

/*
 * Check if displacement micromaps are supported on the device.
 *
 * Parameters:
 *   physical_device - VkPhysicalDevice handle
 *
 * Returns:
 *   true if VK_NV_displacement_micromap is available
 */
bool nvvk_displacement_is_supported(NvvkDevice physical_device);

/*
 * Query displacement micromap properties.
 *
 * Parameters:
 *   physical_device - VkPhysicalDevice handle
 *   props - Output properties structure
 *
 * Returns:
 *   NVVK_SUCCESS on success
 */
NvvkResult nvvk_displacement_get_properties(
    NvvkDevice physical_device,
    NvvkDisplacementMicromapProperties* props
);

/*
 * Calculate maximum triangles at given subdivision level.
 *
 * Each subdivision level quadruples the triangle count:
 *   Level 0 = 1, Level 1 = 4, Level 2 = 16, Level 3 = 64, etc.
 */
uint32_t nvvk_displacement_max_triangles_at_level(uint32_t subdivision_level);

/*
 * Calculate triangles per micromap block for a given format.
 */
uint32_t nvvk_displacement_triangles_per_block(NvvkDisplacementFormat format);

/*
 * Calculate block size in bytes for a given format.
 */
uint32_t nvvk_displacement_block_size_bytes(NvvkDisplacementFormat format);

/*
 * Estimate memory usage for displacement data.
 *
 * Parameters:
 *   config - Displacement configuration
 *   triangle_count - Number of base triangles
 *
 * Returns:
 *   Estimated memory usage in bytes
 */
size_t nvvk_displacement_estimate_memory(
    const NvvkDisplacementConfig* config,
    uint32_t triangle_count
);

/*
 * Get extension name.
 */
const char* nvvk_displacement_get_extension_name(void);

/*
 * Get required dependency extension names.
 */
const char* nvvk_displacement_get_opacity_micromap_ext(void);
const char* nvvk_displacement_get_acceleration_structure_ext(void);

/*
 * Example usage with ray tracing:
 *
 *   // Check support
 *   NvvkDisplacementMicromapProperties props;
 *   if (nvvk_displacement_is_supported(physical_device)) {
 *       nvvk_displacement_get_properties(physical_device, &props);
 *
 *       // Configure displacement
 *       NvvkDisplacementConfig config = {
 *           .format = NVVK_DISPLACEMENT_64_TRIANGLES_64_BYTES,
 *           .bias_scale_format = NVVK_DISPLACEMENT_BIAS_SCALE_FP16,
 *           .subdivision_level = 3,
 *       };
 *
 *       // Estimate memory
 *       size_t mem = nvvk_displacement_estimate_memory(&config, base_triangle_count);
 *
 *       // Create displacement micromap and attach to acceleration structure
 *       // (requires VkAccelerationStructureTrianglesDisplacementMicromapNV)
 *   }
 */

#ifdef __cplusplus
}
#endif

#endif /* NVVK_DISPLACEMENT_H */
