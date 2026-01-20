# nvvk C API Reference

C-compatible API for integrating nvvk with C/C++ projects like DXVK and vkd3d-proton.

## Table of Contents

- [Types](#types)
- [Low Latency API](#low-latency-api)
- [Frame Generation API](#frame-generation-api)
- [Present Injection API](#present-injection-api)
- [Diagnostics API](#diagnostics-api)
- [Utility Functions](#utility-functions)

---

## Types

### Result Codes

```c
typedef enum NvvkResult {
    NVVK_SUCCESS = 0,
    NVVK_ERROR_NOT_SUPPORTED = -1,
    NVVK_ERROR_INVALID_HANDLE = -2,
    NVVK_ERROR_OUT_OF_MEMORY = -3,
    NVVK_ERROR_DEVICE_LOST = -4,
    NVVK_ERROR_UNKNOWN = -5,
} NvvkResult;
```

### Latency Markers

```c
typedef enum NvvkLatencyMarker {
    NVVK_MARKER_SIMULATION_START = 0,
    NVVK_MARKER_SIMULATION_END = 1,
    NVVK_MARKER_RENDERSUBMIT_START = 2,
    NVVK_MARKER_RENDERSUBMIT_END = 3,
    NVVK_MARKER_PRESENT_START = 4,
    NVVK_MARKER_PRESENT_END = 5,
    NVVK_MARKER_INPUT_SAMPLE = 6,
    NVVK_MARKER_TRIGGER_FLASH = 7,
    // Out-of-band markers for async operations
    NVVK_MARKER_OUT_OF_BAND_RENDERSUBMIT_START = 8,
    NVVK_MARKER_OUT_OF_BAND_RENDERSUBMIT_END = 9,
    NVVK_MARKER_OUT_OF_BAND_PRESENT_START = 10,
    NVVK_MARKER_OUT_OF_BAND_PRESENT_END = 11,
} NvvkLatencyMarker;
```

### Frame Timings

```c
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
```

---

## Low Latency API

### nvvk_low_latency_init

Initialize a low latency context for a swapchain.

```c
NvvkLowLatencyHandle* nvvk_low_latency_init(
    VkDevice device,
    VkSwapchainKHR swapchain,
    PFN_vkGetDeviceProcAddr get_device_proc_addr
);
```

**Parameters:**
- `device` - Vulkan device handle
- `swapchain` - Swapchain to enable low latency on
- `get_device_proc_addr` - Function pointer for loading device functions

**Returns:** Handle to low latency context, or `NULL` on failure.

**Memory Ownership:** Caller owns the returned handle. Must call `nvvk_low_latency_destroy()` to free.

---

### nvvk_low_latency_destroy

Destroy a low latency context and free resources.

```c
void nvvk_low_latency_destroy(NvvkLowLatencyHandle* handle);
```

**Parameters:**
- `handle` - Handle from `nvvk_low_latency_init()`, may be `NULL`

**Memory Ownership:** Frees the handle. Do not use after calling.

---

### nvvk_low_latency_enable

Enable low latency mode with optional boost.

```c
NvvkResult nvvk_low_latency_enable(
    NvvkLowLatencyHandle* handle,
    bool boost,
    uint32_t min_interval_us
);
```

**Parameters:**
- `handle` - Low latency context
- `boost` - Enable boost mode for additional latency reduction
- `min_interval_us` - Minimum frame interval in microseconds (0 = no limit)

**Returns:** `NVVK_SUCCESS` or error code.

---

### nvvk_low_latency_disable

Disable low latency mode.

```c
NvvkResult nvvk_low_latency_disable(NvvkLowLatencyHandle* handle);
```

---

### nvvk_low_latency_sleep

Sleep until optimal frame start time.

```c
NvvkResult nvvk_low_latency_sleep(
    NvvkLowLatencyHandle* handle,
    VkSemaphore semaphore,
    uint64_t value
);
```

**Parameters:**
- `handle` - Low latency context
- `semaphore` - Timeline semaphore to signal when sleep completes
- `value` - Semaphore value to signal

---

### nvvk_low_latency_begin_frame

Begin a new frame. Increments present ID and sets simulation start marker.

```c
uint64_t nvvk_low_latency_begin_frame(NvvkLowLatencyHandle* handle);
```

**Returns:** Frame ID for this frame.

---

### nvvk_low_latency_get_timings

Get frame timing data from the driver.

```c
uint32_t nvvk_low_latency_get_timings(
    NvvkLowLatencyHandle* handle,
    NvvkFrameTimings* timings,
    uint32_t max_count
);
```

**Parameters:**
- `handle` - Low latency context
- `timings` - Array to receive timing data
- `max_count` - Maximum entries to write

**Returns:** Number of timing entries written.

**Memory Ownership:** Caller provides the buffer. No allocation performed.

---

## Frame Generation API

### nvvk_frame_gen_init

Initialize frame generation context.

```c
NvvkFrameGenHandle* nvvk_frame_gen_init(
    VkDevice device,
    uint32_t width,
    uint32_t height,
    NvvkFrameGenMode mode,
    PFN_vkGetDeviceProcAddr get_device_proc_addr
);
```

**Parameters:**
- `device` - Vulkan device
- `width` - Frame width in pixels
- `height` - Frame height in pixels
- `mode` - Generation mode (`NVVK_FRAME_GEN_OFF`, `PERFORMANCE`, `BALANCED`, `QUALITY`)
- `get_device_proc_addr` - Function pointer for loading device functions (optional, may be `NULL`)

**Returns:** Handle or `NULL` on failure.

**Memory Ownership:** Caller owns the handle. Call `nvvk_frame_gen_destroy()` to free.

---

### nvvk_frame_gen_destroy

Destroy frame generation context.

```c
void nvvk_frame_gen_destroy(NvvkFrameGenHandle* handle);
```

**Memory Ownership:** Frees handle and all associated GPU resources.

---

### nvvk_frame_gen_get_stats

Get frame generation statistics.

```c
void nvvk_frame_gen_get_stats(
    const NvvkFrameGenHandle* handle,
    NvvkFrameGenStats* stats
);
```

**Memory Ownership:** Caller provides the stats buffer. No allocation.

---

## Present Injection API

### nvvk_present_injection_init

Initialize present injection context.

```c
NvvkPresentInjectionHandle* nvvk_present_injection_init(
    VkDevice device,
    VkSwapchainKHR swapchain,
    NvvkInjectionMode injection_mode,
    NvvkTimingMode timing_mode
);
```

**Memory Ownership:** Caller owns returned handle.

---

### nvvk_present_injection_destroy

Destroy present injection context.

```c
void nvvk_present_injection_destroy(NvvkPresentInjectionHandle* handle);
```

---

## Diagnostics API

### nvvk_diagnostics_init

Initialize diagnostics context for GPU crash debugging.

```c
NvvkDiagnosticsHandle* nvvk_diagnostics_init(
    VkDevice device,
    PFN_vkGetDeviceProcAddr get_device_proc_addr
);
```

**Memory Ownership:** Caller owns returned handle.

---

### nvvk_diagnostics_set_checkpoint

Insert a checkpoint marker into a command buffer.

```c
void nvvk_diagnostics_set_checkpoint(
    const NvvkDiagnosticsHandle* handle,
    VkCommandBuffer cmd,
    const void* marker
);
```

**Parameters:**
- `handle` - Diagnostics context
- `cmd` - Command buffer to insert checkpoint into
- `marker` - User pointer that can be retrieved after GPU hang

---

## Utility Functions

### nvvk_get_version

Get library version.

```c
uint32_t nvvk_get_version(void);
```

**Returns:** Version encoded as `(major << 16) | (minor << 8) | patch`.

---

### nvvk_is_nvidia_gpu

Check if running on NVIDIA GPU.

```c
bool nvvk_is_nvidia_gpu(void);
```

---

### nvvk_get_low_latency_extension_name

Get the Vulkan extension name for low latency.

```c
const char* nvvk_get_low_latency_extension_name(void);
```

**Returns:** `"VK_NV_low_latency2"`

---

## Memory Management Summary

| Function | Returns | Ownership |
|----------|---------|-----------|
| `nvvk_*_init` | Handle pointer | Caller owns, must destroy |
| `nvvk_*_destroy` | void | Frees handle |
| `nvvk_*_get_timings` | count | Caller provides buffer |
| `nvvk_*_get_stats` | void | Caller provides buffer |
| `nvvk_get_*_extension_name` | const char* | Static, do not free |

### Rules

1. **All `_init` functions** return handles that the caller owns and must destroy.
2. **All `_destroy` functions** accept `NULL` safely.
3. **Output buffers** are always provided by the caller (no internal allocation).
4. **Extension names** are static strings - do not free.
5. **Handle validity** - handles are invalid after `_destroy` is called.
