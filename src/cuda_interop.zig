//! VK_NV_cuda_kernel_launch Extension Wrapper
//!
//! Provides CUDA kernel execution from Vulkan command buffers.
//! This enables CUDA/Vulkan interoperability without separate contexts,
//! useful for AI inference, compute workloads, and frame generation.
//!
//! Key capabilities:
//! - Load PTX kernels directly into Vulkan
//! - Launch CUDA kernels from Vulkan command buffers
//! - Share memory between CUDA and Vulkan
//! - No need for CUDA/Vulkan context interop
//!
//! Requires NVIDIA driver 590+ and VK_NV_cuda_kernel_launch extension.
//!
//! Workflow:
//! 1. Create CUDA module from PTX (vkCreateCudaModuleNV)
//! 2. Create function handle (vkCreateCudaFunctionNV)
//! 3. Launch kernel in command buffer (vkCmdCudaLaunchKernelNV)
//! 4. Cleanup with vkDestroyCudaFunctionNV/vkDestroyCudaModuleNV

const std = @import("std");
const vk = @import("vulkan.zig");

// =============================================================================
// Extension Constants
// =============================================================================

pub const VK_NV_CUDA_KERNEL_LAUNCH_EXTENSION_NAME = "VK_NV_cuda_kernel_launch";
pub const VK_NV_CUDA_KERNEL_LAUNCH_SPEC_VERSION: u32 = 2;

// Structure types
pub const VK_STRUCTURE_TYPE_CUDA_MODULE_CREATE_INFO_NV: u32 = 1000307000;
pub const VK_STRUCTURE_TYPE_CUDA_FUNCTION_CREATE_INFO_NV: u32 = 1000307001;
pub const VK_STRUCTURE_TYPE_CUDA_LAUNCH_INFO_NV: u32 = 1000307002;
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_CUDA_KERNEL_LAUNCH_FEATURES_NV: u32 = 1000307003;
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_CUDA_KERNEL_LAUNCH_PROPERTIES_NV: u32 = 1000307004;

// Object types
pub const VK_OBJECT_TYPE_CUDA_MODULE_NV: u32 = 1000307000;
pub const VK_OBJECT_TYPE_CUDA_FUNCTION_NV: u32 = 1000307001;

// =============================================================================
// Vulkan Handles
// =============================================================================

pub const VkCudaModuleNV = *opaque {};
pub const VkCudaFunctionNV = *opaque {};

// =============================================================================
// Vulkan Structures
// =============================================================================

pub const VkPhysicalDeviceCudaKernelLaunchFeaturesNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_CUDA_KERNEL_LAUNCH_FEATURES_NV,
    pNext: ?*anyopaque = null,
    cudaKernelLaunchFeatures: u32 = 0,
};

pub const VkPhysicalDeviceCudaKernelLaunchPropertiesNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_CUDA_KERNEL_LAUNCH_PROPERTIES_NV,
    pNext: ?*anyopaque = null,
    computeCapabilityMinor: u32 = 0,
    computeCapabilityMajor: u32 = 0,
};

pub const VkCudaModuleCreateInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_CUDA_MODULE_CREATE_INFO_NV,
    pNext: ?*const anyopaque = null,
    dataSize: usize = 0,
    pData: ?*const anyopaque = null,
};

pub const VkCudaFunctionCreateInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_CUDA_FUNCTION_CREATE_INFO_NV,
    pNext: ?*const anyopaque = null,
    module: ?VkCudaModuleNV = null,
    pName: ?[*:0]const u8 = null,
};

pub const VkCudaLaunchInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_CUDA_LAUNCH_INFO_NV,
    pNext: ?*const anyopaque = null,
    function: ?VkCudaFunctionNV = null,
    gridDimX: u32 = 1,
    gridDimY: u32 = 1,
    gridDimZ: u32 = 1,
    blockDimX: u32 = 1,
    blockDimY: u32 = 1,
    blockDimZ: u32 = 1,
    sharedMemBytes: u32 = 0,
    paramCount: usize = 0,
    pParams: ?*const ?*const anyopaque = null,
    extraCount: usize = 0,
    pExtras: ?*const ?*const anyopaque = null,
};

// =============================================================================
// Function Types
// =============================================================================

pub const PFN_vkCreateCudaModuleNV = *const fn (
    device: vk.VkDevice,
    pCreateInfo: *const VkCudaModuleCreateInfoNV,
    pAllocator: ?*const vk.VkAllocationCallbacks,
    pModule: *VkCudaModuleNV,
) callconv(.c) i32;

pub const PFN_vkGetCudaModuleCacheNV = *const fn (
    device: vk.VkDevice,
    module: VkCudaModuleNV,
    pCacheSize: *usize,
    pCacheData: ?*anyopaque,
) callconv(.c) i32;

pub const PFN_vkCreateCudaFunctionNV = *const fn (
    device: vk.VkDevice,
    pCreateInfo: *const VkCudaFunctionCreateInfoNV,
    pAllocator: ?*const vk.VkAllocationCallbacks,
    pFunction: *VkCudaFunctionNV,
) callconv(.c) i32;

pub const PFN_vkDestroyCudaModuleNV = *const fn (
    device: vk.VkDevice,
    module: VkCudaModuleNV,
    pAllocator: ?*const vk.VkAllocationCallbacks,
) callconv(.c) void;

pub const PFN_vkDestroyCudaFunctionNV = *const fn (
    device: vk.VkDevice,
    function: VkCudaFunctionNV,
    pAllocator: ?*const vk.VkAllocationCallbacks,
) callconv(.c) void;

pub const PFN_vkCmdCudaLaunchKernelNV = *const fn (
    commandBuffer: vk.VkCommandBuffer,
    pLaunchInfo: *const VkCudaLaunchInfoNV,
) callconv(.c) void;

// =============================================================================
// High-Level Wrapper
// =============================================================================

/// CUDA compute capability
pub const ComputeCapability = struct {
    major: u32,
    minor: u32,

    pub fn fromVk(props: VkPhysicalDeviceCudaKernelLaunchPropertiesNV) ComputeCapability {
        return .{
            .major = props.computeCapabilityMajor,
            .minor = props.computeCapabilityMinor,
        };
    }

    /// Get SM version string (e.g., "sm_89" for Ada Lovelace)
    pub fn smVersion(self: ComputeCapability) struct { buf: [8]u8, len: usize } {
        var buf: [8]u8 = undefined;
        const len = std.fmt.formatIntBuf(&buf, self.major * 10 + self.minor, 10, .lower, .{});
        // Prepend "sm_"
        var result: [8]u8 = .{ 's', 'm', '_', 0, 0, 0, 0, 0 };
        @memcpy(result[3..][0..len], buf[0..len]);
        return .{ .buf = result, .len = 3 + len };
    }

    /// Check if this is Ada Lovelace or newer (SM 8.9+)
    pub fn isAdaOrNewer(self: ComputeCapability) bool {
        return self.major > 8 or (self.major == 8 and self.minor >= 9);
    }

    /// Check if this is Blackwell or newer (SM 10.0+)
    pub fn isBlackwellOrNewer(self: ComputeCapability) bool {
        return self.major >= 10;
    }
};

/// CUDA module context (holds PTX/cubin)
pub const CudaModule = struct {
    device: vk.VkDevice,
    module: VkCudaModuleNV,
    vkDestroyCudaModuleNV: ?PFN_vkDestroyCudaModuleNV,

    pub fn deinit(self: *CudaModule) void {
        if (self.vkDestroyCudaModuleNV) |destroy| {
            destroy(self.device, self.module, null);
        }
    }
};

/// CUDA function handle (kernel entry point)
pub const CudaFunction = struct {
    device: vk.VkDevice,
    function: VkCudaFunctionNV,
    name: []const u8,
    vkDestroyCudaFunctionNV: ?PFN_vkDestroyCudaFunctionNV,

    pub fn deinit(self: *CudaFunction) void {
        if (self.vkDestroyCudaFunctionNV) |destroy| {
            destroy(self.device, self.function, null);
        }
    }
};

/// Kernel launch configuration
pub const LaunchConfig = struct {
    /// Grid dimensions (number of blocks)
    grid: struct { x: u32 = 1, y: u32 = 1, z: u32 = 1 } = .{},
    /// Block dimensions (threads per block)
    block: struct { x: u32 = 1, y: u32 = 1, z: u32 = 1 } = .{},
    /// Dynamic shared memory size in bytes
    shared_mem_bytes: u32 = 0,

    /// Create config for 1D launch
    pub fn linear(total_threads: u32, threads_per_block: u32) LaunchConfig {
        const blocks = (total_threads + threads_per_block - 1) / threads_per_block;
        return .{
            .grid = .{ .x = blocks, .y = 1, .z = 1 },
            .block = .{ .x = threads_per_block, .y = 1, .z = 1 },
        };
    }

    /// Create config for 2D launch (e.g., image processing)
    pub fn grid2D(width: u32, height: u32, block_x: u32, block_y: u32) LaunchConfig {
        return .{
            .grid = .{
                .x = (width + block_x - 1) / block_x,
                .y = (height + block_y - 1) / block_y,
                .z = 1,
            },
            .block = .{ .x = block_x, .y = block_y, .z = 1 },
        };
    }

    /// Convert to Vulkan structure
    pub fn toVk(self: LaunchConfig, function: VkCudaFunctionNV) VkCudaLaunchInfoNV {
        return .{
            .function = function,
            .gridDimX = self.grid.x,
            .gridDimY = self.grid.y,
            .gridDimZ = self.grid.z,
            .blockDimX = self.block.x,
            .blockDimY = self.block.y,
            .blockDimZ = self.block.z,
            .sharedMemBytes = self.shared_mem_bytes,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "extension constants" {
    try std.testing.expectEqualStrings(
        "VK_NV_cuda_kernel_launch",
        VK_NV_CUDA_KERNEL_LAUNCH_EXTENSION_NAME,
    );
}

test "compute capability" {
    // Ada Lovelace (RTX 40 series)
    const ada = ComputeCapability{ .major = 8, .minor = 9 };
    try std.testing.expect(ada.isAdaOrNewer());
    try std.testing.expect(!ada.isBlackwellOrNewer());

    // Blackwell (RTX 50 series)
    const blackwell = ComputeCapability{ .major = 10, .minor = 0 };
    try std.testing.expect(blackwell.isAdaOrNewer());
    try std.testing.expect(blackwell.isBlackwellOrNewer());
}

test "launch config linear" {
    const config = LaunchConfig.linear(1000, 256);
    try std.testing.expectEqual(@as(u32, 4), config.grid.x); // ceil(1000/256) = 4
    try std.testing.expectEqual(@as(u32, 256), config.block.x);
}

test "launch config 2D" {
    const config = LaunchConfig.grid2D(1920, 1080, 16, 16);
    try std.testing.expectEqual(@as(u32, 120), config.grid.x); // ceil(1920/16)
    try std.testing.expectEqual(@as(u32, 68), config.grid.y); // ceil(1080/16)
}
