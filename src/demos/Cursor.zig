const std = @import("std");
const zgui = @import("zgui");

x: f32 = 0.0,
y: f32 = 0.0,
max_speed: f32 = DefaultMaxSpeed,
color: [4]f32 = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
is_first_update: bool = true,
label: []const u8 = "O",

const Self = @This();

const DefaultMaxSpeed = 5.0;
pub const Margin = 15.0;

pub fn update(self: *Self) void {
    const window_size = zgui.getContentRegionAvail();

    if (self.is_first_update) {
        self.x = (window_size[0] - Margin) / 2.0;
        self.y = (window_size[1] - Margin) / 2.0;
        self.is_first_update = false;
    }

    if (zgui.isKeyDown(.up_arrow)) {
        self.y -= self.max_speed;
    } else if (zgui.isKeyDown(.down_arrow)) {
        self.y += self.max_speed;
    } else if (zgui.isKeyDown(.left_arrow)) {
        self.x -= self.max_speed;
    } else if (zgui.isKeyDown(.right_arrow)) {
        self.x += self.max_speed;
    }

    if (self.x >= window_size[0] - Margin) {
        self.x = window_size[0] - Margin;
    }

    if (self.y >= window_size[1] - Margin) {
        self.y = window_size[1] - Margin;
    }

    if (self.x < 0) {
        self.x = 0;
    }

    if (self.y < 0) {
        self.y = 0;
    }
}

pub fn draw(self: *const Self, draw_list: zgui.DrawList) void {
    const window_pos = zgui.getCursorScreenPos();
    const zgui_color = zgui.colorConvertFloat4ToU32(self.color);

    draw_list.addTextUnformatted(
        [2]f32{ window_pos[0] + self.x, window_pos[1] + self.y },
        zgui_color,
        self.label,
    );
}
