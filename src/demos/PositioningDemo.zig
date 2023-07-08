const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");
const Cursor = @import("Cursor.zig");
const ID = @import("../ID.zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
cursor: Cursor = .{},
game_object_x: f32 = 0.0,
game_object_z: f32 = 0.0,
width: f32 = 0.0,
height: f32 = 0.0,
is_first_update: bool = true,

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 100;
const PositionRange: f32 = 200.0;

const PositionOffset = AK.AkVector64{
    .x = 20000000.0,
    .y = 30000000.0,
    .z = 40000000.0,
};

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
        .cursor = .{},
    };

    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Helicopter");

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "Positioning_Demo", .{});

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_POSITIONING_DEMO, DemoGameObjectID, .{});

    const shifted_pos = AK.AkSoundPosition{
        .position = PositionOffset,
        .orientation_front = .{
            .z = 1.0,
        },
        .orientation_top = .{
            .y = 1.0,
        },
    };
    try AK.SoundEngine.setPosition(root.ListenerGameObjectID, shifted_pos, .{});
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    const neutral_pos = AK.AkSoundPosition{
        .position = .{},
        .orientation_front = .{
            .z = 1.0,
        },
        .orientation_top = .{
            .y = 1.0,
        },
    };
    AK.SoundEngine.setPosition(root.ListenerGameObjectID, neutral_pos, .{}) catch {};

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;

    zgui.setNextWindowSize(.{
        .w = 640,
        .h = 480,
        .cond = .first_use_ever,
    });

    if (zgui.begin("Positioning Demo", .{ .popen = &self.is_visible, .flags = .{} })) {
        const window_size = zgui.getContentRegionAvail();

        if (self.is_first_update) {
            self.width = window_size[0] - Cursor.Margin;
            self.height = window_size[1] - Cursor.Margin;
            self.is_first_update = false;
        }

        self.cursor.update();
        try self.updateGameObjectPos();

        zgui.text("X: {d:.2}", .{self.game_object_x});
        zgui.text("Z: {d:.2}", .{self.game_object_z});

        var draw_list = zgui.getWindowDrawList();

        const white_color = zgui.colorConvertFloat4ToU32([4]f32{ 1.0, 1.0, 1.0, 1.0 });

        const window_pos = zgui.getCursorScreenPos();

        draw_list.addRect(.{
            .pmin = window_pos,
            .pmax = [2]f32{ window_pos[0] + window_size[0] - Cursor.Margin, window_pos[1] + window_size[1] - Cursor.Margin },
            .col = white_color,
        });

        self.cursor.draw(draw_list);

        zgui.end();
    }

    if (!self.is_visible) {
        AK.SoundEngine.stopAll(.{ .game_object_id = DemoGameObjectID });
    }
}

pub fn isVisible(self: *Self) bool {
    return self.is_visible;
}

pub fn show(self: *Self) void {
    self.is_visible = true;
}

pub fn demoInterface(self: *Self) DemoInterface {
    return DemoInterface.toDemoInteface(self);
}

fn pixelsToAkPosX(self: Self, in_x: f32) f32 {
    return ((in_x / self.width) - 0.5) * PositionRange;
}

fn pixelsToAkPosY(self: Self, in_y: f32) f32 {
    return ((in_y / self.height) - 0.5) * PositionRange;
}

fn updateGameObjectPos(self: *Self) !void {
    const x = self.cursor.x;
    const y = self.cursor.y;

    self.game_object_x = self.pixelsToAkPosX(x);
    self.game_object_z = self.pixelsToAkPosY(y);

    var sound_position = AK.AkSoundPosition{
        .position = .{
            .x = self.game_object_x,
            .z = self.game_object_z,
        },
        .orientation_front = .{
            .z = 1.0,
        },
        .orientation_top = .{
            .y = 1.0,
        },
    };

    sound_position.position = .{
        .x = sound_position.position.x + PositionOffset.x,
        .y = sound_position.position.y + PositionOffset.y,
        .z = sound_position.position.z + PositionOffset.z,
    };

    try AK.SoundEngine.setPosition(DemoGameObjectID, sound_position, .{});
}
