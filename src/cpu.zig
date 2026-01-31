//! CPU Monitoring Module
//!
//! Uses the Windows Performance Data Helper (PDH) API to query CPU usage.
//! Uses manual bindings for PDH functions.

const std = @import("std");
const log = @import("log.zig");

// Zig 0.15+ calling convention for Windows x86_64
const WINAPI: std.builtin.CallingConvention = .{ .x86_64_win = .{} };

// Windows type definitions
const HANDLE = ?*anyopaque;
const LONG = i32;
const DWORD = u32;
const LPCWSTR = [*:0]const u16;

// PDH types
const PDH_HQUERY = HANDLE;
const PDH_HCOUNTER = HANDLE;
const PDH_STATUS = LONG;

const ERROR_SUCCESS: LONG = 0;
const PDH_FMT_DOUBLE: DWORD = 0x00000200;

// PDH counter value structure
const PDH_FMT_COUNTERVALUE = extern struct {
    CStatus: DWORD,
    padding: DWORD = 0,
    doubleValue: f64,
};

// PDH function declarations - link against pdh.lib
extern "pdh" fn PdhOpenQueryW(
    szDataSource: ?LPCWSTR,
    dwUserData: usize,
    phQuery: *PDH_HQUERY,
) callconv(WINAPI) PDH_STATUS;

extern "pdh" fn PdhAddCounterW(
    hQuery: PDH_HQUERY,
    szFullCounterPath: LPCWSTR,
    dwUserData: usize,
    phCounter: *PDH_HCOUNTER,
) callconv(WINAPI) PDH_STATUS;

extern "pdh" fn PdhCollectQueryData(hQuery: PDH_HQUERY) callconv(WINAPI) PDH_STATUS;

extern "pdh" fn PdhGetFormattedCounterValue(
    hCounter: PDH_HCOUNTER,
    dwFormat: DWORD,
    lpdwType: ?*DWORD,
    pValue: *PDH_FMT_COUNTERVALUE,
) callconv(WINAPI) PDH_STATUS;

extern "pdh" fn PdhCloseQuery(hQuery: PDH_HQUERY) callconv(WINAPI) PDH_STATUS;

// Module-level state
var pdh_initialized: bool = false;
var cpu_query: PDH_HQUERY = null;
var cpu_total: PDH_HCOUNTER = null;

// Counter path as UTF-16 (computed at compile time)
const counter_path = toUtf16("\\Processor(_Total)\\% Processor Time");

/// Initialize the PDH subsystem for CPU monitoring.
pub fn init() !void {
    const open_result = PdhOpenQueryW(null, 0, &cpu_query);
    if (open_result != ERROR_SUCCESS) {
        log.logFmt("PDH failed to open query: {d}", .{open_result});
        return error.PdhOpenQueryFailed;
    }

    const add_result = PdhAddCounterW(cpu_query, counter_path, 0, &cpu_total);
    if (add_result != ERROR_SUCCESS) {
        log.logFmt("PDH failed to add counter: {d}", .{add_result});
        return error.PdhAddCounterFailed;
    }

    // Initial data collection (PDH needs one collection before values are valid)
    const collect_result = PdhCollectQueryData(cpu_query);
    if (collect_result != ERROR_SUCCESS) {
        log.logFmt("PDH failed to collect query data: {d}", .{collect_result});
        return error.PdhCollectFailed;
    }

    log.log("PDH initialized successfully");
    pdh_initialized = true;
}

/// CPU statistics
pub const CpuStats = struct {
    usage: f64,
    temp: u32,
};

/// Get current CPU usage and temperature.
pub fn getUsageAndTemp() CpuStats {
    var stats = CpuStats{ .usage = 0, .temp = 0 };

    if (!pdh_initialized) {
        return stats;
    }

    // Collect fresh data
    const collect_result = PdhCollectQueryData(cpu_query);
    if (collect_result != ERROR_SUCCESS) {
        log.logFmt("PDH failed to collect query data: {d}", .{collect_result});
        return stats;
    }

    // Get the formatted value
    var counter_val: PDH_FMT_COUNTERVALUE = undefined;
    const format_result = PdhGetFormattedCounterValue(
        cpu_total,
        PDH_FMT_DOUBLE,
        null,
        &counter_val,
    );

    if (format_result != ERROR_SUCCESS) {
        log.logFmt("PDH failed to get formatted counter value: {d}", .{format_result});
        return stats;
    }

    stats.usage = counter_val.doubleValue;

    // Temperature: WIP (would need WMI or driver-specific APIs)
    return stats;
}

/// Shutdown the PDH subsystem.
pub fn shutdown() void {
    if (pdh_initialized) {
        _ = PdhCloseQuery(cpu_query);
        pdh_initialized = false;
    }
}

/// Helper to convert ASCII string to UTF-16 at compile time
/// Returns a sentinel-terminated array (the sentinel is 0)
fn toUtf16(comptime s: []const u8) *const [s.len:0]u16 {
    // Create a sentinel-terminated array at compile time
    const result = comptime blk: {
        var arr: [s.len:0]u16 = undefined;
        for (s, 0..) |c, i| {
            arr[i] = c;
        }
        break :blk arr;
    };
    return &result;
}
