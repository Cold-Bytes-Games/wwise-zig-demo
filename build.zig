const std = @import("std");

const zgui = @import("vendor/zgui/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "wwise-zig-demo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.subsystem = .Windows;

    b.installArtifact(exe);

    const zigwin32_dependency = b.dependency("zigwin32", .{});

    // Use local dependency for now until wwise-zig is tagged
    // const wwise_zig_dependency = b.anonymousDependency("vendor/wwise-zig", @import("vendor/wwise-zig/build.zig"), .{
    //     .use_communication = true,
    //     .include_file_package_io_blocking = true,
    //     .include_file_package_io_deferred = true,
    //     .target = target,
    //     .optimize = optimize,
    // });

    const zgui_pkg = zgui.package(b, target, optimize, .{
        .options = .{
            .backend = .win32_dx11,
        },
    });

    //exe.addModule("wwise-zig", wwise_zig_dependency.module("wwise-zig"));
    exe.addModule("zgui", zgui_pkg.zgui);
    exe.addModule("zigwin32", zigwin32_dependency.module("zigwin32"));
    // exe.linkLibrary(wwise_zig_dependency.artifact("wwise-c"));

    zgui_pkg.link(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
