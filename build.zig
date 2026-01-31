const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options - defaults to native, but can cross-compile
    const target = b.standardTargetOptions(.{});

    // Standard optimization options (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall)
    const optimize = b.standardOptimizeOption(.{});

    // Define our executable using the new Zig 0.15 API
    // In 0.15+, we use root_module instead of root_source_file
    const exe = b.addExecutable(.{
        .name = "NanoMonitor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Set subsystem to Windows (GUI app, no console)
    exe.subsystem = .Windows;

    // Link against Windows system libraries
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("kernel32"); // For LoadLibrary/GetProcAddress
    exe.linkSystemLibrary("pdh"); // Performance Data Helper for CPU stats

    // Note: NVAPI is now loaded dynamically at runtime via LoadLibrary
    // This avoids the MSVC C++ runtime dependency

    // Install the executable to zig-out/bin/
    b.installArtifact(exe);

    // Create a "run" step: `zig build run`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Allow passing arguments: `zig build run -- arg1 arg2`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run NanoMonitor");
    run_step.dependOn(&run_cmd.step);

    // Create a test step
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
