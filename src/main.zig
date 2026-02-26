const std = @import("std");
const zgui = @import("zgui");
const AK = @import("wwise-zig");

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {}); // We are providing our own entry point
    @cInclude("SDL3/SDL_main.h");
});

pub const MAX_THREAD_WORKERS = 8;
pub const LISTENER_GAME_OBJECT_ID: AK.AkGameObjectID = 1;

const DemoInterface = @import("DemoInterface.zig");
const NullDemo = @import("demos/NullDemo.zig");
const FramePacer = @import("FramePacer.zig");

const DemoEntry = struct {
    name: [:0]const u8,
    instance_type: type,
};

const MenuEntry = struct {
    name: [:0]const u8,
    entries: []const MenuData,
};

const MenuData = union(enum) {
    demo: DemoEntry,
    menu: MenuEntry,
};

const AllMenus = [_]MenuData{
    .{
        .menu = .{
            .name = "Dialogue Demos",
            .entries = &.{
                .{
                    .demo = .{
                        .name = "Localization Demo",
                        .instance_type = @import("demos/LocalizationDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "Dynamic Dialogue Demo",
                        .instance_type = @import("demos/DynamicDialogueDemo.zig"),
                    },
                },
            },
        },
    },
    .{
        .demo = .{
            .name = "RTPC Demo (Car Engine)",
            .instance_type = @import("demos/RtpcCarEngineDemo.zig"),
        },
    },
    .{
        .demo = .{
            .name = "Footsteps Demo",
            .instance_type = @import("demos/FootstepsDemo.zig"),
        },
    },
    .{
        .demo = .{
            .name = "Subtitles/Markers Demo",
            .instance_type = @import("demos/SubtitleDemo.zig"),
        },
    },
    .{
        .menu = .{
            .name = "Music Callbacks Demo",
            .entries = &.{
                .{
                    .demo = .{
                        .name = "Music Sync Callback Demo",
                        .instance_type = @import("demos/MusicSyncCallbackDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "Music Playlist Callback Demo",
                        .instance_type = @import("demos/MusicPlaylistCallbackDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "MIDI Callback Demo",
                        .instance_type = @import("demos/MIDICallbackDemo.zig"),
                    },
                },
            },
        },
    },
    .{
        .demo = .{
            .name = "Interactive Music Demo",
            .instance_type = @import("demos/InteractiveMusicDemo.zig"),
        },
    },
    .{
        .demo = .{
            .name = "MIDI API Demo (Metronome)",
            .instance_type = @import("demos/MIDIMetronomeDemo.zig"),
        },
    },
    .{
        .menu = .{
            .name = "Positioning Demo",
            .entries = &.{
                .{
                    .demo = .{
                        .name = "Position Demo",
                        .instance_type = @import("demos/PositioningDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "Multi-Position Demo",
                        .instance_type = @import("demos/MultiPositioningDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "3d Bus - Clustering/3D Submix",
                        .instance_type = @import("demos/3dBusSubmixDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "3d Bus - 3D Portal and Standard Room",
                        .instance_type = @import("demos/3dBusCoupledRoomsSimpleDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "3d Bus - 2X 3D Portals",
                        .instance_type = @import("demos/3dBusCoupledRoomsWithFeedback.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "3D Audio Objects and Spatialized Bed",
                        .instance_type = @import("demos/3dAudioDemo.zig"),
                    },
                },
            },
        },
    },
    .{
        .menu = .{
            .name = "Spatial Audio",
            .entries = &.{
                .{
                    .demo = .{
                        .name = "Spatial Audio - Portals",
                        .instance_type = @import("demos/SpatialAudioPortalsDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "Spatial Audio - Portals and Geometry",
                        .instance_type = @import("demos/SpatialAudioPortalsAndGeometryDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "Spatial Audio - Geometry",
                        .instance_type = @import("demos/SpatialAudioGeometryDemo.zig"),
                    },
                },
            },
        },
    },
    .{
        .menu = .{
            .name = "Bank & Event Loading Demo",
            .entries = &.{
                .{
                    .demo = .{
                        .name = "Prepare Event & Bank Demo",
                        .instance_type = @import("demos/PrepareDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "External Sources Demo",
                        .instance_type = @import("demos/ExternalSourcesDemo.zig"),
                    },
                },
                .{
                    .demo = .{
                        .name = "Autobanks Demo",
                        .instance_type = @import("demos/AutobanksDemo.zig"),
                    },
                },
            },
        },
    },
    .{
        .demo = .{
            .name = "Background Music/DVR Demo",
            .instance_type = @import("demos/BGMDemo.zig"),
        },
    },
    .{
        .demo = .{
            .name = "Options",
            .instance_type = @import("demos/OptionsDemo.zig"),
        },
    },
};

pub const WwiseContext = struct {
    io_hook: ?*AK.IOHooks.CAkFilePackageLowLevelIODeferred = null,
    init_bank_id: AK.AkBankID = 0,
    memory_settings: AK.AkMemSettings = .{},
    stream_mgr_settings: AK.StreamMgr.AkStreamMgrSettings = .{},
    device_settings: AK.StreamMgr.AkDeviceSettings = .{},
    init_settings: AK.AkInitSettings = .{},
    platform_init_settings: AK.AkPlatformInitSettings = .{},
    comm_settings: if (AK.Comm != void) AK.Comm.AkCommSettings else void = .{},
    job_worker_settings: if (AK.JobWorkerMgr != void) AK.JobWorkerMgr.InitSettings else void = .{},
    spatial_audio_settings: if (AK.SpatialAudio != void) AK.SpatialAudio.AkSpatialAudioInitSettings else void = .{},

    pub fn init(self: *WwiseContext, allocator: std.mem.Allocator) !void {
        // Get default settings
        try self.getDefaultWwiseSettings(allocator);

        // Create memory manager
        try AK.MemoryMgr.init(&self.memory_settings);

        // Create streaming manager
        _ = AK.StreamMgr.create(&self.stream_mgr_settings);

        // Create the I/O hook using default FilePackage blocking I/O Hook
        var io_hook = try AK.IOHooks.CAkFilePackageLowLevelIODeferred.create(allocator);
        try io_hook.init(&self.device_settings);
        self.io_hook = io_hook;

        // Gather init settings and init the sound engine
        try AK.SoundEngine.init(allocator, &self.init_settings, &self.platform_init_settings);

        // Setup communication for debugging with the Wwise Authoring
        if (AK.Comm != void) {
            self.comm_settings.setAppNetworkName("wwise-zig Integration Demo");

            try AK.Comm.init(&self.comm_settings);
        }

        if (AK.JobWorkerMgr != void and self.job_worker_settings.num_worker_threads > 0) {
            try AK.JobWorkerMgr.initWorkers(&self.job_worker_settings);
        }

        // Setup I/O Hook base path
        const current_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(current_dir);

        // TODO: Add path depending on platform
        const sound_banks_path = try std.fs.path.join(allocator, &[_][]const u8{ current_dir, "WwiseProject\\GeneratedSoundBanks\\Windows" });
        defer allocator.free(sound_banks_path);

        try io_hook.setBasePath(allocator, sound_banks_path);

        try AK.StreamMgr.setCurrentLanguage(allocator, "English(US)");

        // Load Init Bank
        self.init_bank_id = try AK.SoundEngine.loadBankString(allocator, "Init.bnk", .{});

        // Init microphone
        try AK.SoundEngine.registerGameObjWithName(allocator, LISTENER_GAME_OBJECT_ID, "Listener");
        try AK.SoundEngine.setDefaultListeners(&.{LISTENER_GAME_OBJECT_ID});

        // Register monitor callback
        try AK.SoundEngine.registerResourceMonitorCallback(resourceMonitorCallback);

        // Register spatial audio
        try AK.SpatialAudio.init(&self.spatial_audio_settings);

        // TODO: Setup monitor local output
    }

    pub fn deinit(self: *WwiseContext, allocator: std.mem.Allocator) !void {
        try AK.SoundEngine.unregisterResourceMonitorCallback(resourceMonitorCallback);

        try AK.SoundEngine.unregisterGameObj(LISTENER_GAME_OBJECT_ID);

        // try AK.SoundEngine.unloadBankID(demo.wwise_context.init_bank_id, null, .{});

        if (AK.Comm != void) {
            AK.Comm.term();
        }

        if (AK.SoundEngine.isInitialized()) {
            AK.SoundEngine.term();
        }

        if (AK.JobWorkerMgr != void and self.job_worker_settings.num_worker_threads > 0) {
            AK.JobWorkerMgr.termWorkers();
        }

        if (self.io_hook) |io_hook| {
            io_hook.term();

            io_hook.destroy(allocator);
        }

        if (AK.IAkStreamMgr.get()) |stream_mgr| {
            stream_mgr.destroy();
        }

        if (AK.MemoryMgr.isInitialized()) {
            AK.MemoryMgr.term();
        }
    }

    fn getDefaultWwiseSettings(self: *WwiseContext, allocator: std.mem.Allocator) !void {
        AK.MemoryMgr.getDefaultSettings(&self.memory_settings);

        AK.StreamMgr.getDefaultSettings(&self.stream_mgr_settings);

        AK.StreamMgr.getDefaultDeviceSettings(&self.device_settings);

        try AK.SoundEngine.getDefaultInitSettings(allocator, &self.init_settings);

        AK.SoundEngine.getDefaultPlatformInitSettings(&self.platform_init_settings);

        // Setup communication for debugging with the Wwise Authoring
        if (AK.Comm != void) {
            try AK.Comm.getDefaultInitSettings(&self.comm_settings);
        }

        if (AK.JobWorkerMgr != void) {
            AK.JobWorkerMgr.getDefaultInitSettings(&self.job_worker_settings);

            const max_workers = blk: {
                const runtime_cpu_count = std.Thread.getCpuCount() catch {
                    break :blk @as(usize, MAX_THREAD_WORKERS);
                };

                break :blk @min(runtime_cpu_count, MAX_THREAD_WORKERS);
            };
            self.job_worker_settings.num_worker_threads = @intCast(max_workers);

            self.init_settings.settings_job_manager = self.job_worker_settings.getJobMgrSettings();

            for (0..AK.AK_NUM_JOB_TYPES) |index| {
                self.init_settings.settings_job_manager.max_active_workers[index] = 2;
            }
        }
    }

    var current_resource_monitor_data: AK.AkResourceMonitorDataSummary = .{};

    fn resourceMonitorCallback(in_data_summary: ?*const AK.AkResourceMonitorDataSummary) callconv(.c) void {
        if (in_data_summary) |data_summary| {
            current_resource_monitor_data = data_summary.*;
        }
    }
};

pub const SdlContext = struct {
    window: *c.SDL_Window = undefined,
    gpu_device: *c.SDL_GPUDevice = undefined,

    pub fn deinit(self: *SdlContext) void {
        c.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, self.window);
        c.SDL_DestroyGPUDevice(self.gpu_device);

        c.SDL_DestroyWindow(self.window);
    }
};

pub const WwiseDemoApp = struct {
    wwise_context: WwiseContext = .{},
    sdl_context: SdlContext = .{},
    main_allocator: std.heap.ThreadSafeAllocator = undefined,
    current_demo: DemoInterface = undefined,
    show_resource_monitor: bool = false,
    frame_pacer: FramePacer = .{},

    pub fn init(self: *WwiseDemoApp) !void {
        const allocator = self.main_allocator.allocator();

        // Init the frame pacer
        self.frame_pacer = try FramePacer.init(60);

        // Create null demo
        var null_demo_instance = try allocator.create(NullDemo);
        try null_demo_instance.init(allocator, self);
        self.current_demo = null_demo_instance.demoInterface();

        // Init zgui
        zgui.init(allocator);

        zgui.backend.init(self.sdl_context.window, .{
            .device = self.sdl_context.gpu_device,
            .color_target_format = @intCast(c.SDL_GetGPUSwapchainTextureFormat(self.sdl_context.gpu_device, self.sdl_context.window)),
            .msaa_samples = c.SDL_GPU_SAMPLECOUNT_1,
        });

        // Init Wwise
        try self.wwise_context.init(allocator);
    }

    pub fn deinit(self: *WwiseDemoApp) void {
        self.wwise_context.deinit(self.main_allocator.allocator()) catch {};

        _ = c.SDL_WaitForGPUIdle(self.sdl_context.gpu_device);

        zgui.backend.deinit();
        zgui.deinit();
        self.current_demo.deinit(self);

        self.sdl_context.deinit();
    }

    pub fn update(self: *WwiseDemoApp) !void {
        // Setup zgui new frame, get current window size and scale
        var window_width: i32 = 0;
        var window_height: i32 = 0;
        try errify(c.SDL_GetWindowSize(self.sdl_context.window, &window_width, &window_height));
        const window_scale: f32 = c.SDL_GetWindowDisplayScale(self.sdl_context.window);

        zgui.backend.newFrame(@intCast(window_width), @intCast(window_height), window_scale);

        // Create the main menu bar
        if (zgui.beginMainMenuBar()) {
            inline for (AllMenus) |menu_data| {
                try self.createMenu(menu_data, self.main_allocator.allocator());
            }

            if (zgui.menuItem("Resource Monitor", .{ .selected = self.show_resource_monitor })) {
                self.show_resource_monitor = !self.show_resource_monitor;
            }

            zgui.endMainMenuBar();
        }

        // Show resource monitor if requested
        if (self.show_resource_monitor) {
            if (zgui.begin("Resource Monitor", .{ .flags = .{ .always_auto_resize = true } })) {
                zgui.text("Total CPU: {d:3.6}", .{WwiseContext.current_resource_monitor_data.total_cpu});
                zgui.text("Plugin CPU: {d:3.6}", .{WwiseContext.current_resource_monitor_data.plugin_cpu});
                zgui.text("Virtual Voices: {}", .{WwiseContext.current_resource_monitor_data.physical_voices});
                zgui.text("Physical Voices: {}", .{WwiseContext.current_resource_monitor_data.virtual_voices});
                zgui.text("Total Voices: {}", .{WwiseContext.current_resource_monitor_data.total_voices});
                zgui.text("Active events: {}", .{WwiseContext.current_resource_monitor_data.nb_active_events});
                zgui.end();
            }
        }

        // Draw the current demo
        if (self.current_demo.isVisible()) {
            try self.current_demo.onUI(self);
        }

        // Tell Wwise to render audio
        try AK.SoundEngine.renderAudio(false);
    }

    pub fn draw(self: *WwiseDemoApp) !void {
        zgui.backend.render();

        const command_buffer = try errify(c.SDL_AcquireGPUCommandBuffer(self.sdl_context.gpu_device));

        var swapchain_texture_opt: ?*c.SDL_GPUTexture = null;
        try errify(c.SDL_AcquireGPUSwapchainTexture(command_buffer, self.sdl_context.window, &swapchain_texture_opt, null, null));
        if (swapchain_texture_opt) |swapchain_texture| {
            zgui.backend.prepareDrawData(command_buffer);

            const target_info: c.SDL_GPUColorTargetInfo = .{
                .texture = swapchain_texture,
                .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 },
                .load_op = c.SDL_GPU_LOADOP_CLEAR,
                .store_op = c.SDL_GPU_STOREOP_STORE,
                .mip_level = 0,
                .layer_or_depth_plane = 0,
                .cycle = false,
            };

            const render_pass = try errify(c.SDL_BeginGPURenderPass(command_buffer, &target_info, 1, null));

            zgui.backend.renderDrawData(command_buffer, render_pass, null);

            c.SDL_EndGPURenderPass(render_pass);
        }

        try errify(c.SDL_SubmitGPUCommandBuffer(command_buffer));
    }

    fn createMenu(self: *WwiseDemoApp, comptime menu_data: MenuData, allocator: std.mem.Allocator) !void {
        switch (menu_data) {
            .demo => |demo_entry| {
                if (zgui.menuItem(demo_entry.name, .{})) {
                    self.current_demo.deinit(self);

                    var new_demo_instance = try allocator.create(demo_entry.instance_type);
                    self.current_demo = new_demo_instance.demoInterface();
                    try self.current_demo.init(allocator, self);
                    self.current_demo.show();
                }
            },
            .menu => |menu| {
                if (zgui.beginMenu(menu.name, true)) {
                    inline for (menu.entries) |menu_entry| {
                        try self.createMenu(menu_entry, allocator);
                    }

                    zgui.endMenu();
                }
            },
        }
    }
};

fn sdlAppInit(app_state: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
    _ = argv; // autofix

    // Create demo instance and setup allocator
    const demo = try std.heap.smp_allocator.create(WwiseDemoApp);
    demo.* = .{};
    demo.main_allocator = .{
        .child_allocator = std.heap.smp_allocator,
    };

    app_state.?.* = demo;

    // Init SDL and create window
    try errify(c.SDL_SetAppMetadata("wwise-zig-demo", "2023.1.13", "coldbytes.wwise-zig.demo"));

    try errify(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD));

    errify(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) catch {};

    const main_scale = c.SDL_GetDisplayContentScale(c.SDL_GetPrimaryDisplay());
    demo.sdl_context.window = try errify(c.SDL_CreateWindow(
        "wwise-zig Integration Demo",
        @intFromFloat(1920.0 * main_scale),
        @intFromFloat(1080.0 * main_scale),
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIDDEN | c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    ));

    _ = c.SDL_SetWindowPosition(demo.sdl_context.window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED);
    _ = c.SDL_ShowWindow(demo.sdl_context.window);

    // Create GPU Device
    demo.sdl_context.gpu_device = try errify(c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_METALLIB, false, null));

    // Claim window for GPU Device
    try errify(c.SDL_ClaimWindowForGPUDevice(demo.sdl_context.gpu_device, demo.sdl_context.window));

    // Set swapchain parameter
    _ = c.SDL_SetGPUSwapchainParameters(demo.sdl_context.gpu_device, demo.sdl_context.window, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.SDL_GPU_PRESENTMODE_MAILBOX);

    // Init the demo app
    try demo.init();

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(app_state: ?*anyopaque) !c.SDL_AppResult {
    const demo: *WwiseDemoApp = @ptrCast(@alignCast(app_state.?));

    try demo.frame_pacer.tick();

    while (demo.frame_pacer.shouldUpdate()) {
        try demo.update();
        try demo.draw();

        demo.frame_pacer.consume();
    }

    return c.SDL_APP_CONTINUE;
}

fn sdlAppEvent(app_state: ?*anyopaque, event: *c.SDL_Event) !c.SDL_AppResult {
    _ = app_state; // autofix

    switch (event.type) {
        c.SDL_EVENT_QUIT => {
            return c.SDL_APP_SUCCESS;
        },
        else => {
            _ = zgui.backend.processEvent(event);
        },
    }

    return c.SDL_APP_CONTINUE;
}

fn sdlAppQuit(app_state: ?*anyopaque, result: anyerror!c.SDL_AppResult) void {
    _ = result catch |err| if (err == error.SdlError) {
        std.log.err("{s}", .{c.SDL_GetError()});
    };

    if (app_state == null) {
        return;
    }

    const demo: *WwiseDemoApp = @ptrCast(@alignCast(app_state.?));

    demo.deinit();

    std.heap.smp_allocator.destroy(demo);
}

pub fn main() !u8 {
    app_err.reset();
    var empty_argv: [0:null]?[*:0]u8 = .{};
    const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMainC, null))));
    return app_err.load() orelse status;
}

fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    return c.SDL_EnterAppMainCallbacks(argc, @ptrCast(argv), sdlAppInitC, sdlAppIterateC, sdlAppEventC, sdlAppQuitC);
}

fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    return sdlAppInit(appstate.?, @ptrCast(argv.?[0..@intCast(argc)])) catch |err| app_err.store(err);
}

fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
    return sdlAppIterate(appstate) catch |err| app_err.store(err);
}

fn sdlAppEventC(appstate: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
    return sdlAppEvent(appstate, event.?) catch |err| app_err.store(err);
}

fn sdlAppQuitC(appstate: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    sdlAppQuit(appstate, app_err.load() orelse result);
}

/// Converts the return value of an SDL function to an error union.
inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
    .bool => void,
    .pointer, .optional => @TypeOf(value.?),
    .int => |info| switch (info.signedness) {
        .signed => @TypeOf(@max(0, value)),
        .unsigned => @TypeOf(value),
    },
    else => @compileError("unerrifiable type: " ++ @typeName(@TypeOf(value))),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .bool => if (!value) error.SdlError,
        .pointer, .optional => value orelse error.SdlError,
        .int => |info| switch (info.signedness) {
            .signed => if (value >= 0) @max(0, value) else error.SdlError,
            .unsigned => if (value != 0) value else error.SdlError,
        },
        else => comptime unreachable,
    };
}

var app_err: ErrorStore = .{};

const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: c.SDL_AtomicInt = .{},
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    fn reset(es: *ErrorStore) void {
        _ = c.SDL_SetAtomicInt(&es.status, status_not_stored);
    }

    fn store(es: *ErrorStore, err: anyerror) c.SDL_AppResult {
        if (c.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
            es.err = err;
            if (@errorReturnTrace()) |src_trace| {
                es.trace_index = src_trace.index;
                const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
                @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
            }
            _ = c.SDL_SetAtomicInt(&es.status, status_stored);
        }
        return c.SDL_APP_FAILURE;
    }

    fn load(es: *ErrorStore) ?anyerror {
        if (c.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};

// Part of the SDL main is based of: https://github.com/castholm/zig-examples/blob/master/breakout/main.zig
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice (including the next paragraph) shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
