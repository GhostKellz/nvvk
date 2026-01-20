# nvvk API Documentation

This directory contains API documentation for nvvk.

## Contents

- [C API Reference](c-api.md) - C-compatible API for integration with C/C++ projects
- [Zig API Reference](zig-api.md) - Native Zig API documentation
- [Memory Management](memory.md) - Memory ownership and lifecycle guidelines

## Quick Start

### Zig

```zig
const nvvk = @import("nvvk");

// Initialize low latency context
var dispatch = nvvk.DeviceDispatch.init(device, get_device_proc_addr);
var ctx = nvvk.LowLatencyContext.init(device, swapchain, &dispatch);

// Enable low latency mode
try ctx.setMode(.{ .enabled = true, .boost = true });

// Frame loop
while (running) {
    const frame_id = ctx.beginFrame();
    // ... render ...
    ctx.endRenderSubmit();
    ctx.beginPresent();
    // ... present ...
    ctx.endPresent();
}
```

### C

```c
#include <nvvk.h>

// Initialize
NvvkLowLatencyHandle* handle = nvvk_low_latency_init(
    device, swapchain, vkGetDeviceProcAddr);

// Enable
nvvk_low_latency_enable(handle, true, 0);

// Frame loop
while (running) {
    uint64_t frame_id = nvvk_low_latency_begin_frame(handle);
    // ... render ...
    nvvk_low_latency_end_render_submit(handle);
    nvvk_low_latency_begin_present(handle);
    // ... present ...
    nvvk_low_latency_end_present(handle);
}

// Cleanup
nvvk_low_latency_destroy(handle);
```

## Supported Extensions

| Extension | Description | Min Driver |
|-----------|-------------|------------|
| VK_NV_low_latency2 | NVIDIA Reflex low latency | 590+ |
| VK_NV_optical_flow | GPU optical flow for frame gen | 590+ |
| VK_NV_device_diagnostic_checkpoints | GPU crash debugging | 590+ |
| VK_NV_ray_tracing | Ray tracing support | 590+ |
| VK_NV_mesh_shader | Mesh shader support | 590+ |

## Thread Safety

All nvvk contexts are **not thread-safe** by default. Synchronize access externally
when using from multiple threads, or create separate contexts per thread.
