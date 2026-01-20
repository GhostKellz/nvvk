# vkd3d-proton Integration Patches

These patches add nvvk integration to vkd3d-proton for NVIDIA Reflex (low latency) and
frame generation support in DX12 games.

## Patches

1. **0001-nvvk-low-latency-integration.patch** - Adds Reflex support via nvvk
2. **0002-nvvk-frame-generation-hooks.patch** - Adds frame generation hooks

## Building vkd3d-proton with nvvk

### Prerequisites

```bash
# Install nvvk
cd /path/to/nvvk
zig build -Doptimize=ReleaseFast
sudo zig build install --prefix /usr/local

# Ensure headers and library are available
ls /usr/local/include/nvvk.h
ls /usr/local/lib/libnvvk.so
```

### Apply Patches

```bash
cd /path/to/vkd3d-proton
git apply /path/to/nvvk/patches/vkd3d-proton/*.patch
```

### Build

```bash
# Configure with nvvk support
meson setup --buildtype release \
  -Denable_nvvk=true \
  build

# Build
ninja -C build
```

### Install

```bash
# Copy built DLLs to your Wine prefix
cp build/src/d3d12/*.dll ~/.wine/drive_c/windows/system32/
```

## Usage

### Enable Low Latency (Reflex)

```bash
# Enable for all vkd3d-proton games
export VKD3D_NVVK_LOW_LATENCY=1

# Enable boost mode (higher power, lower latency)
export VKD3D_NVVK_LOW_LATENCY_BOOST=1

wine game.exe
```

### Enable Frame Generation

```bash
# Enable frame generation
export VKD3D_NVVK_FRAME_GEN=1

# Set mode: performance, balanced, quality
export VKD3D_NVVK_FRAME_GEN_MODE=balanced

wine game.exe
```

### Environment Variables

| Variable | Values | Description |
|----------|--------|-------------|
| `VKD3D_NVVK_LOW_LATENCY` | 0, 1 | Enable Reflex |
| `VKD3D_NVVK_LOW_LATENCY_BOOST` | 0, 1 | Enable boost mode |
| `VKD3D_NVVK_FRAME_GEN` | 0, 1 | Enable frame generation |
| `VKD3D_NVVK_FRAME_GEN_MODE` | performance, balanced, quality | Frame gen quality |
| `VKD3D_NVVK_DEBUG` | 0, 1 | Enable debug output |

## Compatibility

### Tested Games

| Game | Low Latency | Frame Gen | Notes |
|------|-------------|-----------|-------|
| TBD | | | Testing in progress |

### Known Issues

- Some DX12 games with async compute may have timing issues with frame generation
- ExecuteIndirect heavy games may need additional latency marker tuning

## Technical Details

### Integration Points

1. **d3d12_swapchain.c** - Swapchain creation with nvvk context init
2. **d3d12_command_queue.c** - ExecuteCommandLists latency markers
3. **d3d12_swapchain.c:Present** - Present interception for frame gen

### DX12-Specific Considerations

DX12 presents unique challenges compared to DX11/DXVK:

1. **ExecuteIndirect**: GPU-driven rendering makes marker placement tricky
2. **Async Compute**: Multiple queues need coordinated markers
3. **Resource Barriers**: Frame gen must respect barrier state

### Latency Markers

The patches inject markers at these points:

```
Frame N:
  [INPUT_SAMPLE]         - When input is polled (ID3D12Device::GetFrameLatency)
  [SIMULATION_START]     - Begin of frame logic
  [SIMULATION_END]       - End of frame logic
  [RENDERSUBMIT_START]   - First ExecuteCommandLists
  [RENDERSUBMIT_END]     - Last ExecuteCommandLists before Present
  [PRESENT_START]        - Before IDXGISwapChain::Present
  [PRESENT_END]          - After Present completes
```

### Frame Generation Flow

```
Real Frame N:
  1. ExecuteCommandLists (render)
  2. Push frame to nvvk history
  3. Present

Generated Frame N.5:
  4. nvvk generates interpolated frame
  5. Acquire swapchain image
  6. Blit generated frame
  7. Present generated frame

Real Frame N+1:
  (repeat)
```
