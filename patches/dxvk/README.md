# DXVK Integration Patches

These patches add nvvk integration to DXVK for NVIDIA Reflex (low latency) and
frame generation support.

## Patches

1. **0001-nvvk-low-latency-integration.patch** - Adds Reflex support via nvvk
2. **0002-nvvk-frame-generation-hooks.patch** - Adds frame generation hooks

## Building DXVK with nvvk

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
cd /path/to/dxvk
git apply /path/to/nvvk/patches/dxvk/*.patch
```

### Build

```bash
# Update meson.build to link nvvk (done by patch)
meson setup --buildtype release build
ninja -C build
```

### Install

```bash
# Copy built DLLs to your Wine prefix
cp build/src/d3d9/*.dll ~/.wine/drive_c/windows/system32/
cp build/src/d3d10/*.dll ~/.wine/drive_c/windows/system32/
cp build/src/d3d11/*.dll ~/.wine/drive_c/windows/system32/
cp build/src/dxgi/*.dll ~/.wine/drive_c/windows/system32/
```

## Usage

### Enable Low Latency (Reflex)

```bash
# Enable for all DXVK games
export DXVK_NVVK_LOW_LATENCY=1

# Enable boost mode (higher power, lower latency)
export DXVK_NVVK_LOW_LATENCY_BOOST=1

wine game.exe
```

### Enable Frame Generation

```bash
# Enable frame generation
export DXVK_NVVK_FRAME_GEN=1

# Set mode: performance, balanced, quality
export DXVK_NVVK_FRAME_GEN_MODE=balanced

wine game.exe
```

### Environment Variables

| Variable | Values | Description |
|----------|--------|-------------|
| `DXVK_NVVK_LOW_LATENCY` | 0, 1 | Enable Reflex |
| `DXVK_NVVK_LOW_LATENCY_BOOST` | 0, 1 | Enable boost mode |
| `DXVK_NVVK_FRAME_GEN` | 0, 1 | Enable frame generation |
| `DXVK_NVVK_FRAME_GEN_MODE` | performance, balanced, quality | Frame gen quality |
| `DXVK_NVVK_DEBUG` | 0, 1 | Enable debug output |

## Compatibility

### Tested Games

| Game | Low Latency | Frame Gen | Notes |
|------|-------------|-----------|-------|
| TBD | | | Testing in progress |

### Known Issues

- Frame generation may cause visual artifacts during fast camera movement
- Some games with built-in frame limiters may conflict with Reflex sleep

## Technical Details

### Integration Points

1. **DxvkDevice::create()** - Initialize nvvk contexts
2. **DxvkPresenter::presentImage()** - Inject latency markers and frame gen
3. **DxvkSwapChain** - Handle swapchain recreation

### Latency Markers

The patches inject markers at these points:

```
Frame N:
  [INPUT_SAMPLE]     - When input is polled
  [SIMULATION_START] - Begin of frame logic
  [SIMULATION_END]   - End of frame logic
  [RENDERSUBMIT_START] - Begin GPU work submission
  [RENDERSUBMIT_END] - End GPU work submission
  [PRESENT_START]    - Before vkQueuePresentKHR
  [PRESENT_END]      - After vkQueuePresentKHR
```

### Frame Generation Flow

```
Real Frame N:
  1. Render game frame
  2. Push to nvvk history
  3. Present

Generated Frame N.5:
  4. nvvk generates interpolated frame
  5. Acquire swapchain image
  6. Copy generated frame
  7. Present generated frame

Real Frame N+1:
  (repeat)
```
