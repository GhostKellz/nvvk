/*
 * nvvk - NVIDIA Vulkan Extensions Library
 *
 * Frame Generation API
 *
 * Provides DLSS Frame Generation alternative using VK_NV_optical_flow.
 * Generates intermediate frames to effectively double frame rate.
 *
 * Requires:
 * - NVIDIA driver 590+
 * - VK_NV_optical_flow extension
 * - RTX 40+ series GPU recommended
 */

#ifndef NVVK_FRAME_GENERATION_H
#define NVVK_FRAME_GENERATION_H

#ifdef __cplusplus
extern "C" {
#endif

#include "nvvk.h"

/* Frame generation quality modes */
typedef enum NvvkFrameGenMode {
    NVVK_FRAME_GEN_OFF = 0,         /* Disabled - passthrough */
    NVVK_FRAME_GEN_PERFORMANCE = 1, /* Fast linear blend, ~1ms */
    NVVK_FRAME_GEN_BALANCED = 2,    /* Bidirectional warp, ~2ms */
    NVVK_FRAME_GEN_QUALITY = 3,     /* Full pipeline, ~3ms */
} NvvkFrameGenMode;

/* Frame generation statistics */
typedef struct NvvkFrameGenStats {
    uint64_t generated_frames;       /* Total frames generated */
    uint64_t skipped_frames;         /* Frames skipped (scene change, etc.) */
    uint64_t avg_gen_time_us;        /* Average generation time in microseconds */
    float confidence;                /* Current confidence score (0.0-1.0) */
    bool scene_change_detected;      /* Scene change detected in last frame */
} NvvkFrameGenStats;

/* Generated frame result */
typedef struct NvvkGeneratedFrame {
    uint64_t image_view;             /* VkImageView handle */
    uint64_t image;                  /* VkImage handle */
    float confidence;                /* Confidence score for this frame */
    uint64_t generation_time_us;     /* Generation time in microseconds */
    uint64_t frame_id;               /* Frame ID (matches Reflex present ID) */
    bool should_present;             /* Whether this frame should be presented */
} NvvkGeneratedFrame;

/* Opaque frame generation context handle */
typedef struct NvvkFrameGenContext* nvvk_frame_gen_ctx_t;

/*
 * Initialize frame generation context.
 *
 * Parameters:
 *   device - VkDevice handle
 *   width - Frame width in pixels
 *   height - Frame height in pixels
 *   mode - Quality mode (performance recommended for most games)
 *
 * Returns:
 *   Context handle on success, NULL on failure
 */
nvvk_frame_gen_ctx_t nvvk_frame_gen_init(
    NvvkDevice device,
    uint32_t width,
    uint32_t height,
    NvvkFrameGenMode mode
);

/*
 * Destroy frame generation context.
 */
void nvvk_frame_gen_destroy(nvvk_frame_gen_ctx_t ctx);

/*
 * Enable or disable frame generation.
 */
void nvvk_frame_gen_set_enabled(nvvk_frame_gen_ctx_t ctx, bool enabled);

/*
 * Set frame generation mode.
 */
void nvvk_frame_gen_set_mode(nvvk_frame_gen_ctx_t ctx, NvvkFrameGenMode mode);

/*
 * Get frame generation statistics.
 */
void nvvk_frame_gen_get_stats(nvvk_frame_gen_ctx_t ctx, NvvkFrameGenStats* stats);

/*
 * Get latency compensation in microseconds.
 *
 * This value should be added to Reflex timing to account for
 * the additional latency introduced by frame generation.
 */
uint64_t nvvk_frame_gen_get_latency_compensation(nvvk_frame_gen_ctx_t ctx);

/*
 * Get current frame ID.
 */
uint64_t nvvk_frame_gen_get_current_frame_id(nvvk_frame_gen_ctx_t ctx);

/*
 * Get extension name for optical flow (required for frame gen).
 */
const char* nvvk_get_optical_flow_extension_name(void);

/*
 * Example usage in DXVK:
 *
 *   // Initialize
 *   nvvk_frame_gen_ctx_t fg = nvvk_frame_gen_init(
 *       device, 1920, 1080, NVVK_FRAME_GEN_PERFORMANCE);
 *
 *   // In render loop, after rendering real frame:
 *   // 1. Push frame to history
 *   // 2. Generate intermediate frame if we have enough history
 *   // 3. Present: real -> generated -> real -> generated...
 *
 *   // Cleanup
 *   nvvk_frame_gen_destroy(fg);
 */

#ifdef __cplusplus
}
#endif

#endif /* NVVK_FRAME_GENERATION_H */
