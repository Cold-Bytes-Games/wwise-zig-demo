const std = @import("std");
const zgui = @import("zgui");

start_x: f32 = 0,
start_y: f32 = 0,
end_x: f32 = 0,
end_y: f32 = 0,
color: [4]f32 = [4]f32{ 1.0, 1.0, 1.0, 1.0 },

const Self = @This();

pub fn draw(self: *const Self, draw_list: zgui.DrawList) void {
    const window_pos = zgui.getCursorScreenPos();
    const zgui_color = zgui.colorConvertFloat4ToU32(self.color);

    draw_list.addLine(.{
        .p1 = [2]f32{ window_pos[0] + self.start_x, window_pos[1] + self.start_y },
        .p2 = [2]f32{ window_pos[0] + self.end_x, window_pos[1] + self.end_y },
        .thickness = 1.0,
        .col = zgui_color,
    });
}
