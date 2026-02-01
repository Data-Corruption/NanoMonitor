//! NanoMonitor - A lightweight hardware monitor overlay
//!
//! This is the main entry point for the application.
//! It creates a transparent layered window that displays CPU/GPU stats.

const cpu = @import("cpu.zig");
const gpu = @import("gpu.zig");
const log = @import("log.zig");
const window = @import("window.zig");

/// Standard Zig entry point - Zig handles the Windows subsystem startup for us
pub fn main() void {
    // Get our module handle (equivalent to hInstance from WinMain)
    const hinstance = window.GetModuleHandleA(null);

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

    // Create the overlay window
    const hwnd = window.createOverlayWindow(hinstance);
    if (hwnd == null) {
        return;
    }

    log.log("NanoMonitor window created, entering message loop");

    // Run the message loop (blocks until window closes)
    window.runMessageLoop();

    // main() returns void, exit code is handled by Zig runtime
}
