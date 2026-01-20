# nvvk Memory Management Guide

This document describes memory ownership rules and lifecycle management for nvvk.

## General Principles

### Ownership Rules

1. **Creator owns**: Whoever allocates memory is responsible for freeing it.
2. **Explicit transfer**: Ownership is never implicitly transferred.
3. **Context lifetime**: Resources are valid only while their parent context exists.

### Zig Allocator Pattern

nvvk uses Zig's allocator pattern. Pass an allocator to functions that need to allocate:

```zig
const allocator = std.heap.page_allocator;
var ctx = FrameGenContext.init(device, config, null, dispatch, allocator);
defer ctx.deinit();  // Uses same allocator internally
```

---

## Context Lifecycle

### Creation and Destruction

All contexts follow the init/deinit pattern:

```zig
// Zig
var ctx = try SomeContext.init(device, config, allocator);
defer ctx.deinit();

// Use ctx...
```

```c
// C
SomeHandle* handle = nvvk_some_init(device, config);
// Use handle...
nvvk_some_destroy(handle);  // Always safe with NULL
```

### GPU Resource Lifecycle

GPU resources (images, buffers, pipelines) are managed internally:

1. Created during `createResources()` or lazily on first use
2. Destroyed during `deinit()` or `destroyResources()`
3. Never outlive their parent context

```zig
var ctx = FrameSynthesisContext.init(device, phys_device, inst_dispatch, dispatch, config, allocator);
defer ctx.deinit();  // Destroys all GPU resources

try ctx.createResources();  // Creates pipelines, images
// Resources are now valid

// After deinit(), all resources are invalid
```

---

## Returned Allocations

Some functions return heap-allocated data that the caller must free.

### Functions That Allocate

| Module | Function | Returns | How to Free |
|--------|----------|---------|-------------|
| low_latency | `getTimings()` | `[]FrameTiming` | `allocator.free(slice)` |
| diagnostics | `getCheckpoints()` | `[]CheckpointData` | `allocator.free(slice)` |
| diagnostics | `CrashDump.format()` | `[]u8` | `allocator.free(slice)` |
| vrr | `queryDisplay()` | `VrrConfig` | `allocator.free(config.display_name.?)` |

### Pattern: Deferred Free

```zig
const timings = try ctx.getTimings(allocator);
defer allocator.free(timings);

for (timings) |t| {
    std.debug.print("Frame {}: {} us\n", .{ t.present_id, t.gpu_render_end_time_us });
}
// Automatically freed at scope exit
```

### Pattern: Conditional Free

```zig
const config = try vrr.queryDisplay(allocator, null);
if (config) |cfg| {
    defer if (cfg.display_name) |name| allocator.free(name);

    std.debug.print("Found display: {s}\n", .{cfg.display_name orelse "unknown"});
}
```

---

## C API Memory Rules

### Handle Ownership

```c
// Caller owns handles returned by _init
NvvkLowLatencyHandle* handle = nvvk_low_latency_init(device, swapchain, proc_addr);
if (!handle) {
    // Handle allocation failure
}

// Use handle...

// Caller must destroy
nvvk_low_latency_destroy(handle);  // Safe with NULL
handle = NULL;  // Good practice
```

### Output Buffers

C API never allocates output buffers. Caller provides them:

```c
NvvkFrameTimings timings[64];
uint32_t count = nvvk_low_latency_get_timings(handle, timings, 64);

// timings is stack-allocated, no need to free
for (uint32_t i = 0; i < count; i++) {
    printf("Frame %lu: %lu us\n", timings[i].present_id, timings[i].gpu_render_end_time_us);
}
```

### Static Strings

Extension names are static and should not be freed:

```c
const char* ext = nvvk_get_low_latency_extension_name();
// ext points to static data - do not free!
```

---

## GPU Memory

### Vulkan Memory Management

nvvk allocates Vulkan memory for internal resources:

1. **Device memory** for images and buffers
2. **Staging memory** for uploads (if needed)
3. **Descriptor pools** for shader bindings

Memory types are selected automatically using `findMemoryType()`:

```zig
// Internal function used by nvvk
fn findMemoryType(
    physical_device: VkPhysicalDevice,
    instance_dispatch: *const InstanceDispatch,
    type_filter: u32,
    properties: u32,
) !u32 {
    // Queries physical device memory properties
    // Finds suitable memory type with required properties
}
```

### External Image Handling

nvvk does **not** take ownership of external images:

```zig
// Your application's images
var prev_frame_view: VkImageView = ...;
var curr_frame_view: VkImageView = ...;

// Passed to nvvk but not owned
try synthesis_ctx.synthesize(
    cmd,
    prev_frame_view,  // Not owned by nvvk
    curr_frame_view,  // Not owned by nvvk
    mv_view,
    null,
    0.5,
);

// You must ensure these remain valid during synthesize()
// and destroy them yourself
```

---

## Thread Safety

### Single-Threaded Contexts

All nvvk contexts are **not thread-safe**. Do not access the same context from multiple threads without synchronization.

```zig
// WRONG: Data race
var ctx = LowLatencyContext.init(...);

// Thread 1
ctx.beginFrame();

// Thread 2 (concurrent)
ctx.setMode(config);  // Race condition!
```

### Safe Patterns

**Option 1: External mutex**
```zig
var mutex = std.Thread.Mutex{};
var ctx = LowLatencyContext.init(...);

// Thread 1
mutex.lock();
defer mutex.unlock();
ctx.beginFrame();

// Thread 2
mutex.lock();
defer mutex.unlock();
ctx.setMode(config);
```

**Option 2: Context per thread**
```zig
threadlocal var ctx: ?LowLatencyContext = null;

fn initForThread() void {
    ctx = LowLatencyContext.init(...);
}
```

---

## Error Handling

### Zig Errors

Functions that can fail return errors:

```zig
ctx.setMode(config) catch |err| switch (err) {
    error.ExtensionNotPresent => {
        // Extension not available
    },
    error.DeviceLost => {
        // GPU crashed, need to recreate device
    },
    else => return err,
};
```

### Resource Cleanup on Error

Use `errdefer` for cleanup when errors can occur during initialization:

```zig
fn createFullContext(allocator: Allocator) !*FullContext {
    const ctx = try allocator.create(FullContext);
    errdefer allocator.destroy(ctx);  // Cleanup if later steps fail

    ctx.low_latency = try LowLatencyContext.init(...);
    errdefer ctx.low_latency.deinit();

    ctx.frame_gen = try FrameGenContext.init(...);
    // If this fails, both errdefers run

    return ctx;
}
```

---

## Checklist

### Before Release

- [ ] All `init()` calls have matching `deinit()` calls
- [ ] All returned slices are freed with the correct allocator
- [ ] VrrConfig display names are freed when non-null
- [ ] GPU resources are destroyed before device destruction
- [ ] No dangling pointers to destroyed contexts

### Common Mistakes

1. **Forgetting to free getTimings() result**
   ```zig
   // WRONG
   const t = try ctx.getTimings(alloc);
   // Memory leak!

   // RIGHT
   const t = try ctx.getTimings(alloc);
   defer alloc.free(t);
   ```

2. **Using context after deinit**
   ```zig
   ctx.deinit();
   ctx.beginFrame();  // Undefined behavior!
   ```

3. **Destroying device before contexts**
   ```zig
   vkDestroyDevice(device, null);
   ctx.deinit();  // Too late! Device already gone
   ```
