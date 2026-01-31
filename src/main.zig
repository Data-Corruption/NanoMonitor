//! NanoMonitor - A lightweight hardware monitor overlay
//!
//! This is the main entry point for the application.
//! It creates a transparent layered window that displays CPU/GPU stats.

const std = @import("std");
const cpu = @import("cpu.zig");
const gpu = @import("gpu.zig");
const log = @import("log.zig");

// In Zig 0.15+, calling conventions are tagged unions that need initialization.
// For Windows x86_64, we use x86_64_win with default CommonOptions
const WINAPI: std.builtin.CallingConvention = .{ .x86_64_win = .{} };

// ============================================================================
// Win32 Type Definitions
// ============================================================================

const HANDLE = ?*anyopaque;
const HWND = ?*anyopaque;
const HDC = ?*anyopaque;
const HINSTANCE = ?*anyopaque;
const HBRUSH = ?*anyopaque;
const HBITMAP = ?*anyopaque;
const HGDIOBJ = ?*anyopaque;
const HCURSOR = ?*anyopaque;
const HMENU = ?*anyopaque;
const LPVOID = ?*anyopaque;

const UINT = u32;
const DWORD = u32;
const WORD = u16;
const BYTE = u8;
const BOOL = i32;
const LONG = i32;
const INT = i32;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const COLORREF = DWORD;
const LPCSTR = [*:0]const u8;
const ATOM = WORD;

// Window styles
const WS_POPUP: DWORD = 0x80000000;
const WS_EX_TOPMOST: DWORD = 0x00000008;
const WS_EX_TOOLWINDOW: DWORD = 0x00000080;
const WS_EX_LAYERED: DWORD = 0x00080000;
const CS_HREDRAW: UINT = 0x0002;
const CS_VREDRAW: UINT = 0x0001;

// Window messages
const WM_DESTROY: UINT = 0x0002;
const WM_TIMER: UINT = 0x0113;

// Other constants
const SW_SHOW: INT = 5;
const MB_ICONERROR: UINT = 0x00000010;
const IDC_ARROW: LPCSTR = @ptrFromInt(32512);
const BLACK_BRUSH: INT = 4;
const TRANSPARENT: INT = 1;
const AC_SRC_OVER: BYTE = 0x00;
const ULW_ALPHA: DWORD = 0x00000002;

// ============================================================================
// Win32 Structures
// ============================================================================

const WNDCLASSEXA = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXA),
    style: UINT = 0,
    lpfnWndProc: WNDPROC = null,
    cbClsExtra: INT = 0,
    cbWndExtra: INT = 0,
    hInstance: HINSTANCE = null,
    hIcon: HANDLE = null,
    hCursor: HCURSOR = null,
    hbrBackground: HBRUSH = null,
    lpszMenuName: ?LPCSTR = null,
    lpszClassName: ?LPCSTR = null,
    hIconSm: HANDLE = null,
};

const MSG = extern struct {
    hwnd: HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

const POINT = extern struct {
    x: LONG = 0,
    y: LONG = 0,
};

const SIZE = extern struct {
    cx: LONG = 0,
    cy: LONG = 0,
};

const RECT = extern struct {
    left: LONG = 0,
    top: LONG = 0,
    right: LONG = 0,
    bottom: LONG = 0,
};

const BLENDFUNCTION = extern struct {
    BlendOp: BYTE = 0,
    BlendFlags: BYTE = 0,
    SourceConstantAlpha: BYTE = 0,
    AlphaFormat: BYTE = 0,
};

const WNDPROC = ?*const fn (HWND, UINT, WPARAM, LPARAM) callconv(WINAPI) LRESULT;

// ============================================================================
// Win32 Function Declarations
// ============================================================================

extern "user32" fn RegisterClassExA(lpWndClass: *const WNDCLASSEXA) callconv(WINAPI) ATOM;
extern "user32" fn CreateWindowExA(
    dwExStyle: DWORD,
    lpClassName: LPCSTR,
    lpWindowName: LPCSTR,
    dwStyle: DWORD,
    X: INT,
    Y: INT,
    nWidth: INT,
    nHeight: INT,
    hWndParent: HWND,
    hMenu: HMENU,
    hInstance: HINSTANCE,
    lpParam: LPVOID,
) callconv(WINAPI) HWND;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: INT) callconv(WINAPI) BOOL;
extern "user32" fn UpdateWindow(hWnd: HWND) callconv(WINAPI) BOOL;
extern "user32" fn GetMessageA(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(WINAPI) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(WINAPI) BOOL;
extern "user32" fn DispatchMessageA(lpMsg: *const MSG) callconv(WINAPI) LRESULT;
extern "user32" fn DefWindowProcA(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) LRESULT;
extern "user32" fn PostQuitMessage(nExitCode: INT) callconv(WINAPI) void;
extern "user32" fn SetTimer(hWnd: HWND, nIDEvent: usize, uElapse: UINT, lpTimerFunc: ?*anyopaque) callconv(WINAPI) usize;
extern "user32" fn MessageBoxA(hWnd: HWND, lpText: LPCSTR, lpCaption: LPCSTR, uType: UINT) callconv(WINAPI) INT;
extern "user32" fn LoadCursorA(hInstance: HINSTANCE, lpCursorName: LPCSTR) callconv(WINAPI) HCURSOR;
extern "user32" fn GetDC(hWnd: HWND) callconv(WINAPI) HDC;
extern "user32" fn ReleaseDC(hWnd: HWND, hDC: HDC) callconv(WINAPI) INT;
extern "user32" fn FillRect(hDC: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(WINAPI) INT;
extern "user32" fn UpdateLayeredWindow(
    hWnd: HWND,
    hdcDst: HDC,
    pptDst: ?*const POINT,
    psize: ?*const SIZE,
    hdcSrc: HDC,
    pptSrc: ?*const POINT,
    crKey: COLORREF,
    pblend: ?*const BLENDFUNCTION,
    dwFlags: DWORD,
) callconv(WINAPI) BOOL;

extern "gdi32" fn CreateCompatibleDC(hdc: HDC) callconv(WINAPI) HDC;
extern "gdi32" fn CreateCompatibleBitmap(hdc: HDC, cx: INT, cy: INT) callconv(WINAPI) HBITMAP;
extern "gdi32" fn SelectObject(hdc: HDC, h: HGDIOBJ) callconv(WINAPI) HGDIOBJ;
extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(WINAPI) BOOL;
extern "gdi32" fn DeleteDC(hdc: HDC) callconv(WINAPI) BOOL;
extern "gdi32" fn GetStockObject(i: INT) callconv(WINAPI) HGDIOBJ;
extern "gdi32" fn SetBkMode(hdc: HDC, mode: INT) callconv(WINAPI) INT;
extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(WINAPI) COLORREF;
extern "gdi32" fn TextOutA(hdc: HDC, x: INT, y: INT, lpString: [*]const u8, c: INT) callconv(WINAPI) BOOL;

// To get HINSTANCE without WinMain
extern "kernel32" fn GetModuleHandleA(lpModuleName: ?LPCSTR) callconv(WINAPI) HINSTANCE;

// ============================================================================
// Application Code
// ============================================================================

// Window dimensions
const WINDOW_WIDTH = 300;
const WINDOW_HEIGHT = 200;

// Timer ID for periodic updates
const UPDATE_TIMER_ID = 1;
const UPDATE_INTERVAL_MS = 1000;

// Store instance handle globally
var g_instance: HINSTANCE = null;

/// Window procedure - handles Windows messages for our overlay window.
fn windowProc(hwnd: HWND, message: UINT, wparam: WPARAM, lparam: LPARAM) callconv(WINAPI) LRESULT {
    switch (message) {
        WM_TIMER => {
            updateOverlay(hwnd);
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        else => return DefWindowProcA(hwnd, message, wparam, lparam),
    }
}

/// Updates the overlay with current CPU/GPU stats.
fn updateOverlay(hwnd: HWND) void {
    // Get device contexts
    const hdc_screen = GetDC(null);
    defer _ = ReleaseDC(null, hdc_screen);

    const hdc = CreateCompatibleDC(hdc_screen);
    defer _ = DeleteDC(hdc);

    const hbmp = CreateCompatibleBitmap(hdc_screen, WINDOW_WIDTH, WINDOW_HEIGHT);
    defer _ = DeleteObject(hbmp);

    _ = SelectObject(hdc, hbmp);

    // Fill background with black
    var rect = RECT{
        .left = 0,
        .top = 0,
        .right = WINDOW_WIDTH,
        .bottom = WINDOW_HEIGHT,
    };
    _ = FillRect(hdc, &rect, @ptrCast(GetStockObject(BLACK_BRUSH)));

    // Get CPU and GPU stats
    const cpu_stats = cpu.getUsageAndTemp();
    const gpu_stats = gpu.getUsageAndTemp();

    // Format the message
    var msg_buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "GPU: {d}%, {d}C  CPU: {d:.1}%, {d}C", .{
        gpu_stats.usage,
        gpu_stats.temp,
        cpu_stats.usage,
        cpu_stats.temp,
    }) catch "Error formatting";

    // Set up text rendering
    _ = SetBkMode(hdc, TRANSPARENT);
    _ = SetTextColor(hdc, rgb(0, 255, 0)); // Green text

    // Draw the text
    _ = TextOutA(hdc, 10, 10, msg.ptr, @intCast(msg.len));

    // Update the layered window
    var blend = BLENDFUNCTION{
        .BlendOp = AC_SRC_OVER,
        .BlendFlags = 0,
        .SourceConstantAlpha = 255,
        .AlphaFormat = 0,
    };

    var pt_zero = POINT{ .x = 0, .y = 0 };
    var size_wnd = SIZE{ .cx = WINDOW_WIDTH, .cy = WINDOW_HEIGHT };

    _ = UpdateLayeredWindow(
        hwnd,
        hdc_screen,
        null,
        &size_wnd,
        hdc,
        &pt_zero,
        0,
        &blend,
        ULW_ALPHA,
    );
}

/// Helper to create a COLORREF from RGB values.
inline fn rgb(r: u8, g: u8, b: u8) COLORREF {
    return @as(COLORREF, r) | (@as(COLORREF, g) << 8) | (@as(COLORREF, b) << 16);
}

/// Standard Zig entry point - Zig handles the Windows subsystem startup for us
pub fn main() void {
    // Get our module handle (equivalent to hInstance from WinMain)
    const hinstance = GetModuleHandleA(null);
    g_instance = hinstance;

    log.log("NanoMonitor starting...");

    // Initialize subsystems
    cpu.init() catch |err| {
        log.logFmt("CPU init failed: {}", .{err});
    };

    gpu.init() catch |err| {
        log.logFmt("GPU init failed: {}", .{err});
    };

    // Ensure cleanup on exit
    defer {
        gpu.shutdown();
        cpu.shutdown();
        log.log("NanoMonitor shutting down");
    }

    // Register window class
    const class_name: LPCSTR = "NanoMonitorClass";

    var wc = WNDCLASSEXA{};
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = windowProc;
    wc.hInstance = hinstance;
    wc.hCursor = LoadCursorA(null, IDC_ARROW);
    wc.hbrBackground = @ptrCast(GetStockObject(BLACK_BRUSH));
    wc.lpszClassName = class_name;

    if (RegisterClassExA(&wc) == 0) {
        _ = MessageBoxA(null, "Window Registration Failed!", "Error", MB_ICONERROR);
        return;
    }

    // Create the layered window
    const hwnd = CreateWindowExA(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
        class_name,
        "NanoMonitor",
        WS_POPUP,
        0,
        0,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        null,
        null,
        hinstance,
        null,
    );

    if (hwnd == null) {
        _ = MessageBoxA(null, "Window Creation Failed!", "Error", MB_ICONERROR);
        return;
    }

    // Set up the update timer
    _ = SetTimer(hwnd, UPDATE_TIMER_ID, UPDATE_INTERVAL_MS, null);

    // Show the window (use SW_SHOW since we don't have nCmdShow from WinMain)
    _ = ShowWindow(hwnd, SW_SHOW);
    _ = UpdateWindow(hwnd);

    // Initial draw
    updateOverlay(hwnd);

    log.log("NanoMonitor window created, entering message loop");

    // Message loop
    var msg: MSG = undefined;
    while (GetMessageA(&msg, null, 0, 0) > 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageA(&msg);
    }

    // main() returns void, exit code is handled by Zig runtime
}

// Tests
test "rgb helper" {
    const red = rgb(255, 0, 0);
    try std.testing.expectEqual(@as(COLORREF, 0x0000FF), red);

    const green = rgb(0, 255, 0);
    try std.testing.expectEqual(@as(COLORREF, 0x00FF00), green);
}
