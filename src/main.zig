const std = @import("std");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zgpu = @import("zgpu");

const DemoState = struct {
    graphics_context: *zgpu.GraphicsContext,
    is_selected: bool = false,
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

    const demo = try allocator.create(DemoState);
    demo.* = .{
        .graphics_context = graphics_context,
    };
    return demo;
}

fn destroy(allocator: std.mem.Allocator, demo: *DemoState) void {
    zgui.backend.deinit();
    zgui.deinit();
    demo.graphics_context.destroy(allocator);
    allocator.destroy(demo);
}

const Languages = &[_][:0]const u8{ "English(US)", "French(Canada)" };

fn update(demo: *DemoState) void {
    zgui.backend.newFrame(
        demo.graphics_context.swapchain_descriptor.width,
        demo.graphics_context.swapchain_descriptor.height,
    );

    if (zgui.beginMainMenuBar()) {
        if (zgui.beginMenu("Dialogue demos", true)) {
            _ = zgui.menuItemPtr("Localization Demo", .{ .selected = &demo.is_selected });
            zgui.endMenu();
        }

        zgui.endMainMenuBar();
    }

    if (demo.is_selected) {
        if (zgui.begin("Localization Demo", .{ .flags = .{ .always_auto_resize = true } })) {
            if (zgui.button("Say \"Hello\"", .{})) {}

            if (zgui.beginCombo("Language", .{ .preview_value = Languages[0] })) {
                for (Languages, 0..) |lang, i| {
                    const is_selected = i == 0;
                    if (zgui.selectable(lang, .{ .selected = is_selected })) {}
                }

                zgui.endCombo();
            }

            zgui.end();
        }
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
        update(demo);
        draw(demo);
    }
}
