const std = @import("std");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zgpu = @import("zgpu");
const DemoInterface = @import("DemoInterface.zig");
const NullDemo = @import("demos/NullDemo.zig");

const DemoState = struct {
    graphics_context: *zgpu.GraphicsContext,
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
            .entries = &.{},
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

fn setup(allocator: std.mem.Allocator, window: *zglfw.Window) !*DemoState {
    const graphics_context = try zgpu.GraphicsContext.create(allocator, window);

    zgui.init(allocator);

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor std.math.max(scale[0], scale[1]);
    };

    zgui.backend.initWithConfig(
        window,
        graphics_context.device,
        @enumToInt(zgpu.GraphicsContext.swapchain_format),
        .{
            .texture_filter_mode = .linear,
            .pipeline_multisample_count = 1,
        },
    );

    const style = zgui.getStyle();
    style.scaleAllSizes(scale_factor);

    var null_demo_instance = try allocator.create(NullDemo);
    try null_demo_instance.init(allocator);

    const demo = try allocator.create(DemoState);
    demo.* = .{
        .graphics_context = graphics_context,
        .current_demo = null_demo_instance.demoInterface(),
    };
    return demo;
}

fn destroy(allocator: std.mem.Allocator, demo: *DemoState) void {
    zgui.backend.deinit();
    zgui.deinit();
    demo.graphics_context.destroy(allocator);
    demo.current_demo.deinit();
    allocator.destroy(demo);
}

const Languages = &[_][:0]const u8{ "English(US)", "French(Canada)" };

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
    zgui.backend.newFrame(
        demo.graphics_context.swapchain_descriptor.width,
        demo.graphics_context.swapchain_descriptor.height,
    );

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

    const swapchain_texture_view = graphics_context.swapchain.getCurrentTextureView();
    defer swapchain_texture_view.release();

    const commands = commands: {
        const encoder = graphics_context.device.createCommandEncoder(null);
        defer encoder.release();

        {
            const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texture_view, null, null, null);
            defer zgpu.endReleasePass(pass);
            zgui.backend.draw(pass);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    graphics_context.submit(&.{commands});
    _ = graphics_context.present();
}

pub fn main() !void {
    zglfw.init() catch {
        std.log.err("Failed to initialize GLFW library.", .{});
        return;
    };
    defer zglfw.terminate();

    const window = zglfw.Window.create(1920, 1080, "wwise-zig Demo", null) catch {
        std.log.err("Failed to create demo window", .{});
        return;
    };
    defer window.destroy();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const demo = try setup(allocator, window);
    defer destroy(allocator, demo);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        try update(allocator, demo);
        draw(demo);
    }
}
