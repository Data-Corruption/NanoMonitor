//! GPU Monitoring Module
//!
//! Uses NVIDIA's NVAPI to query GPU usage and temperature.
//! Loads NVAPI dynamically at runtime to avoid MSVC runtime dependency.

const std = @import("std");
const log = @import("log.zig");

// Zig 0.15+ calling convention for Windows x86_64
const WINAPI: std.builtin.CallingConvention = .{ .x86_64_win = .{} };

// Windows types for dynamic loading
const HMODULE = ?*anyopaque;
const FARPROC = ?*anyopaque;
const LPCSTR = [*:0]const u8;

// Kernel32 functions for dynamic loading
extern "kernel32" fn LoadLibraryA(lpLibFileName: LPCSTR) callconv(WINAPI) HMODULE;
extern "kernel32" fn GetProcAddress(hModule: HMODULE, lpProcName: LPCSTR) callconv(WINAPI) FARPROC;
extern "kernel32" fn FreeLibrary(hLibModule: HMODULE) callconv(WINAPI) i32;

// NVAPI types
const NvAPI_Status = i32;
const NvPhysicalGpuHandle = ?*anyopaque;
const NvU32 = u32;
const NvS32 = i32;

const NVAPI_OK: NvAPI_Status = 0;
const NVAPI_MAX_PHYSICAL_GPUS = 64;
const NVAPI_THERMAL_TARGET_ALL = 15;

// P-States info structure
const NV_GPU_DYNAMIC_PSTATES_INFO_EX = extern struct {
    version: NvU32,
    flags: NvU32,
    utilization: [8]extern struct {
        bIsPresent: NvU32,
        percentage: NvU32,
    },
};

const NV_GPU_DYNAMIC_PSTATES_INFO_EX_VER: NvU32 = @sizeOf(NV_GPU_DYNAMIC_PSTATES_INFO_EX) | (1 << 16);

// Thermal settings structure
const NV_GPU_THERMAL_SETTINGS = extern struct {
    version: NvU32,
    count: NvU32,
    sensor: [3]extern struct {
        controller: NvS32,
        defaultMinTemp: NvS32,
        defaultMaxTemp: NvS32,
        currentTemp: NvS32,
        target: NvS32,
    },
};

const NV_GPU_THERMAL_SETTINGS_VER: NvU32 = @sizeOf(NV_GPU_THERMAL_SETTINGS) | (2 << 16);

// Function pointer types for dynamic loading
const NvAPI_Initialize_t = *const fn () callconv(WINAPI) NvAPI_Status;
const NvAPI_Unload_t = *const fn () callconv(WINAPI) NvAPI_Status;
const NvAPI_EnumPhysicalGPUs_t = *const fn (*[NVAPI_MAX_PHYSICAL_GPUS]NvPhysicalGpuHandle, *NvU32) callconv(WINAPI) NvAPI_Status;
const NvAPI_GPU_GetDynamicPstatesInfoEx_t = *const fn (NvPhysicalGpuHandle, *NV_GPU_DYNAMIC_PSTATES_INFO_EX) callconv(WINAPI) NvAPI_Status;
const NvAPI_GPU_GetThermalSettings_t = *const fn (NvPhysicalGpuHandle, NvU32, *NV_GPU_THERMAL_SETTINGS) callconv(WINAPI) NvAPI_Status;

// NVAPI uses a query interface pattern - we need to use NvAPI_QueryInterface
const NvAPI_QueryInterface_t = *const fn (u32) callconv(WINAPI) ?*anyopaque;

// Function IDs for NvAPI_QueryInterface (these are documented/known values)
const NVAPI_INITIALIZE_ID: u32 = 0x0150E828;
const NVAPI_UNLOAD_ID: u32 = 0xD22BDD7E;
const NVAPI_ENUMPHYSICALGPUS_ID: u32 = 0xE5AC921F;
const NVAPI_GPU_GETDYNAMICPSTATESINFOEX_ID: u32 = 0x60DED2ED;
const NVAPI_GPU_GETTHERMALSETTINGS_ID: u32 = 0xE3640A56;

// Module state
var nvapi_initialized: bool = false;
var physical_gpu: NvPhysicalGpuHandle = null;
var nvapi_dll: HMODULE = null;

// Function pointers (loaded dynamically)
var pfn_NvAPI_Initialize: ?NvAPI_Initialize_t = null;
var pfn_NvAPI_Unload: ?NvAPI_Unload_t = null;
var pfn_NvAPI_EnumPhysicalGPUs: ?NvAPI_EnumPhysicalGPUs_t = null;
var pfn_NvAPI_GPU_GetDynamicPstatesInfoEx: ?NvAPI_GPU_GetDynamicPstatesInfoEx_t = null;
var pfn_NvAPI_GPU_GetThermalSettings: ?NvAPI_GPU_GetThermalSettings_t = null;

/// GPU statistics returned by getUsageAndTemp
pub const GpuStats = struct {
    usage: u32,
    temp: u32,
};

/// Initialize NVAPI by loading the DLL dynamically.
pub fn init() !void {
    // Load nvapi64.dll from system
    nvapi_dll = LoadLibraryA("nvapi64.dll");
    if (nvapi_dll == null) {
        log.log("Failed to load nvapi64.dll - NVIDIA GPU not available");
        return error.NvapiLoadFailed;
    }

    // Get the query interface function
    const query_interface_ptr = GetProcAddress(nvapi_dll, "nvapi_QueryInterface");
    if (query_interface_ptr == null) {
        log.log("Failed to get nvapi_QueryInterface");
        _ = FreeLibrary(nvapi_dll);
        nvapi_dll = null;
        return error.NvapiQueryInterfaceFailed;
    }

    const queryInterface: NvAPI_QueryInterface_t = @ptrCast(query_interface_ptr);

    // Load all required functions via QueryInterface
    pfn_NvAPI_Initialize = @ptrCast(queryInterface(NVAPI_INITIALIZE_ID));
    pfn_NvAPI_Unload = @ptrCast(queryInterface(NVAPI_UNLOAD_ID));
    pfn_NvAPI_EnumPhysicalGPUs = @ptrCast(queryInterface(NVAPI_ENUMPHYSICALGPUS_ID));
    pfn_NvAPI_GPU_GetDynamicPstatesInfoEx = @ptrCast(queryInterface(NVAPI_GPU_GETDYNAMICPSTATESINFOEX_ID));
    pfn_NvAPI_GPU_GetThermalSettings = @ptrCast(queryInterface(NVAPI_GPU_GETTHERMALSETTINGS_ID));

    if (pfn_NvAPI_Initialize == null or pfn_NvAPI_EnumPhysicalGPUs == null) {
        log.log("Failed to get required NVAPI functions");
        _ = FreeLibrary(nvapi_dll);
        nvapi_dll = null;
        return error.NvapiFunctionsFailed;
    }

    // Initialize NVAPI
    const init_status = pfn_NvAPI_Initialize.?();
    if (init_status != NVAPI_OK) {
        log.logFmt("NVAPI_Initialize failed: {d}", .{init_status});
        _ = FreeLibrary(nvapi_dll);
        nvapi_dll = null;
        return error.NvapiInitFailed;
    }

    // Enumerate physical GPUs
    var gpu_handles: [NVAPI_MAX_PHYSICAL_GPUS]NvPhysicalGpuHandle = undefined;
    var gpu_count: NvU32 = 0;

    const enum_status = pfn_NvAPI_EnumPhysicalGPUs.?(&gpu_handles, &gpu_count);
    if (enum_status != NVAPI_OK or gpu_count == 0) {
        log.logFmt("Failed to enumerate GPUs: {d}", .{enum_status});
        if (pfn_NvAPI_Unload) |unload| _ = unload();
        _ = FreeLibrary(nvapi_dll);
        nvapi_dll = null;
        return error.NvapiEnumFailed;
    }

    physical_gpu = gpu_handles[0];
    nvapi_initialized = true;
    log.log("NVAPI initialized successfully (dynamic loading)");
}

/// Get GPU usage and temperature.
pub fn getUsageAndTemp() GpuStats {
    var stats = GpuStats{ .usage = 0, .temp = 0 };

    if (!nvapi_initialized) {
        return stats;
    }

    // Get usage percentage
    if (pfn_NvAPI_GPU_GetDynamicPstatesInfoEx) |getDynamicPstates| {
        var pstates_info: NV_GPU_DYNAMIC_PSTATES_INFO_EX = undefined;
        pstates_info.version = NV_GPU_DYNAMIC_PSTATES_INFO_EX_VER;

        const usage_status = getDynamicPstates(physical_gpu, &pstates_info);
        if (usage_status == NVAPI_OK) {
            stats.usage = pstates_info.utilization[0].percentage;
        }
    }

    // Get temperature
    if (pfn_NvAPI_GPU_GetThermalSettings) |getThermalSettings| {
        var thermal_settings: NV_GPU_THERMAL_SETTINGS = undefined;
        thermal_settings.version = NV_GPU_THERMAL_SETTINGS_VER;

        const temp_status = getThermalSettings(physical_gpu, NVAPI_THERMAL_TARGET_ALL, &thermal_settings);
        if (temp_status == NVAPI_OK) {
            const temp_signed = thermal_settings.sensor[0].currentTemp;
            stats.temp = if (temp_signed >= 0) @intCast(temp_signed) else 0;
        }
    }

    return stats;
}

/// Shutdown NVAPI.
pub fn shutdown() void {
    if (nvapi_initialized) {
        if (pfn_NvAPI_Unload) |unload| {
            _ = unload();
        }
        nvapi_initialized = false;
    }
    if (nvapi_dll != null) {
        _ = FreeLibrary(nvapi_dll);
        nvapi_dll = null;
    }
}
