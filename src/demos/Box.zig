const std = @import("std");
const zgui = @import("zgui");

x: f32 = 0.0,
y: f32 = 0.0,
width: f32 = 0.0,
height: f32 = 0.0,
color: [4]f32 = [4]f32{ 1.0, 1.0, 1.0, 1.0 },

const Self = @This();

pub fn draw(self: *const Self, draw_list: zgui.DrawList) void {
    const window_pos = zgui.getCursorScreenPos();
    const zgui_color = zgui.colorConvertFloat4ToU32(self.color);

    draw_list.addRect(.{
        .pmin = [2]f32{ window_pos[0] + self.x, window_pos[1] + self.y },
        .pmax = [2]f32{ window_pos[0] + self.x + self.width, window_pos[1] + self.y + self.height },
        .col = zgui_color,
    });
}
