# nvvk Zig API Reference

Native Zig API for nvvk.

## Table of Contents

- [Core Types](#core-types)
- [Low Latency Module](#low-latency-module)
- [Frame Generation Module](#frame-generation-module)
- [Optical Flow Module](#optical-flow-module)
- [Frame Synthesis Module](#frame-synthesis-module)
- [Motion Vectors Module](#motion-vectors-module)
- [Diagnostics Module](#diagnostics-module)
- [VRR Integration](#vrr-integration)

---

## Core Types

### DeviceDispatch

Device-level Vulkan function dispatch table.

```zig
const DeviceDispatch = struct {
    device: VkDevice,
    // VK_NV_low_latency2
    vkSetLatencySleepModeNV: ?PFN_vkSetLatencySleepModeNV,
    vkLatencySleepNV: ?PFN_vkLatencySleepNV,
    vkSetLatencyMarkerNV: ?PFN_vkSetLatencyMarkerNV,
    vkGetLatencyTimingsNV: ?PFN_vkGetLatencyTimingsNV,
    // ... additional functions

    pub fn init(device: VkDevice, getDeviceProcAddr: PFN_vkGetDeviceProcAddr) DeviceDispatch;
    pub fn hasLowLatency2(self: *const DeviceDispatch) bool;
    pub fn hasDiagnosticCheckpoints(self: *const DeviceDispatch) bool;
    pub fn hasComputePipelines(self: *const DeviceDispatch) bool;
};
```

### InstanceDispatch

Instance-level Vulkan function dispatch table.

```zig
const InstanceDispatch = struct {
    instance: VkInstance,
    vkGetPhysicalDeviceMemoryProperties: ?PFN_vkGetPhysicalDeviceMemoryProperties,

    pub fn init(instance: VkInstance, loader: *const Loader) InstanceDispatch;
};
```

---

## Low Latency Module

### LowLatencyContext

Context for NVIDIA Reflex low latency functionality.

```zig
const LowLatencyContext = struct {
    device: VkDevice,
    swapchain: u64,
    dispatch: *const DeviceDispatch,
    current_present_id: u64,

    pub fn init(
        device: VkDevice,
        swapchain: u64,
        dispatch: *const DeviceDispatch,
    ) LowLatencyContext;

    pub fn isSupported(self: *const LowLatencyContext) bool;
    pub fn setMode(self: *LowLatencyContext, config: ModeConfig) VulkanError!void;
    pub fn sleep(self: *LowLatencyContext, semaphore: u64, value: u64) VulkanError!void;
    pub fn setMarker(self: *LowLatencyContext, marker: Marker) void;
    pub fn beginFrame(self: *LowLatencyContext) u64;
    pub fn endSimulation(self: *LowLatencyContext) void;
    pub fn beginRenderSubmit(self: *LowLatencyContext) void;
    pub fn endRenderSubmit(self: *LowLatencyContext) void;
    pub fn beginPresent(self: *LowLatencyContext) void;
    pub fn endPresent(self: *LowLatencyContext) void;
    pub fn getTimings(self: *LowLatencyContext, allocator: Allocator) ![]FrameTiming;
};
```

**Memory Ownership:**
- `getTimings()` returns an allocated slice. **Caller must free with `allocator.free()`**.

### ModeConfig

```zig
const ModeConfig = struct {
    enabled: bool = false,
    boost: bool = false,
    min_interval_us: u32 = 0,

    pub fn disabled() ModeConfig;
};
```

### Marker

```zig
const Marker = enum {
    simulation_start,
    simulation_end,
    rendersubmit_start,
    rendersubmit_end,
    present_start,
    present_end,
    input_sample,
    trigger_flash,
    out_of_band_rendersubmit_start,
    out_of_band_rendersubmit_end,
    out_of_band_present_start,
    out_of_band_present_end,
};
```

---

## Frame Generation Module

### FrameGenContext

Frame generation context for interpolating frames.

```zig
const FrameGenContext = struct {
    pub fn init(
        device: VkDevice,
        config: FrameGenConfig,
        synthesis_ctx: ?*FrameSynthesisContext,
        dispatch: ?*const DeviceDispatch,
        allocator: Allocator,
    ) FrameGenContext;

    pub fn deinit(self: *FrameGenContext) void;
    pub fn setEnabled(self: *FrameGenContext, enabled: bool) void;
    pub fn setMode(self: *FrameGenContext, mode: FrameGenMode) void;
    pub fn pushFrame(self: *FrameGenContext, frame: FrameInput) void;
    pub fn execute(self: *FrameGenContext, cmd: VkCommandBuffer) !?GeneratedFrame;
    pub fn getStats(self: *const FrameGenContext) FrameGenStats;
    pub fn getLatencyCompensation(self: *const FrameGenContext) u64;
    pub fn getCurrentFrameId(self: *const FrameGenContext) u64;
};
```

**Memory Ownership:**
- `deinit()` must be called to free internal resources.
- The context does not own frame images passed to `pushFrame()`.

### FrameGenMode

```zig
const FrameGenMode = enum {
    off,
    performance,  // Fast, lower quality
    balanced,     // Default
    quality,      // Best quality, higher latency
};
```

### FrameGenConfig

```zig
const FrameGenConfig = struct {
    width: u32,
    height: u32,
    mode: FrameGenMode = .balanced,
    target_fps: f32 = 60.0,
    min_confidence: f32 = 0.5,
};
```

---

## Optical Flow Module

### OpticalFlowContext

GPU-accelerated optical flow estimation.

```zig
const OpticalFlowContext = struct {
    pub fn init(
        device: VkDevice,
        physical_device: VkPhysicalDevice,
        get_instance_proc_addr: PFN_vkGetInstanceProcAddr,
        get_device_proc_addr: PFN_vkGetDeviceProcAddr,
        config: OpticalFlowConfig,
    ) !OpticalFlowContext;

    pub fn deinit(self: *OpticalFlowContext) void;
    pub fn bindImage(
        self: *OpticalFlowContext,
        binding_point: SessionBindingPoint,
        image_view: VkImageView,
        layout: u32,
    ) !void;
    pub fn execute(
        self: *OpticalFlowContext,
        cmd: VkCommandBuffer,
        regions: ?[]const VkRect2D,
        flags: ExecuteFlags,
    ) !void;
};
```

**Memory Ownership:**
- `deinit()` destroys the optical flow session.
- Images bound via `bindImage()` are not owned by the context.

### OpticalFlowConfig

```zig
const OpticalFlowConfig = struct {
    width: u32,
    height: u32,
    image_format: u32 = 0,  // 0 = use default
    output_grid_size: GridSize = .@"4x4",
    hint_grid_size: GridSize = .unknown,
    performance_level: PerformanceLevel = .fast,
    bidirectional: bool = false,
    enable_cost: bool = false,
    enable_global_flow: bool = false,
    flags: u32 = 0,
};
```

### GridSize

```zig
const GridSize = enum(u32) {
    unknown = 0,
    @"1x1" = 0x00000001,
    @"2x2" = 0x00000002,
    @"4x4" = 0x00000004,
    @"8x8" = 0x00000008,
};
```

---

## Frame Synthesis Module

### FrameSynthesisContext

GPU compute pipeline for frame warping and blending.

```zig
const FrameSynthesisContext = struct {
    pub fn init(
        device: ?VkDevice,
        physical_device: ?VkPhysicalDevice,
        instance_dispatch: ?*const InstanceDispatch,
        dispatch: ?*const DeviceDispatch,
        config: SynthesisConfig,
        allocator: Allocator,
    ) FrameSynthesisContext;

    pub fn deinit(self: *FrameSynthesisContext) void;
    pub fn createResources(self: *FrameSynthesisContext) !void;
    pub fn synthesize(
        self: *FrameSynthesisContext,
        cmd: VkCommandBuffer,
        prev_frame: VkImageView,
        curr_frame: VkImageView,
        motion_vectors: VkImageView,
        cost_map: ?VkImageView,
        blend_factor: f32,
    ) !void;
    pub fn getOutputView(self: *const FrameSynthesisContext) ?VkImageView;
    pub fn getOutputImage(self: *const FrameSynthesisContext) ?VkImage;
};
```

**Memory Ownership:**
- `deinit()` destroys all GPU resources (pipelines, images, memory).
- Input images are not owned by the context.

---

## Motion Vectors Module

### MotionVectorContext

Motion vector extraction using optical flow.

```zig
const MotionVectorContext = struct {
    pub fn init(
        device: VkDevice,
        config: MotionVectorConfig,
        dispatch: ?*const DeviceDispatch,
        allocator: Allocator,
    ) MotionVectorContext;

    pub fn createResources(
        self: *MotionVectorContext,
        physical_device: VkPhysicalDevice,
        instance_dispatch: *const InstanceDispatch,
        get_instance_proc_addr: PFN_vkGetInstanceProcAddr,
        get_device_proc_addr: PFN_vkGetDeviceProcAddr,
    ) !void;

    pub fn destroyResources(self: *MotionVectorContext) void;
    pub fn compute(
        self: *MotionVectorContext,
        cmd: VkCommandBuffer,
        current_frame: VkImageView,
    ) !void;
    pub fn getMotionVectors(self: *const MotionVectorContext) ?*const MotionVectorBuffer;
};
```

---

## Diagnostics Module

### DiagnosticsContext

GPU crash diagnostics and checkpoints.

```zig
const DiagnosticsContext = struct {
    pub fn init(device: VkDevice, dispatch: *const DeviceDispatch) DiagnosticsContext;
    pub fn isSupported(self: *const DiagnosticsContext) bool;
    pub fn setCheckpoint(self: *const DiagnosticsContext, cmd: VkCommandBuffer, marker: ?*const anyopaque) void;
    pub fn setTaggedCheckpoint(self: *const DiagnosticsContext, cmd: VkCommandBuffer, tag: CheckpointTag) void;
    pub fn getCheckpoints(self: *const DiagnosticsContext, queue: VkQueue, allocator: Allocator) ![]CheckpointData;
};
```

**Memory Ownership:**
- `getCheckpoints()` returns an allocated slice. **Caller must free**.

### CrashDump

```zig
const CrashDump = struct {
    timestamp_ns: i128,
    checkpoints: []CheckpointData,
    last_stage: PipelineStage,
    last_tag: ?CheckpointTag,

    pub fn generate(ctx: *const DiagnosticsContext, queue: VkQueue, allocator: Allocator) !CrashDump;
    pub fn deinit(self: *CrashDump, allocator: Allocator) void;
    pub fn format(self: *const CrashDump, allocator: Allocator) ![]u8;
    pub fn writeToFile(self: *const CrashDump, path: []const u8, allocator: Allocator) !void;
};
```

**Memory Ownership:**
- `deinit()` frees checkpoint data.
- `format()` returns allocated string. **Caller must free**.

---

## VRR Integration

### VrrConfig

```zig
const VrrConfig = struct {
    min_hz: u32 = 48,
    max_hz: u32 = 144,
    lfc_supported: bool = false,
    source: VrrSource = .none,
    enabled: bool = false,
    display_name: ?[]const u8 = null,

    pub fn default() VrrConfig;
    pub fn minIntervalUs(self: VrrConfig) u64;
    pub fn maxIntervalUs(self: VrrConfig) u64;
    pub fn isInRange(self: VrrConfig, fps: u32) bool;
    pub fn effectiveMinHz(self: VrrConfig) u32;
    pub fn calculateInjectionInterval(self: VrrConfig, avg_frame_time_us: u64) u64;
};
```

### Query Functions

```zig
pub fn queryDisplay(allocator: Allocator, display_name: ?[]const u8) !?VrrConfig;
pub fn queryFirstDisplay(allocator: Allocator) !?VrrConfig;
pub fn isVrrAvailable(allocator: Allocator) bool;
pub fn getSystemStatus(allocator: Allocator) !VrrStatus;
```

**Memory Ownership:**
- `queryDisplay()` allocates `display_name`. **Caller must free** with `allocator.free(config.display_name.?)`.

---

## Memory Ownership Summary

| Function | Returns | Caller Must Free |
|----------|---------|------------------|
| `LowLatencyContext.getTimings()` | `[]FrameTiming` | Yes |
| `DiagnosticsContext.getCheckpoints()` | `[]CheckpointData` | Yes |
| `CrashDump.format()` | `[]u8` | Yes |
| `vrr.queryDisplay()` | `VrrConfig` | Yes (`display_name`) |
| All `deinit()` functions | void | N/A (frees internal) |

### Best Practices

1. Always pair `init()` with `deinit()` or `destroy*()`.
2. Check return values for `null` before using.
3. Use `defer` for cleanup:
   ```zig
   var ctx = try Context.init(...);
   defer ctx.deinit();
   ```
4. When receiving allocated slices, immediately set up cleanup:
   ```zig
   const timings = try ctx.getTimings(allocator);
   defer allocator.free(timings);
   ```
