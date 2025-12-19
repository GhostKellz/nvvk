/*
 * nvvk - NVIDIA Vulkan Extensions Library
 *
 * VK_NV_low_latency2 wrapper (NVIDIA Reflex)
 *
 * Provides reduced input-to-display latency through:
 * - Low latency mode enable/disable
 * - Frame timing markers
 * - Optimal frame pacing via sleep
 * - Latency timing collection
 */

#ifndef NVVK_LOW_LATENCY_H
#define NVVK_LOW_LATENCY_H

#ifdef __cplusplus
extern "C" {
#endif

#include "nvvk.h"

/* Latency markers for frame timing */
typedef enum NvvkLatencyMarker {
    NVVK_LATENCY_MARKER_SIMULATION_START = 0,
    NVVK_LATENCY_MARKER_SIMULATION_END = 1,
    NVVK_LATENCY_MARKER_RENDERSUBMIT_START = 2,
    NVVK_LATENCY_MARKER_RENDERSUBMIT_END = 3,
    NVVK_LATENCY_MARKER_PRESENT_START = 4,
    NVVK_LATENCY_MARKER_PRESENT_END = 5,
    NVVK_LATENCY_MARKER_INPUT_SAMPLE = 6,
    NVVK_LATENCY_MARKER_TRIGGER_FLASH = 7,
    NVVK_LATENCY_MARKER_OUT_OF_BAND_RENDERSUBMIT_START = 8,
    NVVK_LATENCY_MARKER_OUT_OF_BAND_RENDERSUBMIT_END = 9,
    NVVK_LATENCY_MARKER_OUT_OF_BAND_PRESENT_START = 10,
    NVVK_LATENCY_MARKER_OUT_OF_BAND_PRESENT_END = 11,
} NvvkLatencyMarker;

/* Frame timing data from driver */
typedef struct NvvkFrameTimings {
    uint64_t present_id;
    uint64_t input_sample_time_us;
    uint64_t sim_start_time_us;
    uint64_t sim_end_time_us;
    uint64_t render_submit_start_time_us;
    uint64_t render_submit_end_time_us;
    uint64_t present_start_time_us;
    uint64_t present_end_time_us;
    uint64_t driver_start_time_us;
    uint64_t driver_end_time_us;
    uint64_t gpu_render_start_time_us;
    uint64_t gpu_render_end_time_us;
} NvvkFrameTimings;

/* Opaque low latency context handle */
typedef struct NvvkLowLatencyContext* nvvk_low_latency_ctx_t;

/*
 * Initialize low latency context for a swapchain.
 *
 * Parameters:
 *   device - VkDevice handle
 *   swapchain - VkSwapchainKHR handle (as uint64_t)
 *   get_device_proc_addr - vkGetDeviceProcAddr function pointer
 *
 * Returns:
 *   Context handle on success, NULL on failure
 */
nvvk_low_latency_ctx_t nvvk_low_latency_init(
    NvvkDevice device,
    NvvkSwapchain swapchain,
    PFN_vkGetDeviceProcAddr get_device_proc_addr
);

/*
 * Destroy low latency context.
 */
void nvvk_low_latency_destroy(nvvk_low_latency_ctx_t ctx);

/*
 * Check if VK_NV_low_latency2 extension is supported.
 */
bool nvvk_low_latency_is_supported(nvvk_low_latency_ctx_t ctx);

/*
 * Enable low latency mode.
 *
 * Parameters:
 *   ctx - Low latency context
 *   boost - Enable low latency boost (increased power consumption)
 *   min_interval_us - Minimum frame interval in microseconds (0 = unlimited)
 *
 * Returns:
 *   NVVK_SUCCESS on success
 */
NvvkResult nvvk_low_latency_enable(
    nvvk_low_latency_ctx_t ctx,
    bool boost,
    uint32_t min_interval_us
);

/*
 * Disable low latency mode.
 */
NvvkResult nvvk_low_latency_disable(nvvk_low_latency_ctx_t ctx);

/*
 * Sleep until the optimal time to start the next frame.
 * Reduces input latency by minimizing time between input and display.
 *
 * Parameters:
 *   ctx - Low latency context
 *   semaphore - Timeline semaphore to signal when sleep completes
 *   value - Timeline value to signal
 */
NvvkResult nvvk_low_latency_sleep(
    nvvk_low_latency_ctx_t ctx,
    NvvkSemaphore semaphore,
    uint64_t value
);

/*
 * Set a latency marker for the current frame.
 */
void nvvk_low_latency_set_marker(
    nvvk_low_latency_ctx_t ctx,
    NvvkLatencyMarker marker
);

/*
 * Begin a new frame. Increments present ID and sets simulation start marker.
 * Returns the new present ID.
 */
uint64_t nvvk_low_latency_begin_frame(nvvk_low_latency_ctx_t ctx);

/*
 * Convenience functions for common marker sequences.
 */
void nvvk_low_latency_end_simulation(nvvk_low_latency_ctx_t ctx);
void nvvk_low_latency_begin_render_submit(nvvk_low_latency_ctx_t ctx);
void nvvk_low_latency_end_render_submit(nvvk_low_latency_ctx_t ctx);
void nvvk_low_latency_begin_present(nvvk_low_latency_ctx_t ctx);
void nvvk_low_latency_end_present(nvvk_low_latency_ctx_t ctx);

/*
 * Mark input sample point. Call this when sampling user input.
 * Critical for accurate input-to-display latency measurement.
 */
void nvvk_low_latency_mark_input_sample(nvvk_low_latency_ctx_t ctx);

/*
 * Get current frame ID (present ID).
 */
uint64_t nvvk_low_latency_get_current_frame_id(nvvk_low_latency_ctx_t ctx);

/*
 * Get frame timing data from driver.
 *
 * Parameters:
 *   ctx - Low latency context
 *   timings - Array to receive timing data
 *   max_count - Maximum number of timings to retrieve
 *
 * Returns:
 *   Number of timings written to array
 */
uint32_t nvvk_low_latency_get_timings(
    nvvk_low_latency_ctx_t ctx,
    NvvkFrameTimings* timings,
    uint32_t max_count
);

/*
 * Example usage in DXVK:
 *
 *   // In DxvkDevice initialization:
 *   m_lowLatencyCtx = nvvk_low_latency_init(
 *       m_vkd.device(),
 *       m_swapchain,
 *       vkGetDeviceProcAddr
 *   );
 *   nvvk_low_latency_enable(m_lowLatencyCtx, true, 0);
 *
 *   // In render loop:
 *   nvvk_low_latency_begin_frame(m_lowLatencyCtx);
 *
 *   // ... game simulation ...
 *   nvvk_low_latency_end_simulation(m_lowLatencyCtx);
 *
 *   nvvk_low_latency_begin_render_submit(m_lowLatencyCtx);
 *   // ... submit commands ...
 *   nvvk_low_latency_end_render_submit(m_lowLatencyCtx);
 *
 *   nvvk_low_latency_begin_present(m_lowLatencyCtx);
 *   vkQueuePresentKHR(...);
 *   nvvk_low_latency_end_present(m_lowLatencyCtx);
 *
 *   // Sleep until optimal next frame time
 *   nvvk_low_latency_sleep(m_lowLatencyCtx, semaphore, value);
 */

#ifdef __cplusplus
}
#endif

#endif /* NVVK_LOW_LATENCY_H */
