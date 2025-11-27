# nvvk

**NVIDIA Vulkan Extensions Library for Linux Gaming**

A Zig library providing optimized NVIDIA Vulkan extension wrappers with C ABI exports for integration with DXVK, vkd3d-proton, and other Vulkan-based translation layers.

![Zig Version](https://img.shields.io/badge/Zig-0.16.0--dev-orange?style=flat&logo=zig&logoColor=white)
![Vulkan](https://img.shields.io/badge/Vulkan-1.3+-red?style=flat&logo=vulkan&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux-blue?style=flat&logo=linux&logoColor=white)
![NVIDIA](https://img.shields.io/badge/NVIDIA-535%2B-76B900?style=flat&logo=nvidia&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=flat)

## Overview

nvvk exposes NVIDIA-specific Vulkan extensions that are often underutilized on Linux:

- **VK_NV_low_latency2** - NVIDIA Reflex integration for reduced input latency
- **VK_NV_device_diagnostics_config** - GPU crash diagnostics and debugging
- **VK_NV_device_diagnostic_checkpoints** - Execution checkpoints for debugging

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Game / Application                    │
├─────────────────────────────────────────────────────────┤
│              DXVK / vkd3d-proton (C++)                  │
├─────────────────────────────────────────────────────────┤
│                  nvvk (Zig + C ABI)                     │
│  ┌─────────────┬─────────────┬─────────────────────┐   │
│  │ low_latency │  diagnostics │  crash_dump         │   │
│  └─────────────┴─────────────┴─────────────────────┘   │
├─────────────────────────────────────────────────────────┤
│                   Vulkan Driver                          │
└─────────────────────────────────────────────────────────┘
```

## Why Zig?

- **Zero-overhead C ABI** - Direct integration with C++ codebases
- **No runtime dependencies** - Static linking, no GC
- **Compile-time safety** - Catch errors before runtime
- **Cross-compilation** - Build for any Linux target

## Usage

### Zig Integration

```zig
const nvvk = @import("nvvk");

// Initialize with your Vulkan device
var dispatch = nvvk.DeviceDispatch.init(device, getDeviceProcAddr);

// Create low latency context for your swapchain
var ll = nvvk.LowLatencyContext.init(device, swapchain, &dispatch);

// Enable low latency mode with boost
try ll.setMode(.{ .enabled = true, .boost = true });

// In render loop
_ = ll.beginFrame();
// ... game logic ...
ll.endSimulation();
ll.beginRenderSubmit();
// ... submit commands ...
ll.endRenderSubmit();
```

### C/C++ Integration

```c
#include <nvvk/nvvk_low_latency.h>

// Initialize low latency mode
nvvk_low_latency_ctx_t* ctx = nvvk_low_latency_init(vk_device, swapchain, vkGetDeviceProcAddr);

// Enable with boost
nvvk_low_latency_enable(ctx, true, 0);

// In render loop
nvvk_low_latency_begin_frame(ctx);
// ... game logic ...
nvvk_low_latency_end_simulation(ctx);
nvvk_low_latency_begin_render_submit(ctx);
// ... render commands ...
nvvk_low_latency_end_render_submit(ctx);
nvvk_low_latency_sleep(ctx, semaphore, value);
```

### DXVK Patch Integration

```cpp
// In dxvk/src/dxvk_device.cpp
#include <nvvk/nvvk_low_latency.h>

void DxvkDevice::initializeLowLatency() {
    if (nvvk_is_nvidia_gpu()) {
        m_lowLatencyCtx = nvvk_low_latency_init(m_vkd.device(), swapchain, vkGetDeviceProcAddr);
        nvvk_low_latency_enable(m_lowLatencyCtx, true, 0);
    }
}
```

## Building

```bash
# Build shared library (default)
zig build -Doptimize=ReleaseFast

# Build static library
zig build -Doptimize=ReleaseFast -Dlinkage=static

# Run tests
zig build test

# Run CLI demo
zig build run
```

## Installation

```bash
# Install to /usr/local
sudo zig build install --prefix /usr/local

# Or specify custom prefix
zig build install --prefix ~/.local
```

## Integration with nvcontrol

nvvk is part of the NVIDIA Linux Gaming Stack:

| Project | Purpose | Language |
|---------|---------|----------|
| **nvcontrol** | GUI/TUI control center | Rust |
| **nvvk** | Vulkan extension library | Zig |
| **nvlatency** | Reflex/latency tools | Zig |
| **nvshader** | Shader cache management | Zig |
| **nvsync** | VRR/G-Sync manager | Zig |
| **nvproton** | Proton integration | Rust + Zig |

## License

MIT License - See [LICENSE](LICENSE)

## Contributing

Contributions welcome! Please read the [TODO.md](TODO.md) for the development roadmap.
