//! Async Sleep Implementation
//!
//! Provides non-blocking sleep with callback support for NVIDIA Reflex.
//! The async sleep allows the application to continue processing while
//! waiting for the optimal frame start time.
//!
//! This is useful for:
//! - Non-blocking frame pacing
//! - Callback-based notification when sleep completes
//! - Integration with async/await patterns

const std = @import("std");
const vk = @import("vulkan.zig");
const low_latency = @import("low_latency.zig");

// =============================================================================
// Simple Spinlock Mutex (Zig 0.16+ compatible)
// =============================================================================

const Mutex = struct {
    state: std.atomic.Value(u32) = .init(0),

    const Self = @This();

    pub fn lock(self: *Self) void {
        while (self.state.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *Self) void {
        self.state.store(0, .release);
    }
};

// =============================================================================
// Types
// =============================================================================

/// Callback function type for async sleep completion
pub const AsyncCallback = *const fn (user_data: ?*anyopaque, result: AsyncResult) void;

/// Result of an async sleep operation
pub const AsyncResult = enum {
    /// Sleep completed successfully
    completed,
    /// Sleep was cancelled
    cancelled,
    /// Error occurred during sleep
    failed,
    /// Timeout expired
    timeout,
};

/// Async sleep request handle
pub const AsyncSleepHandle = struct {
    id: u64,
    cancelled: std.atomic.Value(bool),
};

/// Async sleep context for managing non-blocking sleep operations
pub const AsyncSleepContext = struct {
    allocator: std.mem.Allocator,
    device: ?vk.VkDevice,
    dispatch: ?*const vk.DeviceDispatch,

    // Pending requests
    pending_requests: std.AutoHashMap(u64, PendingRequest),
    request_lock: Mutex,
    next_request_id: std.atomic.Value(u64),

    // Stats
    completed_count: std.atomic.Value(u64),
    cancelled_count: std.atomic.Value(u64),
    failed_count: std.atomic.Value(u64),

    const PendingRequest = struct {
        semaphore: u64,
        value: u64,
        callback: ?AsyncCallback,
        user_data: ?*anyopaque,
        handle: *AsyncSleepHandle,
        start_time_us: i64,
    };

    /// Initialize async sleep context
    pub fn init(
        device: ?vk.VkDevice,
        dispatch: ?*const vk.DeviceDispatch,
        allocator: std.mem.Allocator,
    ) AsyncSleepContext {
        return .{
            .allocator = allocator,
            .device = device,
            .dispatch = dispatch,
            .pending_requests = std.AutoHashMap(u64, PendingRequest).init(allocator),
            .request_lock = .{},
            .next_request_id = std.atomic.Value(u64).init(1),
            .completed_count = std.atomic.Value(u64).init(0),
            .cancelled_count = std.atomic.Value(u64).init(0),
            .failed_count = std.atomic.Value(u64).init(0),
        };
    }

    /// Cleanup async sleep context
    pub fn deinit(self: *AsyncSleepContext) void {
        // Cancel all pending requests
        self.request_lock.lock();
        defer self.request_lock.unlock();

        var it = self.pending_requests.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.handle.cancelled.store(true, .release);
            self.allocator.destroy(entry.value_ptr.handle);
        }
        self.pending_requests.deinit();
    }

    /// Submit an async sleep request
    /// Returns a handle that can be used to cancel the request
    pub fn sleepAsync(
        self: *AsyncSleepContext,
        semaphore: u64,
        value: u64,
        callback: ?AsyncCallback,
        user_data: ?*anyopaque,
    ) !*AsyncSleepHandle {
        const request_id = self.next_request_id.fetchAdd(1, .monotonic);

        // Create handle
        const handle = try self.allocator.create(AsyncSleepHandle);
        handle.* = .{
            .id = request_id,
            .cancelled = std.atomic.Value(bool).init(false),
        };

        // Create pending request
        const request = PendingRequest{
            .semaphore = semaphore,
            .value = value,
            .callback = callback,
            .user_data = user_data,
            .handle = handle,
            .start_time_us = @divTrunc(std.time.nanoTimestamp(), 1000),
        };

        // Add to pending
        {
            self.request_lock.lock();
            defer self.request_lock.unlock();
            try self.pending_requests.put(request_id, request);
        }

        // Spawn worker thread
        _ = try std.Thread.spawn(.{}, sleepWorkerThread, .{ self, request_id });

        return handle;
    }

    /// Cancel a pending sleep request
    pub fn cancel(self: *AsyncSleepContext, handle: *AsyncSleepHandle) void {
        handle.cancelled.store(true, .release);

        // Remove from pending
        self.request_lock.lock();
        defer self.request_lock.unlock();

        if (self.pending_requests.fetchRemove(handle.id)) |_| {
            _ = self.cancelled_count.fetchAdd(1, .monotonic);
        }
    }

    /// Check if a request is still pending
    pub fn isPending(self: *AsyncSleepContext, handle: *const AsyncSleepHandle) bool {
        self.request_lock.lock();
        defer self.request_lock.unlock();
        return self.pending_requests.contains(handle.id);
    }

    /// Get statistics
    pub fn getStats(self: *const AsyncSleepContext) AsyncSleepStats {
        return .{
            .pending_count = self.pending_requests.count(),
            .completed_count = self.completed_count.load(.acquire),
            .cancelled_count = self.cancelled_count.load(.acquire),
            .failed_count = self.failed_count.load(.acquire),
        };
    }

    fn sleepWorkerThread(self: *AsyncSleepContext, request_id: u64) void {
        self.executeRequest(request_id);
    }

    fn executeRequest(self: *AsyncSleepContext, request_id: u64) void {
        // Get request
        var request: ?PendingRequest = null;
        {
            self.request_lock.lock();
            defer self.request_lock.unlock();
            if (self.pending_requests.get(request_id)) |r| {
                request = r;
            }
        }

        if (request == null) return;
        const req = request.?;

        // Check if cancelled
        if (req.handle.cancelled.load(.acquire)) {
            self.invokeCallback(req.callback, req.user_data, .cancelled);
            return;
        }

        // Execute the actual sleep
        var result: AsyncResult = .completed;

        if (self.dispatch) |dispatch| {
            if (self.device) |device| {
                if (dispatch.vkLatencySleepNV) |sleep_fn| {
                    const sleep_info = vk.VkLatencySleepInfoNV{
                        .signalSemaphore = @ptrFromInt(req.semaphore),
                        .value = req.value,
                    };

                    const vk_result = sleep_fn(device, @ptrFromInt(req.semaphore), &sleep_info);
                    if (vk_result != 0) {
                        result = .failed;
                        _ = self.failed_count.fetchAdd(1, .monotonic);
                    }
                } else {
                    // No Vulkan sleep function - do a timed sleep instead
                    std.time.sleep(1_000_000); // 1ms
                }
            } else {
                // No device - simulate sleep
                std.time.sleep(1_000_000); // 1ms
            }
        } else {
            // No dispatch - simulate sleep
            std.time.sleep(1_000_000); // 1ms
        }

        // Check cancelled again
        if (req.handle.cancelled.load(.acquire)) {
            result = .cancelled;
        }

        // Remove from pending
        {
            self.request_lock.lock();
            defer self.request_lock.unlock();
            _ = self.pending_requests.remove(request_id);
        }

        // Update stats
        if (result == .completed) {
            _ = self.completed_count.fetchAdd(1, .monotonic);
        }

        // Invoke callback
        self.invokeCallback(req.callback, req.user_data, result);

        // Clean up handle
        self.allocator.destroy(req.handle);
    }

    fn invokeCallback(
        self: *AsyncSleepContext,
        callback: ?AsyncCallback,
        user_data: ?*anyopaque,
        result: AsyncResult,
    ) void {
        _ = self;
        if (callback) |cb| {
            cb(user_data, result);
        }
    }
};

/// Statistics for async sleep operations
pub const AsyncSleepStats = struct {
    pending_count: usize,
    completed_count: u64,
    cancelled_count: u64,
    failed_count: u64,
};

// =============================================================================
// Convenience Functions
// =============================================================================

/// Simple async sleep that waits for completion
pub fn sleepAsyncBlocking(
    ctx: *AsyncSleepContext,
    semaphore: u64,
    value: u64,
    timeout_ns: u64,
) !AsyncResult {
    var completed = std.atomic.Value(bool).init(false);
    var result: AsyncResult = .timeout;

    const CallbackContext = struct {
        completed: *std.atomic.Value(bool),
        result: *AsyncResult,
    };

    var cb_ctx = CallbackContext{
        .completed = &completed,
        .result = &result,
    };

    const callback = struct {
        fn cb(user_data: ?*anyopaque, res: AsyncResult) void {
            if (user_data) |ptr| {
                const ctx_ptr: *CallbackContext = @ptrCast(@alignCast(ptr));
                ctx_ptr.result.* = res;
                ctx_ptr.completed.store(true, .release);
            }
        }
    }.cb;

    const handle = try ctx.sleepAsync(semaphore, value, callback, &cb_ctx);
    _ = handle;

    // Wait for completion with timeout
    const start = std.time.nanoTimestamp();
    while (!completed.load(.acquire)) {
        if (@as(u64, @intCast(std.time.nanoTimestamp() - start)) > timeout_ns) {
            return .timeout;
        }
        std.time.sleep(100_000); // 100us
    }

    return result;
}

// =============================================================================
// Tests
// =============================================================================

test "AsyncSleepContext initialization" {
    const allocator = std.testing.allocator;
    var ctx = AsyncSleepContext.init(null, null, allocator);
    defer ctx.deinit();

    const stats = ctx.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.pending_count);
    try std.testing.expectEqual(@as(u64, 0), stats.completed_count);
}

test "AsyncSleepStats" {
    const stats = AsyncSleepStats{
        .pending_count = 5,
        .completed_count = 100,
        .cancelled_count = 2,
        .failed_count = 1,
    };

    try std.testing.expectEqual(@as(usize, 5), stats.pending_count);
    try std.testing.expectEqual(@as(u64, 100), stats.completed_count);
}
