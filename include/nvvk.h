/*
 * nvvk - NVIDIA Vulkan Extensions Library for Linux Gaming
 *
 * C API header for integration with DXVK, vkd3d-proton, and other
 * Vulkan-based translation layers.
 *
 * Usage:
 *   #include <nvvk/nvvk.h>
 *   // Link with -lnvvk
 *
 * Individual module headers:
 *   #include <nvvk/nvvk_low_latency.h>      - NVIDIA Reflex
 *   #include <nvvk/nvvk_frame_generation.h> - Frame Generation
 *   #include <nvvk/nvvk_diagnostics.h>      - GPU Crash Debugging
 *   #include <nvvk/nvvk_optical_flow.h>     - Optical Flow
 */

#ifndef NVVK_H
#define NVVK_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

/* =============================================================================
 * Version
 * ============================================================================= */

#define NVVK_VERSION_MAJOR 0
#define NVVK_VERSION_MINOR 4
#define NVVK_VERSION_PATCH 1

#define NVVK_MAKE_VERSION(major, minor, patch) \
    (((major) << 16) | ((minor) << 8) | (patch))

#define NVVK_VERSION \
    NVVK_MAKE_VERSION(NVVK_VERSION_MAJOR, NVVK_VERSION_MINOR, NVVK_VERSION_PATCH)

/* Minimum recommended driver version */
#define NVVK_MIN_DRIVER_MAJOR 590
#define NVVK_MIN_DRIVER_MINOR 48

/* =============================================================================
 * Result Codes
 * ============================================================================= */

typedef enum NvvkResult {
    NVVK_SUCCESS = 0,
    NVVK_ERROR_NOT_SUPPORTED = -1,
    NVVK_ERROR_INVALID_HANDLE = -2,
    NVVK_ERROR_OUT_OF_MEMORY = -3,
    NVVK_ERROR_DEVICE_LOST = -4,
    NVVK_ERROR_UNKNOWN = -5,
    NVVK_ERROR_EXTENSION_NOT_PRESENT = -6,
    NVVK_ERROR_TIMEOUT = -7,
} NvvkResult;

/* =============================================================================
 * Opaque Handle Types
 * ============================================================================= */

typedef void* NvvkDevice;
typedef void* NvvkPhysicalDevice;
typedef void* NvvkInstance;
typedef void* NvvkQueue;
typedef void* NvvkCommandBuffer;
typedef void* NvvkImageView;
typedef void* NvvkImage;
typedef uint64_t NvvkSwapchain;
typedef uint64_t NvvkSemaphore;

/* =============================================================================
 * Function Pointer Types
 * ============================================================================= */

typedef void* (*PFN_vkGetDeviceProcAddr)(void* device, const char* pName);
typedef void* (*PFN_vkGetInstanceProcAddr)(void* instance, const char* pName);

/* Async callback type */
typedef void (*NvvkAsyncCallback)(void* user_data, NvvkResult result);

/* =============================================================================
 * Library Information
 * ============================================================================= */

/**
 * Get library version (encoded as major<<16 | minor<<8 | patch).
 */
uint32_t nvvk_get_version(void);

/**
 * Check if running on NVIDIA GPU.
 */
bool nvvk_is_nvidia_gpu(void);

/* =============================================================================
 * Extension Names
 * ============================================================================= */

const char* nvvk_get_low_latency_extension_name(void);
const char* nvvk_get_diagnostic_checkpoints_extension_name(void);
const char* nvvk_get_diagnostics_config_extension_name(void);
const char* nvvk_get_memory_decompression_extension_name(void);
const char* nvvk_get_mesh_shader_extension_name(void);
const char* nvvk_get_ray_tracing_extension_name(void);
const char* nvvk_get_optical_flow_extension_name(void);

/**
 * Get the Vulkan layer name for frame generation.
 */
const char* nvvk_get_layer_name(void);

/* =============================================================================
 * Low Latency (NVIDIA Reflex) - See nvvk_low_latency.h for full API
 * ============================================================================= */

typedef struct NvvkLowLatencyContext* NvvkLowLatencyHandle;

NvvkLowLatencyHandle nvvk_low_latency_init(
    NvvkDevice device,
    NvvkSwapchain swapchain,
    PFN_vkGetDeviceProcAddr get_device_proc_addr
);
void nvvk_low_latency_destroy(NvvkLowLatencyHandle handle);
bool nvvk_low_latency_is_supported(NvvkLowLatencyHandle handle);
NvvkResult nvvk_low_latency_enable(NvvkLowLatencyHandle handle, bool boost, uint32_t min_interval_us);
NvvkResult nvvk_low_latency_disable(NvvkLowLatencyHandle handle);
uint64_t nvvk_low_latency_begin_frame(NvvkLowLatencyHandle handle);

/* Async sleep with callback (non-blocking) */
NvvkResult nvvk_low_latency_sleep_async(
    NvvkLowLatencyHandle handle,
    NvvkSemaphore semaphore,
    uint64_t value,
    NvvkAsyncCallback callback,
    void* user_data
);

/* =============================================================================
 * Frame Generation - See nvvk_frame_generation.h for full API
 * ============================================================================= */

typedef enum NvvkFrameGenMode {
    NVVK_FRAME_GEN_OFF = 0,
    NVVK_FRAME_GEN_PERFORMANCE = 1,
    NVVK_FRAME_GEN_BALANCED = 2,
    NVVK_FRAME_GEN_QUALITY = 3,
} NvvkFrameGenMode;

typedef struct NvvkFrameGenStats {
    uint64_t generated_frames;
    uint64_t skipped_frames;
    uint64_t avg_gen_time_us;
    float confidence;
    bool scene_change_detected;
    uint8_t _padding[3];
} NvvkFrameGenStats;

typedef struct NvvkFrameGenContext* NvvkFrameGenHandle;

NvvkFrameGenHandle nvvk_frame_gen_init(
    NvvkDevice device,
    uint32_t width,
    uint32_t height,
    NvvkFrameGenMode mode,
    PFN_vkGetDeviceProcAddr get_device_proc_addr
);
void nvvk_frame_gen_destroy(NvvkFrameGenHandle handle);
void nvvk_frame_gen_set_enabled(NvvkFrameGenHandle handle, bool enabled);
void nvvk_frame_gen_set_mode(NvvkFrameGenHandle handle, NvvkFrameGenMode mode);
void nvvk_frame_gen_get_stats(NvvkFrameGenHandle handle, NvvkFrameGenStats* stats);
uint64_t nvvk_frame_gen_get_latency_compensation(NvvkFrameGenHandle handle);
uint64_t nvvk_frame_gen_get_current_frame_id(NvvkFrameGenHandle handle);

/* =============================================================================
 * Present Injection - See nvvk_present_injection.h for full API
 * ============================================================================= */

typedef enum NvvkInjectionMode {
    NVVK_INJECTION_DISABLED = 0,
    NVVK_INJECTION_SINGLE = 1,
    NVVK_INJECTION_DOUBLE = 2,
} NvvkInjectionMode;

typedef enum NvvkTimingMode {
    NVVK_TIMING_FIXED = 0,
    NVVK_TIMING_ADAPTIVE = 1,
    NVVK_TIMING_VRR = 2,
} NvvkTimingMode;

typedef struct NvvkInjectionStats {
    uint64_t real_frames;
    uint64_t generated_frames;
    uint64_t skipped_frames;
    uint64_t avg_present_interval_us;
    float effective_fps;
    uint64_t injection_overhead_us;
    uint32_t _padding;
} NvvkInjectionStats;

typedef struct NvvkPresentInjectionContext* NvvkPresentInjectionHandle;

NvvkPresentInjectionHandle nvvk_present_injection_init(
    NvvkDevice device,
    NvvkSwapchain swapchain,
    NvvkInjectionMode injection_mode,
    NvvkTimingMode timing_mode
);
void nvvk_present_injection_destroy(NvvkPresentInjectionHandle handle);
void nvvk_present_injection_set_enabled(NvvkPresentInjectionHandle handle, bool enabled);
bool nvvk_present_injection_should_inject(NvvkPresentInjectionHandle handle);
uint64_t nvvk_present_injection_get_timing(NvvkPresentInjectionHandle handle);
void nvvk_present_injection_record_present(NvvkPresentInjectionHandle handle, bool is_generated);
void nvvk_present_injection_get_stats(NvvkPresentInjectionHandle handle, NvvkInjectionStats* stats);

/* =============================================================================
 * Diagnostics - See nvvk_diagnostics.h for full API
 * ============================================================================= */

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

typedef struct NvvkDiagnosticsContext* NvvkDiagnosticsHandle;

NvvkDiagnosticsHandle nvvk_diagnostics_init(
    NvvkDevice device,
    PFN_vkGetDeviceProcAddr get_device_proc_addr
);
void nvvk_diagnostics_destroy(NvvkDiagnosticsHandle handle);
bool nvvk_diagnostics_is_supported(NvvkDiagnosticsHandle handle);
void nvvk_diagnostics_set_checkpoint(
    NvvkDiagnosticsHandle handle,
    NvvkCommandBuffer cmd,
    const void* marker
);
void nvvk_diagnostics_set_tagged_checkpoint(
    NvvkDiagnosticsHandle handle,
    NvvkCommandBuffer cmd,
    NvvkCheckpointTag tag
);

#ifdef __cplusplus
}
#endif

#endif /* NVVK_H */
