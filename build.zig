const std = @import("std");

const zglfw = @import("vendor/zig-gamedev/libs/zglfw/build.zig");
const zgpu = @import("vendor/zig-gamedev/libs/zgpu/build.zig");
const zgui = @import("vendor/zig-gamedev/libs/zgui/build.zig");
const zpool = @import("vendor/zig-gamedev/libs/zpool/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "wwise-zig-demo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Use local dependency for now until wwise-zig is tagged
    // const wwise_zig_dependency = b.anonymousDependency("vendor/wwise-zig", @import("vendor/wwise-zig/build.zig"), .{
    //     .use_communication = true,
    //     .include_file_package_io_blocking = true,
    //     .include_file_package_io_deferred = true,
    //     .target = target,
    //     .optimize = optimize,
    // });

    const zglfw_pkg = zglfw.package(b, target, optimize, .{});
    const zgui_pkg = zgui.package(b, target, optimize, .{
        .options = .{
            .backend = .glfw_wgpu,
        },
    });
    const zpool_pkg = zpool.package(b, target, optimize, .{});
    const zgpu_pkg = zgpu.package(b, target, optimize, .{
        .options = .{ .uniforms_buffer_size = 4 * 1024 * 1024 },
        .deps = .{ .zpool = zpool_pkg.zpool, .zglfw = zglfw_pkg.zglfw },
    });

    //exe.addModule("wwise-zig", wwise_zig_dependency.module("wwise-zig"));
    exe.addModule("zglfw", zglfw_pkg.zglfw);
    exe.addModule("zgpu", zgpu_pkg.zgpu);
    exe.addModule("zgui", zgui_pkg.zgui);
    exe.addModule("zpool", zpool_pkg.zpool);
    // exe.linkLibrary(wwise_zig_dependency.artifact("wwise-c"));

    zglfw_pkg.link(exe);
    zgpu_pkg.link(exe);
    zgui_pkg.link(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
