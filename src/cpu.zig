//! CPU Monitoring Module
//!
//! Uses Windows PDH for CPU usage and AMD RyzenMaster SDK for temperature.
//! The RyzenMaster SDK is loaded dynamically and uses C++ vtable calls.

const std = @import("std");
const log = @import("log.zig");

// Zig 0.15+ calling convention for Windows x86_64
const WINAPI: std.builtin.CallingConvention = .{ .x86_64_win = .{} };

// Windows type definitions
const HANDLE = ?*anyopaque;
const HMODULE = ?*anyopaque;
const LONG = i32;
const DWORD = u32;
const LPCWSTR = [*:0]const u16;
const LPCSTR = [*:0]const u8;
const FARPROC = ?*anyopaque;

// Kernel32 functions
extern "kernel32" fn LoadLibraryA(lpLibFileName: LPCSTR) callconv(WINAPI) HMODULE;
extern "kernel32" fn GetProcAddress(hModule: HMODULE, lpProcName: LPCSTR) callconv(WINAPI) FARPROC;
extern "kernel32" fn FreeLibrary(hLibModule: HMODULE) callconv(WINAPI) i32;
extern "kernel32" fn SetDllDirectoryA(lpPathName: ?LPCSTR) callconv(WINAPI) i32;

// PDH types and functions
const PDH_HQUERY = HANDLE;
const PDH_HCOUNTER = HANDLE;
const PDH_STATUS = LONG;

const ERROR_SUCCESS: LONG = 0;
const PDH_FMT_DOUBLE: DWORD = 0x00000200;

const PDH_FMT_COUNTERVALUE = extern struct {
    CStatus: DWORD,
    padding: DWORD = 0,
    doubleValue: f64,
};

extern "pdh" fn PdhOpenQueryW(szDataSource: ?LPCWSTR, dwUserData: usize, phQuery: *PDH_HQUERY) callconv(WINAPI) PDH_STATUS;
extern "pdh" fn PdhAddCounterW(hQuery: PDH_HQUERY, szFullCounterPath: LPCWSTR, dwUserData: usize, phCounter: *PDH_HCOUNTER) callconv(WINAPI) PDH_STATUS;
extern "pdh" fn PdhCollectQueryData(hQuery: PDH_HQUERY) callconv(WINAPI) PDH_STATUS;
extern "pdh" fn PdhGetFormattedCounterValue(hCounter: PDH_HCOUNTER, dwFormat: DWORD, lpdwType: ?*DWORD, pValue: *PDH_FMT_COUNTERVALUE) callconv(WINAPI) PDH_STATUS;
extern "pdh" fn PdhCloseQuery(hQuery: PDH_HQUERY) callconv(WINAPI) PDH_STATUS;

// ============================================================================
// AMD RyzenMaster SDK - C++ Vtable Definitions
// ============================================================================

// Device type enum (from DeviceType.h)
const AOD_DEVICE_TYPE = enum(i32) {
    dtInvalid = -1,
    dtCPU = 0,
    dtBIOS = 1,
};

// CPUParameters structure (from IDevice.h)
// This must match the C++ struct layout EXACTLY
const EffectiveFreqData = extern struct {
    uLength: c_uint,
    dFreq: ?*f64,
    dState: ?*f64,
    dCurrentFreq: ?*f64,
    dCurrentTemp: ?*f64,
};

const OCMode = extern struct {
    uOCMode: c_uint,
};

const CPUParameters = extern struct {
    eMode: OCMode,
    stFreqData: EffectiveFreqData,
    dPeakCoreVoltage: f64,
    dPeakCoreVoltage_1: f64,
    dSocVoltage: f64,
    dTemperature: f64, // <-- This is what we want!
    dAvgCoreVoltage: f64,
    dAvgCoreVoltage_1: f64,
    dPeakSpeed: f64,
    fPPTLimit: f32,
    fPPTValue: f32,
    fTDCLimit_VDD: f32,
    fTDCValue_VDD: f32,
    fTDCValue_VDD_1: f32,
    fEDCLimit_VDD: f32,
    fEDCValue_VDD: f32,
    fEDCValue_VDD_1: f32,
    fcHTCLimit: f32,
    fFCLKP0Freq: f32,
    fCCLK_Fmax: f32,
    fTDCLimit_SOC: f32,
    fTDCValue_SOC: f32,
    fEDCLimit_SOC: f32,
    fEDCValue_SOC: f32,
    fVDDCR_VDD_Power: f32,
    fVDDCR_SOC_Power: f32,
    fTDCLimit_CCD: f32,
    fTDCValue_CCD: f32,
    fEDCLimit_CCD: f32,
    fEDCValue_CCD: f32,
};

// IPlatform vtable structure
// Order MUST match the C++ class declaration exactly!
const IPlatformVTable = extern struct {
    // slot 0: Init(const char* vendor, bool bUseCPUOnly)
    init: *const fn (*IPlatform, ?[*:0]const u8, bool) callconv(WINAPI) bool,
    // slot 1: UnInit()
    uninit: *const fn (*IPlatform) callconv(WINAPI) bool,
    // slot 2: GetIDeviceManager() - returns reference (pointer)
    getDeviceManager: *const fn (*IPlatform) callconv(WINAPI) *IDeviceManager,
};

const IPlatform = extern struct {
    vtable: *const IPlatformVTable,
};

// IDeviceManager vtable structure
// Note: MSVC may add a hidden destructor slot even if not declared in header
const IDeviceManagerVTable = extern struct {
    // slot 0: hidden destructor (MSVC may add this for polymorphic classes)
    destructor: ?*const fn (*IDeviceManager) callconv(WINAPI) void,
    // slot 1: Init
    init: *const fn (*IDeviceManager, ?[*:0]const u8, bool) callconv(WINAPI) bool,
    // slot 2: UnInit
    uninit: *const fn (*IDeviceManager) callconv(WINAPI) bool,
    // slot 3: GetDevice(AOD_DEVICE_TYPE, uIndex)
    getDeviceByType: *const fn (*IDeviceManager, AOD_DEVICE_TYPE, c_ulong) callconv(WINAPI) ?*IDevice,
    // slot 4: GetDevice(uIndex)
    getDeviceByIndex: *const fn (*IDeviceManager, c_ulong) callconv(WINAPI) ?*IDevice,
    // slot 5: GetDeviceCount(AOD_DEVICE_TYPE)
    getDeviceCountByType: *const fn (*IDeviceManager, AOD_DEVICE_TYPE) callconv(WINAPI) c_ulong,
    // slot 6: GetDeviceCount(const wchar_t*)
    getDeviceCountByName: *const fn (*IDeviceManager, ?[*:0]const u16) callconv(WINAPI) c_ulong,
    // slot 7: GetTotalDeviceCount()
    getTotalDeviceCount: *const fn (*IDeviceManager) callconv(WINAPI) c_ulong,
};

const IDeviceManager = extern struct {
    vtable: *const IDeviceManagerVTable,
};

// IDevice/ICPUEx vtable structure
// IDevice has: Init, UnInit, GetName, GetDescription, GetVendor, GetRole, GetClassName, GetType, GetIndex, ~destructor
// ICPUEx adds: GetL1DataCache, GetL1InstructionCache, GetL2Cache, GetL3Cache, GetCoreCount, GetCorePark, GetPackage, GetCPUParameters, GetChipsetName, GetFamily, GetStepping, GetModel
const ICPUExVTable = extern struct {
    // IDevice methods (slots 0-9)
    init: *const fn (*IDevice, c_ulong) callconv(WINAPI) bool,
    uninit: *const fn (*IDevice) callconv(WINAPI) bool,
    getName: *const fn (*IDevice) callconv(WINAPI) ?[*:0]const u16,
    getDescription: *const fn (*IDevice) callconv(WINAPI) ?[*:0]const u16,
    getVendor: *const fn (*IDevice) callconv(WINAPI) ?[*:0]const u16,
    getRole: *const fn (*IDevice) callconv(WINAPI) ?[*:0]const u16,
    getClassName: *const fn (*IDevice) callconv(WINAPI) ?[*:0]const u16,
    getType: *const fn (*IDevice) callconv(WINAPI) AOD_DEVICE_TYPE,
    getIndex: *const fn (*IDevice) callconv(WINAPI) c_ulong,
    destructor: *const fn (*IDevice) callconv(WINAPI) void, // virtual ~IDevice()

    // ICPUEx additional methods (slots 10-21)
    getL1DataCache: *const fn (*IDevice, *anyopaque) callconv(WINAPI) c_int,
    getL1InstructionCache: *const fn (*IDevice, *anyopaque) callconv(WINAPI) c_int,
    getL2Cache: *const fn (*IDevice, *anyopaque) callconv(WINAPI) c_int,
    getL3Cache: *const fn (*IDevice, *anyopaque) callconv(WINAPI) c_int,
    getCoreCount: *const fn (*IDevice, *c_uint) callconv(WINAPI) c_int,
    getCorePark: *const fn (*IDevice, *c_uint) callconv(WINAPI) c_int,
    getPackage: *const fn (*IDevice) callconv(WINAPI) ?[*:0]const u16,
    getCPUParameters: *const fn (*IDevice, *CPUParameters) callconv(WINAPI) c_int, // <-- slot 17!
    getChipsetName: *const fn (*IDevice, ?[*:0]u16) callconv(WINAPI) c_int,
    getFamily: *const fn (*IDevice, *c_ulong) callconv(WINAPI) c_int,
    getStepping: *const fn (*IDevice, *c_ulong) callconv(WINAPI) c_int,
    getModel: *const fn (*IDevice, *c_ulong) callconv(WINAPI) c_int,
};

const IDevice = extern struct {
    vtable: *const ICPUExVTable,
};

// Function pointer type for GetPlatform()
const GetPlatformFn = *const fn () callconv(WINAPI) *IPlatform;

// ============================================================================
// Module State
// ============================================================================

var pdh_initialized: bool = false;
var cpu_query: PDH_HQUERY = null;
var cpu_total: PDH_HCOUNTER = null;

var ryzen_initialized: bool = false;
var platform_dll: HMODULE = null;
var platform: ?*IPlatform = null;
var cpu_device: ?*IDevice = null;

const counter_path = toUtf16("\\Processor(_Total)\\% Processor Time");

// ============================================================================
// Public API
// ============================================================================

pub const CpuStats = struct {
    usage: f64,
    temp: u32,
};

pub fn init() !void {
    // Initialize PDH for CPU usage
    initPdh() catch |err| {
        log.logFmt("PDH init failed: {}", .{err});
    };

    // Initialize RyzenMaster SDK for CPU temperature
    initRyzenMaster() catch |err| {
        log.logFmt("RyzenMaster init failed (AMD CPU temp unavailable): {}", .{err});
    };
}

pub fn getUsageAndTemp() CpuStats {
    var stats = CpuStats{ .usage = 0, .temp = 0 };

    // Get CPU usage from PDH
    if (pdh_initialized) {
        const collect_result = PdhCollectQueryData(cpu_query);
        if (collect_result == ERROR_SUCCESS) {
            var counter_val: PDH_FMT_COUNTERVALUE = undefined;
            const format_result = PdhGetFormattedCounterValue(cpu_total, PDH_FMT_DOUBLE, null, &counter_val);
            if (format_result == ERROR_SUCCESS) {
                stats.usage = counter_val.doubleValue;
            }
        }
    }

    // Get CPU temperature from RyzenMaster
    if (ryzen_initialized and cpu_device != null) {
        var params: CPUParameters = std.mem.zeroes(CPUParameters);
        const result = cpu_device.?.vtable.getCPUParameters(cpu_device.?, &params);
        if (result == 0) { // 0 = success
            const temp_f64 = params.dTemperature;
            if (temp_f64 > 0 and temp_f64 < 200) { // Sanity check
                stats.temp = @intFromFloat(temp_f64);
            }
        } else {
            // Log only once to avoid spam
            log.logFmt("GetCPUParameters failed: {d}", .{result});
        }
    }

    return stats;
}

pub fn shutdown() void {
    // Shutdown RyzenMaster
    if (platform != null) {
        _ = platform.?.vtable.uninit(platform.?);
    }
    if (platform_dll != null) {
        _ = FreeLibrary(platform_dll);
        platform_dll = null;
    }
    ryzen_initialized = false;
    cpu_device = null;
    platform = null;

    // Shutdown PDH
    if (pdh_initialized) {
        _ = PdhCloseQuery(cpu_query);
        pdh_initialized = false;
    }
}

// ============================================================================
// Private Implementation
// ============================================================================

fn initPdh() !void {
    const open_result = PdhOpenQueryW(null, 0, &cpu_query);
    if (open_result != ERROR_SUCCESS) {
        return error.PdhOpenQueryFailed;
    }

    const add_result = PdhAddCounterW(cpu_query, counter_path, 0, &cpu_total);
    if (add_result != ERROR_SUCCESS) {
        return error.PdhAddCounterFailed;
    }

    const collect_result = PdhCollectQueryData(cpu_query);
    if (collect_result != ERROR_SUCCESS) {
        return error.PdhCollectFailed;
    }

    log.log("PDH initialized successfully");
    pdh_initialized = true;
}

fn initRyzenMaster() !void {
    log.log("RyzenMaster: Setting DLL directory...");

    // Set DLL search path to RyzenMaster SDK bin directory
    // This is needed because Platform.dll depends on Device.dll and Qt DLLs
    _ = SetDllDirectoryA("C:\\Program Files\\AMD\\RyzenMasterMonitoringSDK\\bin");

    log.log("RyzenMaster: Loading Platform.dll...");

    // Load Platform.dll
    platform_dll = LoadLibraryA("Platform.dll");
    if (platform_dll == null) {
        log.log("Failed to load Platform.dll - RyzenMaster SDK not installed?");
        return error.PlatformDllLoadFailed;
    }

    log.log("RyzenMaster: Getting GetPlatform function...");

    // Get the GetPlatform function
    const get_platform_ptr = GetProcAddress(platform_dll, "GetPlatform");
    if (get_platform_ptr == null) {
        log.log("Failed to get GetPlatform function");
        _ = FreeLibrary(platform_dll);
        platform_dll = null;
        return error.GetPlatformFailed;
    }

    log.log("RyzenMaster: Calling GetPlatform()...");

    const getPlatform: GetPlatformFn = @ptrCast(get_platform_ptr);

    // Call GetPlatform() to get the IPlatform reference
    platform = getPlatform();
    if (platform == null) {
        log.log("GetPlatform returned null");
        _ = FreeLibrary(platform_dll);
        platform_dll = null;
        return error.PlatformNull;
    }

    log.log("RyzenMaster: Got platform pointer, checking vtable...");
    log.logFmt("RyzenMaster: platform ptr = {*}", .{platform.?});

    // Check if vtable looks valid
    const vtable_ptr = platform.?.vtable;
    log.logFmt("RyzenMaster: vtable ptr = {*}", .{vtable_ptr});

    log.log("RyzenMaster: Calling IPlatform::Init...");

    // Initialize the platform (CPU only mode)
    const init_result = platform.?.vtable.init(platform.?, null, true);
    if (!init_result) {
        log.log("IPlatform::Init failed");
        _ = FreeLibrary(platform_dll);
        platform_dll = null;
        platform = null;
        return error.PlatformInitFailed;
    }

    log.log("RyzenMaster: Init succeeded! Getting device manager...");

    // Get the device manager
    const dev_manager = platform.?.vtable.getDeviceManager(platform.?);
    log.logFmt("RyzenMaster: dev_manager ptr = {*}", .{dev_manager});

    log.log("RyzenMaster: Getting CPU device count...");

    // Get the CPU device count
    const cpu_count = dev_manager.vtable.getDeviceCountByType(dev_manager, .dtCPU);
    log.logFmt("RyzenMaster: CPU count = {d}", .{cpu_count});

    if (cpu_count == 0) {
        log.log("No CPU devices found");
        _ = platform.?.vtable.uninit(platform.?);
        _ = FreeLibrary(platform_dll);
        platform_dll = null;
        platform = null;
        return error.NoCpuDevice;
    }

    log.log("RyzenMaster: Getting CPU device...");

    // Get the first CPU device
    cpu_device = dev_manager.vtable.getDeviceByType(dev_manager, .dtCPU, 0);
    if (cpu_device == null) {
        log.log("Failed to get CPU device");
        _ = platform.?.vtable.uninit(platform.?);
        _ = FreeLibrary(platform_dll);
        platform_dll = null;
        platform = null;
        return error.CpuDeviceNull;
    }

    log.logFmt("RyzenMaster: cpu_device ptr = {*}", .{cpu_device.?});

    ryzen_initialized = true;
    log.log("RyzenMaster SDK initialized successfully - AMD CPU temp available!");
}

fn toUtf16(comptime s: []const u8) *const [s.len:0]u16 {
    const result = comptime blk: {
        var arr: [s.len:0]u16 = undefined;
        for (s, 0..) |c, i| {
            arr[i] = c;
        }
        break :blk arr;
    };
    return &result;
}
