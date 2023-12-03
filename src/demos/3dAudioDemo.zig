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
cursor: Cursor = .{},
game_object_x: f32 = 0.0,
game_object_z: f32 = 0.0,
width: f32 = 0.0,
height: f32 = 0.0,
last_x: f32 = 0.0,
last_y: f32 = 0.0,
tick: i32 = 0,
last_footstep_tick: i32 = -1,
is_first_update: bool = true,
// Metering  info for the output device
mm_peaks: u32 = 0,
pt_peaks: u32 = 0,
obj_peaks: u32 = 0,
main_mix_peaks: [36]f32 = [_]f32{0} ** 36,
passthrough_peaks: [2]f32 = [_]f32{0} ** 2,
object_peaks: [20]f32 = [_]f32{0} ** 20,

const Self = @This();

const GameObjectAmbience: AK.AkGameObjectID = 100;
const GameObjectFootsteps: AK.AkGameObjectID = 101;
const PositionRange: f32 = 200.0;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
    };

    try AK.SoundEngine.registerGameObjWithName(allocator, GameObjectAmbience, "Ambience");
    try AK.SoundEngine.registerGameObjWithName(allocator, GameObjectFootsteps, "Footsteps");

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "ThreeD_Audio_Demo.bnk", .{});

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_3D_AUDIO_DEMO, GameObjectAmbience, .{});

    try AK.SoundEngine.registerOutputDeviceMeteringCallback(0, deviceMeteringCallback, .{ .enable_bus_meter_peak = true }, self);
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    AK.SoundEngine.registerOutputDeviceMeteringCallback(0, null, .{}, null) catch {};

    AK.SoundEngine.unregisterGameObj(GameObjectFootsteps) catch {};
    AK.SoundEngine.unregisterGameObj(GameObjectAmbience) catch {};

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;

    self.tick += 1;

    zgui.setNextWindowSize(.{
        .w = 640,
        .h = 480,
        .cond = .first_use_ever,
    });

    if (zgui.begin("3D Audio Objects and Spatialized Bed", .{ .popen = &self.is_visible, .flags = .{} })) {
        const window_size = zgui.getContentRegionAvail();

        if (self.is_first_update) {
            self.width = window_size[0] - Cursor.Margin;
            self.height = window_size[1] - Cursor.Margin;
            self.is_first_update = false;

            self.cursor.update();
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

        const origin_x: f32 = (self.width - Cursor.Margin) / 2.0;
        const origin_y: f32 = (self.height - Cursor.Margin) / 2.0;
        draw_list.addTextUnformatted(
            [2]f32{ window_pos[0] + origin_x, window_pos[1] + origin_y },
            white_color,
            "X",
        );

        const line_height: i32 = @intFromFloat(zgui.getFontSize());

        var metering_y = line_height * 10;
        draw_list.addTextUnformatted([2]f32{ window_pos[0] + 50, window_pos[1] + @as(f32, @floatFromInt(metering_y)) }, white_color, "Main Mix:");
        metering_y += line_height;
        for (0..self.mm_peaks) |index| {
            const db = linearToDb(self.main_mix_peaks[index]);
            const length = std.math.clamp(@as(u32, @intCast(@as(i32, @intFromFloat(db)) + 100)), 10, 150);
            draw_list.addLine(.{
                .p1 = [2]f32{ window_pos[0] + 50.0, window_pos[1] + @as(f32, @floatFromInt(metering_y)) },
                .p2 = [2]f32{ window_pos[0] + 50.0 + @as(f32, @floatFromInt(length)), window_pos[1] + @as(f32, @floatFromInt(metering_y)) },
                .col = white_color,
                .thickness = 1.0,
            });
            metering_y += 5;
        }

        if (self.pt_peaks > 0) {
            draw_list.addTextUnformatted([2]f32{ window_pos[0] + 50, window_pos[1] + @as(f32, @floatFromInt(metering_y)) }, white_color, "Passthrough Mix:");
            metering_y += line_height;
            for (0..self.pt_peaks) |index| {
                const db = linearToDb(self.passthrough_peaks[index]);
                const length = std.math.clamp(@as(u32, @intCast(@as(i32, @intFromFloat(db)) + 100)), 10, 150);
                draw_list.addLine(.{
                    .p1 = [2]f32{ window_pos[0] + 50.0, window_pos[1] + @as(f32, @floatFromInt(metering_y)) },
                    .p2 = [2]f32{ window_pos[0] + 50.0 + @as(f32, @floatFromInt(length)), window_pos[1] + @as(f32, @floatFromInt(metering_y)) },
                    .col = white_color,
                    .thickness = 1.0,
                });
                metering_y += 5;
            }
        }

        if (self.obj_peaks > 0) {
            draw_list.addTextUnformatted([2]f32{ window_pos[0] + 50, window_pos[1] + @as(f32, @floatFromInt(metering_y)) }, white_color, "3D Audio Objects:");
            metering_y += line_height;
            for (0..self.obj_peaks) |index| {
                const db = linearToDb(self.object_peaks[index]);
                const length = std.math.clamp(@as(u32, @intCast(@as(i32, @intFromFloat(db)) + 100)), 10, 150);
                draw_list.addLine(.{
                    .p1 = [2]f32{ window_pos[0] + 50.0, window_pos[1] + @as(f32, @floatFromInt(metering_y)) },
                    .p2 = [2]f32{ window_pos[0] + 50.0 + @as(f32, @floatFromInt(length)), window_pos[1] + @as(f32, @floatFromInt(metering_y)) },
                    .col = white_color,
                    .thickness = 1.0,
                });
                metering_y += 5;
            }
        }

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

inline fn linearToDb(in_linear_value: f32) f32 {
    if (in_linear_value == 0.0) {
        return 0.0;
    }

    return 20.0 * std.math.log10(in_linear_value);
}

fn deviceMeteringCallback(in_callback_info: *AK.AkOutputDeviceMeteringCallbackInfo) callconv(.C) void {
    var self: *Self = @ptrCast(@alignCast(in_callback_info.base.cookie));

    @memset(self.main_mix_peaks[0..], 0.0);
    @memset(self.passthrough_peaks[0..], 0.0);
    @memset(self.object_peaks[0..], 0.0);

    self.mm_peaks = @min(36, in_callback_info.main_mix_config.num_channels);
    self.pt_peaks = @min(2, in_callback_info.passthrough_mix_config.num_channels);
    self.obj_peaks = @min(20, in_callback_info.num_system_audio_objects);

    if (in_callback_info.main_mix_metering) |main_mix_metering| {
        const peaks = main_mix_metering.peak;

        for (0..self.mm_peaks) |index| {
            self.main_mix_peaks[index] = peaks[index];
        }
    }

    if (in_callback_info.passthrough_metering) |passthrough_metering| {
        const peaks = passthrough_metering.peak;

        for (0..self.pt_peaks) |index| {
            self.passthrough_peaks[index] = peaks[index];
        }
    }

    if (in_callback_info.num_system_audio_objects > 0) {
        for (0..self.obj_peaks) |index| {
            if (in_callback_info.system_audio_object_metering[index]) |object_metering| {
                self.object_peaks[index] = object_metering.peak[0];
            }
        }
    }
}

fn pixelsToAkPosX(self: Self, in_x: f32) f32 {
    return ((in_x / self.width) - 0.5) * PositionRange;
}

fn pixelsToAkPosY(self: Self, in_y: f32) f32 {
    return -((in_y / self.height) - 0.5) * PositionRange;
}

fn updateGameObjectPos(self: *Self) !void {
    const x = self.cursor.x;
    const y = self.cursor.y;

    self.game_object_x = self.pixelsToAkPosX(x);
    self.game_object_z = self.pixelsToAkPosY(y);

    const sound_position = AK.AkSoundPosition{
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

    try AK.SoundEngine.setPosition(GameObjectFootsteps, sound_position, .{});

    const dx = x - self.last_x;
    const dy = y - self.last_y;
    const dist = std.math.sqrt(dx * dx + dy * dy);

    if (dist < 0.1 and self.last_footstep_tick != -1) {
        _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_SANDSTEP, GameObjectFootsteps, .{});
        self.last_footstep_tick = -1;
    } else if (dist > 0.1 and (self.tick - self.last_footstep_tick) > 20) {
        _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_SANDSTEP, GameObjectFootsteps, .{});
        self.last_footstep_tick = self.tick;
    }

    self.last_x = x;
    self.last_y = y;
}
