/*
 * nvvk - NVIDIA Vulkan Extensions Library
 *
 * CUDA Interop API (VK_NV_cuda_kernel_launch)
 *
 * Provides CUDA kernel execution from Vulkan command buffers.
 * Enables CUDA/Vulkan interoperability without separate contexts.
 *
 * Key capabilities:
 * - Load PTX kernels directly into Vulkan
 * - Launch CUDA kernels from Vulkan command buffers
 * - Share memory between CUDA and Vulkan
 * - No need for CUDA/Vulkan context interop
 *
 * Requires:
 * - NVIDIA driver 590+
 * - VK_NV_cuda_kernel_launch extension
 */

#ifndef NVVK_CUDA_H
#define NVVK_CUDA_H

#ifdef __cplusplus
extern "C" {
#endif

#include "nvvk.h"

/* Extension name */
#define NVVK_CUDA_KERNEL_LAUNCH_EXTENSION_NAME "VK_NV_cuda_kernel_launch"

/* CUDA compute capability */
typedef struct NvvkComputeCapability {
    uint32_t major;    /* e.g., 8 for Ada, 10 for Blackwell */
    uint32_t minor;    /* e.g., 9 for Ada (sm_89) */
} NvvkComputeCapability;

/* Kernel launch configuration */
typedef struct NvvkCudaLaunchConfig {
    /* Grid dimensions (number of blocks) */
    uint32_t grid_x;
    uint32_t grid_y;
    uint32_t grid_z;
    /* Block dimensions (threads per block) */
    uint32_t block_x;
    uint32_t block_y;
    uint32_t block_z;
    /* Dynamic shared memory size in bytes */
    uint32_t shared_mem_bytes;
} NvvkCudaLaunchConfig;

/* Opaque CUDA module handle */
typedef struct NvvkCudaModule* nvvk_cuda_module_t;

/* Opaque CUDA function handle */
typedef struct NvvkCudaFunction* nvvk_cuda_function_t;

/*
 * Check if CUDA kernel launch is supported on the device.
 *
 * Parameters:
 *   physical_device - VkPhysicalDevice handle
 *
 * Returns:
 *   true if VK_NV_cuda_kernel_launch is available
 */
bool nvvk_cuda_is_supported(NvvkDevice physical_device);

/*
 * Query CUDA compute capability for a physical device.
 *
 * Parameters:
 *   physical_device - VkPhysicalDevice handle
 *   capability - Output compute capability
 *
 * Returns:
 *   NVVK_SUCCESS on success
 */
NvvkResult nvvk_cuda_get_compute_capability(
    NvvkDevice physical_device,
    NvvkComputeCapability* capability
);

/*
 * Check if GPU is Ada Lovelace (RTX 40) or newer.
 */
bool nvvk_cuda_is_ada_or_newer(const NvvkComputeCapability* cap);

/*
 * Check if GPU is Blackwell (RTX 50) or newer.
 */
bool nvvk_cuda_is_blackwell_or_newer(const NvvkComputeCapability* cap);

/*
 * Create CUDA module from PTX code.
 *
 * Parameters:
 *   device - VkDevice handle
 *   ptx_data - PTX source code or cubin binary
 *   ptx_size - Size in bytes
 *   get_device_proc_addr - vkGetDeviceProcAddr function
 *
 * Returns:
 *   Module handle on success, NULL on failure
 */
nvvk_cuda_module_t nvvk_cuda_module_create(
    NvvkDevice device,
    const void* ptx_data,
    size_t ptx_size,
    PFN_nvvkGetDeviceProcAddr get_device_proc_addr
);

/*
 * Destroy CUDA module.
 */
void nvvk_cuda_module_destroy(nvvk_cuda_module_t module);

/*
 * Create CUDA function (kernel entry point) from module.
 *
 * Parameters:
 *   device - VkDevice handle
 *   module - CUDA module containing the kernel
 *   function_name - Entry point name (e.g., "kernel_main")
 *   get_device_proc_addr - vkGetDeviceProcAddr function
 *
 * Returns:
 *   Function handle on success, NULL on failure
 */
nvvk_cuda_function_t nvvk_cuda_function_create(
    NvvkDevice device,
    nvvk_cuda_module_t module,
    const char* function_name,
    PFN_nvvkGetDeviceProcAddr get_device_proc_addr
);

/*
 * Destroy CUDA function.
 */
void nvvk_cuda_function_destroy(nvvk_cuda_function_t function);

/*
 * Launch CUDA kernel in command buffer.
 *
 * Parameters:
 *   cmd - VkCommandBuffer to record into
 *   function - CUDA function to launch
 *   config - Launch configuration (grid/block dimensions)
 *   params - Kernel parameters (device pointers, scalars)
 *   param_count - Number of parameters
 *
 * Returns:
 *   NVVK_SUCCESS on success
 */
NvvkResult nvvk_cuda_launch_kernel(
    NvvkCommandBuffer cmd,
    nvvk_cuda_function_t function,
    const NvvkCudaLaunchConfig* config,
    const void* const* params,
    size_t param_count
);

/*
 * Create linear launch config (1D grid).
 *
 * Parameters:
 *   total_threads - Total number of threads needed
 *   threads_per_block - Threads per block (typically 256 or 512)
 *   config - Output launch config
 */
void nvvk_cuda_config_linear(
    uint32_t total_threads,
    uint32_t threads_per_block,
    NvvkCudaLaunchConfig* config
);

/*
 * Create 2D launch config (for image processing).
 *
 * Parameters:
 *   width - Image width
 *   height - Image height
 *   block_x - Block width (typically 16 or 32)
 *   block_y - Block height (typically 16 or 32)
 *   config - Output launch config
 */
void nvvk_cuda_config_2d(
    uint32_t width,
    uint32_t height,
    uint32_t block_x,
    uint32_t block_y,
    NvvkCudaLaunchConfig* config
);

/*
 * Get extension name.
 */
const char* nvvk_cuda_get_extension_name(void);

/*
 * Example usage with a denoising kernel:
 *
 *   // Load PTX kernel
 *   nvvk_cuda_module_t module = nvvk_cuda_module_create(
 *       device, denoise_ptx, denoise_ptx_size, vkGetDeviceProcAddr);
 *
 *   nvvk_cuda_function_t kernel = nvvk_cuda_function_create(
 *       device, module, "denoise_kernel", vkGetDeviceProcAddr);
 *
 *   // Configure launch for 1920x1080 image
 *   NvvkCudaLaunchConfig config;
 *   nvvk_cuda_config_2d(1920, 1080, 16, 16, &config);
 *
 *   // Launch kernel
 *   void* params[] = { &input_ptr, &output_ptr, &width, &height };
 *   nvvk_cuda_launch_kernel(cmd, kernel, &config, params, 4);
 *
 *   // Cleanup
 *   nvvk_cuda_function_destroy(kernel);
 *   nvvk_cuda_module_destroy(module);
 */

#ifdef __cplusplus
}
#endif

#endif /* NVVK_CUDA_H */
