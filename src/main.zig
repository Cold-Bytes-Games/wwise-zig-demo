const std = @import("std");
const d3d11 = zigwin32.graphics.direct3d11;
const d3d = zigwin32.graphics.direct3d;
const dxgi = zigwin32.graphics.dxgi;
const win32 = zigwin32.everything;
const zgui = @import("zgui");
const zigwin32 = @import("zigwin32");
const AK = @import("wwise-zig");

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {}); // We are providing our own entry point
    @cInclude("SDL3/SDL_main.h");
});

// Use wide API for zigwin32
pub const UNICODE = true;

pub const MaxThreadWorkers = 8;

const L = std.unicode.utf8ToUtf16LeStringLiteral;

const DemoInterface = @import("DemoInterface.zig");
const NullDemo = @import("demos/NullDemo.zig");

pub const DxContext = struct {
    device: ?*d3d11.ID3D11Device = null,
    device_context: ?*d3d11.ID3D11DeviceContext = null,
    swap_chain: ?*dxgi.IDXGISwapChain = null,
    main_render_target_view: ?*d3d11.ID3D11RenderTargetView = null,
    hwnd: ?win32.HWND = null,

    pub fn createDeviceD3D(self: *DxContext) bool {
        var sd = std.mem.zeroes(dxgi.DXGI_SWAP_CHAIN_DESC);
        sd.BufferCount = 2;
        sd.BufferDesc.Width = 0;
        sd.BufferDesc.Height = 0;
        sd.BufferDesc.Format = .R8G8B8A8_UNORM;
        sd.BufferDesc.RefreshRate.Numerator = 60;
        sd.BufferDesc.RefreshRate.Denominator = 1;
        sd.Flags = @intFromEnum(dxgi.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH);
        sd.BufferUsage = dxgi.DXGI_USAGE_RENDER_TARGET_OUTPUT;
        sd.OutputWindow = self.hwnd;
        sd.SampleDesc.Count = 1;
        sd.SampleDesc.Quality = 0;
        sd.Windowed = @intFromBool(true);
        sd.SwapEffect = .DISCARD;

        var feature_level: d3d.D3D_FEATURE_LEVEL = undefined;
        const feature_level_array = &[_]d3d.D3D_FEATURE_LEVEL{
            .@"11_0",
            .@"10_0",
        };
        if (d3d11.D3D11CreateDeviceAndSwapChain(null, .HARDWARE, null, .{}, feature_level_array, 2, d3d11.D3D11_SDK_VERSION, &sd, &self.swap_chain, &self.device, &feature_level, &self.device_context) != win32.S_OK) {
            return false;
        }

        self.createRenderTarget();

        return true;
    }

    pub fn createRenderTarget(self: *DxContext) void {
        var back_buffer_opt: ?*d3d11.ID3D11Texture2D = null;
        if (self.swap_chain) |swap_chain| {
            _ = swap_chain.GetBuffer(0, d3d11.IID_ID3D11Texture2D, @ptrCast(&back_buffer_opt));
        }
        if (self.device) |device| {
            _ = device.CreateRenderTargetView(@ptrCast(back_buffer_opt), null, @ptrCast(&self.main_render_target_view));
        }
        if (back_buffer_opt) |back_buffer| {
            _ = back_buffer.IUnknown.Release();
        }
    }

    pub fn cleanupDeviceD3D(self: *DxContext) void {
        self.cleanupRenderTarget();
        if (self.swap_chain) |swap_chain| {
            _ = swap_chain.IUnknown.Release();
        }
        if (self.device_context) |device_context| {
            _ = device_context.IUnknown.Release();
        }
        if (self.device) |device| {
            _ = device.IUnknown.Release();
        }
    }

    pub fn cleanupRenderTarget(self: *DxContext) void {
        if (self.main_render_target_view) |main_render_target_view| {
            _ = main_render_target_view.IUnknown.Release();
            self.main_render_target_view = null;
        }
    }

    pub fn deinit(self: *DxContext) void {
        self.cleanupDeviceD3D();
        _ = win32.DestroyWindow(self.hwnd);
    }
};

pub const WwiseContext = struct {
    io_hook: ?*AK.IOHooks.CAkFilePackageLowLevelIODeferred = null,
    init_bank_id: AK.AkBankID = 0,
    memory_settings: AK.AkMemSettings = .{},
    stream_mgr_settings: AK.StreamMgr.AkStreamMgrSettings = .{},
    device_settings: AK.StreamMgr.AkDeviceSettings = .{},
    init_settings: AK.AkInitSettings = .{},
    platform_init_settings: AK.AkPlatformInitSettings = .{},
    music_settings: AK.MusicEngine.AkMusicSettings = .{},
    comm_settings: if (AK.Comm != void) AK.Comm.AkCommSettings else void = .{},
    job_worker_settings: if (AK.JobWorkerMgr != void) AK.JobWorkerMgr.InitSettings else void = .{},
    spatial_audio_settings: if (AK.SpatialAudio != void) AK.SpatialAudio.AkSpatialAudioInitSettings else void = .{},
};

pub const SdlContext = struct {
    window: *c.SDL_Window = undefined,
    gpu_device: *c.SDL_GPUDevice = undefined,
};

pub const DemoState = struct {
    graphics_context: DxContext = .{},
    wwise_context: WwiseContext = .{},
    sdl_context: SdlContext = .{},
    main_allocator: std.heap.ThreadSafeAllocator = undefined,
    current_demo: DemoInterface = undefined,
    show_resource_monitor: bool = false,
};

var current_resource_monitor_data: AK.AkResourceMonitorDataSummary = .{};

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

pub const ListenerGameObjectID: AK.AkGameObjectID = 1;

fn setupZGUI(allocator: std.mem.Allocator, demo: *DemoState) !void {
    _ = demo; // autofix
    zgui.init(allocator);

    // if (!demo.graphics_context.createDeviceD3D()) {
    //     return error.D3D11CreationFailed;
    // }

    // zgui.backend.init(
    //     demo.graphics_context.hwnd,
    //     demo.graphics_context.device,
    //     demo.graphics_context.device_context,
    // );
}

fn getDefaultWwiseSettings(allocator: std.mem.Allocator, demo: *DemoState) !void {
    var wwise_context = &demo.wwise_context;

    AK.MemoryMgr.getDefaultSettings(&wwise_context.memory_settings);

    AK.StreamMgr.getDefaultSettings(&wwise_context.stream_mgr_settings);

    AK.StreamMgr.getDefaultDeviceSettings(&wwise_context.device_settings);

    try AK.SoundEngine.getDefaultInitSettings(allocator, &wwise_context.init_settings);

    AK.SoundEngine.getDefaultPlatformInitSettings(&wwise_context.platform_init_settings);

    AK.MusicEngine.getDefaultInitSettings(&wwise_context.music_settings);

    // Setup communication for debugging with the Wwise Authoring
    if (AK.Comm != void) {
        try AK.Comm.getDefaultInitSettings(&wwise_context.comm_settings);
    }

    if (AK.JobWorkerMgr != void) {
        AK.JobWorkerMgr.getDefaultInitSettings(&wwise_context.job_worker_settings);

        const max_workers = blk: {
            const runtime_cpu_count = std.Thread.getCpuCount() catch {
                break :blk @as(usize, MaxThreadWorkers);
            };

            break :blk @min(runtime_cpu_count, MaxThreadWorkers);
        };
        wwise_context.job_worker_settings.num_worker_threads = @intCast(max_workers);

        wwise_context.init_settings.settings_job_manager = wwise_context.job_worker_settings.getJobMgrSettings();

        for (0..AK.AK_NUM_JOB_TYPES) |index| {
            wwise_context.init_settings.settings_job_manager.max_active_workers[index] = 2;
        }
    }
}

pub fn initWwise(allocator: std.mem.Allocator, demo: *DemoState) !void {
    // Create memory manager
    try AK.MemoryMgr.init(&demo.wwise_context.memory_settings);

    // Create streaming manager
    _ = AK.StreamMgr.create(&demo.wwise_context.stream_mgr_settings);

    // Create the I/O hook using default FilePackage blocking I/O Hook
    var io_hook = try AK.IOHooks.CAkFilePackageLowLevelIODeferred.create(allocator);
    try io_hook.init(&demo.wwise_context.device_settings);
    demo.wwise_context.io_hook = io_hook;

    // Gather init settings and init the sound engine
    try AK.SoundEngine.init(allocator, &demo.wwise_context.init_settings, &demo.wwise_context.platform_init_settings);

    try AK.MusicEngine.init(&demo.wwise_context.music_settings);

    // Setup communication for debugging with the Wwise Authoring
    if (AK.Comm != void) {
        demo.wwise_context.comm_settings.setAppNetworkName("wwise-zig Integration Demo");

        try AK.Comm.init(&demo.wwise_context.comm_settings);
    }

    if (AK.JobWorkerMgr != void and demo.wwise_context.job_worker_settings.num_worker_threads > 0) {
        try AK.JobWorkerMgr.initWorkers(&demo.wwise_context.job_worker_settings);
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
    demo.wwise_context.init_bank_id = try AK.SoundEngine.loadBankString(allocator, "Init.bnk", .{});

    // Init microphone
    try AK.SoundEngine.registerGameObjWithName(allocator, ListenerGameObjectID, "Listener");
    try AK.SoundEngine.setDefaultListeners(&.{ListenerGameObjectID});

    // Register monitor callback
    try AK.SoundEngine.registerResourceMonitorCallback(resourceMonitorCallback);

    // Register spatial audio
    try AK.SpatialAudio.init(&demo.wwise_context.spatial_audio_settings);
    // TODO: Setup monitor local output
}

pub fn destroyWwise(allocator: std.mem.Allocator, demo: *DemoState) !void {
    try AK.SoundEngine.unregisterResourceMonitorCallback(resourceMonitorCallback);

    try AK.SoundEngine.unregisterGameObj(ListenerGameObjectID);

    // try AK.SoundEngine.unloadBankID(demo.wwise_context.init_bank_id, null, .{});

    if (AK.Comm != void) {
        AK.Comm.term();
    }

    if (AK.SoundEngine.isInitialized()) {
        AK.SoundEngine.term();
    }

    if (AK.JobWorkerMgr != void and demo.wwise_context.job_worker_settings.num_worker_threads > 0) {
        AK.JobWorkerMgr.termWorkers();
    }

    if (demo.wwise_context.io_hook) |io_hook| {
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

fn resourceMonitorCallback(in_data_summary: ?*const AK.AkResourceMonitorDataSummary) callconv(.C) void {
    if (in_data_summary) |data_summary| {
        current_resource_monitor_data = data_summary.*;
    }
}

fn destroy(demo: *DemoState) void {
    zgui.backend.deinit();
    zgui.deinit();
    demo.graphics_context.deinit();
    demo.current_demo.deinit(demo);
}

fn createMenu(comptime menu_data: MenuData, allocator: std.mem.Allocator, demo: *DemoState) !void {
    switch (menu_data) {
        .demo => |demo_entry| {
            if (zgui.menuItem(demo_entry.name, .{})) {
                demo.current_demo.deinit(demo);

                var new_demo_instance = try allocator.create(demo_entry.instance_type);
                demo.current_demo = new_demo_instance.demoInterface();
                try demo.current_demo.init(allocator, demo);
                demo.current_demo.show();
            }
        },
        .menu => |menu| {
            if (zgui.beginMenu(menu.name, true)) {
                inline for (menu.entries) |menu_entry| {
                    try createMenu(menu_entry, allocator, demo);
                }

                zgui.endMenu();
            }
        },
    }
}

fn update(allocator: std.mem.Allocator, demo: *DemoState) !void {
    var width: u32 = 1920;
    var height: u32 = 1080;

    if (demo.graphics_context.swap_chain) |swap_chain| {
        var desc: dxgi.DXGI_SWAP_CHAIN_DESC = undefined;

        _ = swap_chain.GetDesc(&desc);

        width = desc.BufferDesc.Width;
        height = desc.BufferDesc.Height;
    }

    zgui.backend.newFrame(width, height);

    if (zgui.beginMainMenuBar()) {
        inline for (AllMenus) |menu_data| {
            try createMenu(menu_data, allocator, demo);
        }

        if (zgui.menuItem("Resource Monitor", .{ .selected = demo.show_resource_monitor })) {
            demo.show_resource_monitor = !demo.show_resource_monitor;
        }

        zgui.endMainMenuBar();
    }

    if (demo.show_resource_monitor) {
        if (zgui.begin("Resource Monitor", .{ .flags = .{ .always_auto_resize = true } })) {
            zgui.text("Total CPU: {d:3.6}", .{current_resource_monitor_data.total_cpu});
            zgui.text("Plugin CPU: {d:3.6}", .{current_resource_monitor_data.plugin_cpu});
            zgui.text("Virtual Voices: {}", .{current_resource_monitor_data.physical_voices});
            zgui.text("Physical Voices: {}", .{current_resource_monitor_data.virtual_voices});
            zgui.text("Total Voices: {}", .{current_resource_monitor_data.total_voices});
            zgui.text("Active events: {}", .{current_resource_monitor_data.nb_active_events});
            zgui.end();
        }
    }

    if (demo.current_demo.isVisible()) {
        try demo.current_demo.onUI(demo);
    }
}

fn draw(demo: *DemoState) void {
    const graphics_context = demo.graphics_context;

    const clear_color = [_]f32{
        0.0,
        0.0,
        0.0,
        1.00,
    };

    if (graphics_context.device_context) |device_context| {
        _ = device_context.OMSetRenderTargets(1, @ptrCast(@constCast(&graphics_context.main_render_target_view)), null);
        _ = device_context.ClearRenderTargetView(graphics_context.main_render_target_view, @ptrCast(&clear_color));
    }

    zgui.backend.draw();

    if (graphics_context.swap_chain) |swap_chain| {
        _ = swap_chain.Present(1, 0);
    }
}

// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();

//     const allocator = gpa.allocator();

//     const demo = try allocator.create(DemoState);
//     demo.* = .{};
//     defer allocator.destroy(demo);

//     var null_demo_instance = try allocator.create(NullDemo);
//     try null_demo_instance.init(allocator, demo);

//     demo.current_demo = null_demo_instance.demoInterface();

//     const win_class: win32.WNDCLASSEXW = .{
//         .cbSize = @sizeOf(win32.WNDCLASSEXW),
//         .style = win32.CS_CLASSDC,
//         .lpfnWndProc = WndProc,
//         .cbClsExtra = 0,
//         .cbWndExtra = 0,
//         .hInstance = win32.GetModuleHandleW(null),
//         .hIcon = null,
//         .hCursor = null,
//         .hbrBackground = null,
//         .lpszMenuName = null,
//         .lpszClassName = L("wwise-zig-demo"),
//         .hIconSm = null,
//     };

//     _ = win32.RegisterClassExW(&win_class);
//     defer _ = win32.UnregisterClassW(win_class.lpszClassName, win_class.hInstance);

//     const hwnd = win32.CreateWindowExW(
//         .{},
//         win_class.lpszClassName,
//         L("wwise-zig Integration Demo"),
//         win32.WS_OVERLAPPEDWINDOW,
//         0,
//         0,
//         1920,
//         1080,
//         null,
//         null,
//         win_class.hInstance,
//         demo,
//     );

//     if (hwnd == null) {
//         std.log.warn("Error creating Win32 Window = 0x{x}\n", .{@intFromEnum(win32.GetLastError())});
//         return error.InvalidWin32Window;
//     }

//     demo.graphics_context.hwnd = hwnd;

//     _ = win32.ShowWindow(hwnd, win32.SW_SHOWDEFAULT);
//     _ = win32.UpdateWindow(hwnd);

//     try getDefaultWwiseSettings(allocator, demo);
//     try initWwise(allocator, demo);
//     defer {
//         destroyWwise(allocator, demo) catch unreachable;
//     }

//     try setupZGUI(allocator, demo);
//     defer destroy(demo);

//     var msg: win32.MSG = std.mem.zeroes(win32.MSG);
//     while (msg.message != win32.WM_QUIT) {
//         if (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
//             _ = win32.TranslateMessage(&msg);
//             _ = win32.DispatchMessageW(&msg);
//             continue;
//         }

//         try update(allocator, demo);
//         draw(demo);

//         try AK.SoundEngine.renderAudio(false);
//     }
// }

fn sdlAppInit(app_state: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
    _ = argv; // autofix

    const demo = try std.heap.smp_allocator.create(DemoState);
    demo.* = .{};
    demo.main_allocator = .{
        .child_allocator = std.heap.smp_allocator,
    };

    app_state.?.* = demo;

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

    _ = c.SDL_SetGPUSwapchainParameters(demo.sdl_context.gpu_device, demo.sdl_context.window, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.SDL_GPU_PRESENTMODE_MAILBOX);

    zgui.init(demo.main_allocator.allocator());

    zgui.backend.init(demo.sdl_context.window, .{
        .device = demo.sdl_context.gpu_device,
        .color_target_format = @intCast(c.SDL_GetGPUSwapchainTextureFormat(demo.sdl_context.gpu_device, demo.sdl_context.window)),
        .msaa_samples = c.SDL_GPU_SAMPLECOUNT_1,
    });

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(app_state: ?*anyopaque) !c.SDL_AppResult {
    const demo: *DemoState = @alignCast(@ptrCast(app_state.?));

    zgui.backend.newFrame(1920.0, 1080.0, 1.0);

    zgui.showDemoWindow(null);

    zgui.backend.render();

    const command_buffer = try errify(c.SDL_AcquireGPUCommandBuffer(demo.sdl_context.gpu_device));

    var swapchain_texture_opt: ?*c.SDL_GPUTexture = null;
    try errify(c.SDL_AcquireGPUSwapchainTexture(command_buffer, demo.sdl_context.window, &swapchain_texture_opt, null, null));
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

    const demo: *DemoState = @alignCast(@ptrCast(app_state.?));

    _ = c.SDL_WaitForGPUIdle(demo.sdl_context.gpu_device);

    zgui.backend.deinit();
    zgui.deinit();

    c.SDL_ReleaseWindowFromGPUDevice(demo.sdl_context.gpu_device, demo.sdl_context.window);
    c.SDL_DestroyGPUDevice(demo.sdl_context.gpu_device);

    c.SDL_DestroyWindow(demo.sdl_context.window);

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
