const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");
const Cursor = @import("Cursor.zig");
const ID = @import("wwise-ids");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
emitter_cursor: Cursor = .{},
listener_cursor: Cursor = .{},
game_object_x: f32 = 0.0,
game_object_z: f32 = 0.0,
width: f32 = 0.0,
height: f32 = 0.0,
repeat: u8 = 0,
is_looping: bool = false,
is_first_update: bool = true,

const Self = @This();

const EmitterObj: AK.AkGameObjectID = 100;
const ListenerObj: AK.AkGameObjectID = 103;
const RepeatTime: u8 = 20;
const PositionRange: f32 = 200.0;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
        .emitter_cursor = .{
            .label = "<E>",
        },
        .listener_cursor = .{
            .label = "<L>",
        },
    };

    try AK.SoundEngine.registerGameObjWithName(allocator, EmitterObj, "Emitter");
    try AK.SoundEngine.registerGameObjWithName(allocator, ListenerObj, "Listener");

    try AK.SoundEngine.setListeners(EmitterObj, &.{ListenerObj});

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "Bus3d_Demo.bnk", .{});

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_CLUSTER, EmitterObj, .{});
    self.is_looping = true;
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    AK.SoundEngine.unregisterGameObj(ListenerObj) catch {};
    AK.SoundEngine.unregisterGameObj(EmitterObj) catch {};

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;

    zgui.setNextWindowSize(.{
        .w = 640,
        .h = 480,
        .cond = .first_use_ever,
    });

    if (zgui.begin("3d Bus - Clustering/3D Submix", .{ .popen = &self.is_visible, .flags = .{} })) {
        if (zgui.button("Play Chirp", .{})) {
            if (self.repeat == 0) {
                _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_CHIRP, EmitterObj, .{});
                self.repeat = RepeatTime;
            }
        }

        if (zgui.button(if (self.is_looping) "Stop Cluster" else "Play Cluster", .{})) {
            if (self.repeat == 0) {
                if (!self.is_looping) {
                    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_CLUSTER, EmitterObj, .{});
                } else {
                    _ = try AK.SoundEngine.postEventID(ID.EVENTS.STOP_CLUSTER, EmitterObj, .{});
                }

                self.is_looping = !self.is_looping;
                self.repeat = RepeatTime;
            }
        }

        if (self.repeat > 0) {
            self.repeat -= 1;
        }

        const window_size = zgui.getContentRegionAvail();

        if (self.is_first_update) {
            self.width = window_size[0] - Cursor.Margin;
            self.height = window_size[1] - Cursor.Margin;
            self.is_first_update = false;

            self.listener_cursor.update();
            self.emitter_cursor.update();

            self.emitter_cursor.x -= 30.0;
            self.listener_cursor.x += 30.0;
        }

        if (zgui.isKeyDown(.mod_shift)) {
            self.listener_cursor.update();
            try self.updateGameObjectPos(self.listener_cursor, ListenerObj);
        } else {
            self.emitter_cursor.update();
            try self.updateGameObjectPos(self.emitter_cursor, EmitterObj);
        }

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

        self.emitter_cursor.draw(draw_list);
        self.listener_cursor.draw(draw_list);

        zgui.end();
    }

    if (!self.is_visible) {
        AK.SoundEngine.stopAll(.{});
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
    return -((in_y / self.height) - 0.5) * PositionRange;
}

fn updateGameObjectPos(self: *Self, in_cursor: Cursor, in_game_object_id: AK.AkGameObjectID) !void {
    const x = in_cursor.x;
    const y = in_cursor.y;

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

    try AK.SoundEngine.setPosition(in_game_object_id, sound_position, .{});
}
