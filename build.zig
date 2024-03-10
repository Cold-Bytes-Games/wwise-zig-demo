const std = @import("std");

const zgui = @import("vendor/zgui/build.zig");
const wwise_zig = @import("wwise-zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{ .default_target = .{
        .os_tag = .windows,
        .abi = .msvc,
    } });
    const optimize = b.standardOptimizeOption(.{});

    const override_wwise_sdk_path_option = b.option([]const u8, "wwise_sdk", "Override the path to the Wwise SDK, by default it will use the path in environment variable WWISESDK");

    const build_soundbanks_step = try wwise_zig.addGenerateSoundBanksStep(b, "WwiseProject/IntegrationDemo.wproj", .{
        .override_wwise_sdk_path = override_wwise_sdk_path_option,
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "wwise-zig-demo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.step.dependOn(&build_soundbanks_step.step);

    exe.subsystem = .Windows;

    b.installArtifact(exe);

    const zigwin32_dependency = b.dependency("zigwin32", .{});

    const wwise_dependency = b.dependency("wwise-zig", .{
        .target = target,
        .optimize = optimize,
        .use_communication = true,
        .use_default_job_worker = true,
        .use_spatial_audio = true,
        .use_static_crt = true,
        .include_file_package_io_blocking = true,
        .configuration = .profile,
        .wwise_sdk = override_wwise_sdk_path_option orelse "",
        .static_plugins = @as([]const []const u8, &.{
            "AkToneSource",
            "AkParametricEQFX",
            "AkDelayFX",
            "AkPeakLimiterFX",
            "AkRoomVerbFX",
            "AkStereoDelayFX",
            "AkSynthOneSource",
            "AkAudioInputSource",
            "AkVorbisDecoder",
        }),
    });

    const zgui_pkg = zgui.package(b, target, optimize, .{
        .options = .{
            .backend = .win32_dx11,
        },
    });

    const wwise_zig_module = wwise_dependency.module("wwise-zig");

    const wwise_id_module = wwise_zig.generateWwiseIDModule(b, "WwiseProject/GeneratedSoundBanks/Wwise_IDs.h", wwise_zig_module, .{
        .previous_step = &build_soundbanks_step.step,
    });

    exe.root_module.addImport("wwise-ids", wwise_id_module);
    exe.root_module.addImport("wwise-zig", wwise_zig_module);
    exe.root_module.addImport("zgui", zgui_pkg.zgui);
    exe.root_module.addImport("zigwin32", zigwin32_dependency.module("zigwin32"));
    zgui_pkg.link(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
