const std = @import("std");
const d3d11 = zigwin32.graphics.direct3d11;
const d3d = zigwin32.graphics.direct3d;
const dxgi = zigwin32.graphics.dxgi;
const win32 = zigwin32.everything;
const zgui = @import("zgui");
const zigwin32 = @import("zigwin32");
const AK = @import("wwise-zig");

const L = std.unicode.utf8ToUtf16LeStringLiteral;

const DemoInterface = @import("DemoInterface.zig");
const NullDemo = @import("demos/NullDemo.zig");

const DxContext = struct {
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
        sd.Flags = @enumToInt(dxgi.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH);
        sd.BufferUsage = dxgi.DXGI_USAGE_RENDER_TARGET_OUTPUT;
        sd.OutputWindow = self.hwnd;
        sd.SampleDesc.Count = 1;
        sd.SampleDesc.Quality = 0;
        sd.Windowed = @boolToInt(true);
        sd.SwapEffect = .DISCARD;

        var feature_level: d3d.D3D_FEATURE_LEVEL = undefined;
        const feature_level_array = &[_]d3d.D3D_FEATURE_LEVEL{
            .@"11_0",
            .@"10_0",
        };
        if (d3d11.D3D11CreateDeviceAndSwapChain(null, .HARDWARE, null, d3d11.D3D11_CREATE_DEVICE_FLAG.initFlags(.{}), feature_level_array, 2, d3d11.D3D11_SDK_VERSION, &sd, &self.swap_chain, &self.device, &feature_level, &self.device_context) != win32.S_OK) {
            return false;
        }

        self.createRenderTarget();

        return true;
    }

    pub fn createRenderTarget(self: *DxContext) void {
        var back_buffer_opt: ?*d3d11.ID3D11Texture2D = null;
        if (self.swap_chain) |swap_chain| {
            _ = swap_chain.IDXGISwapChain_GetBuffer(0, d3d11.IID_ID3D11Texture2D, @ptrCast(?*?*anyopaque, &back_buffer_opt));
        }
        if (self.device) |device| {
            _ = device.ID3D11Device_CreateRenderTargetView(@ptrCast(?*d3d11.ID3D11Resource, back_buffer_opt), null, @ptrCast(?*?*d3d11.ID3D11RenderTargetView, &self.main_render_target_view));
        }
        if (back_buffer_opt) |back_buffer| {
            _ = back_buffer.IUnknown_Release();
        }
    }

    pub fn cleanupDeviceD3D(self: *DxContext) void {
        self.cleanupRenderTarget();
        if (self.swap_chain) |swap_chain| {
            _ = swap_chain.IUnknown_Release();
        }
        if (self.device_context) |device_context| {
            _ = device_context.IUnknown_Release();
        }
        if (self.device) |device| {
            _ = device.IUnknown_Release();
        }
    }

    pub fn cleanupRenderTarget(self: *DxContext) void {
        if (self.main_render_target_view) |main_render_target_view| {
            _ = main_render_target_view.IUnknown_Release();
            self.main_render_target_view = null;
        }
    }

    pub fn deinit(self: *DxContext) void {
        self.cleanupDeviceD3D();
        _ = win32.DestroyWindow(self.hwnd);
    }
};

const WwiseContext = struct {
    io_hook: ?*AK.IOHooks.CAkFilePackageLowLevelIOBlocking = null,
    init_bank_id: AK.AkBankID = 0,
};

const DemoState = struct {
    graphics_context: DxContext = .{},
    wwise_context: WwiseContext = .{},
    is_selected: bool = false,
    current_demo: DemoInterface = undefined,
};

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
            },
        },
    },
    .{
        .demo = .{
            .name = "Interactive Music Demo",
            .instance_type = NullDemo,
        },
    },
    .{
        .demo = .{
            .name = "MIDI API Demo (Metronome)",
            .instance_type = NullDemo,
        },
    },
    .{
        .demo = .{
            .name = "Microphone Demo",
            .instance_type = NullDemo,
        },
    },
    .{
        .menu = .{
            .name = "Positioning Demo",
            .entries = &.{},
        },
    },
    .{
        .menu = .{
            .name = "Bank & Event Loading Demo",
            .entries = &.{},
        },
    },
    .{
        .demo = .{
            .name = "Background Music/DVR Demo",
            .instance_type = NullDemo,
        },
    },
    .{
        .demo = .{
            .name = "Options",
            .instance_type = NullDemo,
        },
    },
};

pub const ListenerGameObjectID: AK.AkGameObjectID = 1;

fn setupZGUI(allocator: std.mem.Allocator, demo: *DemoState) !void {
    zgui.init(allocator);

    if (!demo.graphics_context.createDeviceD3D()) {
        return error.D3D11CreationFailed;
    }

    zgui.backend.init(
        demo.graphics_context.hwnd,
        demo.graphics_context.device,
        demo.graphics_context.device_context,
    );
}

fn setupWwise(allocator: std.mem.Allocator, demo: *DemoState) !void {
    // Create memory manager
    var memory_settings: AK.AkMemSettings = .{};
    AK.MemoryMgr.getDefaultSettings(&memory_settings);
    try AK.MemoryMgr.init(&memory_settings);

    // Create streaming manager
    var stream_settings: AK.StreamMgr.AkStreamMgrSettings = .{};
    AK.StreamMgr.getDefaultSettings(&stream_settings);
    _ = AK.StreamMgr.create(&stream_settings);

    var device_settings: AK.StreamMgr.AkDeviceSettings = .{};
    AK.StreamMgr.getDefaultDeviceSettings(&device_settings);

    // Create the I/O hook using default FilePackage blocking I/O Hook
    var io_hook = try AK.IOHooks.CAkFilePackageLowLevelIOBlocking.create(allocator);
    try io_hook.init(&device_settings, false);
    demo.wwise_context.io_hook = io_hook;

    // Gather init settings and init the sound engine
    var init_settings: AK.AkInitSettings = .{};
    AK.SoundEngine.getDefaultInitSettings(&init_settings);

    var platform_init_settings: AK.AkPlatformInitSettings = .{};
    AK.SoundEngine.getDefaultPlatformInitSettings(&platform_init_settings);

    try AK.SoundEngine.init(allocator, &init_settings, &platform_init_settings);

    var music_init_settings: AK.MusicEngine.AkMusicSettings = .{};
    AK.MusicEngine.getDefaultInitSettings(&music_init_settings);
    try AK.MusicEngine.init(&music_init_settings);

    // Setup communication for debugging with the Wwise Authoring
    if (AK.Comm != void) {
        var comm_settings: AK.Comm.AkCommSettings = .{};
        try AK.Comm.getDefaultInitSettings(&comm_settings);

        comm_settings.setAppNetworkName("wwise-zig Integration Demo");

        try AK.Comm.init(&comm_settings);
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
}

fn destroyWwise(allocator: std.mem.Allocator, demo: *DemoState) !void {
    try AK.SoundEngine.unregisterGameObj(ListenerGameObjectID);

    // try AK.SoundEngine.unloadBankID(demo.wwise_context.init_bank_id, null, .{});

    if (AK.Comm != void) {
        AK.Comm.term();
    }

    AK.SoundEngine.term();

    if (demo.wwise_context.io_hook) |io_hook| {
        io_hook.term();

        io_hook.destroy(allocator);
    }

    AK.MemoryMgr.term();
}

fn destroy(demo: *DemoState) void {
    zgui.backend.deinit();
    zgui.deinit();
    demo.graphics_context.deinit();
    demo.current_demo.deinit();
}

fn createMenu(comptime menu_data: MenuData, allocator: std.mem.Allocator, demo: *DemoState) !void {
    switch (menu_data) {
        .demo => |demo_entry| {
            if (zgui.menuItem(demo_entry.name, .{})) {
                demo.current_demo.deinit();

                var new_demo_instance = try allocator.create(demo_entry.instance_type);
                demo.current_demo = new_demo_instance.demoInterface();
                try demo.current_demo.init(allocator);
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

        _ = swap_chain.IDXGISwapChain_GetDesc(&desc);

        width = desc.BufferDesc.Width;
        height = desc.BufferDesc.Height;
    }

    zgui.backend.newFrame(width, height);

    if (zgui.beginMainMenuBar()) {
        inline for (AllMenus) |menu_data| {
            try createMenu(menu_data, allocator, demo);
        }

        zgui.endMainMenuBar();
    }

    if (demo.current_demo.isVisible()) {
        try demo.current_demo.onUI();
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
        _ = device_context.ID3D11DeviceContext_OMSetRenderTargets(1, @ptrCast(?[*]?*d3d11.ID3D11RenderTargetView, @constCast(&graphics_context.main_render_target_view)), null);
        _ = device_context.ID3D11DeviceContext_ClearRenderTargetView(graphics_context.main_render_target_view, @ptrCast(*const f32, &clear_color));
    }

    zgui.backend.draw();

    if (graphics_context.swap_chain) |swap_chain| {
        _ = swap_chain.IDXGISwapChain_Present(1, 0);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var null_demo_instance = try allocator.create(NullDemo);
    try null_demo_instance.init(allocator);

    const demo = try allocator.create(DemoState);
    demo.* = .{
        .current_demo = null_demo_instance.demoInterface(),
    };
    defer allocator.destroy(demo);

    const win_class: win32.WNDCLASSEXW = .{
        .cbSize = @sizeOf(win32.WNDCLASSEXW),
        .style = win32.CS_CLASSDC,
        .lpfnWndProc = WndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = win32.GetModuleHandleW(null),
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = L("wwise-zig-demo"),
        .hIconSm = null,
    };

    _ = win32.RegisterClassExW(&win_class);
    defer _ = win32.UnregisterClassW(win_class.lpszClassName, win_class.hInstance);

    const hwnd = win32.CreateWindowExW(
        win32.WINDOW_EX_STYLE.initFlags(.{}),
        win_class.lpszClassName,
        L("wwise-zig Integration Demo"),
        win32.WS_OVERLAPPEDWINDOW,
        0,
        0,
        1920,
        1080,
        null,
        null,
        win_class.hInstance,
        demo,
    );

    if (hwnd == null) {
        std.log.warn("Error creating Win32 Window = 0x{x}\n", .{@enumToInt(win32.GetLastError())});
        return error.InvalidWin32Window;
    }

    demo.graphics_context.hwnd = hwnd;

    _ = win32.ShowWindow(hwnd, win32.SW_SHOWDEFAULT);
    _ = win32.UpdateWindow(hwnd);

    try setupWwise(allocator, demo);
    defer {
        destroyWwise(allocator, demo) catch unreachable;
    }

    try setupZGUI(allocator, demo);
    defer destroy(demo);

    var msg: win32.MSG = std.mem.zeroes(win32.MSG);
    while (msg.message != win32.WM_QUIT) {
        if (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);
            continue;
        }

        try update(allocator, demo);
        draw(demo);

        try AK.SoundEngine.renderAudio(false);
    }
}

pub fn WndProc(hWnd: win32.HWND, msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.C) win32.LRESULT {
    if (zgui.backend.wndProcHandler(hWnd, msg, wParam, lParam) != 0) {
        return 1;
    }

    var demo_opt: ?*DemoState = null;
    if (msg == win32.WM_NCCREATE) {
        const create_struct = @intToPtr(*win32.CREATESTRUCTW, @intCast(usize, lParam));

        demo_opt = @ptrCast(?*DemoState, @alignCast(@alignOf(*DemoState), create_struct.lpCreateParams));

        win32.SetLastError(win32.ERROR_SUCCESS);
        if (win32.SetWindowLongPtrW(hWnd, win32.GWL_USERDATA, @intCast(isize, @ptrToInt(demo_opt))) == 0) {
            if (win32.GetLastError() != win32.ERROR_SUCCESS)
                return 1;
        }
    } else {
        demo_opt = @intToPtr(?*DemoState, @intCast(usize, win32.GetWindowLongPtrW(hWnd, win32.GWL_USERDATA)));
    }

    switch (msg) {
        win32.WM_SIZE => {
            if (wParam != win32.SIZE_MINIMIZED) {
                if (demo_opt) |demo| {
                    if (demo.graphics_context.swap_chain) |swap_chain| {
                        demo.graphics_context.cleanupRenderTarget();
                        _ = swap_chain.IDXGISwapChain_ResizeBuffers(0, @intCast(u32, lParam) & 0xFFFF, (@intCast(u32, lParam) >> 16) & 0xFFFF, .UNKNOWN, 0);
                        demo.graphics_context.createRenderTarget();
                    }
                }
            }
            return 0;
        },
        win32.WM_SYSCOMMAND => {
            if ((wParam & 0xfff0) == win32.SC_KEYMENU) {
                return 0;
            }
        },
        win32.WM_DESTROY => {
            _ = win32.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }

    return win32.DefWindowProcW(hWnd, msg, wParam, lParam);
}

pub export fn WinMain(hInstance: ?win32.HINSTANCE, hPrevInstance: ?win32.HINSTANCE, lpCmdLine: ?std.os.windows.LPWSTR, nShowCmd: i32) i32 {
    _ = hInstance;
    _ = hPrevInstance;
    _ = lpCmdLine;
    _ = nShowCmd;

    main() catch unreachable;

    return 0;
}
