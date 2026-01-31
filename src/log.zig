//! Logging utilities for NanoMonitor
//!
//! In Zig, we use doc comments (//!) at the top of files to document the module.

const std = @import("std");

/// The log file path - using a module-level constant
const LOG_FILE_PATH = "NanoMonitor.log";

/// Appends a message to the log file.
///
/// In Zig, errors are values and must be explicitly handled.
/// The `!void` return type means "returns void OR an error".
pub fn appendToLogFile(message: []const u8) !void {
    // Open file for appending, create if doesn't exist
    const file = try std.fs.cwd().createFile(LOG_FILE_PATH, .{
        .truncate = false, // Don't truncate existing content
    });
    defer file.close(); // `defer` runs when the scope exits

    // Seek to end of file
    try file.seekFromEnd(0);

    // Get current timestamp
    const timestamp = std.time.timestamp();

    // In Zig 0.15+, writer() requires a buffer for buffered writing
    // We'll use unbuffered direct writes instead
    var buf: [1024]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "[{d}] {s}\n", .{ timestamp, message }) catch {
        return error.FormatError;
    };

    try file.writeAll(formatted);
}

/// Log helper that ignores errors (fire-and-forget logging)
pub fn log(message: []const u8) void {
    appendToLogFile(message) catch |err| {
        // In debug builds, we might want to see this
        std.debug.print("Failed to write log: {}\n", .{err});
    };
}

/// Formatted logging - accepts format string and arguments
pub fn logFmt(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, fmt, args) catch {
        log("(log message too long)");
        return;
    };
    log(message);
}
