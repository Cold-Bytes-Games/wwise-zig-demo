const gui = @import("gui.zig");
const std = @import("std");
const win32 = std.os.windows;

pub fn init(window: ?*anyopaque, device: ?*anyopaque, device_context: ?*anyopaque) void {
    _ = ImGui_ImplWin32_Init(window);
    _ = ImGui_ImplDX11_Init(device, device_context);
}

pub fn deinit() void {
    ImGui_ImplDX11_Shutdown();
    ImGui_ImplWin32_Shutdown();
}

pub fn newFrame(fb_width: u32, fb_height: u32) void {
    ImGui_ImplDX11_NewFrame();
    ImGui_ImplWin32_NewFrame();

    gui.io.setDisplaySize(@as(f32, @floatFromInt(fb_width)), @as(f32, @floatFromInt(fb_height)));
    gui.io.setDisplayFramebufferScale(1.0, 1.0);

    gui.newFrame();
}

pub fn draw() void {
    gui.render();
    _ = ImGui_ImplDX11_RenderDrawData(gui.getDrawData());
}

pub fn wndProcHandler(hWnd: ?*anyopaque, msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) win32.LRESULT {
    return ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam);
}

// Those functions are defined in `imgui_impl_win32.cpp` and 'imgui_impl_dx11.cpp`

extern fn ImGui_ImplWin32_Init(hwnd: ?*anyopaque) bool;
extern fn ImGui_ImplWin32_Shutdown() void;
extern fn ImGui_ImplWin32_NewFrame() void;

extern fn ImGui_ImplWin32_WndProcHandler(hWnd: ?*anyopaque, msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) win32.LRESULT;

extern fn ImGui_ImplWin32_EnableDpiAwareness() void;
extern fn ImGui_ImplWin32_GetDpiScaleForHwnd(hwnd: ?*anyopaque) f32;
extern fn ImGui_ImplWin32_GetDpiScaleForMonitor(hmonitor: ?*anyopaque) f32;

extern fn ImGui_ImplWin32_EnableAlphaCompositing(hwnd: ?*anyopaque) void;

extern fn ImGui_ImplDX11_Init(device: ?*anyopaque, device_context: ?*anyopaque) bool;
extern fn ImGui_ImplDX11_Shutdown() void;
extern fn ImGui_ImplDX11_NewFrame() void;
extern fn ImGui_ImplDX11_RenderDrawData(draw_data: *const anyopaque) void;

extern fn ImGui_ImplDX11_InvalidateDeviceObjects() void;
extern fn ImGui_ImplDX11_CreateDeviceObjects() bool;
