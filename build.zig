const std = @import("std");
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

    const sdl_dependency = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });

    const wwise_dependency = b.dependency("wwise-zig", .{
        .target = target,
        .optimize = optimize,
        .use_communication = true,
        .use_default_job_worker = true,
        .use_spatial_audio = true,
        .use_static_crt = true,
        .include_file_package_io_deferred = true,
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

    const zgui_dependency = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3_gpu,
    });

    const wwise_zig_module = wwise_dependency.module("wwise-zig");

    const wwise_id_module = wwise_zig.generateWwiseIDModule(b, "WwiseProject/GeneratedSoundBanks/Wwise_IDs.h", wwise_zig_module, .{
        .previous_step = &build_soundbanks_step.step,
    });

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "wwise-ids",
                .module = wwise_id_module,
            },
            .{
                .name = "wwise-zig",
                .module = wwise_zig_module,
            },
            .{
                .name = "zgui",
                .module = zgui_dependency.module("root"),
            },
        },
    });
    exe_module.linkLibrary(zgui_dependency.artifact("imgui"));
    exe_module.linkLibrary(sdl_dependency.artifact("SDL3"));

    const exe = b.addExecutable(.{
        .name = "wwise-zig-demo",
        .root_module = exe_module,
    });
    exe.step.dependOn(&build_soundbanks_step.step);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
